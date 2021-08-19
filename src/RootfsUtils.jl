module RootfsUtils

using ArgParse: ArgParse
using Base.BinaryPlatforms
using Dates
using Pkg
using Pkg.Artifacts
using SHA
using Sandbox
using Scratch
using Test
using ghr_jll

export AlpinePackage
export alpine_bootstrap
export chroot
export debootstrap
export ensure_artifact_exists_locally
export parse_build_args
export parse_test_args
export test_sandbox
export upload_rootfs_image_github_actions

include("types.jl")

include("build/alpine.jl")
include("build/args.jl")
include("build/common.jl")
include("build/debian.jl")

include("test_and_run/args.jl")
include("test_and_run/test.jl")

include("utils/args.jl")
include("utils/chroot.jl")

end # module
