function parse_test_args(args::AbstractVector, file::AbstractString)
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

    arch = _process_optional_string_arg(parsed_args, "arch")
    command = _process_optional_command_args(parsed_args, "command"; default_command)
    url = _process_optional_string_arg(parsed_args, "url")
    treehash = _process_optional_treehash_arg(parsed_args, "treehash")

    return (; arch, command, treehash, url)
end
