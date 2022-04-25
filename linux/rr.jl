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
    "coreutils",
    "curl",
    "git",
    "libcapnp-dev",
    "locales",
    "make",
    "manpages-dev",
    "ninja-build",
    "pkg-config",
    "python3-pexpect",
    "vim",
    "zlib1g",
    "zlib1g-dev",
]

release = "bookworm"
cmake_version = "3.23.1"

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages, release) do rootfs, chroot_ENV
    my_chroot(args...) = root_chroot(rootfs, "bash", "-eu", "-o", "pipefail", "-c", args...; ENV=chroot_ENV)
    my_chroot_command(args...) = root_chroot_command(rootfs, "bash", "-eu", "-o", "pipefail", "-c", args...; ENV=chroot_ENV)

    my_chroot("apt-get update")
    my_chroot("DEBIAN_FRONTEND=noninteractive apt-get install -y cmake")
    my_chroot("DEBIAN_FRONTEND=noninteractive apt-get install -y gdb")

    cmake_url = "https://github.com/Kitware/CMake/releases/download/v$(cmake_version)/cmake-$(cmake_version)-linux-$(arch).tar.gz"
    cmake_install_cmd = """
    cd /usr/local
    curl -fL $(cmake_url) | tar zx
    """
    my_chroot(cmake_install_cmd)

    my_chroot("which cmake")
    my_chroot("which -a cmake")
    my_chroot("cmake --version")
    
    if arch == :aarch64
        gpp = "g++"
    else
        gpp = "g++-multilib"
    end
    my_chroot("DEBIAN_FRONTEND=noninteractive apt-get install -y $(gpp)")
    cmd = """
    mkdir -p /tmp/build
    cd /tmp/build
    git clone https://github.com/rr-debugger/rr.git
    cd rr
    cmake --version
    rm -rf obj
    mkdir obj
    cd obj
    cmake ..
    make --output-sync -j2
    ctest --output-on-failure
    cd /
    rm -rf /tmp/build
    """
    my_chroot(cmd)
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
