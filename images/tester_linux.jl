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
tarball_path = debootstrap(arch, image; packages)

# Upload it
upload_rootfs_image_github_actions(tarball_path)
