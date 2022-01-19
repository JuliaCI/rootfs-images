function _create_temp_directory(; parent::String)
    mkpath(parent)
    isdir(parent) || throw(ErrorException("The parent directory was not created"))

    new_temp_dir = mktempdir(parent; cleanup = true)
    isdir(new_temp_dir) || throw(ErrorException("The temporary directory was not created"))
    isempty(readdir(new_temp_dir)) || throw(ErrorException("The temporary directory is not empty"))

    return new_temp_dir
end
