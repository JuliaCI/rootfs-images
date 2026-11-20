# Add images of a rootfs-images release to RootfsImages/Artifacts.toml, replacing older
# versions of the same images:
#
#     julia RootfsImages/add_images.jl v8.13 package_linux.x86_64 package_linux.i686 ...
#
# Only uses standard libraries, so it runs without an environment.

using Pkg.Artifacts: bind_artifact!
import Downloads, SHA, Tar

const artifacts_toml = joinpath(@__DIR__, "Artifacts.toml")

function add_image(tag, image)
    url = "https://github.com/JuliaCI/rootfs-images/releases/download/$(tag)/$(image).tar.gz"
    mktempdir() do dir
        tarball = Downloads.download(url, joinpath(dir, "$(image).tar.gz"))
        sha256 = bytes2hex(open(SHA.sha256, tarball))
        # A non-ASCII symlink target makes Pkg's tree hash differ from Tar.jl's (JuliaLang/Pkg.jl#4707);
        # Julia versions without that fix would reject the image.
        tree_hash = open(`gzip -dc $(tarball)`) do io
            Tar.tree_hash(io; skip_empty=true) do hdr
                if hdr.type == :symlink && !isascii(hdr.link)
                    error("$(image) from $(tag) has a symlink with a non-ASCII target: $(hdr.path) -> $(hdr.link)")
                end
                true
            end
        end
        @info "Adding $(image) from $(tag)" tree_hash sha256
        bind_artifact!(artifacts_toml, image, Base.SHA1(tree_hash);
                       download_info=[(url, sha256)], lazy=true, force=true)
    end
end

tag, images = ARGS[1], ARGS[2:end]
isempty(images) && error("usage: julia add_images.jl TAG IMAGE.ARCH...")
foreach(image -> add_image(tag, image), images)
