## This rootfs includes everything that must be installed to build Julia
## within an alpine-based environment with GCC 9.

using RootfsUtils

arch, image, = parse_build_args(ARGS, @__FILE__)

# Build alpine-based image with the following extra packages:
packages = [
    AlpinePackage("bash"),
    AlpinePackage("cmake"),
    AlpinePackage("curl"),
    AlpinePackage("git"),
    AlpinePackage("less"),
    AlpinePackage("m4"),
    AlpinePackage("perl"),
    AlpinePackage("python3"),
    AlpinePackage("wget"),

    # Install gcc/g++/gfortran v9, which comes from the Alpine v3.11 line
    AlpinePackage("g++~9", "v3.11"),
    AlpinePackage("gcc~9", "v3.11"),
    AlpinePackage("gfortran~9", "v3.11"),
]
artifact_hash, tarball_path, = alpine_bootstrap(image; packages)

# Upload it
upload_rootfs_image_github_actions(tarball_path)

# Test that we can use our new rootfs image with Sandbox.jl
test_sandbox(artifact_hash)
