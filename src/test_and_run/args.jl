function parse_test_args(args::AbstractVector, file::AbstractString)
    settings = ArgParse.ArgParseSettings(;
        description = "Run commands inside rootfs images",
    )
    default_command = "/bin/bash"
    ArgParse.@add_arg_table! settings begin
        "--url", "-u"
            required = false
            default = ""
            help = "URL from which to download the rootfs image"
        "--treehash", "-t"
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

    _command_str_vec  = parsed_args["command"]
    _treehash         = parsed_args["treehash"]::String
    _url              = parsed_args["url"]::String

    if isempty(_command_str_vec)
        command_str_vec = String[default_command]
    else
        command_str_vec = convert(Vector{String}, _command_str_vec)::Vector{String}
    end
    command = `$(command_str_vec)`

    if isempty(strip(_treehash))
        @warn("Hash not provided; this will download the tarball, then fail, so you can see the true hash")
        treehash = Base.SHA1("0000000000000000000000000000000000000000")
    else
        treehash = Base.SHA1(_treehash)
    end

    url = isempty(strip(_url)) ? nothing : _url

    return (; command, treehash, url)
end
