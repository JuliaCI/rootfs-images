# Utility functions
getuid() = ccall(:getuid, Cint, ())
getgid() = ccall(:getgid, Cint, ())
chroot(rootfs, cmds...; uid=getuid(), gid=getgid()) = run(`sudo chroot --userspec=$(uid):$(gid) $(rootfs) $(cmds)`)
