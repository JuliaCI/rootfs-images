# Utility functions

getuid() = ccall(:getuid, Cint, ())
getgid() = ccall(:getgid, Cint, ())

function chroot_command(rootfs, cmds...; ENV::AbstractDict, uid=getuid(), gid=getgid())
    command = `sudo chroot --userspec=$(uid):$(gid) $(rootfs) $(cmds)`
    return setenv(command, ENV)
end

function root_chroot_command(varargs...; ENV::AbstractDict)
    uid = 0
    gid = 0
    return chroot_command(varargs...; ENV, uid, gid)
end

chroot(varargs...; kwargs...)      = run(chroot_command(varargs...; kwargs...))
root_chroot(varargs...; kwargs...) = run(root_chroot_command(varargs...; kwargs...))
