module RootfsUtils

import ArgParse
import Dates
import Pkg
import SHA
import Sandbox
import Scratch
import Tar
import Test
import ghr_jll

using Test: @test, @testset

include("types.jl")

include("build_img/alpine.jl")
include("build_img/args.jl")
include("build_img/awscli.jl")
include("build_img/archive.jl")
include("build_img/common.jl")
include("build_img/debian.jl")
include("build_img/gcc.jl")
include("build_img/rust.jl")
include("build_img/windows.jl")
include("build_img/windows_docker.jl")
include("windows_rules.jl")

include("test_img/args.jl")
include("test_img/test.jl")

include("utils/args.jl")
include("utils/chroot.jl")
include("utils/tmp.jl")

end # module
