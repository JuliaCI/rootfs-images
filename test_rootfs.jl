using Pkg.Artifacts: artifact_path
using RootfsUtils: parse_test_args, ensure_artifact_exists_locally
using Sandbox: Sandbox, SandboxConfig, with_executor

args            = parse_test_args(ARGS, @__FILE__)
command         = args.command
mount_julia     = args.mount_julia
multiarch       = args.multiarch
read_write_maps = args.read_write_maps
tmpfs_size      = args.tmpfs_size
treehash        = args.treehash
url             = args.url
working_dir     = args.working_dir

# If the artifact is not locally existent, download it
ensure_artifact_exists_locally(; treehash, url)

read_only_maps = Dict{String, String}()
read_only_maps["/"] = artifact_path(treehash)

path_list = String[
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
]

if mount_julia
    read_only_maps["/opt/julia/"] = dirname(abspath(Sys.BINDIR))
    pushfirst!(path_list, "/opt/julia/bin")
end

environment_variables = Dict{String, String}()
environment_variables["PATH"] = join(path_list, ":")
environment_variables["HOME"] = "/home/juliaci"
environment_variables["USER"] = "juliaci"

config = SandboxConfig(
    read_only_maps,
    read_write_maps,
    environment_variables;
    stdin,
    stdout,
    stderr,
    multiarch,
    tmpfs_size,
    pwd        = working_dir,
    uid        = 0,
    gid        = 0,
)

with_executor() do exe
    run(exe, config, command)
end
