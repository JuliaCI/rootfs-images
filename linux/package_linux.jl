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
    "m4",
    "make",
    "patch",
    "perl",
    "pkg-config",
    "python",
    "python3",
    "vim",
    "wget",
]

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages) do rootfs, chroot_ENV
    my_chroot(args...) = root_chroot(rootfs, "bash", "-c", args...; ENV=chroot_ENV)

    host_triplet = "$(arch)-linux-gnu"
    glibc_version_dict = Dict(
        "x86_64" => v"2.12.2",
        "i686" => v"2.12.2",
        "aarch64" => v"2.19",
        "armv7l" => v"2.19",
        "powerpc64le" => v"2.17",
    )
    target_subdir = replace(host_triplet, "armv7l" => "arm")
    # Install GCC 9 from Elliot's repo
    repo_release_url = "https://github.com/staticfloat/linux-gcc-toolchains/releases/download/GCC-v9.1.0-$(host_triplet)"
    gcc_install_cmd = """
    cd /usr/local
    curl -L $(repo_release_url)/GCC.v9.1.0.$(host_triplet)-target_libc+glibc-target_os+linux-target_arch+$(arch).tar.gz | tar zx
    curl -L $(repo_release_url)/Binutils.v2.38.0.$(host_triplet)-target_libc+glibc-target_os+linux-target_arch+$(arch).tar.gz | tar zx
    curl -L $(repo_release_url)/Zlib.v1.2.12.$(host_triplet).tar.gz | tar zx
    cd /usr/local/$(target_subdir)/
    curl -L $(repo_release_url)/Glibc.$(glibc_version_dict[arch]).$(host_triplet).tar.gz | tar zx
    cd /usr/local/$(target_subdir)/usr
    curl -L $(repo_release_url)/LinuxKernelHeaders.v5.15.14.$(host_triplet)-host+any.tar.gz | tar zx
    """
    gcc_symlink_cmd = """
    # Create symlinks for `gcc` -> `$(host_triplet)-gcc`, etc...
    for tool_path in /usr/local/bin/$(host_triplet)-*; do
        tool="\$(basename "\${tool_path}" | sed -e 's/$(host_triplet)-//')"
        ln -sf "$(host_triplet)-\${tool}" "/usr/local/bin/\${tool}"
    done
    """
    my_chroot(gcc_install_cmd)
    my_chroot(gcc_symlink_cmd)
    libstdcxx_replace_cmd = """
    # Copy g++'s libstdc++.so over the system-wide one,
    # so that we can run things built by our g++
    cp -fv /usr/local/$(host_triplet)/lib*/libstdc++*.so* /lib/*-linux-*/
    """
    my_chroot(libstdcxx_replace_cmd)
    
    # Show what is installed
    my_chroot("which gcc")
    my_chroot("which -a gcc")
    my_chroot("which g++")
    my_chroot("which -a g++")

    # We're not going to even install gfortran anymore :)
    #my_chroot("which gfortran")
    #my_chroot("which -a gfortran")
    #my_chroot("gfortran --version")
    my_chroot("gcc --version")
    my_chroot("g++ --version")
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
