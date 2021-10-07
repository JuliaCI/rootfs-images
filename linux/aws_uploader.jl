using RootfsUtils: parse_build_args, debootstrap, chroot, upload_gha, test_sandbox

arch, image, = parse_build_args(ARGS, @__FILE__)

# Build debian-based image with the following extra packages:
packages = [
    "awscli",
    "bash",
    "curl",
    "locales",
    "vim",
]
artifact_hash, tarball_path = debootstrap(arch, image; packages)

# Upload it
upload_gha(tarball_path)

# Test that we can use our new rootfs image with Sandbox.jl
test_sandbox(artifact_hash)
