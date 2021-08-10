using Pkg.Artifacts
using RootfsUtils
using Sandbox

command, treehash, url, = parse_test_args(ARGS, @__FILE__)

# If the artifact is not locally existent, download it
ensure_artifact_exists_locally(; treehash, url)

config = SandboxConfig(
    Dict("/" => artifact_path(treehash)),
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
    run(exe, config, command)
end
