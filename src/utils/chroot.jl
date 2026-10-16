# Utility functions

getuid() = ccall(:getuid, Cint, ())
getgid() = ccall(:getgid, Cint, ())

function chroot_command(rootfs, cmds...; ENV::AbstractDict, uid=getuid(), gid=getgid())
    # `sudo` replaces the environment according to the host's policy (e.g. its
    # `secure_path`, which lacks `/usr/sbin` on some distributions), so set it in the chroot
    env = ["$(key)=$(value)" for (key, value) in ENV]
    return `sudo chroot --userspec=$(uid):$(gid) $(rootfs) /usr/bin/env -i $(env) $(cmds)`
end

function root_chroot_command(varargs...; ENV::AbstractDict)
    uid = 0
    gid = 0
    return chroot_command(varargs...; ENV, uid, gid)
end

chroot(varargs...; kwargs...)      = run(chroot_command(varargs...; kwargs...))
root_chroot(varargs...; kwargs...) = run(root_chroot_command(varargs...; kwargs...))
