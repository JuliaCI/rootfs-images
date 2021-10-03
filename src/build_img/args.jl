function generate_image_name(arch::AbstractString, file::AbstractString)
    return "$(splitext(basename(file))[1]).$(arch)"
end

function parse_build_args(args::AbstractVector, file::AbstractString)
    settings = ArgParse.ArgParseSettings(;
        description = "Build a rootfs image",
    )
    ArgParse.@add_arg_table! settings begin
        "--arch", "-a"
            arg_type = String
            required = true
            help = "The architecture for which you would like to build"
        "--no-archive"
            action = :store_true
            help = "When this flag is provided, the .tar.gz archive will not be created"
    end
    parsed_args = ArgParse.parse_args(args, settings)
    arch = _process_required_string_arg(parsed_args, "arch")::String
    image = generate_image_name(arch, file)::String
    no_archive = parsed_args["no-archive"]::Bool
    archive = !no_archive
    return (; arch, archive, image)
end
