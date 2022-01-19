using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

packages = [
    "bash",
    "build-essential",
    "capnproto",
    "ccache",
    "cmake",
    "coreutils",
    "curl",
    "g++-multilib",
    "gdb",
    "git",
    "libcapnp-dev",
    "locales",
    "make",
    "manpages-dev",
    "ninja-build",
    "pkg-config",
    "python3-pexpect",
    "vim",
]

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages)
upload_gha(tarball_path)
test_sandbox(artifact_hash)
