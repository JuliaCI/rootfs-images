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
    "git",
    "libcapnp-dev",
    "locales",
    "localepurge",
    "make",
    "manpages-dev",
    "ninja-build",
    "pkg-config",
    "python3-pexpect",
    "sysvinit-utils",
    "vim",
    "zlib1g",
    "zlib1g-dev",
]

release = "bookworm"

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages, release) do rootfs, chroot_ENV
    my_chroot(args...) = root_chroot(rootfs, "bash", "-eu", "-o", "pipefail", "-c", args...; ENV=chroot_ENV)
    my_chroot_command(args...) = root_chroot_command(rootfs, "bash", "-eu", "-o", "pipefail", "-c", args...; ENV=chroot_ENV)

    if arch in ("aarch64",)
        gpp = "g++"
    else
        gpp = "g++-multilib"
    end

    apt_update_and_upgrade = () -> begin
        my_chroot("DEBIAN_FRONTEND=noninteractive apt update")
        my_chroot("DEBIAN_FRONTEND=noninteractive apt upgrade -y")
    end
    apt_update_and_upgrade()
    my_chroot("DEBIAN_FRONTEND=noninteractive apt install -y gdb")
    my_chroot("DEBIAN_FRONTEND=noninteractive apt install -y $(gpp)")
    apt_update_and_upgrade()

    my_chroot("cmake --version")
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
