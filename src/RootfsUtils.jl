module RootfsUtils

using ArgParse: ArgParse
using Base.BinaryPlatforms
using Dates
using Pkg
using Pkg.Artifacts
using SHA
using Scratch
using Test
using ghr_jll

export AlpinePackage
export alpine_bootstrap
export chroot
export debootstrap
export parse_build_args
export test_sandbox
export upload_rootfs_image_github_actions

include("types.jl")

include("build/alpine.jl")
include("build/args.jl")
include("build/common.jl")
include("build/debian.jl")
include("build/utils.jl")

include("run/args.jl")
include("run/test.jl")

end # module
