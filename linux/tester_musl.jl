using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: AlpinePackage, alpine_bootstrap

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

packages = AlpinePackage.([
    "bash",
    "curl",
    "file",
    "gdb",
    "git",
    "lldb",
    "make",
    "vim",
    "zstd",
])

artifact_hash, tarball_path, = alpine_bootstrap(image; archive, packages)
upload_gha(tarball_path)
test_sandbox(artifact_hash)
