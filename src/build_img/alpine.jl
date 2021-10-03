function repository_arg(repo)
    if startswith(repo, "https://")
        return "--repository=$(repo)"
    end
    return "--repository=http://dl-cdn.alpinelinux.org/alpine/$(repo)/main"
end

function alpine_bootstrap(f::Function, name::String;
                          archive::Bool = true,
                          force::Bool = false,
                          git_rev = "97bdddbacbe7f7fa6165ed2bdfa86d7d0ab43420", # v3.13
                          packages::Vector{AlpinePackage} = AlpinePackage[],
                          release::VersionNumber = v"3.13.6",
                          variant::String = "minirootfs")
    return create_rootfs(name; archive, force) do rootfs
        rootfs_url = "https://github.com/alpinelinux/docker-alpine/raw/$(git_rev)/x86_64/alpine-$(variant)-$(release)-x86_64.tar.gz"
        @info("Downloading Alpine rootfs", url=rootfs_url)
        rm(rootfs)
        Pkg.Artifacts.download_verify_unpack(rootfs_url, nothing, rootfs; verbose=true)

        # Call user callback, if requested
        f(rootfs)

        # Remove special `dev` files, take ownership, force symlinks to be relative, etc...
        rootfs_info = """
                    rootfs_type=alpine
                    release=$(release)
                    variant=$(variant)
                    packages=$(join([pkg.name for pkg in packages], ","))
                    build_date=$(Dates.now())
                    """
        cleanup_rootfs(rootfs; rootfs_info)

        # Generate one `apk` invocation per repository
        repos = unique([pkg.repo for pkg in packages])
        for repo in repos
            apk_args = ["/sbin/apk", "add", "--no-chown"]
            if repo !== nothing
                push!(apk_args, repository_arg(repo))
            end
            for pkg in filter(pkg -> pkg.repo == repo, packages)
                push!(apk_args, pkg.name)
            end
            chroot(rootfs, apk_args...)
        end
    end
end
# If no user callback is provided, default to doing nothing
alpine_bootstrap(name::String; kwargs...) = alpine_bootstrap(p -> nothing, name; kwargs...)
