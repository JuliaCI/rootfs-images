# This image is a bit of an anomaly; we install pdflatex, python3.... pretty much the kitchen sink
# It is used by pipelines that use the SciML ecosystem such as the SciMLBenchmarks repository.

using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

packages = [
    "bash",
    "locales",
    "zip",
    "unzip",
    "zstd",

    # Work around bug in debootstrap where virtual dependencies are not properly installed
    # X-ref: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=878961
    # X-ref: https://bugs.launchpad.net/ubuntu/+source/debootstrap/+bug/86536
    "perl-openssl-defaults",
    "dbus-user-session",
    "python3-sip",


    # Get a C compiler, for compiling python extensions
    "build-essential",
    # Get latex, so that we can invoke `pdflatex` and friends
    "texlive-full",
    "pdf2svg",
    # Some of our packages require PyCall.jl/Conda.jl deps
    "python3",
    "liblapack3",

    # These are just for debugging
    "curl",
    "vim",
    "gdb",
    "lldb",
]

artifact_hash, tarball_path, = debootstrap(arch, image; archive, packages)
upload_gha(tarball_path)
test_sandbox(artifact_hash)
