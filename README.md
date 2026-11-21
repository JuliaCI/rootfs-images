# Rootfs images for Base Julia CI

[![Build][build-img]][build-url]

[build-img]: https://github.com/JuliaCI/rootfs-images/actions/workflows/linux.yml/badge.svg "Build"
[build-url]: https://github.com/JuliaCI/rootfs-images/actions/workflows/linux.yml?query=branch%3Amain

The [Base Julia](https://github.com/JuliaLang/julia) CI setup makes use of rootfs images that contain our build tools.
Every image is a directory tree, published as `<image>.<arch>.tar.gz` on a release of this repository and identified by its git tree hash:

- Linux images (`linux/*.jl`) are the root of the sandbox a job runs in. Most are based on Debian, making use of `debootstrap` to provide a quick and easy rootfs with packages installed through an initial `apt` invocation.
- Windows toolchains (`windows/package_windows.jl`, images `package_windows.{x86_64,i686}`) hold MSYS2 and the GCC of GCCToolchain_jll, which Julia's Windows builds use; see [below](#windows-toolchains).

This repository contains the scripts to build the rootfs images.
The other configuration files for Base Julia CI are located in the [`.buildkite`](https://github.com/JuliaLang/julia/tree/master/.buildkite) directory in the [Julia](https://github.com/JuliaLang/julia) repository.

The documentation for the Base Julia CI setup is located in the [base-buildkite-docs](https://github.com/JuliaCI/base-buildkite-docs) repository.

## Cloning this repository

```
git clone https://github.com/JuliaCI/rootfs-images.git
cd rootfs-images
```

## Instantiating the environment

```
julia --project -e 'import Pkg; Pkg.instantiate()'
```

## Testing out a rootfs image

`test_rootfs.jl` runs a command, by default a shell, in an image listed in
[`RootfsImages/Artifacts.toml`](RootfsImages/Artifacts.toml), named `<image>.<arch>.<tag>`:

```
julia --project test_rootfs.jl package_linux.x86_64.v8.13
julia --project test_rootfs.jl package_linux.x86_64.v8.13 -- gcc --version
```

It installs the image like Pkg installs any artifact (from the Pkg server, or else from the release, checking the tree hash), so it works before RootfsImages is registered. The current directory's `build/` is mapped as the working directory (`--map-build-dir=temp` for a throwaway one); `--help` lists the other options.

- **On Linux**, a Linux image is the root of a [Sandbox.jl](https://github.com/staticfloat/Sandbox.jl) sandbox, as in CI.
- **On Windows**, a Windows toolchain runs as in CI: the tree's own `bash` (not a login shell), with the toolchain's directories ahead of `PATH` and the `MSYSTEM` that its `toolchain.env` names, and `HOME` and the temporary directory outside the tree (`temp/`), so the installed tree is never modified.
- **On Linux, for a Windows VM**: make an NTFS disk of the tree with `platforms/windows-kvm/ntfsdisk.sh` from [sandboxed-buildkite-agent](https://github.com/JuliaCI/sandboxed-buildkite-agent), as the CI hosts do, and attach it to the VM; in the guest, give its `JLTC` volume a drive letter and run `<letter>:\msys64\usr\bin\bash.exe` with the environment of `toolchain.env`.

An image that is not listed (e.g. one built from a branch) can be given by URL and tree hash instead.
Running with only `--url` prints the tree hash to pass with `--treehash`:

```
julia --project test_rootfs.jl --url https://github.com/JuliaCI/rootfs-images/releases/download/v8.13/package_linux.x86_64.tar.gz
julia --project test_rootfs.jl --url https://github.com/JuliaCI/rootfs-images/releases/download/v8.13/package_linux.x86_64.tar.gz --treehash <tree hash>
```

## Windows toolchains

A `package_windows.<arch>` image is a tree with:

- `msys64/`: [MSYS2](https://www.msys2.org), with the packages Julia's build needs;
- `gcc/`: the GCC of GCCToolchain_jll, built like the one CompilerSupportLibraries_jll comes from (older tags have no `gcc/` and use MSYS2's compilers);
- `toolchain.env`: the environment the toolchain needs, as `KEY=VALUE` lines: `PATH_PREPEND` (`;`-separated directories, relative to the tree), `MSYSTEM` and `MSYS2_PATH_TYPE=inherit`, each exactly once;
- `toolchain.json`: which image this is, what it was made from, and the installed MSYS2 packages.

Both arches run on x86_64 Windows; `i686` is the target. CI attaches the tree to the Windows VM as a read-only disk with drive letter `T:`, and the build step runs through julia-buildkite's `utilities/windows/toolchain.sh`. A tree must follow the rules in [`src/windows_rules.jl`](src/windows_rules.jl): every file mode 0755 (on Windows, Tar.jl turns 0644 into an ACL that forbids running a program), only files and directories, names valid on NTFS, and short paths. The builders check them, and so does `add_images.jl`.

New toolchains are built natively on a `windows-2022` runner, as rows of the build workflow. The trees of the tags that predate this (v8.5, v8.10, built as Docker images) were converted from the published images, by digest:

```
julia --project windows/convert_docker.jl --arch x86_64 --tag v8.10 \
    --image juliapackaging/package-windows-x86_64@sha256:<digest>
```

## Serving images from the Pkg server

The Pkg servers only mirror artifacts that a registered package lists in its `Artifacts.toml`.
The `RootfsImages` package in the [`RootfsImages`](RootfsImages) directory exists for that: it
has no code, and its `Artifacts.toml` lists rootfs images as lazy artifacts. Once a version that
lists an image is registered in General, the image can be fetched by tree hash from
`https://pkg.julialang.org/artifact/<git-tree-sha1>`, e.g. by the artifact store of
[sandboxed-buildkite-agent](https://github.com/JuliaCI/sandboxed-buildkite-agent).

The Pkg servers look at the artifacts of a version only when they first see it. When a
release is published, the `register_images` job of the build workflow runs, once all images are
built and uploaded:

```
julia RootfsImages/add_images.jl v8.13 <every image of the build matrix>
```

This adds each image as `<image>.<arch>.<tag>`, keeping the entries of other tags (CI pins
different releases of the same image, and release branches keep older ones), and bumps the
patch version. The job opens a pull request with the result. GitHub doesn't start workflows
for it, so close and reopen it to run the required checks, merge it, and register the merge
commit with `@JuliaRegistrator register subdir=RootfsImages`.

A listed name never changes content: `add_images.jl` refuses an image whose tree hash differs
from the one listed, and writes nothing unless every image passes its checks. It also refuses
images with a symlink whose target isn't ASCII (Pkg and the Pkg servers disagree on their tree
hash, JuliaLang/Pkg.jl#4707), and Windows toolchains that break the tree rules. To list images
added to an older release, run it with that tag and their names by hand; `--from DIR` reads the
tarballs from `DIR` instead of the release, to prepare the entries before uploading them.
