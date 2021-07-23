## This rootfs includes just enough of the tools for our buildkite agent
## to run inside of.  Most CI steps will be run within a different image
## nested inside of this one.

include(joinpath(dirname(@__DIR__), "rootfs_utils.jl"))

# Build debian-based image with the following extra packages:
packages = [
    # General package getting/installing packages
    "apt-transport-https",
    "curl",
    "gnupg2",
    "openssh-client",
    "wget",
    # We use these in our buildkite plugins a lot
    "git",
    "jq",
    "openssl",
    "python3",
    # Debugging
    "vim",
]
tarball_path = debootstrap("buildkite_agent"; packages) do rootfs
    # Also download buildkite-agent
    @info("Installing buildkite-agent...")
    buildkite_install_cmd = """
    echo 'deb https://apt.buildkite.com/buildkite-agent stable main' >> /etc/apt/sources.list && \\
    curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x32A37959C2FA5C3C99EFBC32A79206696452D198" | apt-key add - && \\
    apt-get update && \\
    DEBIAN_FRONTEND=noninteractive apt-get install -y buildkite-agent
    """
    chroot(rootfs, "bash", "-c", buildkite_install_cmd; uid=0, gid=0)
end

# Upload it
upload_rootfs_image_github_actions(tarball_path)
