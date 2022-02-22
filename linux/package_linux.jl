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

    if arch == "x86_64"
        host_triplet = "x86_64-linux-gnu"
        # Install GCC 9 from Elliot's repo
        repo_release_url = "https://github.com/staticfloat/linux-gcc-toolchains/releases/download/GCC-v9.1.0-x86_64-linux-gnu"
        gcc_install_cmd = """
        cd /usr/local
        curl -L $(repo_release_url)/GCC.v9.1.0.$(host_triplet)-target_libc+glibc-target_os+linux-target_arch+x86_64.tar.gz | tar zx
        curl -L $(repo_release_url)/Binutils.v2.24.0.$(host_triplet)-target_libc+glibc-target_os+linux-target_arch+x86_64.tar.gz | tar zx
        curl -L $(repo_release_url)/Zlib.v1.2.12.$(host_triplet).tar.gz | tar zx
        cd /usr/local/$(host_triplet)/
        curl -L $(repo_release_url)/Glibc.v2.12.2.$(host_triplet).tar.gz | tar zx
        curl -L $(repo_release_url)/LinuxKernelHeaders.v5.15.14.x86_64-linux-target_os+linux-target_arch+x86_64.tar.gz | tar zx
        """
        gcc_symlink_cmd = """
        # Create symlinks for `gcc` -> `x86_64-linux-gnu-gcc`, etc...
        for tool_path in /usr/local/bin/$(host_triplet)-*; do
            tool="\$(basename "\${tool_path}" | sed -e 's/$(host_triplet)-//')"
            ln -sf "$(host_triplet)-\${tool}" "/usr/local/bin/\${tool}"
        done
        """
        my_chroot(gcc_install_cmd)
        my_chroot(gcc_symlink_cmd)
    else
        # Install GCC 9 from apt
        @info("Installing gcc-9")
        gcc_install_cmd = """
        echo 'deb http://deb.debian.org/debian stable main' >> /etc/apt/sources.list && \\
        apt-get update && \\
        DEBIAN_FRONTEND=noninteractive apt-get install -y gcc-9 g++-9 gfortran-9
        """
        gcc_symlink_cmd = """
        # Create symlinks for `gcc` -> `gcc-9`, etc...
        for tool_path in /usr/bin/*-9; do
            tool="\$(basename "\${tool_path}" | sed -e 's/-9//')"
            ln -sf "\${tool}-9" "/usr/bin/\${tool}"
        done
        """
        my_chroot(gcc_install_cmd)
        my_chroot(gcc_symlink_cmd)
    end
    my_chroot("which gcc")
    my_chroot("which -a gcc")
    my_chroot("which g++")
    my_chroot("which -a g++")

    # We're not going to even install gfortran in some cases.  :)
    #my_chroot("which gfortran")
    #my_chroot("which -a gfortran")
    #my_chroot("gfortran --version")
    my_chroot("gcc --version")
    my_chroot("g++ --version")
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
