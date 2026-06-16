# Install a pinned Rust toolchain (rustc + cargo + std) into a Debian-based
# rootfs.
#
# Julia's MMTk garbage collector (`WITH_THIRD_PARTY_GC=mmtk`) ships a Rust
# binding that is compiled from source with `cargo build` during the Julia
# build. The binding's `rust-toolchain` file pins an exact compiler version, so
# the version we install here must be kept in sync with it:
#   JuliaLang/julia : src/gc-mmtk/mmtk_julia/rust-toolchain
#
# We install the official standalone Rust distribution (NOT `rustup`) straight
# into `/usr/local`, so that `cargo`/`rustc` land on the default PATH and work
# in the non-login, non-interactive shells that Buildkite uses -- with no
# `RUSTUP_HOME`/`CARGO_HOME` plumbing and no toolchain download required at
# Julia build time. Because there is no `rustup` proxy, the `rust-toolchain`
# pin is satisfied simply by installing that exact version here.
const DEFAULT_RUST_VERSION = "1.92.0"

function rust_target(arch::String)
    rust_target_mapping = Dict(
        "x86_64" => "x86_64-unknown-linux-gnu",
        "i686" => "i686-unknown-linux-gnu",
        "aarch64" => "aarch64-unknown-linux-gnu",
        "armv7l" => "armv7-unknown-linux-gnueabihf",
        "powerpc64le" => "powerpc64le-unknown-linux-gnu",
    )
    return rust_target_mapping[normalize_arch(arch)]
end

function install_rust(rootfs::String, chroot_ENV::AbstractDict, arch::String;
                      version::String = DEFAULT_RUST_VERSION)
    target = rust_target(arch)
    my_chroot(args...) = root_chroot(rootfs, "bash", "-eu", "-o", "pipefail", "-c", args...; ENV=chroot_ENV)
    my_chroot("""
    tarball="rust-$(version)-$(target).tar.gz"
    curl -fsSL "https://static.rust-lang.org/dist/\${tarball}" -o "/tmp/\${tarball}"
    mkdir -p /tmp/rust-install
    tar -C /tmp/rust-install --strip-components=1 -xf "/tmp/\${tarball}"
    /tmp/rust-install/install.sh \\
        --prefix=/usr/local \\
        --components=rustc,cargo,rust-std-$(target)
    rm -rf /tmp/rust-install "/tmp/\${tarball}"
    """)

    # Print the installed versions, and fail the image build if `rustc`/`cargo`
    # are broken or the wrong version landed on the PATH.
    my_chroot("rustc --version")
    my_chroot("cargo --version")
end
