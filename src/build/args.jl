function generate_image_name(arch::AbstractString, file::AbstractString)
    return "$(splitext(basename(file))[1]).$(arch)"
end

function parse_build_args(args::AbstractVector, file::AbstractString)
    settings = ArgParse.ArgParseSettings(;
        description = "Build a rootfs image",
    )
    ArgParse.@add_arg_table! settings begin
        "--arch"
            arg_type = String
            required = true
            help = "The architecture for which you would like to build"
    end
    parsed_args = ArgParse.parse_args(args, settings)
    arch = parsed_args["arch"]::String
    image = generate_image_name(arch, file)
    return (; arch, image)
end
