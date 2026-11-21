# Building Windows toolchain trees (`package_windows.<arch>`): MSYS2 in `msys64/`, optionally a
# GCC in `gcc/`, and the `toolchain.env`/`toolchain.json` that describe them. The rules a tree
# must follow are in `../windows_rules.jl`; both builders (the native one in
# `windows/package_windows.jl` and the converter of published Docker images in
# `windows/convert_docker.jl`) go through `create_windows_toolchain`.

# State that a pacman run or a login shell leaves behind, relative to `msys64/`. The keyring
# (`etc/pacman.d/gnupg`) is per installation: a job that wants pacman runs `pacman-key --init`.
# `etc/mtab` is written by a login shell's post-install script; the non-login bash that CI and
# `test_rootfs.jl` start does not need it (bash, gcc, make and cmake work without it).
# `var/lib/pacman/local` stays: it is the inventory of installed packages.
const MSYS2_STRIP = ["etc/pacman.d/gnupg", "etc/mtab", "var/cache/pacman/pkg", "var/lib/pacman/sync"]
const MSYS2_EMPTY = ["var/log", "tmp", "home"]  # kept, but emptied

"""
    normalize_windows_tree!(root)

Bring a tree to the form `windows_rules.jl` requires: strip installation state from MSYS2,
replace hard links by copies, and make every file and directory 0755 (on Windows, Julia's
`chmod` sets the corresponding ACL).
"""
function normalize_windows_tree!(root::String)
    # A tree has no links (the rules reject them); refuse them before deleting anything, which
    # could otherwise happen through a link to elsewhere
    for (dir, dirs, files) in walkdir(root), name in vcat(dirs, files)
        path = joinpath(dir, name)
        islink(path) && error("Windows toolchain trees can't contain links: $(relpath(path, root)) -> $(readlink(path))")
    end
    msys64 = joinpath(root, "msys64")
    for rel in MSYS2_STRIP
        rm(joinpath(msys64, rel); recursive=true, force=true)
    end
    for rel in MSYS2_EMPTY
        dir = joinpath(msys64, rel)
        isdir(dir) || continue
        foreach(p -> rm(p; recursive=true, force=true), readdir(dir; join=true))
    end

    # Writable first: a file that is read-only on Windows can't be replaced
    chmod(root, 0o755; recursive=true)
    nlinks = 0
    for (dir, _, files) in walkdir(root), file in files
        path = joinpath(dir, file)
        if !islink(path) && stat(path).nlink > 1
            tmp = path * ".unlink-tmp"
            cp(path, tmp)
            mv(tmp, path; force=true)
            nlinks += 1
        end
    end
    nlinks > 0 && @info("Replaced hard links by copies", count=nlinks)
    chmod(root, 0o755; recursive=true)
    return root
end

"""
    msys2_packages(root) -> Vector{String}

The installed MSYS2 packages as `pacman -Q` prints them (`name version`), read from pacman's
local database so that it also works for a tree on Linux.
"""
function msys2_packages(root::String)
    localdb = joinpath(root, "msys64", "var", "lib", "pacman", "local")
    packages = String[]
    for entry in sort(readdir(localdb))
        desc = joinpath(localdb, entry, "desc")
        isfile(desc) || continue
        fields = Dict{String,String}()
        lines = readlines(desc)
        for (i, line) in enumerate(lines)
            if startswith(line, '%') && endswith(line, '%') && i < length(lines)
                fields[strip(line, '%')] = lines[i+1]
            end
        end
        push!(packages, "$(fields["NAME"]) $(fields["VERSION"])")
    end
    isempty(packages) && error("No packages in $(localdb)")
    return packages
end

json_string(s::AbstractString) = "\"" * escape_string(s, "\"") * "\""

"""
    write_toolchain_files(root; image, arch, tag, source, path_prepend, msystem)

Write `toolchain.env` (what the job wrapper and the local launcher read) and `toolchain.json`
(what a job log shows: which image this is and what is in it) at the root of the tree.
`source` says where the tree came from: a recipe commit, or a Docker image digest.
"""
function write_toolchain_files(root::String; image::String, arch::String, tag::String,
                               source::String, path_prepend::Vector{String}, msystem::String)
    env = render_toolchain_env(; path_prepend, msystem)
    write(joinpath(root, "toolchain.env"), env)
    packages = join(("    " * json_string(p) for p in msys2_packages(root)), ",\n")
    write(joinpath(root, "toolchain.json"), """
    {
      "image": $(json_string(image)),
      "arch": $(json_string(arch)),
      "tag": $(json_string(tag)),
      "source": $(json_string(source)),
      "msys2_packages": [
    $(packages)
      ]
    }
    """)
    return nothing
end

"""
    check_windows_tree(root; strict_paths=true)

Check a tree against `windows_rules.jl` by way of the tar stream `Tar.create` makes of it (the
same headers the published tarball will have), and throw if anything is wrong.
"""
function check_windows_tree(root::String; strict_paths::Bool=true)
    stream = Base.BufferStream()
    writer = @async try
        Tar.create(root, stream)
    finally
        close(stream)
    end
    c = WindowsTreeCheck(; strict_paths)
    Tar.tree_hash(hdr -> check_header!(c, hdr), stream; skip_empty=true)
    wait(writer)
    env_path = joinpath(root, "toolchain.env")
    finish!(c, isfile(env_path) ? read(env_path, String) : nothing)
    for w in c.warnings
        @warn(w)
    end
    if !isempty(c.errors)
        foreach(e -> @error(e), first(c.errors, 50))
        error("The Windows toolchain tree breaks $(length(c.errors)) rule(s)")
    end
    return nothing
end

"""
    create_windows_toolchain(f, name; archive=true, force=false, strict_paths=true,
                             tarball_path=image_tarball_path(name; force))

Create an artifact by calling `f(root)` on an empty directory, which must populate `msys64/`
(and `gcc/`) and write the toolchain files; then normalize and check it, and archive it as
`tarball_path` (by default `<name>.tar.gz` in the scratch space). Returns
`(; artifact_hash, tarball_path)` like `create_rootfs`.
"""
function create_windows_toolchain(f::Function, name::String; archive::Bool=true,
                                  force::Bool=false, strict_paths::Bool=true,
                                  tarball_path::String=image_tarball_path(name; force))
    artifact_hash = Pkg.Artifacts.create_artifact() do root
        f(root)
        normalize_windows_tree!(root)
        check_windows_tree(root; strict_paths)
    end
    @info("Created $(name)", artifact_hash)
    return archive_image(artifact_hash, tarball_path; archive)
end

"""
    toolchain_cmd(root, args; home, tmp) -> Cmd

A command that runs `args` (an argv) in the toolchain tree at `root` the way the CI job wrapper
does: under the tree's non-login `bash` (an interactive one when `args` is empty),
with `PATH` = the tree's `PATH_PREPEND` + the inherited `PATH` minus Git for Windows' own MSYS
directories, the tree's `MSYSTEM` and `MSYS2_PATH_TYPE`, and `HOME`/`TMP`/`TEMP`/`TMPDIR`
outside the tree, so that it stays unmodified (and `verify_artifact` true). A login shell
(`bash -l`) would not: MSYS2's profile runs post-install scripts that rewrite `etc/mtab`.
"""
function toolchain_cmd(root::String, args::Vector{String}; home::String, tmp::String)
    Sys.iswindows() || error("Windows toolchains only run on Windows")
    env_vars = parse_toolchain_env(read(joinpath(root, "toolchain.env"), String))
    prepend = [joinpath(root, split(entry, '/')...) for entry in toolchain_path_entries(env_vars)]
    inherited = filter(split(get(ENV, "PATH", ""), ';')) do entry
        !isempty(entry) && !occursin(r"\\Git\\(usr|mingw64)\\bin\\?$"i, entry)
    end
    bash = joinpath(root, "msys64", "usr", "bin", "bash.exe")
    # The tree's bash execs the command (an argv, as on Linux), after its PATH lookup
    cmd = isempty(args) ? `$(bash)` : `$(bash) -c 'exec "$@"' bash $(args)`
    return addenv(cmd, "PATH" => join(vcat(prepend, inherited), ';'),
                  "MSYSTEM" => env_vars["MSYSTEM"], "MSYS2_PATH_TYPE" => env_vars["MSYS2_PATH_TYPE"],
                  "HOME" => home, "TMP" => tmp, "TEMP" => tmp, "TMPDIR" => tmp)
end
