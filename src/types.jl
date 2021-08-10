# Helper structure for installing alpine packages that may or may not be part of an older Alpine release
struct AlpinePackage
    name::String
    repo::Union{Nothing,String}

    AlpinePackage(name, repo=nothing) = new(name, repo)
end
