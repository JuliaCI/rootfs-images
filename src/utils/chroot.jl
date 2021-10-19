# Utility functions

getuid() = ccall(:getuid, Cint, ())
getgid() = ccall(:getgid, Cint, ())

function chroot(rootfs, cmds...; ENV::AbstractDict, uid=getuid(), gid=getgid())
    command = `sudo chroot --userspec=$(uid):$(gid) $(rootfs) $(cmds)`
    return run(setenv(command, ENV))
end

root_chroot(args...; ENV::AbstractDict) = chroot(args...; ENV, uid=0, gid=0)
