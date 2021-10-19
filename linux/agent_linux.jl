using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap
using RootfsUtils: root_chroot

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

packages = [
    "apt-transport-https",
    "curl",
    "git",
    "gnupg2",
    "jq",
    "locales",
    "openssh-client",
    "openssl",
    "python3",
    "vim",
    "wget",
]

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages) do rootfs, chroot_ENV
    my_chroot(args...) = root_chroot(args...; ENV=chroot_ENV)

    @info("Installing buildkite-agent...")
    buildkite_install_cmd = """
    echo 'deb https://apt.buildkite.com/buildkite-agent stable main' >> /etc/apt/sources.list && \\
    curl -sfL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x32A37959C2FA5C3C99EFBC32A79206696452D198" | apt-key add - && \\
    apt-get update && \\
    DEBIAN_FRONTEND=noninteractive apt-get install -y buildkite-agent
    """
    my_chroot(rootfs, "bash", "-c", buildkite_install_cmd)
    my_chroot(rootfs, "bash", "-c", "which buildkite-agent")
    my_chroot(rootfs, "bash", "-c", "which -a buildkite-agent")
    my_chroot(rootfs, "bash", "-c", "buildkite-agent --help")

    @info("Installing yq...")
    yq_install_cmd = """
    mkdir /tmp-install-yq && \\
    cd /tmp-install-yq && \\
    wget https://github.com/mikefarah/yq/releases/download/v4.13.4/yq_linux_amd64.tar.gz -O - | tar xzv && mv yq_linux_amd64 /usr/bin/yq && \\
    cd / && \\
    rm -rfv /tmp-install-yq
    """
    my_chroot(rootfs, "bash", "-c", yq_install_cmd)
    my_chroot(rootfs, "bash", "-c", "which yq")
    my_chroot(rootfs, "bash", "-c", "which -a yq")
    my_chroot(rootfs, "bash", "-c", "yq --version")
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
