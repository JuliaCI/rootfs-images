## This rootfs does not include the compiler toolchain.

using RootfsUtils: AlpinePackage, parse_build_args, alpine_bootstrap, chroot, upload_gha, test_sandbox

arch, image, = parse_build_args(ARGS, @__FILE__)

# Build alpine-based image with the following extra packages:
packages = [
    AlpinePackage("bash"),
    AlpinePackage("curl"),
    AlpinePackage("gdb"),
    AlpinePackage("vim"),
]
artifact_hash, tarball_path, = alpine_bootstrap(image; packages)

# Upload it
upload_gha(tarball_path)

# Test that we can use our new rootfs image with Sandbox.jl
test_sandbox(artifact_hash)
