# Rootfs images for Base Julia CI

[![Build][build-img]][build-url]

[build-img]: https://github.com/JuliaCI/rootfs-images/actions/workflows/build.yml/badge.svg "Build"
[build-url]: https://github.com/JuliaCI/rootfs-images/actions/workflows/build.yml?query=branch%3Amain

The [Base Julia](https://github.com/JuliaLang/julia) CI setup makes use of rootfs images that contain our build tools.
Most images are based on Debian, making use of `debootstrap` to provide a quick and easy rootfs with packages installed through an initial `apt` invocation.

This repository contains the scripts to build the rootfs images.
The other configuration files for Base Julia CI are located in the [`.buildkite`](https://github.com/JuliaLang/julia/tree/master/.buildkite) directory in the [Julia](https://github.com/JuliaLang/julia) repository.

The documentation for the Base Julia CI setup is located in the [base-buildkite-docs](https://github.com/JuliaCI/base-buildkite-docs) repository.

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
