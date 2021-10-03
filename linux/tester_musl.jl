using RootfsUtils: AlpinePackage, parse_build_args, alpine_bootstrap, chroot, upload_gha, test_sandbox

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

# Build alpine-based args.image with the following extra packages:
packages = [
    AlpinePackage("bash"),
    AlpinePackage("curl"),
    AlpinePackage("gdb"),
    AlpinePackage("vim"),
]

artifact_hash, tarball_path, = alpine_bootstrap(image; archive, packages)
upload_gha(tarball_path)
test_sandbox(artifact_hash)
