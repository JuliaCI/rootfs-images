using RootfsUtils: parse_build_args, debootstrap, chroot, upload_gha, test_sandbox

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

packages = String[]
locale = false

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages, locale)
upload_gha(tarball_path)
test_sandbox(artifact_hash)
