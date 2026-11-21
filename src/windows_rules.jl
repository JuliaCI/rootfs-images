# Rules for Windows toolchain trees (`package_windows.<arch>`): the layout every consumer relies
# on, the `toolchain.env` format, and checks on a tarball's headers. Only uses the Tar standard
# library, so `RootfsImages/add_images.jl` can include it without an environment.
#
# A tree holds `msys64/`, optionally `gcc/`, `toolchain.env` and `toolchain.json`. Consumers use
# it in three ways: extracted by Pkg on native Windows, converted into an NTFS disk for a KVM
# guest, or listed in RootfsImages. Hence:
# - every file is 0755: on Windows, Tar.jl turns the mode into an ACL, and a 0644 `.exe` can't be
#   run ("Access is denied"). Pkg's tree hash on Windows also derives the mode from
#   `Sys.isexecutable`, so only "all files executable" hashes the same everywhere;
# - only files and directories: no symlinks (Windows needs privileges to create them, and Pkg
#   copies them instead, which changes nothing in the hash but is brittle), no hard links (the
#   builders materialize them), no special files;
# - names must be valid and distinct on NTFS (case-insensitive), and paths short enough to leave
#   room for the prefix a consumer installs the tree under (the Pkg depot, `T:\`).

const WINDOWS_TREE_TOP_LEVEL = ("msys64", "gcc", "toolchain.env", "toolchain.json")
const WINDOWS_TREE_REQUIRED = ("msys64", "toolchain.env", "toolchain.json")

# Relative to the tree root, with `/` separators (as in a tarball)
const WINDOWS_TREE_MAX_PATH = 200

const TOOLCHAIN_ENV_KEYS = ("PATH_PREPEND", "MSYSTEM", "MSYS2_PATH_TYPE")
const TOOLCHAIN_MSYSTEMS = ("MSYS", "MINGW64", "MINGW32", "UCRT64", "CLANG64")

const NTFS_RESERVED_NAMES = Set(vcat(["CON", "PRN", "AUX", "NUL", "CONIN\$", "CONOUT\$"],
                                     ["COM$i" for i in 1:9], ["LPT$i" for i in 1:9]))

"""
    parse_toolchain_env(str) -> Dict{String,String}

Parse the contents of `toolchain.env`: `KEY=VALUE` lines (CRLF tolerated), every key of
`TOOLCHAIN_ENV_KEYS` exactly once, nothing else. `PATH_PREPEND` is a `;`-separated list of
directories relative to the tree root, with `\\` separators. Throws an `ArgumentError` on any
deviation, so that a consumer never guesses.
"""
function parse_toolchain_env(str::AbstractString)
    env = Dict{String,String}()
    for (lineno, line) in enumerate(split(str, '\n'))
        line = chomp(line)
        line = endswith(line, '\r') ? line[1:end-1] : line
        isempty(line) && continue
        bad(msg) = throw(ArgumentError("toolchain.env line $(lineno): $(msg): $(repr(line))"))
        key, sep, value = partition_eq(line)
        sep || bad("not KEY=VALUE")
        key in TOOLCHAIN_ENV_KEYS || bad("unknown key $(repr(key))")
        haskey(env, key) && bad("duplicate key $(repr(key))")
        isempty(value) && bad("empty value")
        env[key] = value
    end
    for key in TOOLCHAIN_ENV_KEYS
        haskey(env, key) || throw(ArgumentError("toolchain.env: missing key $(key)"))
    end
    env["MSYSTEM"] in TOOLCHAIN_MSYSTEMS ||
        throw(ArgumentError("toolchain.env: unknown MSYSTEM $(repr(env["MSYSTEM"]))"))
    env["MSYS2_PATH_TYPE"] == "inherit" ||
        throw(ArgumentError("toolchain.env: MSYS2_PATH_TYPE must be inherit (a login shell drops PATH entries otherwise)"))
    toolchain_path_entries(env)  # validates PATH_PREPEND
    return env
end

function partition_eq(line)
    i = findfirst('=', line)
    i === nothing && return (line, false, "")
    return (String(line[1:prevind(line, i)]), true, String(line[nextind(line, i):end]))
end

"""
    toolchain_path_entries(env) -> Vector{String}

The `PATH_PREPEND` entries of a parsed `toolchain.env`, as relative paths with `/` separators.
"""
function toolchain_path_entries(env::AbstractDict)
    entries = split(env["PATH_PREPEND"], ';')
    map(entries) do entry
        parts = split(entry, '\\')
        if isempty(entry) || any(p -> isempty(p) || p in (".", "..") || occursin(r"[/:]", p), parts)
            throw(ArgumentError("toolchain.env: PATH_PREPEND entry $(repr(entry)) is not a relative directory with `\\` separators"))
        end
        join(parts, '/')
    end
end

"""
    render_toolchain_env(; path_prepend, msystem) -> String

The contents of `toolchain.env` for the given `PATH_PREPEND` entries (relative, `/` or `\\`
separators) and `MSYSTEM`. Round-trips through `parse_toolchain_env`.
"""
function render_toolchain_env(; path_prepend::AbstractVector{<:AbstractString}, msystem::AbstractString)
    entries = [replace(entry, '/' => '\\') for entry in path_prepend]
    str = """
    PATH_PREPEND=$(join(entries, ';'))
    MSYSTEM=$(msystem)
    MSYS2_PATH_TYPE=inherit
    """
    parse_toolchain_env(str)
    return str
end

# Why a single path component is invalid on NTFS (or as a Windows path), or `nothing`
function ntfs_name_problem(name::AbstractString)
    any(c -> c in "<>:\"|?*\\" || c < ' ', name) && return "invalid character"
    (endswith(name, '.') || endswith(name, ' ')) && return "trailing dot or space"
    stem = uppercase(first(split(name, '.')))
    stem in NTFS_RESERVED_NAMES && return "reserved name"
    return nothing
end

"""
    WindowsTreeCheck(; strict_paths=true)

Accumulates the problems of a Windows toolchain tree, one tarball header at a time
(`check_header!`), then for the tree as a whole (`finish!`). Paths longer than
`WINDOWS_TREE_MAX_PATH` are errors when `strict_paths`, warnings otherwise (converted trees keep
what the Docker images had).
"""
mutable struct WindowsTreeCheck
    strict_paths::Bool
    errors::Vector{String}
    warnings::Vector{String}
    folded::Dict{String,String}    # lowercase path => path
    dirs::Set{String}
    top::Set{String}
end
WindowsTreeCheck(; strict_paths::Bool=true) =
    WindowsTreeCheck(strict_paths, String[], String[], Dict{String,String}(), Set{String}(), Set{String}())

function check_header!(c::WindowsTreeCheck, hdr)
    path = rstrip(hdr.path, '/')
    path in ("", ".") && return true
    err(msg) = push!(c.errors, "$(path): $(msg)")
    if hdr.type == :file
        hdr.mode == 0o755 || err("file mode is $(string(hdr.mode, base=8)), must be 755")
    elseif hdr.type == :directory
        push!(c.dirs, path)
    else
        err("$(hdr.type) entries are not allowed (only files and directories)")
    end
    parts = split(path, '/')
    push!(c.top, first(parts))
    for part in parts
        problem = ntfs_name_problem(part)
        problem === nothing || err("$(problem) in $(repr(part))")
    end
    if length(path) > WINDOWS_TREE_MAX_PATH
        msg = "$(path): longer than $(WINDOWS_TREE_MAX_PATH) characters"
        push!(c.strict_paths ? c.errors : c.warnings, msg)
    end
    folded = lowercase(path)
    other = get(c.folded, folded, nothing)
    if other !== nothing && other != path
        err("differs from $(other) only in case")
    end
    c.folded[folded] = path
    return true
end

# Checks that need the whole tree; `env_str` is the contents of `toolchain.env`, if present.
function finish!(c::WindowsTreeCheck, env_str::Union{Nothing,AbstractString})
    for name in c.top
        name in WINDOWS_TREE_TOP_LEVEL || push!(c.errors, "$(name): unexpected at the top level")
    end
    for name in WINDOWS_TREE_REQUIRED
        name in c.top || push!(c.errors, "$(name): missing")
    end
    if env_str !== nothing
        try
            env = parse_toolchain_env(env_str)
            for entry in toolchain_path_entries(env)
                entry in c.dirs || push!(c.errors, "toolchain.env: PATH_PREPEND entry $(entry) is not a directory of the tree")
            end
        catch e
            e isa ArgumentError || rethrow()
            push!(c.errors, e.msg)
        end
    end
    return c
end

"""
    check_windows_tarball(tar_cmd_or_path; strict_paths=true) -> (; tree_hash, errors, warnings)

Check an uncompressed tar stream (a path, or a command that writes one to stdout, e.g.
`gzip -dc x.tar.gz`) against the rules above, and compute its git tree hash (`skip_empty=true`,
as Pkg) in the same pass.
"""
function check_windows_tarball(source; strict_paths::Bool=true)
    c = WindowsTreeCheck(; strict_paths)
    tree_hash = open(io -> Tar.tree_hash(hdr -> check_header!(c, hdr), io; skip_empty=true), source)
    env_str = mktempdir() do dir
        open(source) do io
            Tar.extract(hdr -> rstrip(hdr.path, '/') == "toolchain.env", io, dir)
        end
        env_path = joinpath(dir, "toolchain.env")
        isfile(env_path) ? read(env_path, String) : nothing
    end
    finish!(c, env_str)
    return (; tree_hash, errors=c.errors, warnings=c.warnings)
end
