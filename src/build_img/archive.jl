# Archiving, checking and publishing images, for every kind of image (Linux rootfs trees and
# Windows toolchain trees alike): an image is an artifact directory, published as a `.tar.gz`
# and identified by its git tree hash.

# Where an image's tarball goes; refuses to overwrite one unless `force`
function image_tarball_path(name::String; force::Bool=false)
    tarball_path = joinpath(Scratch.@get_scratch!("rootfs-images"), "$(name).tar.gz")
    if !force && isfile(tarball_path)
        @error("Refusing to overwrite tarball without `force` set", tarball_path)
        error()
    end
    return tarball_path
end

# A command that writes the uncompressed tar stream of a `.tar.gz` to stdout. Pkg's own 7-Zip,
# so that it works where there is no `gzip` (Windows).
decompress_cmd(tarball_path) = `$(Pkg.PlatformEngines.exe7z()) x $(tarball_path) -so`

# Release gate (PR builds aren't archived): the Pkg server must compute the hash we publish.
function check_tarball_tree_hash(tarball_path, artifact_hash)
    tar_hash = open(io -> Tar.tree_hash(io; skip_empty=true), decompress_cmd(tarball_path))
    if tar_hash != bytes2hex(artifact_hash.bytes)
        error("Tree hash mismatch: Pkg computed $(artifact_hash), Tar.jl computed $(tar_hash)")
    end
end

# Archive the artifact `artifact_hash` into `tarball_path` and check the tarball's tree hash,
# unless archiving is disabled (`--no-archive`) or this is a pull request build. Builds of
# `main` and manually dispatched builds (of any branch) pass the tarball on to the workflow
# (`tarball_name`/`tarball_path` outputs), which keeps it as a workflow artifact.
function archive_image(artifact_hash::Base.SHA1, tarball_path::String; archive::Bool=true)
    if !archive
        info_msg = "Skipping tarball creation because the `--no-archive` command-line flag was passed"
        @info info_msg artifact_hash basename(tarball_path)
        return (; artifact_hash, tarball_path = nothing)
    end
    if is_github_actions_pr()
        info_msg = "Skipping tarball creation because the build is a `pull_request` build"
        @info info_msg artifact_hash basename(tarball_path)
        return (; artifact_hash, tarball_path = nothing)
    end

    @info "Archiving" artifact_hash tarball_path
    Pkg.Artifacts.archive_artifact(artifact_hash, tarball_path)
    check_tarball_tree_hash(tarball_path, artifact_hash)
    if is_github_actions()
        is_push = is_github_actions_push()
        is_main = get_github_actions_ref() == "refs/heads/main"
        if (is_push && is_main) || is_github_actions_event("workflow_dispatch")
            github_actions_set_output("tarball_name" => basename(tarball_path))
            github_actions_set_output("tarball_path" => tarball_path)
        end
    end
    return (; artifact_hash, tarball_path)
end

function upload_rootfs_image(tarball_path::String;
                             github_repo::String,
                             tag_name::String,
                             num_retries::Int = 3)
    # Upload it to `github_repo`
    tarball_url = "https://github.com/$(github_repo)/releases/download/$(tag_name)/$(basename(tarball_path))"
    @info("Uploading to $(github_repo)@$(tag_name)", tarball_url, size=filesize(tarball_path))
    cmd = ghr_jll.ghr()
    append!(cmd.exec, ["-u", dirname(github_repo), "-r", basename(github_repo)])
    append!(cmd.exec, [tag_name, tarball_path])
    for _ in 1:num_retries
        p = run(cmd)
        if success(p)
            return tarball_url
        end
    end
    error("Unable to upload!")
end

get_github_actions_event_name() = convert(String, strip(ENV["GITHUB_EVENT_NAME"]))::String
get_github_actions_ref()        = convert(String, strip(ENV["GITHUB_REF"]))::String
get_github_actions_repo()       = convert(String, strip(ENV["GITHUB_REPOSITORY"]))::String

function is_github_actions()
    ci =  lowercase(strip(get(ENV, "CI",             "")))
    gha = lowercase(strip(get(ENV, "GITHUB_ACTIONS", "")))
    is_ci  = (ci ==  "1") || (ci ==  "true")
    is_gha = (gha == "1") || (gha == "true")
    return is_ci && is_gha
end

function is_github_actions_event(event_name::AbstractString)
    is_github_actions() || return false
    return get_github_actions_event_name() == event_name
end

is_github_actions_pr() = is_github_actions_event("pull_request")
is_github_actions_push() = is_github_actions_event("push")
is_github_actions_release() = is_github_actions_event("release")

function github_actions_set_output(io::IO, p::Pair{String, String})
    name = p[1]::String
    value = p[2]::String
    @debug "Setting GitHub Actions output" name value
    println(io, "::set-output name=$(name)::$(value)")
    return nothing
end
github_actions_set_output(p::Pair) = github_actions_set_output(stdout, p)

function upload_gha(tarball_path::Nothing)
    if !is_github_actions()
        @info "Skipping release artifact upload because this is not a GitHub Actions build"
        return nothing
    end

    if !is_github_actions_pr()
        error_msg = "You are only allowed to skip tarball creation if the build is a `pull_request` build"
        throw(ErrorException(error_msg))
    end

    GITHUB_EVENT_NAME = get_github_actions_event_name()
    GITHUB_REF        = get_github_actions_ref()

    @info "Skipping release artifact upload because the build is a `pull_request` build" GITHUB_EVENT_NAME GITHUB_REF
    return nothing
end

function upload_gha(tarball_path::String)
    if !is_github_actions()
        @info "Skipping release artifact upload because this is not a GitHub Actions build"
        return nothing
    end

    GITHUB_EVENT_NAME = get_github_actions_event_name()
    GITHUB_REF        = get_github_actions_ref()
    m = match(r"^refs\/tags\/(.*?)$", GITHUB_REF)

    if !is_github_actions_release()
        @info "Skipping release artifact upload because this is not a `release` build" GITHUB_EVENT_NAME GITHUB_REF
        return nothing
    end

    if m === nothing
        error_msg = "This is a `release` event, but the ref does not look like a tag."
        @error error_msg GITHUB_EVENT_NAME GITHUB_REF
        throw(ErrorException(error_msg))
    end

    github_repo = get_github_actions_repo()
    tag_name = convert(String, m[1])::String

    return upload_rootfs_image(
        tarball_path;
        github_repo,
        tag_name,
    )
end
