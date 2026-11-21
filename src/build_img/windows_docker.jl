# Reading the published `juliapackaging/package-windows-<arch>` Docker images, for
# `windows/convert_docker.jl`: their manifests and configs, which layers hold the toolchain, and
# the PATH their Dockerfile set (in the registry, so only visible in a layer's hive).

# A minimal JSON reader (objects, arrays, strings, numbers, true/false/null), since the
# environment has no JSON package; manifests and configs are small and machine-written.
function parse_json(str::String)
    pos = Ref(1)
    peek() = (skipws(); str[pos[]])
    skipws() = while pos[] <= ncodeunits(str) && str[pos[]] in " \t\r\n"; pos[] += 1; end
    function expect(c)
        peek() == c || error("JSON: expected $(c) at $(pos[])")
        pos[] += 1
    end
    function value()
        c = peek()
        if c == '{'
            pos[] += 1
            obj = Dict{String,Any}()
            peek() == '}' && (pos[] += 1; return obj)
            while true
                key = value()::String
                expect(':')
                obj[key] = value()
                peek() == ',' ? (pos[] += 1) : (expect('}'); return obj)
            end
        elseif c == '['
            pos[] += 1
            arr = Any[]
            peek() == ']' && (pos[] += 1; return arr)
            while true
                push!(arr, value())
                peek() == ',' ? (pos[] += 1) : (expect(']'); return arr)
            end
        elseif c == '"'
            m = match(r"\G\"((?:[^\"\\]|\\.)*)\""s, str, pos[])
            pos[] += ncodeunits(m.match)
            return unescape_string(replace(m[1], "\\/" => "/"))
        else
            m = match(r"\G(?:true|false|null|-?[0-9.eE+-]+)", str, pos[])
            m === nothing && error("JSON: unexpected $(repr(c)) at $(pos[])")
            pos[] += ncodeunits(m.match)
            return m.match == "true" ? true : m.match == "false" ? false :
                   m.match == "null" ? nothing : parse(Float64, m.match)
        end
    end
    return value()
end

# Non-empty layers in order, with the command that created each (from the config's history)
function image_layers(manifest, config)
    digests = [layer["digest"] for layer in manifest["layers"]]
    commands = [get(h, "created_by", "") for h in config["history"] if !get(h, "empty_layer", false)]
    length(commands) == length(digests) ||
        error("$(length(digests)) layers but $(length(commands)) non-empty history entries")
    return collect(zip(digests, commands))
end

# Decode the UTF-16LE strings of a binary file, as `strings -el` does
function utf16_strings(bytes::Vector{UInt8}; minlen=8)
    out = String[]
    for m in eachmatch(r"(?:[\x20-\x7e]\x00){8,}"s, String(copy(bytes)))
        units = reinterpret(UInt16, Vector{UInt8}(codeunits(m.match)))
        length(units) >= minlen && push!(out, transcode(String, units))
    end
    return out
end

# The toolchain part of the PATH that `setx /M PATH` wrote into a layer's System registry hive
# (`Hives/System_Delta`): the entries up to `C:\msys64\usr\bin`, without
# `C:\buildkite-agent\bin` (mounted by the old Docker setup, not part of the toolchain), as
# paths relative to `C:\` with `/` separators.
function path_prepend_from_hive(hive::Vector{UInt8})
    candidates = filter(s -> occursin(r"(?i)^[^;]*;.*C:\\msys64\\usr\\bin;", s), utf16_strings(hive))
    isempty(candidates) && error("No PATH in the System hive")
    entries = split(only(unique(candidates)), ';')
    last = findfirst(==("C:\\msys64\\usr\\bin"), entries)
    prepend = filter(!=("C:\\buildkite-agent\\bin"), entries[1:last])
    return map(prepend) do entry
        m = match(r"^C:\\((?:msys64|gcc)(?:\\[^\\]+)*)$", entry)
        m === nothing && error("PATH entry $(entry) is not inside the toolchain")
        replace(m[1], '\\' => '/')
    end
end

# Which layers hold the trees: `COPY ... in C:\msys64` (required) and `COPY ... in C:\gcc`,
# and the last layer that sets PATH. `layers` as returned by `image_layers`.
function toolchain_layers(layers)
    trees = Dict{String,String}()
    for (digest, command) in layers
        m = match(r"COPY [^ ]+ in C:\\(msys64|gcc)\s*$", command)
        m === nothing && continue
        haskey(trees, m[1]) && error("Two layers copy C:\\$(m[1])")
        trees[m[1]] = digest
    end
    haskey(trees, "msys64") || error("No layer copies C:\\msys64")
    setx = findlast(((_, command),) -> occursin(r"setx /M PATH"i, command), layers)
    setx === nothing && error("No layer sets PATH")
    return trees, layers[setx][1]
end
