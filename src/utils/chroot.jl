# Utility functions
getuid() = ccall(:getuid, Cint, ())
getgid() = ccall(:getgid, Cint, ())
function chroot(rootfs, cmds...; ENV=copy(ENV), uid=getuid(), gid=getgid())
    run(setenv(`sudo chroot --userspec=$(uid):$(gid) $(rootfs) $(cmds)`, ENV))
end
