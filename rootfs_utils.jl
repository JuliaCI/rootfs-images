using Scratch, Pkg, Pkg.Artifacts, ghr_jll, SHA, Dates, Base.BinaryPlatforms

# Utility functions
getuid() = ccall(:getuid, Cint, ())
getgid() = ccall(:getgid, Cint, ())
chroot(rootfs, cmds...; uid=getuid(), gid=getgid()) = run(`sudo chroot --userspec=$(uid):$(gid) $(rootfs) $(cmds)`)

# Common ARGS parsing
function parse_args(ARGS)
    # Default `arch` to current native arch
    arch = Base.BinaryPlatforms.arch(HostPlatform())

    arch_idx = findfirst(arg -> startswith(arg, "--arch"), ARGS)
    if arch_idx !== nothing
        if ARGS[arch_idx] == "--arch"
            if length(ARGS) < arch_idx + 1
                error("--arch requires an argument!")
            end
            arch = ARGS[arch_idx + 1]
        else
            arch = split(ARGS[arch_idx], "=")[2]
        end
        if arch ∉ keys(Base.BinaryPlatforms.arch_mapping)
            error("Invalid choice for --arch: $(arch)")
        end
    end

    # Return all our parsed args here
    return String(arch)
end

# Sometimes rootfs images have absolute symlinks within them; this
# is very bad for us as it breaks our ability to look at a rootfs
# without `chroot`'ing into it; so we fix up all the links to be
# relative here.
function force_relative(link, rootfs)
    target = readlink(link)
    if !isabspath(target)
        return
    end
    target = joinpath(rootfs, target[2:end])
    rm(link; force=true)
    symlink(relpath(target, dirname(link)), link)
end
function force_relative(rootfs)
    for (root, dirs, files) in walkdir(rootfs)
        for f in files
            f = joinpath(root, f)
            if islink(f)
                force_relative(f, rootfs)
            end
        end
        for d in dirs
            d = joinpath(root, d)
            if islink(d)
                force_relative(d, rootfs)
            end
        end
    end
end

function cleanup_rootfs(rootfs; rootfs_info=nothing)
    # Remove special `dev` files
    @info("Cleaning up `/dev`")
    for f in readdir(joinpath(rootfs, "dev"); join=true)
        # Keep the symlinks around (such as `/dev/fd`), as they're useful
        if !islink(f)
            run(`sudo rm -rf "$(f)"`)
        end
    end

    # take ownership of the entire rootfs
    @info("Chown'ing rootfs")
    run(`sudo chown $(getuid()):$(getgid()) -R "$(rootfs)"`)

    # Add `juliaci` user and group
    @info("Adding 'juliaci' user and group as 1000:1000")
    open(joinpath(rootfs, "etc", "passwd"), append=true) do io
        println(io, "juliaci:x:1000:1000:juliaci:/home/juliaci:/bin/sh")
    end
    open(joinpath(rootfs, "etc", "group"), append=true) do io
        println(io, "juliaci:x:1000:juliaci")
    end
    mkpath(joinpath(rootfs, "home", "juliaci"))

    # Write out a reasonable default `/etc/resolv.conf` file
    open(joinpath(rootfs, "etc", "resolv.conf"), write=true) do io
        write(io, """
        nameserver 1.1.1.1
        nameserver 8.8.8.8
        """)
    end

    # Write out a reasonable default `/etc/hosts` file
    open(joinpath(rootfs, "etc", "hosts"), write=true) do io
        write(io, """
        127.0.0.1   localhost localhost.localdomain
        ::1         localhost localhost.localdomain
        """)
    end

    # If we've been given a `rootfs_info` parameter, write it out as /etc/rootfs-info
    if rootfs_info !== nothing
        open(io -> write(io, rootfs_info),
             joinpath(rootfs, "etc", "rootfs-info"),
             write=true,
        )
    end

    @info("Forcing all symlinks to be relative")
    force_relative(rootfs)
end

function create_rootfs(f::Function, name::String; force::Bool=false)
    tarball_path = joinpath(@get_scratch!("rootfs-images"), "$(name).tar.gz")
    if !force && isfile(tarball_path)
        @error("Refusing to overwrite tarball without `force` set", tarball_path)
        error()
    end

    artifact_hash = create_artifact(f)

    # Archive it into a `.tar.gz` file (but only if this is not a pull request build).
    if is_github_actions_pr()
        info_msg = "Skipping tarball creation because the build is a `pull_request` build"
        @info info_msg artifact_hash
        return nothing
    end
    @info "Archiving" tarball_path artifact_hash
    archive_artifact(artifact_hash, tarball_path)
    return tarball_path
end

function normalize_arch(image_arch::String)
    if image_arch in ("x86_64", "amd64", "x64")
        return "x86_64"
    end
    if image_arch in ("i686", "i386", "x86")
        return "i686"
    end
    if image_arch in ("armv7l", "arm", "armhf")
        return "armv7l"
    end
    if image_arch in ("aarch64", "armv8", "arm64")
        return "aarch64"
    end
    if image_arch in ("powerpc64le", "ppc64le", "ppc64el")
        return "powerpc64le"
    end
end

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

function can_run_natively(image_arch::String)
    native_arch = Base.BinaryPlatforms.arch(HostPlatform())
    if native_arch == "x86_64"
        # We'll assume all `x86_64` chips can run `i686` code
        return image_arch in ("x86_64", "i686")
    end
    if native_arch == "aarch64"
        # We'll assume all `aarch64` chips can run `armv7l`, even though this may not be true
        return image_arch in ("aarch64", "armv7l")
    end
    return native_arch == image_arch
end

function qemu_installed(image_arch::String)
    qemu_arch_mapping = Dict(
        "x86_64" => "x86_64",
        "i686" => "i386",
        "aarch64" => "aarch64",
        "armv7l" => "arm",
        "powerpc64le" => "ppc64le",
    )
    return Sys.which("qemu-$(qemu_arch_mapping[image_arch])-static") !== nothing
end

function debootstrap(f::Function, arch::String, name::String;
                     release::String="buster",
                     variant::String="minbase",
                     packages::Vector{String}=String[],
                     force::Bool=false)
    if Sys.which("debootstrap") === nothing
        error("Must install `debootstrap`!")
    end

    arch = normalize_arch(arch)
    if !can_run_natively(arch) && !qemu_installed(arch)
        error("Must install qemu-user-static and binfmt_misc!")
    end

    return create_rootfs(name; force) do rootfs
        packages_string = join(push!(packages, "locales"), ",")
        @info("Running debootstrap", release, variant, packages)
        run(`sudo debootstrap --arch=$(debian_arch(arch)) --variant=$(variant) --include=$(packages_string) $(release) "$(rootfs)"`)

        # This is necessary on any 32-bit userspaces to work around the
        # following bad interaction between qemu, linux and openssl:
        # https://serverfault.com/questions/1045118/debootstrap-armhd-buster-unable-to-get-local-issuer-certificate
        if isfile(joinpath(rootfs, "usr", "bin", "c_rehash"))
            chroot(rootfs, "/usr/bin/c_rehash"; uid=0, gid=0)
        end

        # Call user callback, if requested
        f(rootfs)

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

        # Set up the one true locale
        @info("Setting up UTF-8 locale")
        open(joinpath(rootfs, "etc", "locale.gen"), "a") do io
            println(io, "en_US.UTF-8 UTF-8")
        end
        chroot(rootfs, "locale-gen")
    end
end
# If no user callback is provided, default to doing nothing
debootstrap(arch::String, name::String; kwargs...) = debootstrap(p -> nothing, arch, name; kwargs...)

# Helper structure for installing alpine packages that may or may not be part of an older Alpine release
struct AlpinePackage
    name::String
    repo::Union{Nothing,String}

    AlpinePackage(name, repo=nothing) = new(name, repo)
end
function repository_arg(repo)
    if startswith(repo, "https://")
        return "--repository=$(repo)"
    end
    return "--repository=http://dl-cdn.alpinelinux.org/alpine/$(repo)/main"
end

function alpine_bootstrap(f::Function, name::String; release::VersionNumber=v"3.13.5", variant="minirootfs",
                          packages::Vector{AlpinePackage}=AlpinePackage[], force::Bool=false)
    return create_rootfs(name; force) do rootfs
        rootfs_url = "https://github.com/alpinelinux/docker-alpine/raw/v$(release.major).$(release.minor)/x86_64/alpine-$(variant)-$(release)-x86_64.tar.gz"
        @info("Downloading Alpine rootfs", url=rootfs_url)
        rm(rootfs)
        Pkg.Artifacts.download_verify_unpack(rootfs_url, nothing, rootfs; verbose=true)

        # Call user callback, if requested
        f(rootfs)

        # Remove special `dev` files, take ownership, force symlinks to be relative, etc...
        rootfs_info = """
                    rootfs_type=alpine
                    release=$(release)
                    variant=$(variant)
                    packages=$(join([pkg.name for pkg in packages], ","))
                    build_date=$(Dates.now())
                    """
        cleanup_rootfs(rootfs; rootfs_info)

        # Generate one `apk` invocation per repository
        repos = unique([pkg.repo for pkg in packages])
        for repo in repos
            apk_args = ["/sbin/apk", "add", "--no-chown"]
            if repo !== nothing
                push!(apk_args, repository_arg(repo))
            end
            for pkg in filter(pkg -> pkg.repo == repo, packages)
                push!(apk_args, pkg.name)
            end
            chroot(rootfs, apk_args...)
        end
    end
end
# If no user callback is provided, default to doing nothing
alpine_bootstrap(name::String; kwargs...) = alpine_bootstrap(p -> nothing, name; kwargs...)

function upload_rootfs_image(tarball_path::String;
                             force_overwrite::Bool,
                             github_repo::String,
                             tag_name::String,
                             num_retries::Int = 3)
    # Upload it to `github_repo`
    tarball_url = "https://github.com/$(github_repo)/releases/download/$(tag_name)/$(basename(tarball_path))"
    @info("Uploading to $(github_repo)@$(tag_name)", tarball_url)
    cmd = ghr_jll.ghr()
    append!(cmd.exec, ["-u", dirname(github_repo), "-r", basename(github_repo)])
    force_overwrite && push!(cmd.exec, "-replace")
    append!(cmd.exec, [tag_name, tarball_path])
    for _ in 1:num_retries
        p = run(cmd)
        if success(p)
            return tarball_url
        end
    end
    error("Unable to upload!")
end

function is_github_actions()
    is_ci  = get(ENV, "CI", "")              == "true"
    is_gha = get(ENV, "GITHUB_ACTIONS", "")  == "true"
    return is_ci && is_gha
end
function _is_github_actions_event(event_name::AbstractString)
    is_gha = is_github_actions()
    is_event = get(ENV, "GITHUB_EVENT_NAME", "") == event_name
    return is_gha && is_event
end
function is_github_actions_pr()
    return _is_github_actions_event("pull_request")
end
function is_github_actions_release()
    return _is_github_actions_event("release")
end
get_github_actions_event_name() = convert(String, ENV["GITHUB_EVENT_NAME"])::String
get_github_actions_ref()        = convert(String, ENV["GITHUB_REF"])::String
get_github_actions_repo()       = convert(String, ENV["GITHUB_REPOSITORY"])::String

function upload_rootfs_image_github_actions(tarball_path::Nothing)
    if !is_github_actions_pr()
        error_msg = "You are only allowed to skip tarball creation if the build is a `pull_request` build"
        throw(ErrorException(error_msg))
    end
    GITHUB_EVENT_NAME = get_github_actions_event_name()
    GITHUB_REF        = get_github_actions_ref()
    @info "Skipping upload because the build is a `pull_request` build" GITHUB_EVENT_NAME GITHUB_REF
    return nothing
end
function upload_rootfs_image_github_actions(tarball_path::String)
    if !is_github_actions()
        @info "Skipping upload because this is not a GitHub Actions build"
        return nothing
    end

    GITHUB_EVENT_NAME = get_github_actions_event_name()
    GITHUB_REF        = get_github_actions_ref()
    m = match(r"^refs\/tags\/(.*?)$", GITHUB_REF)

    if !is_github_actions_release()
        @info "Skipping upload because this is not a `release` build" GITHUB_EVENT_NAME GITHUB_REF
        return nothing
    end

    if m === nothing
        error_msg = "This is a `release` event, but the ref does not look like a tag."
        @error error_msg GITHUB_EVENT_NAME GITHUB_REF
        throw(ErrorException(error_msg))
    end

    force_overwrite = false
    github_repo = get_github_actions_repo()
    tag_name = convert(String, m[1])::String

    return upload_rootfs_image(
        tarball_path;
        force_overwrite,
        github_repo,
        tag_name,
    )
end
