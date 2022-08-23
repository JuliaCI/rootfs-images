using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap
using RootfsUtils: root_chroot

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
    "python",
    "python3",
    "vim",
    "wget",
]

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages) do rootfs, chroot_ENV
    my_chroot(args...) = root_chroot(rootfs, "bash", "-eu", "-o", "pipefail", "-c", args...; ENV=chroot_ENV)

    host_triplet = "$(arch)-linux-gnu"
    gcc_triplet = host_triplet
    cross_tags = "target_libc+glibc-target_os+linux-target_arch+$(arch)"
    if arch == "armv7l"
        host_triplet = "armv7l-linux-gnueabihf"
        gcc_triplet = "arm-linux-gnueabihf"
        cross_tags = "target_libc+glibc-target_os+linux-target_call_abi+eabihf-target_arch+$(arch)"
    end
    glibc_version_dict = Dict(
        "x86_64" => v"2.12.2",
        "i686" => v"2.12.2",
        "aarch64" => v"2.19",
        "armv7l" => v"2.19",
        "powerpc64le" => v"2.19",
    )

    # Install GCC 9 from Elliot's repo
    repo_release_url = "https://github.com/staticfloat/linux-gcc-toolchains/releases/download/GCC-v9.1.0-$(host_triplet)"
    gcc_install_cmd = """
    cd /usr/local
    curl -fL $(repo_release_url)/GCC.v9.1.0.$(host_triplet)-$(cross_tags).tar.gz | tar zx
    curl -fL $(repo_release_url)/Binutils.v2.38.0.$(host_triplet)-$(cross_tags).tar.gz | tar zx
    curl -fL $(repo_release_url)/Zlib.v1.2.12.$(host_triplet).tar.gz | tar zx
    cd /usr/local/$(gcc_triplet)/
    curl -fL $(repo_release_url)/Glibc.v$(glibc_version_dict[arch]).$(host_triplet).tar.gz | tar zx
    cd /usr/local/$(gcc_triplet)/usr
    curl -fL $(repo_release_url)/LinuxKernelHeaders.v5.15.14.$(host_triplet)-host+any.tar.gz | tar zx
    """
    gcc_symlink_cmd = """
    # Create symlinks for `gcc` -> `$(gcc_triplet)-gcc`, etc...
    for tool_path in /usr/local/bin/$(gcc_triplet)-*; do
        tool="\$(basename "\${tool_path}" | sed -e 's/$(gcc_triplet)-//')"
        ln -vsf "$(gcc_triplet)-\${tool}" "/usr/local/bin/\${tool}"
    done
    # Also create symlinks for `cc` and `c++`.
    ln -vsf "/usr/local/bin/gcc" "/usr/local/bin/cc"
    ln -vsf "/usr/local/bin/g++" "/usr/local/bin/c++"
    """
    my_chroot(gcc_install_cmd)
    my_chroot(gcc_symlink_cmd)
    libstdcxx_replace_cmd = """
    # Copy g++'s libstdc++.so over the system-wide one,
    # so that we can run things built by our g++
    cp -fv /usr/local/$(gcc_triplet)/lib*/libstdc++*.so* /lib/*-linux-*/
    """
    my_chroot(libstdcxx_replace_cmd)

    # Show what is installed
    my_chroot("which gcc")
    my_chroot("which -a gcc")
    my_chroot("which g++")
    my_chroot("which -a g++")

    my_chroot("gcc --version")
    my_chroot("g++ --version")
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
