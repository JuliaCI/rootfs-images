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
            help = "Architecture of the rootfs image"
        "--map-build-dir"
            arg_type = String
            required = false
            default = "persist"
            help = string(
                "Whether to map a persistant build directory into the sandbox. ",
                "Possible values: persist, temp, no. ",
                "If not specified, defaults to persist",
            )
        "--url", "-u"
            arg_type = String
            required = false
            default = ""
            help = "URL from which to download the rootfs image"
        "--treehash", "-t"
            arg_type = String
            required = false
            default = ""
            help = "Tree hash of the rootfs image"
        "command"
            required = false
            default = Any[]
            nargs = 'R' # 'R' = all remaining tokens
            help = "The command to run. If not specified, defaults to $(default_command)"
    end
    parsed_args = ArgParse.parse_args(args, settings)

    arch              = _process_optional_string_arg(  parsed_args, "arch")
    command           = _process_optional_command_args(parsed_args, "command"; default_command)
    map_build_dir     = _process_optional_string_arg(  parsed_args, "map-build-dir")
    url               = _process_optional_string_arg(  parsed_args, "url")
    treehash          = _process_optional_treehash_arg(parsed_args, "treehash")

    read_write_maps = Dict{String, String}()
    if map_build_dir == "persist"
        build_dir_persist = joinpath(dirname(file), "build")
        mkpath(build_dir_persist)
        read_write_maps["/build"] = build_dir_persist
        working_dir   = "/build"
    elseif map_build_dir == "temp"
        build_dir_temp = mktempdir(; cleanup = true)
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
        treehash,
        url,
        working_dir,
    )

    return result
end
