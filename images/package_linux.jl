## This rootfs includes everything that must be installed to build Julia
## within a debian-based environment with GCC 9.

include(joinpath(dirname(@__DIR__), "rootfs_utils.jl"))
arch, = parse_args(ARGS)
image = "$(splitext(basename(@__FILE__))[1]).$(arch)"

# For each architecture, we want to use the oldest Debian release that
# supports that architecture.
arch_to_release = Dict(
    "aarch64"     => "stretch",
    "armv7l"      => "jessie",
    "i686"        => "jessie",
    "powerpc64le" => "stretch",
    "x86_64"      => "jessie",
)
release = arch_to_release[arch]

# Build debian-based image with the following extra packages:
packages = [
    "automake",
    "bash",
    "bison",
    "cmake",
    "curl",
    "flex",
    "g++",
    "gcc",
    "gdb",
    "gfortran",
    "git",
    "less",
    "libatomic1",
    "libtool",
    "m4",
    "make",
    "perl",
    "pkg-config",
    "python",
    "python3",
    "vim",
    "wget",
]
tarball_path = debootstrap(arch, image; packages, release) do rootfs
    # Print the gcc version to the log
    chroot(rootfs, "bash", "-c", "gcc --version"; uid=0, gid=0)
    chroot(rootfs, "bash", "-c", "g++ --version"; uid=0, gid=0)
    chroot(rootfs, "bash", "-c", "gfortran --version"; uid=0, gid=0)
end

# Upload it
upload_rootfs_image_github_actions(tarball_path)
