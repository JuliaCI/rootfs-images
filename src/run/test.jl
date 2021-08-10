function test_sandbox(artifact_hash)
    test_cmd = `$(Base.julia_cmd())`
    push!(test_cmd.exec, "--project=$(Base.active_project())")
    push!(test_cmd.exec, joinpath(dirname(dirname(@__DIR__)), "test_rootfs.jl"))
    push!(test_cmd.exec, "")
    push!(test_cmd.exec, "$(artifact_hash)")
    push!(test_cmd.exec, "/bin/bash")
    push!(test_cmd.exec, "-c")
    push!(test_cmd.exec, "echo Hello from inside the sandbox")
    @testset "Test sandbox" begin
        @testset begin
            run(test_cmd)
        end
        @testset begin
            @test success(test_cmd)
            @test read(test_cmd, String) == "Hello from inside the sandbox\n"
        end
    end
    return nothing
end
