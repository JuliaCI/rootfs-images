using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap
using RootfsUtils: root_chroot
using RootfsUtils: root_chroot_command

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

packages = [
    "bash",
    "build-essential",
    "capnproto",
    "ccache",
    "cmake",
    "coreutils",
    "curl",
    "g++-multilib",
    "git",
    "libcapnp-dev",
    "locales",
    "make",
    "manpages-dev",
    "ninja-build",
    "pkg-config",
    "python3-pexpect",
    "vim",
    "tree",
]

release = "bookworm"

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages, release) do rootfs, chroot_ENV
    my_chroot(args...)         = root_chroot(        rootfs, "bash", "-c", args...; ENV=chroot_ENV)
    my_chroot_command(args...) = root_chroot_command(rootfs, "bash", "-c", args...; ENV=chroot_ENV)

    my_chroot("apt-get update")
    my_chroot("DEBIAN_FRONTEND=noninteractive apt-get install -y gdb")
    my_chroot("cmake --version")

    let
        str = read(my_chroot_command("cmake --version"), String)
        m = match(r"cmake version ([\d]*)\.([\d]*)\.([\d]*)", str)
        installed_ver = VersionNumber("$(m[1]).$(m[2]).$(m[3])")
        desired_ver = v"3.22.1"
        @info "cmake version" installed_ver desired_ver
        if installed_ver < desired_ver
            msg = "Failed to install a sufficiently recent version of cmake"
            throw(ErrorException(msg))
        end
    end
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
