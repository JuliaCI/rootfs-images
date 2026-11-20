# Add images of a rootfs-images release to RootfsImages/Artifacts.toml, as
# `<image>.<arch>.<tag>`, and bump the package's patch version:
#
#     julia RootfsImages/add_images.jl v8.13 package_linux.x86_64 package_linux.i686 ...
#
# Entries of other tags stay: CI pins different releases of the same image (release branches
# keep the toolchain they were branched with). Only uses standard libraries, so it runs without
# an environment.

using Pkg.Artifacts: bind_artifact!
import Downloads, SHA, Tar

const artifacts_toml = joinpath(@__DIR__, "Artifacts.toml")
const project_toml = joinpath(@__DIR__, "Project.toml")

function add_image(tag, image)
    url = "https://github.com/JuliaCI/rootfs-images/releases/download/$(tag)/$(image).tar.gz"
    mktempdir() do dir
        tarball = Downloads.download(url, joinpath(dir, "$(image).tar.gz"))
        sha256 = bytes2hex(open(SHA.sha256, tarball))
        # A non-ASCII symlink target makes Pkg's tree hash differ from Tar.jl's (JuliaLang/Pkg.jl#4707);
        # the Pkg server, which verifies with Tar.jl, would reject the image.
        tree_hash = open(`gzip -dc $(tarball)`) do io
            Tar.tree_hash(io; skip_empty=true) do hdr
                if hdr.type == :symlink && !isascii(hdr.link)
                    error("$(image) from $(tag) has a symlink with a non-ASCII target: $(hdr.path) -> $(hdr.link)")
                end
                true
            end
        end
        @info "Adding $(image) from $(tag)" tree_hash sha256
        bind_artifact!(artifacts_toml, "$(image).$(tag)", Base.SHA1(tree_hash);
                       download_info=[(url, sha256)], lazy=true, force=true)
    end
end

function bump_patch_version()
    project = read(project_toml, String)
    m = match(r"^version = \"(.*)\"$"m, project)
    old = VersionNumber(m[1])
    new = VersionNumber(old.major, old.minor, old.patch + 1)
    write(project_toml, replace(project, m.match => "version = \"$(new)\""))
    @info "Bumped RootfsImages" old new
end

tag, images = ARGS[1], ARGS[2:end]
isempty(images) && error("usage: julia add_images.jl TAG IMAGE.ARCH...")
foreach(image -> add_image(tag, image), images)
bump_patch_version()
