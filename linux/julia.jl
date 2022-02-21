using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap
using RootfsUtils: root_chroot

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

julia_version_number = v"1.7.2"

packages = [
    "build-essential",
    "bzip2",
    "cmake",
    "curl",
    "gfortran",
    "git",
    "less",
    "libatomic1",
    "locales",
    "m4",
    "perl",
    "pkg-config",
    "python",
    "python3",
    "wget",
]

julia_longarch_dict = Dict(
    "aarch64" => "aarch64",
    "armv7l"  => "",
    "i686"    => "i686",
    "x86_64"  => "x86_64",
)

julia_shortarch_dict = Dict(
    "aarch64" => "aarch64",
    "armv7l"  => "armv7l",
    "i686"    => "x86",
    "x86_64"  => "x64",
)

julia_longarch  = julia_longarch_dict[arch]
julia_shortarch = julia_shortarch_dict[arch]
julia_major = julia_version_number.major
julia_minor = julia_version_number.minor
julia_patch = julia_version_number.patch
julia_majmin = "$(julia_major).$(julia_minor)"
julia_version_str = "$(julia_major).$(julia_minor).$(julia_patch)"
julia_tarball = "julia-$(julia_version_str)-linux-$(julia_longarch).tar.gz"
julia_url = "https://julialang-s3.julialang.org/bin/linux/$(julia_shortarch)/$(julia_majmin)/$(julia_tarball)"

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages) do rootfs, chroot_ENV
    my_chroot(args...) = root_chroot(rootfs, "bash", "-c", args...; ENV=chroot_ENV)

    @info "Downloading Julia from: $(julia_url)"
    julia_install_cmd = """
    mkdir /tmp-install-julia && \\
    cd /tmp-install-julia && \\
    wget --no-verbose $(julia_url)
    tar xzf $(julia_tarball)
    rm $(julia_tarball)
    mv julia-$(julia_version_str) julia
    mkdir -p /opt
    mv julia /opt
    cd / && \\
    rm -rfv /tmp-install-julia
    """
    my_chroot(julia_install_cmd)
    my_chroot("mkdir -p /usr/local/bin")
    my_chroot("ln -s /opt/julia/bin/julia /usr/local/bin/julia")
    my_chroot("which julia")
    my_chroot("which -a julia")
    my_chroot("julia --version")
    my_chroot("julia -e 'import InteractiveUtils; InteractiveUtils.versioninfo()'")
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
