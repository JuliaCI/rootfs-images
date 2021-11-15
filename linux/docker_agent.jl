using RootfsUtils: parse_build_args, debootstrap, chroot, upload_gha, test_sandbox

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

@info arch
# Build debian-based image with the following extra packages:
packages = [
    "bash",
    "curl",
    "locales",
    "vim",
    "keychain",
    "git",
    "procps",
    "build-essential",    
    "apt-transport-https" ,
    "curl" ,
    "gnupg-agent",
    "gnupg",
    "software-properties-common",
    "unzip",
]

artifact_hash, tarball_path = debootstrap(arch, image; archive, packages) do rootfs, chroot_ENV
    my_chroot(args...) = chroot(args...; ENV=chroot_ENV, uid=0, gid=0)

    @info("Installing AWS cli v2...")
    awscliv2_install_cmd = """
    cd /usr/bin
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    """
    my_chroot(rootfs, "bash", "-c", awscliv2_install_cmd)

    @info("Installing docker...")
    docker_install_cmd = """
    # Enter the location we want to write files out to
    cd /usr/bin
    # Download tarball, piping it directly into `tar`, and tell `tar` to only extract one file, stripping one element of its path name:
    curl -L https://download.docker.com/linux/static/stable/x86_64/docker-20.10.10.tgz | tar -zxv --strip-components=1 docker/docker    """
    my_chroot(rootfs, "bash", "-c", docker_install_cmd)
end
upload_gha(tarball_path)
test_sandbox(artifact_hash)