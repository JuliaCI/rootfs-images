using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap
using RootfsUtils: root_chroot

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

packages = [
    "bash",
    "coreutils",
    "curl",
    "git",
    "locales",
    "localepurge",
    "make",
]

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages) do rootfs, chroot_ENV
    my_chroot(args...) = root_chroot(rootfs, "bash", "-eu", "-o", "pipefail", "-c", args...; ENV=chroot_ENV)

    additional_packages = String[
        "latexmk",
        "python3-pygments",
        "texlive-latex-base",
        "texlive-latex-extra",
        "texlive-latex-recommended",
        "texlive-luatex",
    ]
    additional_packages_string = join(additional_packages, " ")
    cmd = """
    set -Eeu -o pipefail
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $(additional_packages_string)
    rm -rf /var/lib/apt/lists/*
    """
    my_chroot(cmd)
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
