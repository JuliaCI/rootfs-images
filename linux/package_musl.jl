using RootfsUtils: AlpinePackage, parse_build_args, alpine_bootstrap, chroot, upload_gha, test_sandbox

args         = parse_build_args(ARGS, @__FILE__)
archive      = args.archive
image        = args.image

packages = [
    AlpinePackage("bash"),
    AlpinePackage("cmake"),
    AlpinePackage("curl"),
    AlpinePackage("gdb"),
    AlpinePackage("git"),
    AlpinePackage("less"),
    AlpinePackage("lldb"),
    AlpinePackage("m4"),
    AlpinePackage("make"),
    AlpinePackage("perl"),
    AlpinePackage("python3"),
    AlpinePackage("tar"),
    AlpinePackage("wget"),

    # Install GCC 9, specifically
    AlpinePackage("g++~9", "v3.11"),
    AlpinePackage("gcc~9", "v3.11"),
    AlpinePackage("gfortran~9", "v3.11"),
]

artifact_hash, tarball_path, = alpine_bootstrap(image; archive, packages)
upload_gha(tarball_path)
test_sandbox(artifact_hash)
