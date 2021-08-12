## This rootfs includes enough of a host toolchain to build the LLVM passes (such as `analyzegc`).

using RootfsUtils

arch, image, = parse_build_args(ARGS, @__FILE__)

# Build debian-based image with the following extra packages:
packages = [
    "build-essential",
    "cmake",
    "curl",
    "gfortran",
    "git",
    "less",
    "libatomic1",
    "locales",
    "m4",
    "perl",
    "pkg-config",
    "python",
    "python3",
    "wget",
]
artifact_hash, tarball_path, = debootstrap(arch, image; packages)

# Upload it
upload_rootfs_image_github_actions(tarball_path)

# Test that we can use our new rootfs image with Sandbox.jl
test_sandbox(artifact_hash)
