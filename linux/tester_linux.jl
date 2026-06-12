using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap
using RootfsUtils: install_awscli

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
    "localepurge",
    "make",
    "net-tools",
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

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages, locales) do rootfs, chroot_ENV
    # The test jobs fetch secrets (e.g. the Buildkite Test Analytics token
    # via `aws ssm get-parameter`) from within the sandbox, using
    # OIDC-issued credentials; they need the AWS CLI to do so.
    install_awscli(rootfs, chroot_ENV, arch)
end
upload_gha(tarball_path)
test_sandbox(artifact_hash)
