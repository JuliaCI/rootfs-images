## This rootfs does not include the compiler toolchain.

include(joinpath(dirname(@__DIR__), "rootfs_utils.jl"))
arch, = parse_args(ARGS)
image = "$(splitext(basename(@__FILE__))[1]).$(arch)"

# Build alpine-based image with the following extra packages:
packages = [
    AlpinePackage("bash"),
    AlpinePackage("curl"),
    AlpinePackage("gdb"),
    AlpinePackage("vim"),
]
tarball_path = alpine_bootstrap(image; packages)

# Upload it
upload_rootfs_image_github_actions(tarball_path)
