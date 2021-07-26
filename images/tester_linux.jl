## This rootfs includes enough of a host toolchain to build the LLVM passes (such as `analyzegc`).

include(joinpath(dirname(@__DIR__), "rootfs_utils.jl"))
arch, = parse_args(ARGS)
image = "$(splitext(basename(@__FILE__))[1]).$(arch)"

# Build debian-based image with the following extra packages:
packages = [
    "bash",
    "curl",
    "gdb",
    "vim",
]
tarball_path = debootstrap(arch, image; packages) do rootfs
    # Install GCC 9, specifically
    @info("Installing a newer version of glibc")
    glibc_install_cmd = """
    echo 'deb http://deb.debian.org/debian testing main' >> /etc/apt/sources.list && \\
    apt-get update && \\
    DEBIAN_FRONTEND=noninteractive apt-get install -y \\
        libc6 libc-bin
    """
    chroot(rootfs, "bash", "-c", glibc_install_cmd; uid=0, gid=0)
    chroot(rootfs, "bash", "-c", "ldd --version"; uid=0, gid=0)
end

# Upload it
upload_rootfs_image_github_actions(tarball_path)
