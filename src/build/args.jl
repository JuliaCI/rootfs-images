function parse_build_args(args::AbstractVector)
    settings = ArgParse.ArgParseSettings()
    ArgParse.@add_arg_table! settings begin
        "--arch"
            required=true
    end
    parsed_args = ArgParse.parse_args(args, settings)
    arch = parsed_args["arch"]::String
    return (; arch)
end
