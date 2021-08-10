## This rootfs does not include the compiler toolchain.

using RootfsUtils

arch, image, = parse_build_args(ARGS, @__FILE__)

# Build debian-based image with the following extra packages:
packages = [
    "bash",
    "curl",
    "gdb",
    "vim",
]
artifact_hash, tarball_path, = debootstrap(arch, image; packages)

# Upload it
upload_rootfs_image_github_actions(tarball_path)

# Test that we can use our new rootfs image with Sandbox.jl
test_sandbox(artifact_hash)
