# Build the Windows toolchain tree `package_windows.<arch>` natively on Windows (a GitHub
# `windows-2022` runner in CI): MSYS2 with the packages Julia's Windows build needs, and the GCC
# of GCCToolchain_jll in `gcc/`, ahead of MSYS2's on PATH.
#
#     julia --project windows/package_windows.jl --arch x86_64
#
# The MSYS2 base and the GCC tarball are pinned by sha256. The MSYS2 packages are not: pacman
# installs the current ones, so a rebuild differs, and the published tree is the record
# (`toolchain.json` lists the packages).

using RootfsUtils: parse_build_args, create_windows_toolchain, write_toolchain_files,
                   toolchain_cmd, upload_gha
import Downloads, Pkg, SHA, Tar

Sys.iswindows() || error("package_windows is built on Windows")

args    = parse_build_args(ARGS, @__FILE__)
arch    = args.arch
archive = args.archive
image   = args.image
arch in ("x86_64", "i686") || error("unknown arch $(arch)")

# The x86_64 MSYS2 base serves both: MSYS2 itself is 64-bit, and the i686 toolchain comes from
# its `mingw32` packages. repo.msys2.org drops installers after about two years; the GitHub
# releases keep them. The `.tar.xz`, since Pkg's 7-Zip doesn't read zstd.
const MSYS2_TAG = "2026-11-20"
const MSYS2_URL = "https://github.com/msys2/msys2-installer/releases/download/$(MSYS2_TAG)/msys2-base-x86_64-$(replace(MSYS2_TAG, "-" => "")).tar.xz"
const MSYS2_SHA256 = "bd267f65e3656706d5e3b27d4f7d6c498e8ee3a54fcc3be200b7079bfc01f74a"

# The C/C++/Fortran toolchain is not MSYS2's, but GCCToolchain_jll (Yggdrasil's
# `G/GCCToolchain`): GCC 15.2 built like the GCC that CompilerSupportLibraries_jll comes from,
# whose runtime DLLs Julia ships (with SJLJ exceptions on i686). MSYS2's newer GCC compiles
# against headers that need symbols those DLLs lack. It goes in its own prefix, `gcc/`, ahead
# of MSYS2's on PATH; MSYS2's own programs keep loading the DLLs next to them. Like MSYS2's GCC,
# it uses unaligned vector moves by default, as 64-bit Windows does not align AVX stack slots
# (GCC PR 54412). Bump only together with CompilerSupportLibraries_jll's GCC.
const GCC_TOOLCHAIN = Dict(
    "x86_64" => ("https://github.com/JuliaBinaryWrappers/GCCToolchain_jll.jl/releases/download/GCCToolchain-v15.2.0+2/GCCToolchain.v15.2.0.x86_64-w64-mingw32.tar.gz",
                 "fe7fec1556dcd5bac07adf21bf862411a29b6b789876eafbac5a9ad1dc7f9164"),
    "i686"   => ("https://github.com/JuliaBinaryWrappers/GCCToolchain_jll.jl/releases/download/GCCToolchain-v15.2.0+2/GCCToolchain.v15.2.0.i686-w64-mingw32.tar.gz",
                 "abeeb7195417b12462799b07027c0dfef431f515df9fa977a3716c8ca5fd7782"),
)

const MINGW = Dict("x86_64" => "mingw64", "i686" => "mingw32")
const MINGW_PREFIX = Dict("x86_64" => "mingw-w64-x86_64", "i686" => "mingw-w64-i686")
const PACKAGES = Dict(
    "x86_64" => ["$(MINGW_PREFIX["x86_64"])-cmake", "diffutils", "git", "m4", "make", "patch", "tar",
                 "p7zip", "curl", "python3", "openssl", "gnupg2"],
    "i686"   => ["$(MINGW_PREFIX["i686"])-cmake", "diffutils", "git", "m4", "make", "patch", "tar",
                 "p7zip", "curl", "python3"],
)
# Julia's build runs under MINGW64 on both: i686 differs only in PATH (the Docker images did the same)
const MSYSTEM = "MINGW64"

function download_verified(url, sha256, dir)
    path = joinpath(dir, basename(url))
    @info("Downloading $(url)")
    Downloads.download(url, path)
    actual = bytes2hex(open(SHA.sha256, path))
    actual == sha256 || error("$(url): sha256 is $(actual), expected $(sha256)")
    return path
end

# Extract a compressed tarball with Pkg's 7-Zip and Tar.jl (symlinks become copies)
function extract(tarball, dest)
    open(`$(Pkg.PlatformEngines.exe7z()) x $(tarball) -so`) do io
        Tar.extract(io, dest; copy_symlinks=true)
    end
end

# Run a login shell of the MSYS2 being built, with none of the runner's own MSYS2 or Git on
# PATH. Afterwards, stop what it left running: pacman starts gpg-agent and dirmngr, which outlive
# it and keep files of the tree open, and an upgrade of the MSYS2 runtime must not find old
# processes using it.
function msys2(root, script)
    msys64 = joinpath(root, "msys64")
    sysroot = get(ENV, "SystemRoot", "C:\\Windows")
    path = join([joinpath(msys64, "usr", "bin"), joinpath(sysroot, "System32"), sysroot,
                 joinpath(sysroot, "System32", "WindowsPowerShell", "v1.0")], ';')
    @info("msys2: $(script)")
    try
        run(addenv(`$(joinpath(msys64, "usr", "bin", "bash.exe")) -lc $(script)`,
                   "PATH" => path, "MSYSTEM" => "MSYS", "CHERE_INVOKING" => "1"))
    finally
        stop_msys2_processes(root)
    end
end

# The root is passed as data (it may hold quotes or wildcard characters) and compared as a
# literal prefix
function stop_msys2_processes(root)
    script = raw"""
        $root = $env:TOOLCHAIN_ROOT.TrimEnd('\') + '\'
        $ps = @(Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) })
        if ($ps.Count -gt 0) {
            $ps | Format-Table Id, Path | Out-String | Write-Output
            $ps | Stop-Process -Force
            $ps | Wait-Process -Timeout 60
        }
        """
    run(addenv(`powershell -NoProfile -NonInteractive -Command $(script)`, "TOOLCHAIN_ROOT" => root))
end

# The commit of the recipe; a local build from a copy without git says so instead of failing
function source_info()
    sha = get(ENV, "GITHUB_SHA", "")
    if isempty(sha)
        sha = try
            readchomp(pipeline(`git -C $(@__DIR__) rev-parse HEAD`; stderr=devnull))
        catch
            return "local build (no git checkout)"
        end
    end
    return "github.com/JuliaCI/rootfs-images@$(sha)"
end

# The release tag on a release build; else the commit, so that a test build is never mistaken
# for a published one
function tag_info()
    m = match(r"^refs/tags/(.+)$", get(ENV, "GITHUB_REF", ""))
    m !== nothing && return String(m[1])
    return "untagged"
end

artifact_hash, tarball_path = mktempdir() do downloads
    msys2_base = download_verified(MSYS2_URL, MSYS2_SHA256, downloads)
    gcc_url, gcc_sha256 = GCC_TOOLCHAIN[arch]
    gcc_tarball = download_verified(gcc_url, gcc_sha256, downloads)

    create_windows_toolchain(image; archive) do root
        extract(msys2_base, root)
        # Tar.jl turns the tarball's 0644 into an ACL that forbids running the .exe files
        chmod(root, 0o755; recursive=true)
        # MSYS2's profile runs its first-start setup (which initializes the keyring) only when
        # HOME is unset, and the runner sets it: initialize the keyring explicitly
        msys2(root, "pacman-key --init && pacman-key --populate msys2")
        # The first upgrade replaces the MSYS2 runtime and stops; the next ones finish it
        msys2(root, "pacman -Syuu --noconfirm --noprogressbar")
        msys2(root, "pacman -Syu --needed --noconfirm --noprogressbar")
        msys2(root, "pacman -Syu --needed --noconfirm --noprogressbar")
        msys2(root, "pacman -S --needed --noconfirm --noprogressbar $(join(PACKAGES[arch], ' '))")
        msys2(root, "git config --system core.longpaths true")
        msys2(root, "pacman -Scc --noconfirm")

        extract(gcc_tarball, joinpath(root, "gcc"))
        path_prepend = ["gcc/bin", "msys64/$(MINGW[arch])/bin", "msys64/usr/bin"]
        write_toolchain_files(root; image, arch, tag=tag_info(), source=source_info(),
                              path_prepend, msystem=MSYSTEM)
    end
end

# Smoke test, through the same environment the CI wrapper sets up: the toolchain's GCC compiles
# and links a program that runs, and the tools Julia's build uses are there.
let root = Pkg.Artifacts.artifact_path(artifact_hash)
    mktempdir() do dir
        home = mkpath(joinpath(dir, "home"))
        tmp = mkpath(joinpath(dir, "tmp"))
        script = """
            set -eux
            case "\$(command -v gcc)" in */gcc/bin/gcc) ;; *) echo "gcc is not the tree's"; exit 1 ;; esac
            gcc --version
            gcc -dumpmachine | grep -q '^$(arch)-w64-mingw32\$'
            printf '#include <stdio.h>\\nint main(void){puts("hello");return 0;}\\n' > hello.c
            gcc -O2 hello.c -o hello.exe
            test "\$(./hello.exe)" = hello
            for tool in make cmake git python3 curl patch m4 7z cygpath; do command -v \$tool; done
            """
        run(Cmd(toolchain_cmd(root, ["bash", "-c", script]; home, tmp); dir))
    end
    Pkg.Artifacts.verify_artifact(artifact_hash) || error("The smoke test modified the tree")
    @info("Smoke test passed; the tree is unmodified", artifact_hash)
end

upload_gha(tarball_path)
