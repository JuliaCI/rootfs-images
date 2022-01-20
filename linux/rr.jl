using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap
using RootfsUtils: root_chroot

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

packages = [
    "bash",
    "build-essential",
    "capnproto",
    "ccache",
    "coreutils",
    "curl",
    "g++-multilib",
    "gdb",
    "git",
    "libcapnp-dev",
    "locales",
    "make",
    "manpages-dev",
    "ninja-build",
    "pkg-config",
    "python3-pexpect",
    "vim",
]

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages) do rootfs, chroot_ENV
    my_chroot(args...) = root_chroot(args...; ENV=chroot_ENV)

    # We need cmake 3.21+ for the `--output-xunit` feature
    @info("Installing cmake")
    cmake_install_cmd = """
    echo 'deb http://deb.debian.org/debian testing main' >> /etc/apt/sources.list && \\
    apt-get update && \\
    DEBIAN_FRONTEND=noninteractive apt-get install -y cmake
    """
    my_chroot(rootfs, "bash", "-c", cmake_install_cmd)
    my_chroot(rootfs, "bash", "-c", "which cmake")
    my_chroot(rootfs, "bash", "-c", "which -a cmake")
    my_chroot(rootfs, "bash", "-c", "cmake --version")
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
