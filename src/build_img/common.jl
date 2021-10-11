# Sometimes rootfs images have absolute symlinks within them; this
# is very bad for us as it breaks our ability to look at a rootfs
# without `chroot`'ing into it; so we fix up all the links to be
# relative here.
function force_relative(link, rootfs)
    target = readlink(link)
    if !isabspath(target)
        return
    end
    target = joinpath(rootfs, target[2:end])
    rm(link; force=true)
    symlink(relpath(target, dirname(link)), link)
end

function force_relative(rootfs)
    for (root, dirs, files) in walkdir(rootfs)
        for f in files
            f = joinpath(root, f)
            if islink(f)
                force_relative(f, rootfs)
            end
        end
        for d in dirs
            d = joinpath(root, d)
            if islink(d)
                force_relative(d, rootfs)
            end
        end
    end
end

function cleanup_rootfs(rootfs; rootfs_info=nothing)
    # Remove special `dev` files
    @info("Cleaning up `/dev`")
    for f in readdir(joinpath(rootfs, "dev"); join=true)
        # Keep the symlinks around (such as `/dev/fd`), as they're useful
        if !islink(f)
            run(`sudo rm -rf "$(f)"`)
        end
    end

    # take ownership of the entire rootfs
    @info("Chown'ing rootfs")
    run(`sudo chown $(getuid()):$(getgid()) -R "$(rootfs)"`)

    # Remove `/var/apt/cache`, as that's mostly downloaded archives
    if isdir(joinpath(rootfs, "var", "apt", "cache"))
        @info("Removing `/var/apt/cache`...")
        rm(joinpath(rootfs, "var", "apt", "cache"); recursive=true, force=true)
    end

    # Remove `/usr/share/doc`, as that's not particularly useful
    if isdir(joinpath(rootfs, "usr", "share", "doc"))
        @info("Removing `/usr/share/doc`...")
        rm(joinpath(rootfs, "usr", "share", "doc"); recursive=true, force=true)
    end

    # Add `juliaci` user and group
    @info("Adding 'juliaci' user and group as 1000:1000")
    open(joinpath(rootfs, "etc", "passwd"), append=true) do io
        println(io, "juliaci:x:1000:1000:juliaci:/home/juliaci:/bin/sh")
    end
    open(joinpath(rootfs, "etc", "group"), append=true) do io
        println(io, "juliaci:x:1000:juliaci")
    end
    mkpath(joinpath(rootfs, "home", "juliaci"))

    # Write out a reasonable default `/etc/resolv.conf` file
    open(joinpath(rootfs, "etc", "resolv.conf"), write=true) do io
        write(io, """
        nameserver 1.1.1.1
        nameserver 8.8.8.8
        """)
    end

    # Write out a reasonable default `/etc/hosts` file
    open(joinpath(rootfs, "etc", "hosts"), write=true) do io
        write(io, """
        127.0.0.1   localhost localhost.localdomain
        ::1         localhost localhost.localdomain
        """)
    end

    # If we've been given a `rootfs_info` parameter, write it out as /etc/rootfs-info
    if rootfs_info !== nothing
        open(io -> write(io, rootfs_info),
             joinpath(rootfs, "etc", "rootfs-info"),
             write=true,
        )
    end

    @info("Forcing all symlinks to be relative")
    force_relative(rootfs)
end

function create_rootfs(f::Function, name::String;
                       archive::Bool=true,
                       force::Bool=false)
    tarball_path = joinpath(Scratch.@get_scratch!("rootfs-images"), "$(name).tar.gz")
    if !force && isfile(tarball_path)
        @error("Refusing to overwrite tarball without `force` set", tarball_path)
        error()
    end

    artifact_hash = Pkg.Artifacts.create_artifact(f)

    # If the `--no-archive` command-line flag was passed, we will skip the tarball creation.
    if !archive
        info_msg = "Skipping tarball creation because the `--no-archive` command-line flag was passed"
        @info info_msg artifact_hash basename(tarball_path)
        return (; artifact_hash, tarball_path = nothing)
    end

    # If this is a pull request build, we will skip the tarball creation.
    if is_github_actions_pr()
        info_msg = "Skipping tarball creation because the build is a `pull_request` build"
        @info info_msg artifact_hash basename(tarball_path)
        return (; artifact_hash, tarball_path = nothing)
    end

    # Archive the artifact into a `.tar.gz` file.
    @info "Archiving" artifact_hash tarball_path
    Pkg.Artifacts.archive_artifact(artifact_hash, tarball_path)
    if is_github_actions()
        is_push = is_github_actions_push()
        is_main = get_github_actions_ref() == "refs/heads/main"
        if is_push && is_main
            github_actions_set_output("tarball_name" => basename(tarball_path))
            github_actions_set_output("tarball_path" => tarball_path)
        end
    end
    return (; artifact_hash, tarball_path)
end

function normalize_arch(image_arch::String)
    if image_arch in ("x86_64", "amd64", "x64")
        return "x86_64"
    end
    if image_arch in ("i686", "i386", "x86")
        return "i686"
    end
    if image_arch in ("armv7l", "arm", "armhf")
        return "armv7l"
    end
    if image_arch in ("aarch64", "armv8", "arm64")
        return "aarch64"
    end
    if image_arch in ("powerpc64le", "ppc64le", "ppc64el")
        return "powerpc64le"
    end
end

function can_run_natively(image_arch::String)
    native_arch = Base.BinaryPlatforms.arch(Base.BinaryPlatforms.HostPlatform())
    if native_arch == "x86_64"
        # We'll assume all `x86_64` chips can run `i686` code
        return image_arch in ("x86_64", "i686")
    end
    if native_arch == "aarch64"
        # We'll assume all `aarch64` chips can run `armv7l`, even though this may not be true
        return image_arch in ("aarch64", "armv7l")
    end
    return native_arch == image_arch
end

function qemu_installed(image_arch::String)
    qemu_arch_mapping = Dict(
        "x86_64" => "x86_64",
        "i686" => "i386",
        "aarch64" => "aarch64",
        "armv7l" => "arm",
        "powerpc64le" => "ppc64le",
    )
    return Sys.which("qemu-$(qemu_arch_mapping[image_arch])-static") !== nothing
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
