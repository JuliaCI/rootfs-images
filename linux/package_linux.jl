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

    # Install GCC 9, specifically
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
    my_chroot("which gcc")
    my_chroot("which -a gcc")
    my_chroot("which g++")
    my_chroot("which -a g++")
    my_chroot("which gfortran")
    my_chroot("which -a gfortran")
    my_chroot("gcc --version")
    my_chroot("g++ --version")
    my_chroot("gfortran --version")
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
