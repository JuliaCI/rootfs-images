# Tests of the image tooling that runs without building an image (no root, no network):
#
#     julia --project test/runtests.jl

using RootfsUtils
using RootfsUtils: parse_toolchain_env, render_toolchain_env, toolchain_path_entries,
                   check_windows_tarball, check_windows_tree, normalize_windows_tree!,
                   msys2_packages, write_toolchain_files, parse_json, image_layers,
                   toolchain_layers, path_prepend_from_hive, utf16_strings
using Test, Tar, Pkg

const GOOD_ENV = "PATH_PREPEND=gcc\\bin;msys64\\usr\\bin\nMSYSTEM=MINGW64\nMSYS2_PATH_TYPE=inherit\n"

# A minimal valid tree; `f(root)` can break it afterwards
function windows_tree(f=identity)
    root = mktempdir()
    for dir in ("msys64/usr/bin", "gcc/bin", "msys64/var/lib/pacman/local/bash-5.3-1")
        mkpath(joinpath(root, dir))
    end
    write(joinpath(root, "msys64/usr/bin/bash.exe"), "MZ")
    write(joinpath(root, "msys64/var/lib/pacman/local/bash-5.3-1/desc"),
          "%NAME%\nbash\n\n%VERSION%\n5.3-1\n\n%DESC%\nThe GNU Bourne Again shell\n")
    write(joinpath(root, "toolchain.env"), GOOD_ENV)
    write(joinpath(root, "toolchain.json"), "{}")
    chmod(root, 0o755; recursive=true)
    f(root)
    return root
end

function check_tree(root; kwargs...)
    tarball = tempname()
    Tar.create(root, tarball)
    try
        return check_windows_tarball(tarball; kwargs...)
    finally
        rm(tarball)
    end
end

@testset "RootfsUtils" begin

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

    has_error(r, pattern) = any(e -> occursin(pattern, e), r.errors)
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
                            ("a\\b", "invalid character"))
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
        hardlink(joinpath(msys64, "usr/bin/bash.exe"), joinpath(msys64, "usr/bin/sh.exe"))
        chmod(joinpath(msys64, "usr/bin/bash.exe"), 0o644)
    end
    normalize_windows_tree!(root)
    msys64 = joinpath(root, "msys64")
    @test !ispath(joinpath(msys64, "etc/pacman.d/gnupg"))
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

end
