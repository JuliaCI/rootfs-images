using Pkg.Artifacts: artifact_path
using RootfsUtils: parse_test_args, ensure_artifact_exists_locally
using Sandbox: Sandbox, SandboxConfig, with_executor

args            = parse_test_args(ARGS, @__FILE__)
command         = args.command
multiarch       = args.multiarch
read_write_maps = args.read_write_maps
tmpfs_size      = args.tmpfs_size
treehash        = args.treehash
url             = args.url
working_dir     = args.working_dir

# If the artifact is not locally existent, download it
ensure_artifact_exists_locally(; treehash, url)

config = SandboxConfig(
    Dict("/" => artifact_path(treehash)), # read-only maps
    read_write_maps,
    Dict(   # environment variables
        "PATH" => "/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin",
        "HOME" => "/home/juliaci",
        "USER" => "juliaci",
    );
    stdin,
    stdout,
    stderr,
    multiarch,
    tmpfs_size,
    pwd        = working_dir,
    uid        = Sandbox.getuid(),
    gid        = Sandbox.getgid(),
)

with_executor() do exe
    run(exe, config, command)
end
