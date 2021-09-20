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
        "command"
            required = false
            default = Any[]
            nargs = 'R' # 'R' = all remaining tokens
            help = "The command to run. If not specified, defaults to $(default_command)"
    end
    parsed_args = ArgParse.parse_args(args, settings)

    map_build_dir     = _process_required_string_arg(  parsed_args, "map-build-dir")
    tmpfs_size        = _process_required_string_arg(  parsed_args, "tmpfs-size")

    arch              = _process_optional_string_arg(  parsed_args, "arch")
    url               = _process_optional_string_arg(  parsed_args, "url")
    treehash          = _process_optional_treehash_arg(parsed_args, "treehash")

    command           = _process_optional_command_args(parsed_args, "command"; default_command)

    read_write_maps = Dict{String, String}()
    if map_build_dir == "persist"
        # If `${REPOSITORY_ROOT}` represents the root directory of the repository,
        # then `build_dir_persist` is the `${REPOSITORY_ROOT}/build/` directory.
        # This of course assumes that the `test_rootfs.jl` script is located at the
        # top-level of the repository.
        build_dir_persist = joinpath(dirname(file), "build")
        mkpath(build_dir_persist)
        read_write_maps["/build"] = build_dir_persist
        working_dir   = "/build"
    elseif map_build_dir == "temp"
        # If `${REPOSITORY_ROOT}` represents the root directory of the repository,
        # then `build_dir_temp_parent` is the `${REPOSITORY_ROOT}/temp/` directory.
        # This of course assumes that the `test_rootfs.jl` script is located at the
        # top-level of the repository.
        build_dir_temp_parent = joinpath(dirname(file), "temp")
        build_dir_temp = mktempdir(build_dir_temp_parent; cleanup = true)
        isdir(build_dir_temp) || throw(ErrorException("The temporary directory was not created"))
        isempty(readdir(build_dir_temp)) || throw(ErrorException("The temporary directory is not empty"))
        read_write_maps["/build"] = build_dir_temp
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
        multiarch,
        read_write_maps,
        tmpfs_size,
        treehash,
        url,
        working_dir,
    )

    return result
end
