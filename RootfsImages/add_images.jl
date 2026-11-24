# List the images of a rootfs-images release in RootfsImages/Artifacts.toml, as
# `<image>.<arch>`, and set the package's version to follow the tag:
#
#     julia RootfsImages/add_images.jl v8.14 package_linux.x86_64 package_linux.i686 ...
#
# RootfsImages lists the images of the latest release, `vA.B`, and its version is `A.B.<patch>`.
# The names leave out the tag, which the version already gives: `artifact"package_linux.x86_64"`
# follows RootfsImages upgrades, and a `[compat]` bound pins a release.
# - for a newer release, the images replace every entry and the version becomes `A.B.0`;
# - for the release the version is of (images added to it later), the new images are added and
#   the patch version is bumped. Nothing new changes nothing.
# Older releases are refused: versions only go up, and replacing the catalog with an older
# release would drop listed names.
#
# The images are named explicitly: the release workflow passes its build matrix, and images
# added to a release later are listed by hand. Each is downloaded from the release (or, with
# `--from DIR`, read from `DIR/<image>.<arch>.tar.gz`, e.g. to prepare the entry of a tarball
# before uploading it; the URL recorded is the release's either way) and checked:
# - its tree hash must be computable by the Pkg servers (no symlink with a non-ASCII target,
#   JuliaLang/Pkg.jl#4707);
# - Windows toolchains (`package_windows.*`) must follow the tree rules of
#   `src/windows_rules.jl`, and their `toolchain.json` must name this image and tag;
# - within a release, an entry that exists must keep its tree hash: a released image never
#   changes, CI pins its tree hash. Re-adding an image with the same tree hash changes nothing,
#   unless the asset at the recorded URL changed its bytes (a download from it would then fail
#   the recorded sha256). A newer release replaces the entries, so the same name then holds
#   that release's image.
# Nothing is written unless every image passes.
#
# Only uses standard libraries, so it runs without an environment.

using Pkg.Artifacts: bind_artifact!
import Downloads, SHA, Tar, TOML

include(joinpath(@__DIR__, "..", "src", "windows_rules.jl"))

release_url(tag, image) = "https://github.com/JuliaCI/rootfs-images/releases/download/$(tag)/$(image).tar.gz"

# The release `vA.B` as `(A, B)`, or `nothing`. No leading zeros, so that a version names one tag.
function parse_tag(tag)
    m = match(r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$", tag)
    return m === nothing ? nothing : (parse(Int, m[1]), parse(Int, m[2]))
end

# The tree hash and sha256 of an image's tarball, after checking it
function inspect_image(tarball, image, tag)
    sha256 = bytes2hex(open(SHA.sha256, tarball))
    tree_hash = open(`gzip -dc $(tarball)`) do io
        Tar.tree_hash(io; skip_empty=true) do hdr
            if hdr.type == :symlink && !isascii(hdr.link)
                error("$(image) has a symlink with a non-ASCII target: $(hdr.path) -> $(hdr.link)")
            end
            true
        end
    end
    if startswith(image, "package_windows.")
        # Paths that are too long are a builder error; the trees converted from the Docker
        # images keep theirs, so only warn here
        check = check_windows_tarball(`gzip -dc $(tarball)`; strict_paths=false)
        foreach(w -> @warn("$(image): $(w)"), check.warnings)
        if !isempty(check.errors)
            foreach(e -> @error("$(image): $(e)"), first(check.errors, 50))
            error("$(image) breaks $(length(check.errors)) rule(s) of Windows toolchain trees")
        end
        @assert check.tree_hash == tree_hash
        json = something(check.toolchain_json, "")
        for (key, value) in ("image" => image, "tag" => tag)
            actual = toolchain_json_field(json, key)
            actual == value || error("$(image): toolchain.json says $(key) is $(repr(actual)), not $(repr(value))")
        end
    end
    return (; tree_hash, sha256)
end

"""
    add_images(artifacts_toml, project_toml, tag, images; from=nothing)

Check every image, then list them in `artifacts_toml` and set the version in `project_toml`:
for a release `vA.B` newer than the version, the images replace every entry and the version
becomes `A.B.0`; for the release the version is of, the new images are added and the patch
version is bumped. Entries are named `<image>.<arch>`. Returns the names that were written.
"""
function add_images(artifacts_toml, project_toml, tag, images; from=nothing)
    release = parse_tag(tag)
    release === nothing && error("$(tag) is not a release tag vA.B, which RootfsImages' version follows")
    current = read_version(project_toml)
    listed = (current.major, current.minor)
    if release < listed
        error("RootfsImages $(current) is of release v$(listed[1]).$(listed[2]), newer than $(tag): " *
              "the catalog lists the latest release, and its version can't go back")
    end
    replacing = release != listed
    existing = isfile(artifacts_toml) ? TOML.parsefile(artifacts_toml) : Dict{String,Any}()
    allunique(images) || error("Images listed more than once: $(join(unique(filter(i -> count(==(i), images) > 1, images)), ", "))")
    entries = []
    for image in images
        occursin(r"^[a-z0-9_]+\.[a-z0-9_]+$", image) || error("$(image) is not IMAGE.ARCH")
        name = image
        url = release_url(tag, image)
        info = mktempdir() do dir
            tarball = if from === nothing
                Downloads.download(url, joinpath(dir, "$(image).tar.gz"))
            else
                joinpath(from, "$(image).tar.gz")
            end
            inspect_image(tarball, image, tag)
        end
        entry = (; name, url, info...)
        # Within the release: a listed image keeps its content (a newer release replaces it)
        if !replacing && haskey(existing, name)
            old = existing[name]["git-tree-sha1"]
            if old != info.tree_hash
                error("$(name) of $(tag) is already listed with tree hash $(old), but the image now has $(info.tree_hash); " *
                      "a released image never changes: publish it under a new tag")
            end
            for download in get(existing[name], "download", [])
                if download["url"] == url && download["sha256"] != info.sha256
                    error("$(url) changed: its sha256 is $(info.sha256), $(name) lists $(download["sha256"]); " *
                          "restore the published asset")
                end
            end
            @info "$(name) is already listed with this tree hash" tree_hash=info.tree_hash
            continue
        end
        @info "Adding $(name)" info.tree_hash info.sha256
        push!(entries, entry)
    end
    isempty(entries) && return String[]
    if replacing
        version = VersionNumber(release..., 0)
        new_toml = artifacts_toml * ".new"
        rm(new_toml; force=true)
        bind_entries(new_toml, entries)
        mv(new_toml, artifacts_toml; force=true)
    else
        version = VersionNumber(current.major, current.minor, current.patch + 1)
        bind_entries(artifacts_toml, entries)
    end
    write_version(project_toml, version)
    @info "RootfsImages $(version)" previous=current replaced=replacing
    return [entry.name for entry in entries]
end

function bind_entries(artifacts_toml, entries)
    for entry in entries
        bind_artifact!(artifacts_toml, entry.name, Base.SHA1(entry.tree_hash);
                       download_info=[(entry.url, entry.sha256)], lazy=true)
    end
end

const VERSION_LINE = r"^version = \"(.*)\"$"m

read_version(project_toml) = VersionNumber(match(VERSION_LINE, read(project_toml, String))[1])

function write_version(project_toml, version)
    project = read(project_toml, String)
    write(project_toml, replace(project, VERSION_LINE => "version = \"$(version)\""))
end

if abspath(PROGRAM_FILE) == @__FILE__
    args = copy(ARGS)
    from = nothing
    i = findfirst(==("--from"), args)
    if i !== nothing
        from = args[i+1]
        deleteat!(args, i:i+1)
    end
    length(args) >= 2 || error("usage: julia add_images.jl [--from DIR] TAG IMAGE.ARCH...")
    tag, images = args[1], args[2:end]
    add_images(joinpath(@__DIR__, "Artifacts.toml"), joinpath(@__DIR__, "Project.toml"), tag, images; from)
end
