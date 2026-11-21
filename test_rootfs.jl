# Run a command (by default, a shell) in a rootfs image: a Linux image as the root of a sandbox
# (on Linux), or a Windows toolchain in the environment CI's job wrapper sets up (on Windows).
# See the README, or `julia --project test_rootfs.jl --help`.

using Pkg.Artifacts: artifact_path
using RootfsUtils: parse_test_args, ensure_artifact_exists_locally, ensure_image_installed,
                   toolchain_cmd, _create_temp_directory
using Sandbox: Sandbox, SandboxConfig, with_executor

args            = parse_test_args(ARGS, @__FILE__)
command         = args.command
mount_julia     = args.mount_julia
multiarch       = args.multiarch
read_write_maps = args.read_write_maps
tmpfs_size      = args.tmpfs_size
working_dir     = args.working_dir
run_as_root     = args.run_as_root

if args.image !== nothing
    treehash = ensure_image_installed(args.image)
else
    treehash = args.treehash
    # If the artifact is not locally existent, download it
    ensure_artifact_exists_locally(; treehash, url=args.url)
end
root = artifact_path(treehash)

if isfile(joinpath(root, "toolchain.env"))
    # A Windows toolchain. Julia is a native process, so the tree's bash keeps the environment
    # (CI needs a PowerShell hop to leave Git for Windows' bash); HOME and the temporary
    # directory stay outside the tree, so that it is not modified.
    if !Sys.iswindows()
        error("This is a Windows toolchain, which runs on Windows. To use it in a Windows VM, ",
              "make a disk of it with sandboxed-buildkite-agent's platforms/windows-kvm/ntfsdisk.sh ",
              "($(root)) and attach it; see the README.")
    end
    repo_temp = joinpath(@__DIR__, "temp")
    home = mkpath(joinpath(repo_temp, "home"))
    tmp = get(read_write_maps, "/tmp", nothing)
    tmp === nothing && (tmp = _create_temp_directory(; parent = repo_temp))
    dir = working_dir == "/build" ? read_write_maps["/build"] : pwd()
    cmd = Cmd(toolchain_cmd(root, command; home, tmp); dir)
    exit(something(run(ignorestatus(cmd)).exitcode, 1))
end

Sys.islinux() || error("Linux images run in a Linux sandbox")
isempty(command) && push!(command, "/bin/bash")

read_only_maps = Dict{String, String}()
read_only_maps["/"] = root

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

uid = Sandbox.getuid()
gid = Sandbox.getgid()
if run_as_root
    uid = 0
    gid = 0
end

config = SandboxConfig(
    read_only_maps,
    read_write_maps,
    environment_variables;
    stdin,
    stdout,
    stderr,
    multiarch,
    tmpfs_size,
    uid,
    gid,
    pwd = working_dir,
)

with_executor() do exe
    run(exe, config, `$(command)`)
end
