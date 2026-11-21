# Add images of a rootfs-images release to RootfsImages/Artifacts.toml, as
# `<image>.<arch>.<tag>`, and bump the package's patch version:
#
#     julia RootfsImages/add_images.jl v8.13 package_linux.x86_64 package_linux.i686 ...
#
# The images are named explicitly: the release workflow passes its build matrix, and images
# added to an older release later are listed by hand. Each is downloaded from the release (or,
# with `--from DIR`, read from `DIR/<image>.<arch>.tar.gz`, e.g. to prepare the entry of a tarball
# before uploading it; the URL recorded is the release's either way) and checked:
# - its tree hash must be computable by the Pkg servers (no symlink with a non-ASCII target,
#   JuliaLang/Pkg.jl#4707);
# - Windows toolchains (`package_windows.*`) must follow the tree rules of
#   `src/windows_rules.jl`;
# - an entry that exists must keep its tree hash: a published name never changes content, CI
#   pins it. Re-adding an image with the same tree hash changes nothing.
# Nothing is written unless every image passes. Entries of other tags stay: CI pins different
# releases of the same image (release branches keep the toolchain they were branched with).
#
# Only uses standard libraries, so it runs without an environment.

using Pkg.Artifacts: bind_artifact!
import Downloads, SHA, Tar, TOML

include(joinpath(@__DIR__, "..", "src", "windows_rules.jl"))

release_url(tag, image) = "https://github.com/JuliaCI/rootfs-images/releases/download/$(tag)/$(image).tar.gz"

# The tree hash and sha256 of an image's tarball, after checking it
function inspect_image(tarball, image)
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
    end
    return (; tree_hash, sha256)
end

"""
    add_images(artifacts_toml, project_toml, tag, images; from=nothing)

Check every image, then bind the new ones in `artifacts_toml` and bump the patch version in
`project_toml`. Returns the names that were added.
"""
function add_images(artifacts_toml, project_toml, tag, images; from=nothing)
    existing = isfile(artifacts_toml) ? TOML.parsefile(artifacts_toml) : Dict{String,Any}()
    new = []
    for image in images
        occursin(r"^[a-z0-9_]+\.[a-z0-9_]+$", image) || error("$(image) is not IMAGE.ARCH")
        name = "$(image).$(tag)"
        url = release_url(tag, image)
        info = mktempdir() do dir
            tarball = if from === nothing
                Downloads.download(url, joinpath(dir, "$(image).tar.gz"))
            else
                joinpath(from, "$(image).tar.gz")
            end
            inspect_image(tarball, image)
        end
        if haskey(existing, name)
            old = existing[name]["git-tree-sha1"]
            if old != info.tree_hash
                error("$(name) is already listed with tree hash $(old), but the image now has $(info.tree_hash); " *
                      "a published image never changes: publish it under a new tag")
            end
            @info "$(name) is already listed with this tree hash" tree_hash=info.tree_hash
            continue
        end
        @info "Adding $(name)" info.tree_hash info.sha256
        push!(new, (; name, url, info...))
    end
    for entry in new
        bind_artifact!(artifacts_toml, entry.name, Base.SHA1(entry.tree_hash);
                       download_info=[(entry.url, entry.sha256)], lazy=true)
    end
    isempty(new) || bump_patch_version(project_toml)
    return [entry.name for entry in new]
end

function bump_patch_version(project_toml)
    project = read(project_toml, String)
    m = match(r"^version = \"(.*)\"$"m, project)
    old = VersionNumber(m[1])
    new = VersionNumber(old.major, old.minor, old.patch + 1)
    write(project_toml, replace(project, m.match => "version = \"$(new)\""))
    @info "Bumped RootfsImages" old new
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
