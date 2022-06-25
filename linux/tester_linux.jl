using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

packages = [
    "bash",
    "curl",
    "file",
    "gdb",
    "git",
    "lldb",
    "locales",
    "make",
    "openssl",
    "procps",
    "vim",
    "zstd",
]

# The test suites use a non-english locale as part of their tests;
# we provide it in the testing image.
locales = [
    "en_US.UTF-8 UTF-8",
    "ko_KR.EUC-KR EUC-KR",
]

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages, locales)
upload_gha(tarball_path)
test_sandbox(artifact_hash)
