function debian_arch(image_arch::String)
    debian_arch_mapping = Dict(
        "x86_64" => "amd64",
        "i686" => "i386",
        "armv7l" => "armhf",
        "aarch64" => "arm64",
        "powerpc64le" => "ppc64el",
    )
    return debian_arch_mapping[normalize_arch(image_arch)]
end

function debootstrap(f::Function, arch::String, name::String;
                     archive::Bool = true,
                     force::Bool = false,
                     locale::Union{Nothing,String} = "en_US.UTF-8 UTF-8",
                     packages::Vector{String} = String[],
                     release::String = "buster",
                     variant::String = "minbase")
    if Sys.which("debootstrap") === nothing
        error("Must install `debootstrap`!")
    end

    if locale !== nothing
        if "locales" ∉ packages
            msg = string(
                "You have set the `locale` keyword argument to `true`. ",
                "However, the `packages` vector does not include the `locales` package. ",
                "Either ",
                "(1) add the `locales` package to the `packages` vector, or ",
                "(2) set the `locale` keyword arguement to `false`.",
            )
            throw(ArgumentError(msg))
        end
    end

    arch = normalize_arch(arch)
    if !can_run_natively(arch) && !qemu_installed(arch)
        error("Must install qemu-user-static and binfmt_misc!")
    end

    chroot_ENV = Dict{String,String}(
        "PATH" => "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    )

    # If `locale` is set, pass that through as `LANG`
    if locale !== nothing
        chroot_ENV["LANG"] = first(split(locale))
    end

    return create_rootfs(name; archive, force) do rootfs
        # If `locale` is set, the first thing we do is to pre-populate `/etc/locales.gen`
        if locale !== nothing
            @info("Setting up locale", locale)
            mkpath(joinpath(rootfs, "etc"))
            open(joinpath(rootfs, "etc", "locale.gen"), "a") do io
                println(io, locale)
            end
        end

        @info("Running debootstrap", release, variant, packages)
        debootstrap_cmd = `sudo debootstrap`
        push!(debootstrap_cmd.exec, "--arch=$(debian_arch(arch))")
        push!(debootstrap_cmd.exec, "--variant=$(variant)")
        if isempty(packages)
            packages_string = "(no packages)"
        else
            packages_string = join(strip.(packages), ",")
            push!(debootstrap_cmd.exec, "--include=$(packages_string)")
        end
        push!(debootstrap_cmd.exec, "--verbose")
        push!(debootstrap_cmd.exec, "$(release)")
        push!(debootstrap_cmd.exec, "$(rootfs)")
        p = run(setenv(debootstrap_cmd, chroot_ENV), (stdin, stdout, stderr); wait = false)
        wait(p)
        if !success(p)
            debootstrap_log_filename = joinpath(rootfs, "debootstrap", "debootstrap.log")
            @info "" debootstrap_log_filename
            debootstrap_log_contents = strip(read(debootstrap_log_filename, String))
            println(stderr, "# BEGIN contents of debootstrap.log")
            println(stderr)
            println(stderr, debootstrap_log_contents)
            println(stderr)
            println(stderr, "# END contents of debootstrap.log")

            throw(ProcessFailedException(p))
        end

        # This is necessary on any 32-bit userspaces to work around the
        # following bad interaction between qemu, linux and openssl:
        # https://serverfault.com/questions/1045118/debootstrap-armhd-buster-unable-to-get-local-issuer-certificate
        if isfile(joinpath(rootfs, "usr", "bin", "c_rehash"))
            chroot(rootfs, "/usr/bin/c_rehash"; ENV=chroot_ENV, uid=0, gid=0)
        end

        # Call user callback, if requested
        f(rootfs, chroot_ENV)

        # Remove special `dev` files, take ownership, force symlinks to be relative, etc...
        rootfs_info="""
                    rootfs_type=debootstrap
                    release=$(release)
                    variant=$(variant)
                    packages=$(packages_string)
                    build_date=$(Dates.now())
                    """
        cleanup_rootfs(rootfs; rootfs_info)

        # Remove `_apt` user so that `apt` doesn't try to `setgroups()`
        @info("Removing `_apt` user")
        open(joinpath(rootfs, "etc", "passwd"), write=true, read=true) do io
            filtered_lines = filter(l -> !startswith(l, "_apt:"), readlines(io))
            truncate(io, 0)
            seek(io, 0)
            for l in filtered_lines
                println(io, l)
            end
        end

        # If we have locale support, ensure that `locale-gen` is run at least once.
        if locale !== nothing
            chroot(rootfs, "locale-gen"; ENV=chroot_ENV)
        end

        # Run `apt clean`
        chroot(rootfs, "apt", "clean"; ENV=chroot_ENV)
    end
end

# If no user callback is provided, default to doing nothing
debootstrap(arch::String, name::String; kwargs...) = debootstrap((p, e) -> nothing, arch, name; kwargs...)
