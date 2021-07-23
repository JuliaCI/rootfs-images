## This rootfs includes enough of a host toolchain to build the LLVM passes.
## Eventually, this image will probably be replaced with the actual builder image,
## as that will have the necessary toolchains as well, but that image is not built yet.

include(joinpath(dirname(@__DIR__), "rootfs_utils.jl"))

# Build debian-based image with the following extra packages:
packages = [
    "build-essential",
    "cmake",
    "curl",
    "gfortran",
    "git",
    "less",
    "libatomic1",
    "m4",
    "perl",
    "pkg-config",
    "python",
    "python3",
    "wget",
]
tarball_path = debootstrap("llvm_passes"; packages)

# Upload it
upload_rootfs_image_github_actions(tarball_path)
