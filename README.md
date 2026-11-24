# Rootfs images for Base Julia CI

[![Build][build-img]][build-url]

[build-img]: https://github.com/JuliaCI/rootfs-images/actions/workflows/linux.yml/badge.svg "Build"
[build-url]: https://github.com/JuliaCI/rootfs-images/actions/workflows/linux.yml?query=branch%3Amain

The [Base Julia](https://github.com/JuliaLang/julia) CI setup makes use of rootfs images that contain our build tools.
Every image is a directory tree, published as `<image>.<arch>.tar.gz` on a release of this repository and identified by its git tree hash:

- Linux images (`linux/*.jl`) are the root of the sandbox a job runs in. Most are based on Debian, making use of `debootstrap` to provide a quick and easy rootfs with packages installed through an initial `apt` invocation.
- Windows toolchains (`windows/package_windows.jl`, image `package_windows.x86_64`) hold MSYS2 and the GCC of GCCToolchain_jll, which Julia's Windows builds use; see [below](#windows-toolchains).

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

`test_rootfs.jl` runs a command, by default a shell, in an image listed in the
[RootfsImages catalog](#serving-images-from-the-pkg-server), named `<image>.<arch>`:

```
julia --project test_rootfs.jl package_linux.x86_64
julia --project test_rootfs.jl package_linux.x86_64 -- gcc --version
```

It looks the name up in [`RootfsImages/Artifacts.toml`](RootfsImages/Artifacts.toml), which lists the latest release only; images of other releases are run by URL and tree hash (see below). It installs the image like Pkg installs any artifact (from the Pkg server, or else from the release, checking the tree hash), so it works before RootfsImages is registered. The current directory's `build/` is mapped as the working directory (`--map-build-dir=temp` for a throwaway one); `--help` lists the other options.

- **On Linux**, a Linux image is the root of a [Sandbox.jl](https://github.com/staticfloat/Sandbox.jl) sandbox, as in CI.
- **On Windows**, a Windows toolchain runs as in CI: the tree's own `bash` (not a login shell), with the toolchain's directories ahead of `PATH` and the `MSYSTEM` that its `toolchain.env` names, and `HOME` and the temporary directory outside the tree (`temp/`), so the installed tree is never modified.

An image that is not listed (of an older release, or built from a branch) can be given by URL and tree hash instead.
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

New toolchains are x86_64 only, as 32-bit Windows is being phased out; the release branches that still build for 32-bit Windows use `package_windows.i686` of v8.5 (it runs on x86_64 Windows too). CI installs the tree as a Pkg artifact into the job's cache (julia-buildkite's `utilities/windows/install_toolchain.jl`) and runs the build through `utilities/windows/toolchain.sh`. A tree must follow the rules in [`src/windows_rules.jl`](src/windows_rules.jl): every file mode 0755 (on Windows, Tar.jl turns 0644 into an ACL that forbids running a program), only files and directories, names valid on NTFS, and short paths. The builders check them, and so does `add_images.jl`.

New toolchains are built natively on a `windows-2022` runner, as rows of the build workflow. The trees of the tags that predate this (v8.5, v8.10, built as Docker images) were converted from the published images, by digest:

```
julia --project windows/convert_docker.jl --arch x86_64 --tag v8.10 \
    --image juliapackaging/package-windows-x86_64@sha256:<digest> --output out/v8.10
```

## Serving images from the Pkg server

The Pkg servers only mirror artifacts that a registered package lists in its `Artifacts.toml`.
The `RootfsImages` package in the [`RootfsImages`](RootfsImages) directory exists for that: it
has no code, and its `Artifacts.toml` lists rootfs images as lazy artifacts. Once a version that
lists an image is registered in General, the image can be fetched by tree hash from
`https://pkg.julialang.org/artifact/<git-tree-sha1>`, e.g. by the artifact store of
[sandboxed-buildkite-agent](https://github.com/JuliaCI/sandboxed-buildkite-agent).

RootfsImages lists the images of the latest release only, and its version follows the tag:
release `vA.B` is listed by RootfsImages `A.B.0`, and images added to that release later by
`A.B.1`, `A.B.2`, .... The images are named `<image>.<arch>`, without the tag, which the
version already gives. A package that depends on RootfsImages uses e.g.
`artifact"package_linux.x86_64"` and gets the image of the release its RootfsImages version
lists; a `[compat]` bound on RootfsImages pins a release. A registered version stays in
General, so the Pkg servers keep serving the images of older releases; locally, run those by
URL and tree hash. (The Linux images of releases before
v8.13 have symlinks whose target isn't ASCII, see below, so the Pkg servers can't serve them.)

When a release is published, the `register_images` job of the build workflow runs, once all
images are built and uploaded:

```
julia RootfsImages/add_images.jl v8.14 <every image of the build matrix>
```

For a release newer than RootfsImages' version, this replaces the listed images with this
release's, as `<image>.<arch>`, and sets the version to `A.B.0`; for the release the
version is of, it adds the images that aren't listed yet and bumps the patch version. It refuses
tags that aren't `vA.B`, and releases older than the current version (versions only go up).
The job opens a pull request with the result. Its workflows wait for approval (GitHub
runs workflows of pull requests opened with `GITHUB_TOKEN` only once approved), so use
"Approve workflows to run" on it to run the required checks, merge it, and register the merge commit with
`@JuliaRegistrator register subdir=RootfsImages`.

A version that skips a minor version (a tag that was never catalogued) isn't sequential for
General's AutoMerge, so a package author approves it with `[merge approved]` on the General
pull request. A new major release (v9.0, RootfsImages 9.0.0) is a breaking version for General:
give its Registrator comment release notes that mention breaking changes.

**Upload every image of a version before registering it.** A Pkg server reads the
`Artifacts.toml` of a registered version once, when it first sees the version, and never
again; an artifact it fails to download is never retried. An image that isn't on its release
yet when the version is registered is therefore not served for that version. The workflow
keeps this order (the job needs every build, and `add_images.jl` downloads each image from the
release); when listing images by hand with `--from`, upload them before registering.

Within a release, a listed name never changes content: `add_images.jl` refuses an image of
the current release whose tree hash differs from the one listed, and writes nothing unless every
image passes its checks. A newer release replaces the entries, so a name then holds that
release's image. It also refuses
images with a symlink whose target isn't ASCII (Pkg and the Pkg servers disagree on their tree
hash, JuliaLang/Pkg.jl#4707), and Windows toolchains that break the tree rules. To list images
added to the current release later, run it with that tag and their names by hand; `--from DIR`
reads the tarballs from `DIR` instead of the release, to prepare the entries before uploading
them.
