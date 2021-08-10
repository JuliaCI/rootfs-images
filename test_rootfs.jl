#!/usr/bin/env julia
using Sandbox, Pkg.Artifacts

usage_msg = "Usage: $(basename(@__FILE__)) <url> [gitsha] [command...]"

isempty(ARGS) && throw(ArgumentError(usage_msg))

url = strip(popfirst!(ARGS))
if isempty(url)
    url = nothing
end
if isempty(ARGS)
    @warn("hash not provided; this will download the tarball, then fail, so you can see the true hash")
    hash = Base.SHA1("0000000000000000000000000000000000000000")
else
    hash = Base.SHA1(strip(popfirst!(ARGS)))
end
if isempty(ARGS)
    cmd = `/bin/bash`
else
    cmd = `$ARGS`
end

# If the artifact is not locally existent, download it
if !artifact_exists(hash)
    @info("Artifact did not exist, downloading")
    url === nothing && throw(ArgumentError(usage_msg))
    was_success = download_artifact(hash, url; verbose=true)
    was_success || throw(ErrorException("Download was not a success"))
end

config = SandboxConfig(
    Dict("/" => artifact_path(hash)),
    Dict{String,String}(),
    Dict(
        "PATH" => "/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin",
        "HOME" => "/home/juliaci",
        "USER" => "juliaci",
    );
    stdin,
    stdout,
    stderr,
    uid=Sandbox.getuid(),
    gid=Sandbox.getgid(),
)

with_executor() do exe
    run(exe, config, cmd)
end
