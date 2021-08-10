## This rootfs does not include the compiler toolchain.

using RootfsUtils

arch, = parse_build_args(ARGS)
image = "$(splitext(basename(@__FILE__))[1]).$(arch)"

# Build alpine-based image with the following extra packages:
packages = [
    AlpinePackage("bash"),
    AlpinePackage("curl"),
    AlpinePackage("gdb"),
    AlpinePackage("vim"),
]
artifact_hash, tarball_path, = alpine_bootstrap(image; packages)

# Upload it
upload_rootfs_image_github_actions(tarball_path)

# Test that we can use our new rootfs image with Sandbox.jl
test_sandbox(artifact_hash)
