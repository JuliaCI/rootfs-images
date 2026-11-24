function test_sandbox(artifact_hash)
    test_cmd = `$(Base.julia_cmd())`
    append!(test_cmd.exec, String[
        "--project=$(Base.active_project())",
        joinpath(dirname(dirname(@__DIR__)), "test_rootfs.jl"),
        "--map-build-dir=temp",
        "--treehash=$(artifact_hash)",
        "--",
        "/bin/bash", "-c", "echo Hello from inside the sandbox",
    ])
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

function ensure_artifact_exists_locally(; treehash, url)
    if !Pkg.Artifacts.artifact_exists(treehash)
        if url === nothing
            error_msg = "The artifact does not exist locally, so you must provide the URL."
            throw(ArgumentError(error_msg))
        end
        @info("Artifact did not exist locally, downloading")
        return_value = Pkg.Artifacts.download_artifact(treehash, url; verbose=true)
        if return_value === true
            @debug "Download was a success"
        else
            @debug "The return value from `download_artifact` was not `true`" return_value
            if !(return_value isa Bool)
                throw(return_value)
            end
            throw(ErrorException("Download was not a success"))
        end
    end
    Pkg.Artifacts.artifact_exists(treehash) || throw(ErrorException("Could not download the artifact"))
    return nothing
end

"""
    ensure_image_installed(name) -> Base.SHA1

Install the image `name` (`IMAGE.ARCH`) as listed in this checkout's
`RootfsImages/Artifacts.toml` (the latest release), which needs no registered version of
RootfsImages: Pkg fetches it from the Pkg server by tree hash, or else from the release URL, and
checks the tree hash.
"""
function ensure_image_installed(name::String)
    artifacts_toml = joinpath(dirname(dirname(@__DIR__)), "RootfsImages", "Artifacts.toml")
    treehash = Pkg.Artifacts.artifact_hash(name, artifacts_toml)
    if treehash === nothing
        known = sort(collect(keys(Pkg.TOML.parsefile(artifacts_toml))))
        throw(ArgumentError("$(name) is not in $(artifacts_toml), which lists the latest release only: " *
                            "$(join(known, ", ")). Run an image of another release with " *
                            "--url URL --treehash HASH."))
    end
    Pkg.Artifacts.ensure_artifact_installed(name, artifacts_toml)
    return treehash
end
