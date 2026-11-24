# Tests of the image tooling that runs without building an image (no root, no network):
#
#     julia --project test/runtests.jl

using RootfsUtils
using RootfsUtils: parse_toolchain_env, render_toolchain_env, toolchain_path_entries,
                   check_windows_tarball, check_windows_tree, normalize_windows_tree!,
                   msys2_packages, write_toolchain_files, parse_json, image_layers,
                   toolchain_layers, path_prepend_from_hive, utf16_strings
using Test, Tar, Pkg, TOML

const GOOD_ENV = "PATH_PREPEND=gcc\\bin;msys64\\usr\\bin\nMSYSTEM=MINGW64\nMSYS2_PATH_TYPE=inherit\n"

# A minimal valid tree; `f(root)` can break it afterwards
function windows_tree(f=identity; image="package_windows.x86_64", tag="v9.0")
    root = mktempdir()
    for dir in ("msys64/usr/bin", "gcc/bin", "msys64/var/lib/pacman/local/bash-5.3-1")
        mkpath(joinpath(root, dir))
    end
    write(joinpath(root, "msys64/usr/bin/bash.exe"), "MZ")
    write(joinpath(root, "msys64/var/lib/pacman/local/bash-5.3-1/desc"),
          "%NAME%\nbash\n\n%VERSION%\n5.3-1\n\n%DESC%\nThe GNU Bourne Again shell\n")
    write_toolchain_files(root; image, arch=String(split(image, '.')[2]), tag, source="test",
                          path_prepend=["gcc/bin", "msys64/usr/bin"], msystem="MINGW64")
    chmod(root, 0o755; recursive=true)
    f(root)
    return root
end

has_error(r, pattern) = any(e -> occursin(pattern, e), r.errors)

function check_tree(root; kwargs...)
    tarball = tempname()
    Tar.create(root, tarball)
    try
        return check_windows_tarball(tarball; kwargs...)
    finally
        rm(tarball)
    end
end

# The catalog script, in a module of its own (it includes `windows_rules.jl` again)
module AddImages
    include(joinpath(@__DIR__, "..", "RootfsImages", "add_images.jl"))
end

@testset "RootfsUtils" begin

@testset "test_rootfs.jl arguments" begin
    file = joinpath(dirname(@__DIR__), "test_rootfs.jl")
    parse(args...) = RootfsUtils.parse_test_args(collect(args), file)
    a = parse("--map-build-dir=no", "package_windows.x86_64")
    @test a.image == "package_windows.x86_64" && a.treehash === nothing && isempty(a.command)
    a = parse("--map-build-dir=no", "package_linux.x86_64", "--", "gcc", "--version")
    @test a.image == "package_linux.x86_64" && a.command == ["gcc", "--version"]
    a = parse("--map-build-dir=no", "--treehash=" * "1"^40, "--", "/bin/bash", "-c", "true")
    @test a.image === nothing && a.treehash == Base.SHA1("1"^40) && a.command == ["/bin/bash", "-c", "true"]
    @test parse("--map-build-dir=no", "package_windows.x86_64.v8.14-rc1").image == "package_windows.x86_64.v8.14-rc1"
    @test_throws ArgumentError parse("--map-build-dir=no")
    # Anything that is not in the catalog is refused before anything is downloaded
    @test_throws ArgumentError RootfsUtils.ensure_image_installed("/bin/bash")
    # Names don't carry the release tag
    @test_throws ArgumentError RootfsUtils.ensure_image_installed("package_linux.x86_64.v8.14")
end


@testset "toolchain.env" begin
    env = parse_toolchain_env(GOOD_ENV)
    @test env["MSYSTEM"] == "MINGW64"
    @test toolchain_path_entries(env) == ["gcc/bin", "msys64/usr/bin"]
    @test parse_toolchain_env(replace(GOOD_ENV, "\n" => "\r\n")) == env
    @test parse_toolchain_env(render_toolchain_env(; path_prepend=["gcc/bin", "msys64/usr/bin"],
                                                   msystem="MINGW64")) == env
    bad = [
        GOOD_ENV * "MSYSTEM=MINGW64\n",                         # duplicate
        GOOD_ENV * "HOME=C:\\x\n",                              # unknown key
        replace(GOOD_ENV, "MSYSTEM=MINGW64\n" => ""),           # missing
        replace(GOOD_ENV, "MINGW64" => ""),                     # empty value
        replace(GOOD_ENV, "MINGW64" => "MINGW128"),             # unknown MSYSTEM
        replace(GOOD_ENV, "inherit" => "minimal"),
        replace(GOOD_ENV, "gcc\\bin" => "C:\\gcc\\bin"),        # absolute
        replace(GOOD_ENV, "gcc\\bin" => "gcc/bin"),             # wrong separator
        replace(GOOD_ENV, "gcc\\bin" => "..\\gcc"),
        replace(GOOD_ENV, "gcc\\bin;" => ";"),                  # empty entry
        "PATH_PREPEND gcc\n",
    ]
    for str in bad
        @test_throws ArgumentError parse_toolchain_env(str)
    end
end

@testset "Windows tree rules" begin
    r = check_tree(windows_tree())
    @test isempty(r.errors) && isempty(r.warnings)
    # The tree hash is Pkg's
    root = windows_tree()
    @test r.tree_hash == bytes2hex(Pkg.GitTools.tree_hash(root))

    @test has_error(check_tree(windows_tree(root -> chmod(joinpath(root, "toolchain.json"), 0o644))),
                    "toolchain.json: file mode is 644")
    @test has_error(check_tree(windows_tree(root -> symlink("bash.exe", joinpath(root, "msys64/usr/bin/sh.exe")))),
                    "symlink entries are not allowed")
    # Headers directly: a case-insensitive file system (macOS) can't hold both names
    c = RootfsUtils.WindowsTreeCheck()
    RootfsUtils.check_header!(c, Tar.Header("msys64/usr/bin/bash.exe", :file, 0o755, 0, ""))
    RootfsUtils.check_header!(c, Tar.Header("msys64/usr/bin/Bash.exe", :file, 0o755, 0, ""))
    @test has_error(c, "only in case")
    # Headers directly: Windows can't create these names in the first place
    for (name, problem) in (("aux.txt", "reserved name"), ("com1", "reserved name"),
                            ("a.", "trailing dot"), ("a ", "trailing dot or space"),
                            ("a:b", "invalid character"), ("a?b", "invalid character"),
                            ("a\\b", "invalid character"), ("COM¹.txt", "reserved name"),
                            ("nul .txt", "reserved name"))
        c = RootfsUtils.WindowsTreeCheck()
        RootfsUtils.check_header!(c, Tar.Header("msys64/$(name)", :file, 0o755, 0, ""))
        @test has_error(c, problem)
    end
    c = RootfsUtils.WindowsTreeCheck()
    RootfsUtils.check_header!(c, Tar.Header("msys64/auxiliary.txt", :file, 0o755, 0, ""))
    @test isempty(c.errors)
    long = joinpath(fill("d" ^ 50, 4)...)
    tree = windows_tree(root -> (mkpath(joinpath(root, "msys64", long)); chmod(root, 0o755; recursive=true)))
    @test has_error(check_tree(tree), "longer than 200")
    r = check_tree(tree; strict_paths=false)
    @test isempty(r.errors) && any(w -> occursin("longer than 200", w), r.warnings)
    @test has_error(check_tree(windows_tree(root -> rm(joinpath(root, "toolchain.json")))), "toolchain.json: missing")
    # The files must be files
    r = check_tree(windows_tree(root -> (rm(joinpath(root, "toolchain.env")); mkdir(joinpath(root, "toolchain.env")))))
    @test has_error(r, "toolchain.env: must be a file")
    # Tar.create writes every directory as 0755, so only a foreign tarball can break this
    c = RootfsUtils.WindowsTreeCheck()
    RootfsUtils.check_header!(c, Tar.Header("gcc", :directory, 0o700, 0, ""))
    @test has_error(c, "gcc: directory mode is 700")
    # Collisions through directories the tarball doesn't list (Windows merges them)
    c = RootfsUtils.WindowsTreeCheck()
    RootfsUtils.check_header!(c, Tar.Header("msys64/lib/Foo/a", :file, 0o755, 0, ""))
    RootfsUtils.check_header!(c, Tar.Header("msys64/lib/foo/b", :file, 0o755, 0, ""))
    @test has_error(c, "msys64/lib/foo: differs from msys64/lib/Foo only in case")
    # A path that is a file and a directory: full extraction keeps only the last
    c = RootfsUtils.WindowsTreeCheck()
    RootfsUtils.check_header!(c, Tar.Header("toolchain.env", :file, 0o755, 0, ""))
    RootfsUtils.check_header!(c, Tar.Header("toolchain.env/child", :file, 0o755, 0, ""))
    @test has_error(c, "toolchain.env: both a file and a directory")
    # Parent directories need no entry of their own, also for PATH_PREPEND
    c = RootfsUtils.WindowsTreeCheck()
    for path in ("msys64/usr/bin/bash.exe", "gcc/bin/gcc.exe", "toolchain.env", "toolchain.json")
        RootfsUtils.check_header!(c, Tar.Header(path, :file, 0o755, 0, ""))
    end
    RootfsUtils.finish!(c, GOOD_ENV)
    @test isempty(c.errors)
    RootfsUtils.finish!(c, replace(GOOD_ENV, "gcc\\bin" => "GCC\\bin"))
    @test has_error(c, "PATH_PREPEND entry GCC/bin is not a directory")
    # Length in UTF-16 units: a non-BMP character counts twice
    c = RootfsUtils.WindowsTreeCheck()
    RootfsUtils.check_header!(c, Tar.Header("msys64/" * "😀"^97, :file, 0o755, 0, ""))
    @test has_error(c, "longer than 200")
    @test has_error(check_tree(windows_tree(root -> mkdir(joinpath(root, "extra")))), "extra: unexpected at the top level")
    @test has_error(check_tree(windows_tree(root -> rm(joinpath(root, "gcc"); recursive=true))),
                    "PATH_PREPEND entry gcc/bin is not a directory")
    @test has_error(check_tree(windows_tree(root -> write(joinpath(root, "toolchain.env"), "MSYSTEM=MINGW64\n"))),
                    "missing key")
end

@testset "normalize_windows_tree!" begin
    root = windows_tree() do root
        msys64 = joinpath(root, "msys64")
        for dir in ("etc/pacman.d/gnupg", "var/cache/pacman/pkg", "var/lib/pacman/sync", "var/log", "tmp", "home/user")
            mkpath(joinpath(msys64, dir))
        end
        write(joinpath(msys64, "var/lib/pacman/sync/msys.db"), "")
        write(joinpath(msys64, "var/log/pacman.log"), "")
        write(joinpath(msys64, "tmp/t.c"), "")
        write(joinpath(msys64, "etc/pacman.d/gnupg/pubring.gpg"), "")
        write(joinpath(msys64, "etc/mtab"), "none / cygdrive binary,posix=0,noacl,user 0 0\n")
        hardlink(joinpath(msys64, "usr/bin/bash.exe"), joinpath(msys64, "usr/bin/sh.exe"))
        chmod(joinpath(msys64, "usr/bin/bash.exe"), 0o644)
    end
    normalize_windows_tree!(root)
    msys64 = joinpath(root, "msys64")
    @test !ispath(joinpath(msys64, "etc/pacman.d/gnupg"))
    @test !ispath(joinpath(msys64, "etc/mtab"))
    @test !ispath(joinpath(msys64, "var/lib/pacman/sync"))
    @test !ispath(joinpath(msys64, "var/cache/pacman/pkg"))
    @test isempty(readdir(joinpath(msys64, "var/log"))) && isempty(readdir(joinpath(msys64, "tmp")))
    @test isempty(readdir(joinpath(msys64, "home")))
    @test isdir(joinpath(msys64, "var/lib/pacman/local"))
    @test stat(joinpath(msys64, "usr/bin/sh.exe")).nlink == 1
    @test read(joinpath(msys64, "usr/bin/sh.exe"), String) == "MZ"
    @test Sys.isexecutable(joinpath(msys64, "usr/bin/bash.exe"))
    @test isempty(check_tree(root).errors)
    check_windows_tree(root)

    # Links are refused before anything is deleted, also through a parent directory
    if !Sys.iswindows()
        keep = mktempdir()
        mkpath(joinpath(keep, "log"))
        write(joinpath(keep, "log", "precious"), "")
        tree = windows_tree() do root
            rm(joinpath(root, "msys64", "var"); recursive=true)
            symlink(keep, joinpath(root, "msys64", "var"))
        end
        @test_throws ErrorException normalize_windows_tree!(tree)
        @test isfile(joinpath(keep, "log", "precious"))
    end
    chmod(joinpath(root, "toolchain.json"), 0o644)
    @test_throws ErrorException check_windows_tree(root)
end

@testset "toolchain files" begin
    root = windows_tree()
    @test msys2_packages(root) == ["bash 5.3-1"]
    write_toolchain_files(root; image="package_windows.x86_64", arch="x86_64", tag="v8.10",
                          source="docker.io/x@sha256:00", path_prepend=["gcc/bin", "msys64/usr/bin"],
                          msystem="MINGW64")
    @test parse_toolchain_env(read(joinpath(root, "toolchain.env"), String)) == parse_toolchain_env(GOOD_ENV)
    json = parse_json(read(joinpath(root, "toolchain.json"), String))
    @test json["image"] == "package_windows.x86_64" && json["tag"] == "v8.10"
    @test json["msys2_packages"] == ["bash 5.3-1"]
end

@testset "Docker image metadata" begin
    @test parse_json("""{"a": [1, "x\\"y", true, null, {"b": "C:\\\\msys64"}], "c": {}}""") ==
          Dict("a" => Any[1.0, "x\"y", true, nothing, Dict("b" => "C:\\msys64")], "c" => Dict{String,Any}())
    manifest = parse_json("""{"config": {"digest": "sha256:c"}, "layers": [{"digest": "sha256:1"},
                             {"digest": "sha256:2"}, {"digest": "sha256:3"}, {"digest": "sha256:4"}]}""")
    config = parse_json("""{"config": {"Env": ["MSYSTEM=MINGW64"]}, "history": [
        {"created_by": "Apply image 10.0.20348.4294"},
        {"created_by": "cmd /S /C #(nop) COPY dir:a845 in C:\\\\msys64 "},
        {"created_by": "cmd /S /C #(nop) COPY dir:9460 in C:\\\\gcc "},
        {"created_by": "cmd /S /C #(nop)  ARG X=1", "empty_layer": true},
        {"created_by": "cmd /S /C setx /M PATH \\"C:\\\\gcc\\\\bin;%PATH%\\""}],
        "rootfs": {"type": "layers"}}""")
    layers = image_layers(manifest, config)
    @test length(layers) == 4
    trees, setx = toolchain_layers(layers)
    @test trees == Dict("msys64" => "sha256:2", "gcc" => "sha256:3") && setx == "sha256:4"

    # Hive data: UTF-16LE strings among binary data
    utf16(s) = reinterpret(UInt8, transcode(UInt16, s))
    hive = vcat(UInt8[0, 1, 2], utf16("C:\\msys64\\usr\\bin\\bash.exe"), UInt8[0xff, 0],
                utf16("C:\\buildkite-agent\\bin;C:\\gcc\\bin;C:\\msys64\\mingw64\\bin;C:\\msys64\\usr\\bin;C:\\Windows\\system32;"),
                UInt8[0, 0])
    @test "C:\\msys64\\usr\\bin\\bash.exe" in utf16_strings(hive)
    @test path_prepend_from_hive(hive) == ["gcc/bin", "msys64/mingw64/bin", "msys64/usr/bin"]
    outside = vcat(utf16("C:\\tools\\bin;C:\\msys64\\usr\\bin;C:\\Windows;"), UInt8[0, 0])
    @test_throws ErrorException path_prepend_from_hive(outside)
    @test_throws ErrorException path_prepend_from_hive(UInt8[1, 2, 3])
end

@testset "add_images.jl" begin
    if Sys.which("gzip") === nothing
        @info "Skipping the add_images.jl tests: no gzip"
    else
    mktempdir() do dir
        artifacts_toml = joinpath(dir, "Artifacts.toml")
        project_toml = joinpath(dir, "Project.toml")
        tarballs = mkpath(joinpath(dir, "tarballs"))
        function publish(image, root)
            tarball = joinpath(tarballs, "$(image).tar.gz")
            open(io -> Tar.create(root, io), pipeline(`gzip -9`, stdout=tarball), "w")
            return bytes2hex(Pkg.GitTools.tree_hash(root))
        end
        add(images...; tag="v9.0") = AddImages.add_images(artifacts_toml, project_toml, tag, collect(images); from=tarballs)
        version() = match(r"version = \"(.*)\"", read(project_toml, String))[1]
        # A catalog of v8.13
        function catalog_v8_13(names...)
            rm(artifacts_toml; force=true)
            for name in names
                Pkg.Artifacts.bind_artifact!(artifacts_toml, name, Base.SHA1("1"^40); lazy=true,
                                             download_info=[("https://example.com/$(name).tar.gz", "2"^64)])
            end
            write(project_toml, "name = \"RootfsImages\"\nversion = \"8.13.0\"\n")
        end

        hash = publish("package_windows.x86_64", windows_tree())
        linux = mktempdir()
        write(joinpath(linux, "hello"), "hi")
        linux_hash = publish("debian_minimal.x86_64", linux)

        # The release the version is of: added to it, patch version
        catalog_v8_13("package_linux.x86_64")
        @test add("debian_minimal.x86_64"; tag="v8.13") == ["debian_minimal.x86_64"]
        @test sort(collect(keys(TOML.parsefile(artifacts_toml)))) ==
              ["debian_minimal.x86_64", "package_linux.x86_64"]
        @test version() == "8.13.1"
        # Within a release a listed name keeps its content, and older releases are refused
        catalog_v8_13("debian_minimal.x86_64")
        before = read(artifacts_toml, String)
        @test_throws ErrorException add("debian_minimal.x86_64"; tag="v8.13")
        @test_throws ErrorException add("debian_minimal.x86_64"; tag="v8.12")
        @test read(artifacts_toml, String) == before && version() == "8.13.0"

        # A new release replaces every entry, also the content of a name it keeps (v8.13's
        # debian_minimal.x86_64 has another tree hash), and sets the version
        catalog_v8_13("debian_minimal.x86_64", "package_linux.x86_64")
        @test add("package_windows.x86_64", "debian_minimal.x86_64") ==
              ["package_windows.x86_64", "debian_minimal.x86_64"]
        entries = TOML.parsefile(artifacts_toml)
        @test sort(collect(keys(entries))) == ["debian_minimal.x86_64", "package_windows.x86_64"]
        @test entries["package_windows.x86_64"]["git-tree-sha1"] == hash
        @test entries["debian_minimal.x86_64"]["git-tree-sha1"] == linux_hash
        @test entries["package_windows.x86_64"]["download"][1]["url"] ==
              "https://github.com/JuliaCI/rootfs-images/releases/download/v9.0/package_windows.x86_64.tar.gz"
        @test version() == "9.0.0"
        @test !isfile(artifacts_toml * ".new")

        # The same content again: nothing changes
        before = read(artifacts_toml, String)
        @test add("package_windows.x86_64") == String[]
        @test read(artifacts_toml, String) == before && version() == "9.0.0"

        # Different content under a published name: refused, and nothing is written, not even
        # the other (new) image of the same call
        write(joinpath(linux, "hello"), "changed")
        publish("debian_minimal.x86_64", linux)
        publish("debian_minimal.i686", linux)
        @test_throws ErrorException add("debian_minimal.i686", "debian_minimal.x86_64")
        @test read(artifacts_toml, String) == before && version() == "9.0.0"

        # An image added to the release later: kept with the others, patch version
        @test add("debian_minimal.i686") == ["debian_minimal.i686"]
        @test length(TOML.parsefile(artifacts_toml)) == 3 && version() == "9.0.1"
        before = read(artifacts_toml, String)

        # Tags that aren't a release vA.B, and older releases, are refused
        for tag in ("v9", "9.0", "v9.0.0", "v9.00", "v09.1", "v9.1-rc1", "v8.13", "v8.99")
            @test_throws ErrorException add("debian_minimal.i686"; tag)
        end
        @test read(artifacts_toml, String) == before && version() == "9.0.1"

        # Windows rules
        publish("package_windows.i686", windows_tree(root -> chmod(joinpath(root, "toolchain.env"), 0o644)))
        @test_throws ErrorException add("package_windows.i686")
        publish("package_windows.i686", windows_tree(root -> rm(joinpath(root, "toolchain.json"))))
        @test_throws ErrorException add("package_windows.i686")

        # Pkg.jl#4707
        bad = mktempdir()
        write(joinpath(bad, "Főtanúsítvány.pem"), "")
        symlink("Főtanúsítvány.pem", joinpath(bad, "link"))
        publish("tester_linux.x86_64", bad)
        @test_throws ErrorException add("tester_linux.x86_64")
        @test_throws ErrorException add("not-an-image")
        @test_throws ErrorException add("debian_minimal.i686", "debian_minimal.i686")
        # The tree must say what it is
        publish("package_windows.i686", windows_tree(image="package_windows.x86_64"))
        @test_throws ErrorException add("package_windows.i686")
        publish("package_windows.i686", windows_tree(image="package_windows.i686", tag="v8.10"))
        @test_throws ErrorException add("package_windows.i686")
        # A listed asset that changed its bytes (same tree, recompressed)
        open(io -> Tar.create(windows_tree(), io),
             pipeline(`gzip -1`, stdout=joinpath(tarballs, "package_windows.x86_64.tar.gz")), "w")
        @test_throws ErrorException add("package_windows.x86_64")
        @test read(artifacts_toml, String) == before && version() == "9.0.1"

        # The next release, with the same image under the same name: its entry points at the new
        # release's asset
        @test add("debian_minimal.i686"; tag="v9.1") == ["debian_minimal.i686"]
        entries = TOML.parsefile(artifacts_toml)
        @test collect(keys(entries)) == ["debian_minimal.i686"]
        @test entries["debian_minimal.i686"]["download"][1]["url"] ==
              "https://github.com/JuliaCI/rootfs-images/releases/download/v9.1/debian_minimal.i686.tar.gz"
        @test version() == "9.1.0"
    end
    end
end

end
