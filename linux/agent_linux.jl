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
    "iproute2",
    "jq",
    "locales",
    "localepurge",
    "openssh-client",
    "openssl",
    "python3",
    "vim",
    "wget",
    "zstd",
]

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages) do rootfs, chroot_ENV
    my_chroot(args...) = root_chroot(rootfs, "bash", "-eu", "-o", "pipefail", "-c", args...; ENV=chroot_ENV)

    apt_update_and_upgrade = () -> begin
        my_chroot("DEBIAN_FRONTEND=noninteractive apt update")
        my_chroot("DEBIAN_FRONTEND=noninteractive apt upgrade -y")
    end
    apt_update_and_upgrade()

    @info("Installing yq...")
    yq_install_cmd = """
    mkdir /tmp-install-yq && \\
    cd /tmp-install-yq && \\
    wget https://github.com/mikefarah/yq/releases/download/v4.13.4/yq_linux_amd64.tar.gz -O - | tar xzv && mv yq_linux_amd64 /usr/bin/yq && \\
    cd / && \\
    rm -rfv /tmp-install-yq
    """
    my_chroot(yq_install_cmd)

    apt_update_and_upgrade()

    my_chroot("which yq")
    my_chroot("which -a yq")
    my_chroot("yq --version")
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
