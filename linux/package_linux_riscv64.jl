using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap
using RootfsUtils: install_awscli
using RootfsUtils: install_gcc_toolchain, install_gcc_cross_toolchain

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

# The `package_linux` image plus a riscv64 cross compiler, in which Julia's riscv64
# builds are cross-compiled on x86_64. The steps that run riscv64 code (flisp, the
# sysimage build) go through qemu-user, which the host registers with binfmt_misc
# (flag `F`), so the image does not need it.
arch == "x86_64" || error("package_linux_riscv64 is only built for x86_64")

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
    install_gcc_cross_toolchain(rootfs, chroot_ENV, arch, "riscv64")

    # The build jobs upload their products to S3 from within the sandbox,
    # using OIDC-issued credentials; they need a recent AWS CLI to do so.
    install_awscli(rootfs, chroot_ENV, arch)
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
