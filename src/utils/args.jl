function _process_required_string_arg(parsed_args::AbstractDict, arg_name::String)
    value_str = convert(String, strip(parsed_args[arg_name]))::String
    isempty(value_str) && throw(ArgumentError("The `$(arg_name)` argument must not be empty"))
    return value_str
end

function _process_optional_string_arg(parsed_args::AbstractDict, arg_name::String)
    value_str = convert(String, strip(parsed_args[arg_name]))::String
    value = isempty(value_str) ? nothing : value_str
    return value
end

function _process_optional_treehash_arg(parsed_args::AbstractDict, arg_name::String)
    _treehash = convert(String, strip(parsed_args[arg_name]))::String
    if isempty(_treehash)
        @warn("Hash not provided; this will download the tarball, then fail, so you can see the true hash")
        treehash_str = "0000000000000000000000000000000000000000"
    else
        treehash_str = _treehash
    end
    treehash = Base.SHA1(treehash_str)
    return treehash
end

function _process_optional_command_args(parsed_args::AbstractDict, arg_name::String; default_command::String)
    _command_str_vec  = parsed_args["command"]
    if isempty(_command_str_vec)
        command_str_vec = String[default_command]
    else
        command_str_vec = convert(Vector{String}, _command_str_vec)::Vector{String}
    end
    command = `$(command_str_vec)`
    return command
end
