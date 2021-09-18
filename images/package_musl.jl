## This rootfs includes everything that must be installed to build Julia
## within an alpine-based environment with GCC 9.

using RootfsUtils: AlpinePackage, parse_build_args, alpine_bootstrap, chroot, upload_gha, test_sandbox

arch, image, = parse_build_args(ARGS, @__FILE__)

# Build alpine-based image with the following extra packages:
packages = [
    AlpinePackage("bash"),
    AlpinePackage("cmake"),
    AlpinePackage("curl"),
    AlpinePackage("gdb"),
    AlpinePackage("git"),
    AlpinePackage("less"),
    AlpinePackage("lldb"),
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
upload_gha(tarball_path)

# Test that we can use our new rootfs image with Sandbox.jl
test_sandbox(artifact_hash)
