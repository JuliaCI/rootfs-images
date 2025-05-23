using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

packages = [
    "build-essential",
    "bzip2",
    "cmake",
    "curl",
    "file",
    "gfortran",
    "git",
    "gdb",
    "less",
    "libatomic1",
    "lldb",
    "locales",
    "localepurge",
    "m4",
    "perl",
    "pkg-config",
    "python3",
    "time",
    "wget",
    "zstd",
]

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages)
upload_gha(tarball_path)
test_sandbox(artifact_hash)
