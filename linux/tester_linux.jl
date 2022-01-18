using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap, root_chroot

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

packages = [
    "bash",
    "curl",
    "gdb",
    "lldb",
    "locales",
    "vim",
]

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages) do rootfs, chroot_ENV
    my_chroot(args...) = root_chroot(args...; ENV=chroot_ENV)

    my_chroot(rootfs, "bash", "-c", "git --version")
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
