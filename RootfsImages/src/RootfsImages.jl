"""
The rootfs images that Julia's CI runs in, built by https://github.com/JuliaCI/rootfs-images.

This package has no code. Its `Artifacts.toml` lists the images as lazy artifacts, so that the
Pkg servers mirror them and they can be fetched by tree hash from
`https://pkg.julialang.org/artifact/<git-tree-sha1>`.
"""
module RootfsImages
end
