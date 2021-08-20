using Base.BinaryPlatforms
using Pkg.Artifacts
using RootfsUtils
using Sandbox

arch, command, treehash, url, = parse_test_args(ARGS, @__FILE__)

# If the artifact is not locally existent, download it
ensure_artifact_exists_locally(; treehash, url)

multiarch = Platform[]
if arch !== nothing
    push!(multiarch, Platform(arch, "linux"; libc="glibc"))
end

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
    multiarch,
)

with_executor() do exe
    run(exe, config, command)
end
