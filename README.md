# Rootfs images for Base Julia CI

[![Build (Linux)][linux-img]][linux-url]
[![Build (Windows)][windows-img]][windows-url]

[linux-img]: https://github.com/JuliaCI/rootfs-images/actions/workflows/linux.yml/badge.svg "Build (Linux)"
[linux-url]: https://github.com/JuliaCI/rootfs-images/actions/workflows/linux.yml?query=branch%3Amain

[windows-img]: https://github.com/JuliaCI/rootfs-images/actions/workflows/windows.yml/badge.svg "Build (Windows)"
[windows-url]: https://github.com/JuliaCI/rootfs-images/actions/workflows/windows.yml?query=branch%3Amain

The [Base Julia](https://github.com/JuliaLang/julia) CI setup makes use of rootfs images that contain our build tools.
Most images are based on Debian, making use of `debootstrap` to provide a quick and easy rootfs with packages installed through an initial `apt` invocation.

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

If you want to test a rootfs image locally, you can use the `test_rootfs.jl` script, passing in the URL of the rootfs you want to test.  It will drop you into a shell within the build environment, where you can recreate build failures more reliably.

To see the instructions for running the `test_rootfs.jl` script, run:
```
julia --project test_rootfs.jl --help
```

#### Example

Suppose that you want to test the rootfs image at `https://github.com/JuliaCI/rootfs-images/releases/download/v3.18/package_linux.x86_64.tar.gz`. First, run the following command:
```
julia --project test_rootfs.jl --url https://github.com/JuliaCI/rootfs-images/releases/download/v3.18/package_linux.x86_64.tar.gz
```

This will print out a message with the tree hash of the rootfs. Now, run the following command:

```
julia --project test_rootfs.jl --url https://github.com/JuliaCI/rootfs-images/releases/download/v3.18/package_linux.x86_64.tar.gz --treehash 1234567890000000000000000000000000000000
```

(Replace `1234567890000000000000000000000000000000` with the tree hash that was printed in the previous step.)

This will drop you into a shell within the build environment.

## Serving images from the Pkg server

The Pkg servers only mirror artifacts that a registered package lists in its `Artifacts.toml`.
The `RootfsImages` package in the [`RootfsImages`](RootfsImages) directory exists for that: it
has no code, and its `Artifacts.toml` lists rootfs images as lazy artifacts. Once a version that
lists an image is registered in General, the image can be fetched by tree hash from
`https://pkg.julialang.org/artifact/<git-tree-sha1>`, e.g. by the artifact store of
[sandboxed-buildkite-agent](https://github.com/JuliaCI/sandboxed-buildkite-agent).

The Pkg servers look at the artifacts of a version only when they first see it. When a
release is published, the `register_images` job of the Linux workflow runs, once all images are
built and uploaded:

```
julia RootfsImages/add_images.jl v8.13 <every image of the release>
```

This adds each image as `<image>.<arch>.<tag>`, keeping the entries of other tags (CI pins
different releases of the same image, and release branches keep older ones), and bumps the
patch version. The job opens a pull request with the result. GitHub doesn't start workflows
for it, so close and reopen it to run the required checks, merge it, and register the merge
commit with `@JuliaRegistrator register subdir=RootfsImages`. To list images of an older
release, run `add_images.jl` with its tag by hand. It refuses images with a symlink whose target
isn't ASCII: Pkg and the Pkg servers disagree on their tree hash (JuliaLang/Pkg.jl#4707).
