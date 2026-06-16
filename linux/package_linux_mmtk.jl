using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap
using RootfsUtils: install_awscli
using RootfsUtils: install_gcc_toolchain
using RootfsUtils: install_rust

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

# This is the `package_linux` image plus a Rust toolchain, used for Julia's
# MMTk garbage collector builds (`WITH_THIRD_PARTY_GC=mmtk`). The MMTk binding
# is compiled from source with `cargo`, and its `build.rs` runs `bindgen`
# (which needs `libclang`) to generate the Julia FFI bindings, so we add
# `clang`/`libclang-dev` on top of the usual `package_linux` package set.
packages = [
    "automake",
    "bash",
    "bison",
    "bzip2",
    "ccache",
    "clang",
    "cmake",
    "curl",
    "flex",
    "gdb",
    "git",
    "less",
    "libatomic1",
    "libclang-dev",
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
    "zstd",
]

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages) do rootfs, chroot_ENV
    # Install the GCC 9 cross-toolchain as the default `gcc`/`g++`/`cc`/`c++`/`ld`.
    install_gcc_toolchain(rootfs, chroot_ENV, arch)

    # Install the Rust toolchain used to build the MMTk garbage collector.
    # Keep the version in sync with `src/gc-mmtk/mmtk_julia/rust-toolchain`
    # in JuliaLang/julia.
    install_rust(rootfs, chroot_ENV, arch)

    # The build jobs upload their products to S3 from within the sandbox,
    # using OIDC-issued credentials; they need a recent AWS CLI to do so.
    install_awscli(rootfs, chroot_ENV, arch)
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
