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

    # Ensure that `/dev/fd` exists, so that `bash` can do command substitution
    dev_fd = joinpath(rootfs, "dev", "fd")
    if !ispath(dev_fd)
        symlink("../proc/self/fd", joinpath(rootfs, "dev", "fd"))
    end

    # take ownership of the entire rootfs
    @info("Chown'ing rootfs")
    run(`sudo chown $(getuid()):$(getgid()) -R "$(rootfs)"`)

    # Remove `/var/apt/cache`, as that's mostly downloaded archives
    if isdir(joinpath(rootfs, "var", "apt", "cache"))
        @info("Removing `/var/apt/cache`...")
        rm(joinpath(rootfs, "var", "apt", "cache"); recursive=true, force=true)
    end

    # Also remove `/var/lib/apt/lists/*` as those files get out of date
    apt_lists_dir = joinpath(rootfs, "var", "lib", "apt", "lists")
    if isdir(apt_lists_dir)
        @info("Removing `/var/lib/apt/lists/*`...")
        rm(apt_lists_dir; recursive=true, force=true)
        mkdir(apt_lists_dir)
    end

    # Remove `/usr/share/{doc,man}`, as that's not particularly useful
    if isdir(joinpath(rootfs, "usr", "share", "doc"))
        @info("Removing `/usr/share/doc`...")
        rm(joinpath(rootfs, "usr", "share", "doc"); recursive=true, force=true)
    end
    if isdir(joinpath(rootfs, "usr", "share", "man"))
        @info("Removing `/usr/share/man`...")
        rm(joinpath(rootfs, "usr", "share", "man"); recursive=true, force=true)
    end

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

# Pkg hashes a symlink by the character count of its target, git and Tar.jl by the byte count
# (JuliaLang/Pkg.jl#4707), so a non-ASCII target gives the image a tree hash that only Pkg
# reproduces. The Pkg server verifies artifacts with Tar.jl and drops such images. The only
# known source is ca-certificates (e.g. `988a38cb.0 -> NetLock_Arany_=Class_Gold=_Főtanúsítvány.pem`);
# replace those links by copies of the certificate, and refuse anything else so it gets looked at.
function dereference_nonascii_symlinks(rootfs)
    certs_dir = joinpath(rootfs, "etc", "ssl", "certs")
    links = String[]
    for (root, dirs, files) in walkdir(rootfs), name in vcat(dirs, files)
        path = joinpath(root, name)
        islink(path) && !isascii(readlink(path)) && push!(links, path)
    end
    # Resolve all links before replacing any, since they can point at one another
    chroot_ENV = Dict("PATH" => "/usr/sbin:/usr/bin:/sbin:/bin")
    targets = map(links) do link
        refuse() = error("Symlink with a non-ASCII target: $(relpath(link, rootfs)) -> $(readlink(link))")
        dirname(link) == certs_dir || refuse()
        resolved = readchomp(chroot_command(rootfs, "readlink", "-f", "/" * relpath(link, rootfs); ENV=chroot_ENV))
        target = joinpath(rootfs, lstrip(resolved, '/'))
        isfile(target) || refuse()
        target
    end
    for (link, target) in zip(links, targets)
        @info("Replacing symlink with a non-ASCII target by a copy",
              link=relpath(link, rootfs), target=readlink(link))
        rm(link)
        cp(target, link)
    end
end

# Build a Linux rootfs in a fresh artifact directory with `f(rootfs)`, then archive it
function create_rootfs(f::Function, name::String;
                       archive::Bool=true,
                       force::Bool=false)
    tarball_path = image_tarball_path(name; force)
    artifact_hash = Pkg.Artifacts.create_artifact() do rootfs
        f(rootfs)
        dereference_nonascii_symlinks(rootfs)
    end
    return archive_image(artifact_hash, tarball_path; archive)
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

function can_run_natively(image_arch::String)
    native_arch = Base.BinaryPlatforms.arch(Base.BinaryPlatforms.HostPlatform())
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

