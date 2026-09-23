using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap
using RootfsUtils: install_awscli
using RootfsUtils: install_gcc_toolchain

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

packages = [
    "automake",
    "bash",
    "bison",
    "bzip2",
    "ccache",
    "cmake",
    "curl",
    "file",
    "flex",
    "gdb",
    "git",
    "less",
    "libatomic1",
    "libtool",
    "lldb",
    "locales",
    "localepurge",
    "m4",
    "make",
    "patch",
    "patchelf",
    "perl",
    "pkg-config",
    "python3",
    "time",
    "vim",
    "wget",
    "xz-utils",
    "zstd",
]

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages) do rootfs, chroot_ENV
    # Install our GCC toolchain as the default `gcc`/`g++`/`gfortran`/`cc`/`c++`/`ld`.
    install_gcc_toolchain(rootfs, chroot_ENV, arch)

    # The build jobs upload their products to S3 from within the sandbox,
    # using OIDC-issued credentials; they need a recent AWS CLI to do so.
    install_awscli(rootfs, chroot_ENV, arch)
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
