## This rootfs includes everything that must be installed to build Julia
## within a CentOS-based environment.

include(joinpath(dirname(@__DIR__), "rootfs_utils.jl"))
arch, = parse_args(ARGS)
image = "$(splitext(basename(@__FILE__))[1]).$(arch)"

# Build CentOS-based image with the following extra packages:
packages = [
    "automake",
    "bash",
    "bison",
    "cmake",
    "curl",
    "flex",
    "gcc",
    "gcc-c++",
    "gcc-gfortran",
    "gdb",
    "git",
    "iproute",
    "iputils",
    "less",
    "libatomic",
    "libtool",
    "m4",
    "make",
    "perl",
    "pkgconfig",
    "vim",
    "wget",
]
tarball_path = centos_bootstrap(image; packages) do rootfs
    # Print the gcc version to the log
    chroot(rootfs, "bash", "-c", "gcc --version"; uid=0, gid=0)
    chroot(rootfs, "bash", "-c", "g++ --version"; uid=0, gid=0)
    chroot(rootfs, "bash", "-c", "gfortran --version"; uid=0, gid=0)
end

# Upload it
upload_rootfs_image_github_actions(tarball_path)
