using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap
using RootfsUtils: root_chroot

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

packages = [
    "apt-transport-https",
    "bzip2",
    "curl",
    "expect",
    "git",
    "gnupg2",
    "iproute2",
    "jq",
    "libgomp1",
    "libicu67",
    "localepurge",
    "locales",
    "openssh-client",
    "openssl",
    "p7zip",
    "python3",
    "ssh",
    "unzip",
    "vim",
    "wget",
    "xz-utils",
    "zstd",
]

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages)
upload_gha(tarball_path)
test_sandbox(artifact_hash)
