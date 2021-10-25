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

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages)
upload_gha(tarball_path)
test_sandbox(artifact_hash)
