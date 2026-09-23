# Install the native GCC toolchain of GCCToolchain_jll (Yggdrasil's `G/GCCToolchain`:
# GCC, binutils, and a sysroot with an old glibc and Linux kernel headers) into
# `/usr/local` of a Debian-based rootfs, and symlink it as the default
# `gcc`/`g++`/`gfortran`/`cc`/`c++`/`ld`.
#
# This is the compiler toolchain used by Julia's Linux package builds, so it is shared
# between the `package_linux` and `package_linux_mmtk` images to keep them in sync.
#
# The toolchain is pinned by `GCCToolchain_jll.Artifacts.toml`, a copy of the
# `Artifacts.toml` of the JLL version named in its first line; to update it, copy the
# file of a newer version. Its GCC must never be newer than the one
# CompilerSupportLibraries_jll is built with (Julia ships that libstdc++/libgcc_s/
# libgfortran); the recipe is bumped together with CSL.
const GCC_TOOLCHAIN_ARTIFACTS_TOML = joinpath(@__DIR__, "GCCToolchain_jll.Artifacts.toml")

function install_gcc_toolchain(rootfs::String, chroot_ENV::AbstractDict, arch::String)
    arch = normalize_arch(arch)
    my_chroot(args...) = root_chroot(rootfs, "bash", "-eu", "-o", "pipefail", "-c", args...; ENV=chroot_ENV)

    # Download (and verify) the toolchain for the image's architecture, and copy it in
    platform = Base.BinaryPlatforms.Platform(arch, "linux"; libc="glibc")
    toolchain = Pkg.Artifacts.ensure_artifact_installed("GCCToolchain", GCC_TOOLCHAIN_ARTIFACTS_TOML; platform)
    run(`sudo cp -R --no-dereference --preserve=mode,timestamps $(toolchain)/. $(rootfs)/usr/local/`)
    # Artifacts are read-only
    my_chroot("chmod -R u+w /usr/local")

    # Its tools are prefixed with the GCC triplet
    gcc_triplet = arch == "armv7l" ? "arm-linux-gnueabihf" : "$(arch)-linux-gnu"
    gcc_version = only(readdir(joinpath(toolchain, "lib", "gcc", gcc_triplet)))

    gcc_symlink_cmd = """
    # Create symlinks for `gcc` -> `$(gcc_triplet)-gcc`, etc...
    for tool_path in /usr/local/bin/$(gcc_triplet)-*; do
        tool="\$(basename "\${tool_path}" | sed -e 's/$(gcc_triplet)-//')"
        ln -vsf "$(gcc_triplet)-\${tool}" "/usr/local/bin/\${tool}"
    done
    # Also create symlinks for `cc` and `c++`.
    ln -vsf "/usr/local/bin/gcc" "/usr/local/bin/cc"
    ln -vsf "/usr/local/bin/g++" "/usr/local/bin/c++"
    """
    # Our GCC's runtime libraries are newer than Debian's, so programs built by it
    # (e.g. build tools that run during a build) may not run against the system ones.
    # Replace those with ours: they are backwards compatible.
    gcc_runtime_cmd = """
    gcc_libdir="/usr/local/lib/gcc/$(gcc_triplet)/$(gcc_version)"
    system_libdir="\$(dirname "\$(echo /usr/lib/*/libstdc++.so.6)")"
    for lib in libstdc++.so.6 libgcc_s.so.1 libgfortran.so.5 libquadmath.so.0 libgomp.so.1 libatomic.so.1; do
        if [[ -e "\${gcc_libdir}/\${lib}" ]]; then
            real="\$(readlink -f "\${gcc_libdir}/\${lib}")"
            cp -v "\${real}" "\${system_libdir}/"
            if [[ "\$(basename "\${real}")" != "\${lib}" ]]; then
                ln -vsf "\$(basename "\${real}")" "\${system_libdir}/\${lib}"
            fi
        fi
    done
    ldconfig
    """
    my_chroot(gcc_symlink_cmd)
    my_chroot(gcc_runtime_cmd)

    # Show what is installed
    for tool in ("gcc", "g++", "gfortran", "ld")
        my_chroot("which $(tool)")
        my_chroot("which -a $(tool)")
    end
    my_chroot("gcc --version")
    my_chroot("g++ --version")
    my_chroot("gfortran --version")
    my_chroot("ld --version")

    # Sanity check: the toolchain builds and runs C, C++ and Fortran code, and what it
    # builds does not need a newer glibc than the one in its sysroot.
    glibc_floor = arch in ("aarch64", "armv7l") ? "2.19" : "2.17"
    sanity_cmd = """
    cd "\$(mktemp -d)"
    printf '#include <stdio.h>\\nint main(void) { puts("hello from C"); return 0; }\\n' > c.c
    printf '#include <iostream>\\n#include <mutex>\\n#include <thread>\\n#include <variant>\\nint main() { std::once_flag f; std::variant<int, double> v = 1.0; std::thread t([&] { std::call_once(f, [&] { std::cout << "hello from C++ " << std::get<double>(v) << std::endl; }); }); t.join(); }\\n' > cxx.cpp
    printf 'program hello\\n  print *, "hello from Fortran"\\nend program\\n' > f.f90
    gcc -O2 c.c -o c
    ./c
    g++ -std=c++20 -O2 -pthread cxx.cpp -o cxx
    ./cxx
    gfortran -O2 f.f90 -o f
    ./f
    for bin in c cxx f; do
        glibc="\$(objdump -T \${bin} | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -uV | tail -n1)"
        echo "\${bin} requires GLIBC_\${glibc}"
        [[ "\$(printf '%s\\n' "\${glibc}" $(glibc_floor) | sort -V | tail -n1)" == $(glibc_floor) ]]
    done
    """
    my_chroot(sanity_cmd)
end
