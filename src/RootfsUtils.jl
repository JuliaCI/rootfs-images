module RootfsUtils

import ArgParse
import Dates
import Pkg
import SHA
import Sandbox
import Scratch
import Test
import ghr_jll

using Test: @test, @testset

# @public AlpinePackage
# @public alpine_bootstrap
# @public chroot
# @public debootstrap
# @public ensure_artifact_exists_locally
# @public parse_build_args
# @public parse_test_args
# @public test_sandbox
# @public upload_gha

include("types.jl")

include("build_img/alpine.jl")
include("build_img/args.jl")
include("build_img/common.jl")
include("build_img/debian.jl")

include("test_img/args.jl")
include("test_img/test.jl")

include("utils/args.jl")
include("utils/chroot.jl")

end # module
