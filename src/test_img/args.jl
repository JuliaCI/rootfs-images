function parse_test_args(args::AbstractVector, file::AbstractString)
    if !isabspath(file)
        throw(ArgumentError("$(file) is not an absolute file"))
    end
    settings = ArgParse.ArgParseSettings(;
        description = "Run commands inside rootfs images",
    )
    default_command = "/bin/bash"
    ArgParse.@add_arg_table! settings begin
        "--arch", "-a"
            arg_type = String
            required = false
            default = ""
            help = "Architecture of the rootfs image."
        "--map-build-dir"
            arg_type = String
            required = false
            default = "persist"
            help = string(
                "Whether to map a persistant build directory into the sandbox. ",
                "Possible values: persist, temp, no.",
            )
        "--mount-julia"
            arg_type = Bool
            required = false
            default = false
            help = string(
                "Whether to mount the current Julia binary into the sandbox. ",
                "Possible values: true, false.",
            )
        "--override-tmp-dir"
            arg_type = Bool
            required = false
            default = true
            help = string(
                "Whether to create a mapping for /tmp. ",
                "Possible values: true, false.",
            )
        "--url", "-u"
            arg_type = String
            required = false
            default = ""
            help = "URL from which to download the rootfs image."
        "--tmpfs-size"
            arg_type = String
            required = false
            default = "1G"
            help = "Size of the temporary filesystem."
        "--treehash", "-t"
            arg_type = String
            required = false
            default = ""
            help = "Tree hash of the rootfs image."
        "--run-as-root", "-r"
            arg_type = Bool
            required = false
            default = false
            help = "Run as root within sandbox."
        "command"
            required = false
            default = Any[]
            nargs = 'R' # 'R' = all remaining tokens
            help = "The command to run. If not specified, defaults to $(default_command)"
    end
    parsed_args = ArgParse.parse_args(args, settings)

    mount_julia       = parsed_args["mount-julia"]::Bool
    override_tmp_dir  = parsed_args["override-tmp-dir"]::Bool
    run_as_root       = parsed_args["run-as-root"]::Bool

    map_build_dir     = _process_required_string_arg(  parsed_args, "map-build-dir")
    tmpfs_size        = _process_required_string_arg(  parsed_args, "tmpfs-size")

    arch              = _process_optional_string_arg(  parsed_args, "arch")
    treehash          = _process_optional_treehash_arg(parsed_args, "treehash")
    url               = _process_optional_string_arg(  parsed_args, "url")

    command           = _process_optional_command_args(parsed_args, "command"; default_command)

    read_write_maps = Dict{String, String}()
    # `repo_root` is the root directory of the repository.
    # This of course assumes that the `test_rootfs.jl` script is located at the
    # top-level of the repository.
    repo_root = dirname(file)
    repo_root_subdir_build = joinpath(repo_root, "build") # $repo_root/build/
    repo_root_subdir_temp = joinpath(repo_root, "temp") # $repo_root/temp/
    if override_tmp_dir
        read_write_maps["/tmp"] = _create_temp_directory(; parent = repo_root_subdir_temp)
    end
    if map_build_dir == "persist"
        mkpath(repo_root_subdir_build)
        read_write_maps["/build"] = repo_root_subdir_build
        working_dir   = "/build"
    elseif map_build_dir == "temp"
        read_write_maps["/build"] = _create_temp_directory(; parent = repo_root_subdir_temp)
        working_dir   = "/build"
    elseif map_build_dir == "no"
        working_dir = "/"
    else
        msg = string(
            "$(map_build_dir) is not a valid value for map_build_dir. ",
            "Valid values include: persist, temp, no. ",
            "If not specified, defaults to persist",
        )
        throw(ArgumentError(msg))
    end

    multiarch = Base.BinaryPlatforms.Platform[]
    if arch !== nothing
        push!(multiarch, Base.BinaryPlatforms.Platform(arch, "linux"; libc="glibc"))
    end

    result = (;
        command,
        mount_julia,
        multiarch,
        read_write_maps,
        tmpfs_size,
        treehash,
        url,
        working_dir,
        run_as_root,
    )

    return result
end
