# Convert a published `juliapackaging/package-windows-<arch>` Docker image into a Windows
# toolchain tree (`package_windows.<arch>`), for the tags that predate the native builder:
#
#     julia --project windows/convert_docker.jl --arch x86_64 --tag v8.10 \
#         --image juliapackaging/package-windows-x86_64@sha256:b0aea06b... --output out/v8.10
#
# Docker tags are mutable, so the image is named by digest only. The trees are taken from the
# image's `COPY ... C:\msys64` and `COPY ... C:\gcc` layers, fetched from Docker Hub and checked
# against their digests; the environment comes from the image itself: `MSYSTEM` from its config,
# and `PATH` from the registry hive of its last `setx /M PATH` layer (the Dockerfiles set PATH
# there, not with ENV). Runs on Linux or macOS (needs `gzip`); it never runs anything from the
# image.
#
# The tarball goes to `--output DIR` as `package_windows.<arch>.tar.gz`, its name on the release
# (one directory per tag, as the names of different tags are the same); `--no-archive` skips it.
# It is not uploaded.

using RootfsUtils: create_windows_toolchain, write_toolchain_files, parse_json, image_layers,
                   toolchain_layers, path_prepend_from_hive
import Downloads, SHA, Tar

function parse_args(args)
    opts = Dict{String,String}()
    archive = true
    output = nothing
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--no-archive"
            archive = false
        elseif arg == "--output" && i < length(args)
            output = args[i += 1]
        elseif arg in ("--arch", "--tag", "--image") && i < length(args)
            opts[arg[3:end]] = args[i += 1]
        else
            error("usage: convert_docker.jl --arch ARCH --tag TAG --image REPO@sha256:DIGEST (--output DIR | --no-archive)")
        end
        i += 1
    end
    for key in ("arch", "tag", "image")
        haskey(opts, key) || error("missing --$(key)")
    end
    m = match(r"^([a-z0-9._/-]+)@(sha256:[0-9a-f]{64})$", opts["image"])
    m === nothing && error("--image must be REPO@sha256:DIGEST, not $(opts["image"])")
    opts["arch"] in ("x86_64", "i686") || error("unknown arch $(opts["arch"])")
    # The images are named after their arch; a mix-up would give an i686 toolchain an x86_64 name
    endswith(m[1], "-$(opts["arch"])") || error("--image $(m[1]) is not the image of --arch $(opts["arch"])")
    archive == (output !== nothing) || error("give either --output DIR or --no-archive")
    return (; arch=opts["arch"], tag=opts["tag"], repo=String(m[1]), digest=String(m[2]), archive, output)
end

const REGISTRY = "https://registry-1.docker.io/v2"

function registry_token(repo)
    url = "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$(repo):pull"
    body = String(take!(Downloads.download(url, IOBuffer())))
    return match(r"\"token\"\s*:\s*\"([^\"]+)\"", body)[1]
end

# Fetch a manifest or blob by digest into `path`, and check the digest
function fetch_verified(url, digest, path; token, accept=nothing)
    headers = ["Authorization" => "Bearer $(token)"]
    accept === nothing || push!(headers, "Accept" => accept)
    Downloads.download(url, path; headers)
    actual = "sha256:" * bytes2hex(open(SHA.sha256, path))
    actual == digest || error("$(url): digest is $(actual), expected $(digest)")
    return path
end

# The System registry hive of a Windows layer (empty if the layer has none)
function system_hive(layer_tgz)
    mktempdir() do dir
        open(io -> Tar.extract(hdr -> hdr.path in ("Hives", "Hives/System_Delta"), io, dir; set_permissions=false),
             `gzip -dc $(layer_tgz)`)
        path = joinpath(dir, "Hives", "System_Delta")
        isfile(path) ? read(path) : UInt8[]
    end
end

function convert(; arch, tag, repo, digest, archive, output)
    image = "package_windows.$(arch)"
    source = "docker.io/$(repo)@$(digest)"
    mktempdir() do work
        token = registry_token(repo)
        manifest = parse_json(read(fetch_verified("$(REGISTRY)/$(repo)/manifests/$(digest)", digest,
                                       joinpath(work, "manifest.json"); token,
                                       accept="application/vnd.docker.distribution.manifest.v2+json"), String))
        config_digest = manifest["config"]["digest"]
        config = parse_json(read(fetch_verified("$(REGISTRY)/$(repo)/blobs/$(config_digest)", config_digest,
                                                joinpath(work, "config.json"); token), String))
        msystem = only(e[9:end] for e in config["config"]["Env"] if startswith(e, "MSYSTEM="))
        layers = image_layers(manifest, config)

        fetch_layer(layer_digest) = fetch_verified("$(REGISTRY)/$(repo)/blobs/$(layer_digest)", layer_digest,
                                                   joinpath(work, last(split(layer_digest, ':')) * ".tar.gz"); token)
        trees, setx_layer = toolchain_layers(layers)
        path_prepend = path_prepend_from_hive(system_hive(fetch_layer(setx_layer)))
        @info("Converting $(source)", tag, layers=trees, path_prepend, msystem)

        # Into the output directory (the scratch space has one tarball per image name, which
        # the tags of an image share), archived and verified next to its final name, which it
        # takes only when complete
        final_path = archive ? joinpath(mkpath(output), "$(image).tar.gz") : nothing
        archive && ispath(final_path) && error("$(final_path) exists")
        tarball_path = archive ? tempname(output; cleanup=false) * ".partial" : tempname()
        result = try create_windows_toolchain(image; archive, strict_paths=false, tarball_path) do root
            for (dir, layer_digest) in sort(collect(trees))
                layer = fetch_layer(layer_digest)
                prefix = "Files/$(dir)"
                extracted = joinpath(work, "extract-$(dir)")
                # Windows layers carry no POSIX modes; normalize_windows_tree! sets them
                open(`gzip -dc $(layer)`) do io
                    Tar.extract(hdr -> hdr.path == prefix || startswith(hdr.path, prefix * "/"),
                                io, extracted; set_permissions=false)
                end
                chmod(extracted, 0o755; recursive=true)
                mv(joinpath(extracted, "Files", dir), joinpath(root, dir))
                rm(layer)
            end
            for entry in path_prepend
                isdir(joinpath(root, entry)) || error("PATH entry $(entry) is not in the tree")
            end
            write_toolchain_files(root; image, arch, tag, source, path_prepend, msystem)
        end
        catch
            rm(tarball_path; force=true)
            rethrow()
        end
        if archive
            ispath(final_path) && error("$(final_path) appeared during the conversion")
            mv(tarball_path, final_path)
            result = (; result.artifact_hash, tarball_path=final_path)
        end
        return result
    end
end

args = parse_args(ARGS)
result = convert(; args...)
println("tree hash: ", result.artifact_hash)
result.tarball_path === nothing || println("tarball: ", result.tarball_path)
