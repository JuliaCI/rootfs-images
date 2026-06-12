# Install the AWS CLI into a Debian-based rootfs.
#
# Julia's Buildkite pipelines obtain short-lived AWS credentials via
# Buildkite OIDC and upload build products to S3 directly from within the
# rootfs sandbox, using S3 conditional writes for write-once semantics
# (`aws s3api put-object --if-none-match '*'`). Conditional writes require
# a recent CLI: AWS CLI v2 >= 2.19, or AWS CLI v1 >= 1.36.
#
# AWS only publishes official AWS CLI v2 binaries for x86_64 and aarch64
# Linux, so on all other architectures we fall back to a pip-installed
# AWS CLI v1, which is pure Python and therefore works everywhere.
function install_awscli(rootfs::String, chroot_ENV::AbstractDict, arch::String)
    arch = normalize_arch(arch)
    env = copy(chroot_ENV)
    env["DEBIAN_FRONTEND"] = "noninteractive"
    my_chroot(args...) = root_chroot(rootfs, "bash", "-eu", "-o", "pipefail", "-c", args...; ENV=env)
    if arch in ("x86_64", "aarch64")
        # Install the official AWS CLI v2 binary distribution.
        my_chroot("""
        apt-get install -y unzip
        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(arch).zip" -o /tmp/awscliv2.zip
        unzip -q /tmp/awscliv2.zip -d /tmp/awscliv2
        /tmp/awscliv2/aws/install
        rm -rf /tmp/awscliv2 /tmp/awscliv2.zip
        """)
    else
        # No official AWS CLI v2 binaries exist for this architecture
        # (and Debian's `awscli` package is too old on bookworm), so
        # install the pure-Python AWS CLI v1 from PyPI instead.
        my_chroot("""
        apt-get install -y python3-pip
        pip3 install --break-system-packages "awscli>=1.36"
        """)
    end

    # Print the installed version, and fail the image build if `aws` is broken.
    my_chroot("aws --version")
end
