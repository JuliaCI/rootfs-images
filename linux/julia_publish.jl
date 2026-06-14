# The `julia_publish` image carries the full toolchain used by the
# `julia-publish` Buildkite pipeline's `publish_all` step to (re)sign and
# (re)package the per-platform Julia release artifacts:
#
#   * AWS CLI v2        -- download/upload artifacts from/to S3 (the step
#                          previously failed with `aws: command not found`
#                          because it ran on a bare agent).
#   * python3           -- kms_gpg_sign.py, plist editing, the PE-signature
#                          checker (stdlib only).
#   * p7zip-full (`7z`) -- repack the Windows `.zip`.
#   * HFS+/DMG tooling  -- build the macOS `.dmg` on Linux. `hfsplus` (populate
#     (`newfs_hfs`/       an HFS+ image) and `dmg` (HFS+ -> compressed UDIF)
#     `hfsplus`/`dmg`)    come from mozilla/libdmg-hfsplus. The HFS+ *creation*
#                          tool `newfs_hfs` is NOT part of libdmg-hfsplus; it is
#                          the `mkfs.hfsplus` from Debian's `hfsprogs` (dropped
#                          after bullseye, gone from trixie), built here from the
#                          diskdev_cmds source -- the same toolchain Mozilla uses
#                          for Firefox DMGs.
#   * wine64            -- run the Windows Inno Setup compiler (`ISCC.exe`,
#                          a Windows binary) to build the `.exe` installer.
#                          The Inno Setup 6 Wine prefix IS provisioned here and
#                          the build hard-fails if it doesn't take; see the
#                          comment at the Wine install below.
#   * Temurin JRE       -- runs jsign (below). Installed as a tarball, not the
#                          openjdk .deb (whose post-install fails in a chroot).
#   * jsign             -- Authenticode-sign the Windows binaries via Azure
#                          Trusted Signing.
#   * git / openssh /   -- general plumbing; `curl` + glibc also let the
#     curl / tar / ...     pipeline fetch the Linux `rcodesign` binary at
#                          runtime (via get_rcodesign.sh) for macOS notarization.
#
# This image is x86_64-only: the `publish_all` step runs exclusively on
# linux/x86_64, so there is no multi-arch matrix here.

using RootfsUtils: parse_build_args, upload_gha, test_sandbox
using RootfsUtils: debootstrap
using RootfsUtils: install_awscli
using RootfsUtils: root_chroot

args         = parse_build_args(ARGS, @__FILE__)
arch         = args.arch
archive      = args.archive
image        = args.image

if arch != "x86_64"
    error("The `julia_publish` image is only supported on x86_64 (got arch=$(arch)).")
end

# Versions of the out-of-distro tools we install from upstream.
const JSIGN_VERSION = "7.4"
const INNO_SETUP_VERSION = "6.7.3"

# Build a debian (trixie) based image with the following extra packages.
packages = [
    "bash",
    "ca-certificates",
    "cmake",
    "curl",
    "g++",                   # build libdmg-hfsplus from source
    "gcc",
    "git",
    "gzip",
    "libbz2-dev",            # libdmg-hfsplus optional bzip2 support
    "libssl-dev",            # libdmg-hfsplus crypto
    "locales",
    "localepurge",
    "make",
    "openssh-client",
    "p7zip-full",            # provides `7z` for the Windows `.zip`
    "python3",
    "tar",
    "unzip",
    "uuid-dev",              # newfs_hfs needs <uuid/uuid.h> (uuid_t) at compile time
    "wine",                  # Windows emulation for the Inno Setup compiler
    "wine64",
    "xauth",                 # for headless Wine prefix init via xvfb
    "xvfb",                  # headless display for `wineboot`/`ISCC.exe`
    "xz-utils",
    "zlib1g-dev",            # libdmg-hfsplus
]

artifact_hash, tarball_path, = debootstrap(arch, image; release = "trixie", archive, packages) do rootfs, chroot_ENV
    env = copy(chroot_ENV)
    env["DEBIAN_FRONTEND"] = "noninteractive"
    my_chroot(cmd) = root_chroot(rootfs, "bash", "-eu", "-o", "pipefail", "-c", cmd; ENV=env)

    # ------------------------------------------------------------------
    # AWS CLI v2 (>= 2.19, needed for S3 conditional writes --if-none-match).
    # Reuse the repo's shared helper (official v2 installer on x86_64).
    # ------------------------------------------------------------------
    install_awscli(rootfs, chroot_ENV, arch)

    # ------------------------------------------------------------------
    # libdmg-hfsplus: Mozilla's `hfsplus` (populate an HFS+ image) and `dmg`
    # (HFS+ -> compressed UDIF) CLI tools for assembling a macOS `.dmg` on
    # Linux.  Small CMake project, built from source in the chroot and
    # installed into /usr/local/bin.  (libdmg-hfsplus has NO mkfs tool -- the
    # HFS+ *creation* tool `newfs_hfs` is built in the next step.)
    # ------------------------------------------------------------------
    my_chroot("""
    tmpdir="\$(mktemp -d)"
    git clone --depth 1 https://github.com/mozilla/libdmg-hfsplus "\$tmpdir/libdmg-hfsplus"
    cd "\$tmpdir/libdmg-hfsplus"
    mkdir -p build && cd build
    cmake ..
    make -j"\$(nproc)"
    # The build produces `dmg/dmg` and `hfs/hfsplus`. Locate them by name
    # rather than hardcoding paths, so the install is robust to small layout
    # changes in the project.
    for tool in dmg hfsplus; do
        found="\$(find . -type f -name "\$tool" -perm -u+x | head -n1)"
        if [ -z "\$found" ]; then
            echo "ERROR: libdmg-hfsplus build did not produce '\$tool'" >&2
            exit 1
        fi
        install -m755 "\$found" "/usr/local/bin/\$tool"
    done
    cd /
    rm -rf "\$tmpdir"
    # Sanity check that the binaries at least run.
    /usr/local/bin/dmg || true
    /usr/local/bin/hfsplus || true
    """)

    # ------------------------------------------------------------------
    # newfs_hfs: the HFS+ filesystem creation tool (`mkfs.hfsplus`).  This is
    # NOT part of libdmg-hfsplus.  It comes from Apple's `diskdev_cmds` (the
    # source Debian packaged as `hfsprogs`, dropped after bullseye), built from
    # the same pinned Fedora-hosted tarball Mozilla uses for Firefox DMGs.
    #
    # The top-level Makefile hardcodes clang + `-fblocks` (only needed for
    # `fsck_hfs`, which we don't build), so we build the `newfs_hfs` target
    # directly with gcc and permissive flags for the ~2009-era C.  Drop the
    # `<sys/sysctl.h>` includes (gone from modern glibc) first.  Links only
    # `-lcrypto` (libssl3 is present via ca-certificates); <uuid/uuid.h> is a
    # compile-time-only dependency (uuid-dev), satisfied via the type, not libuuid.
    # ------------------------------------------------------------------
    my_chroot("""
    set -euo pipefail
    url="https://src.fedoraproject.org/repo/pkgs/hfsplus-tools/diskdev_cmds-540.1.linux3.tar.gz/0435afc389b919027b69616ad1b05709/diskdev_cmds-540.1.linux3.tar.gz"
    sha="b01b203a97f9a3bf36a027c13ddfc59292730552e62722d690d33bd5c24f5497"
    tmpdir="\$(mktemp -d)"
    curl -fsSL "\$url" -o "\$tmpdir/diskdev_cmds.tar.gz"
    echo "\$sha  \$tmpdir/diskdev_cmds.tar.gz" | sha256sum -c -
    tar -xzf "\$tmpdir/diskdev_cmds.tar.gz" -C "\$tmpdir"
    cd "\$tmpdir/diskdev_cmds-540.1.linux3"
    { grep -rl 'sysctl.h' . || true; } | xargs --no-run-if-empty sed -i '/sysctl.h/d'
    cd newfs_hfs.tproj
    make -f Makefile.lnx CC=gcc \\
        CFLAGS="-O2 -I../include -D_FILE_OFFSET_BITS=64 -DLINUX=1 -DBSD=1 -Wno-implicit-function-declaration -Wno-implicit-int -fcommon" \\
        LDFLAGS="" \\
        newfs_hfs
    install -m755 newfs_hfs /usr/local/bin/newfs_hfs
    cd /
    rm -rf "\$tmpdir"
    # Sanity check: format a scratch image and confirm the HFS+ signature ('H+').
    scratch="\$(mktemp)"
    truncate -s 16M "\$scratch"
    newfs_hfs -v SmokeTest "\$scratch"
    if [ "\$(dd if="\$scratch" bs=1 skip=1024 count=2 2>/dev/null)" != "H+" ]; then
        echo "ERROR: newfs_hfs did not produce an HFS+ volume" >&2; exit 1
    fi
    rm -f "\$scratch"
    """)

    # ------------------------------------------------------------------
    # JRE for jsign.  We install a self-contained Temurin (Adoptium) JRE
    # tarball rather than the openjdk .deb: the openjdk JRE's post-install
    # (via ca-certificates-java) needs a working JVM at configure time, which
    # fails in a minimal debootstrap chroot.  A tarball has no dpkg hooks.
    # (ISCC.exe runs under Wine, not the JVM -- Java is only for jsign.)
    # ------------------------------------------------------------------
    my_chroot("""
    set -euo pipefail
    mkdir -p /opt
    curl -fsSL "https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jre/hotspot/normal/eclipse" -o /tmp/jre.tar.gz
    tar -xzf /tmp/jre.tar.gz -C /opt
    rm -f /tmp/jre.tar.gz
    jredir="\$(find /opt -maxdepth 1 -type d -name 'jdk-21*' | head -n1)"
    if [ -z "\$jredir" ] || [ ! -x "\$jredir/bin/java" ]; then
        echo "ERROR: Temurin JRE not found after extract" >&2; ls -la /opt >&2; exit 1
    fi
    # Expose java via a stable path + wrapper. The `java` launcher finds its
    # bundled libjli.so / libjvm.so only via an `\$ORIGIN`-relative RPATH, and
    # glibc computes `\$ORIGIN` by reading /proc/self/exe. The debootstrap build
    # chroot has no /proc mounted, so `\$ORIGIN` expansion fails and java dies
    # with "libjli.so: cannot open shared object file" regardless of how it is
    # invoked (symlink or real path). Set LD_LIBRARY_PATH explicitly so the
    # libraries are found by absolute path, independent of /proc / \$ORIGIN.
    ln -sfn "\$jredir" /opt/temurin
    printf '%s\\n' '#!/bin/sh' 'exec env LD_LIBRARY_PATH="/opt/temurin/lib:/opt/temurin/lib/server\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}" /opt/temurin/bin/java "\$@"' > /usr/local/bin/java
    chmod +x /usr/local/bin/java
    java -version
    """)

    # ------------------------------------------------------------------
    # jsign (Authenticode signing via Azure Trusted Signing).  We install the
    # standalone JAR and a tiny `/usr/local/bin/jsign` wrapper so that `jsign`
    # is on PATH and uses the Temurin JRE installed above.  (We deliberately
    # avoid the upstream `.deb`, whose JRE dependency is the problematic
    # openjdk package we just side-stepped.)
    # ------------------------------------------------------------------
    my_chroot("""
    mkdir -p /usr/local/lib /usr/local/bin
    curl -fsSL "https://github.com/ebourg/jsign/releases/download/$(JSIGN_VERSION)/jsign-$(JSIGN_VERSION).jar" -o /usr/local/lib/jsign.jar
    printf '%s\\n' '#!/bin/sh' 'exec java -jar /usr/local/lib/jsign.jar "\$@"' > /usr/local/bin/jsign
    chmod +x /usr/local/bin/jsign
    jsign --version
    """)

    # ------------------------------------------------------------------
    # 32-bit Wine support (WoW64).  Inno Setup -- both its installer and the
    # `ISCC.exe` compiler -- is a 32-bit Windows application, so a win64 Wine
    # prefix must be able to run 32-bit PE binaries via C:\\windows\\syswow64.
    # Debian's `wine64` alone does NOT populate syswow64: without the i386 Wine
    # libraries the installer fails with
    #   wine: failed to load L"...syswow64\\ntdll.dll" error c0000135 (DLL_NOT_FOUND)
    # so we enable the i386 architecture and install the 32-bit Wine package.
    # ------------------------------------------------------------------
    my_chroot("""
    set -euo pipefail
    dpkg --add-architecture i386
    apt-get update
    apt-get install -y --no-install-recommends wine32:i386
    rm -rf /var/lib/apt/lists/*
    """)

    # ------------------------------------------------------------------
    # Wine + Inno Setup 6.
    #
    # We install Wine and a JRE so the pipeline can run the Inno Setup compiler
    # (`ISCC.exe`), and we initialize a Wine prefix + install Inno Setup 6
    # silently under xvfb during the image build, into
    #   "C:\\Program Files (x86)\\Inno Setup 6"
    #
    # Headless Wine prefix init inside a debootstrap chroot is historically
    # flaky, so this is hardened: we first mount /proc, /dev/pts and /dev/shm
    # (the bare `sudo chroot` build env mounts none of these, and Wine's
    # preloader reads /proc/self/maps -- without it Wine fails immediately with
    # "could not load ntdll.so"), unmounting them again via a trap so they never
    # leak into the image tarball; WINEDLLOVERRIDES disables the Mono/Gecko
    # first-run downloads; and `wineserver -w` blocks on the async
    # `wineboot --init` before the installer runs. We then HARD-FAIL the image
    # build if `ISCC.exe` is missing or does not run under Wine -- better a
    # red image build than silently shipping an image that can't build the
    # Windows `.exe` installer at publish time.
    #
    # The Wine prefix is created for the `juliaci` (uid 1000) user, since that
    # is the user the sandbox runs as.
    # ------------------------------------------------------------------
    my_chroot("""
    set -euo pipefail
    # Mount the virtual filesystems Wine needs (see comment above); a trap
    # tears them down on exit (success or failure) so they never end up in the
    # image tarball. Kill wineserver first so nothing holds /proc open.
    cleanup_wine_mounts() {
        wineserver -k 2>/dev/null || true
        umount /dev/shm 2>/dev/null || umount -l /dev/shm 2>/dev/null || true
        umount /dev/pts 2>/dev/null || umount -l /dev/pts 2>/dev/null || true
        umount /proc    2>/dev/null || umount -l /proc    2>/dev/null || true
    }
    trap cleanup_wine_mounts EXIT
    mount -t proc proc /proc
    mkdir -p /dev/pts /dev/shm
    mount -t devpts devpts /dev/pts || true
    mount -t tmpfs  tmpfs  /dev/shm || true

    export WINEPREFIX=/home/juliaci/.wine
    export WINEARCH=win64
    export WINEDEBUG=-all
    export HOME=/home/juliaci
    # Disable Wine's Mono/Gecko first-run downloads. Inno Setup needs neither,
    # and the prompt otherwise hangs headlessly or flakily fetches them over
    # the network during prefix init.
    export WINEDLLOVERRIDES="mscoree,mshtml="
    mkdir -p "\$WINEPREFIX"

    # Initialize the Wine prefix headlessly, then BLOCK until the wineserver
    # has fully exited -- `wineboot --init` is asynchronous, so without this
    # the Inno Setup install below can run against a half-built prefix.
    xvfb-run -a wineboot --init
    wineserver -w || true

    # Download and silently install Inno Setup 6.
    curl -fsSL "https://github.com/jrsoftware/issrc/releases/download/is-$(replace(INNO_SETUP_VERSION, '.' => '_'))/innosetup-$(INNO_SETUP_VERSION).exe" -o /tmp/innosetup.exe
    xvfb-run -a wine /tmp/innosetup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-
    wineserver -w || true
    rm -f /tmp/innosetup.exe

    # HARD requirement: ISCC.exe must be present AND actually run under Wine,
    # or the image is useless for Windows installer builds. Fail the image
    # build loudly rather than silently shipping a broken prefix.
    ISCC="\$WINEPREFIX/drive_c/Program Files (x86)/Inno Setup 6/ISCC.exe"
    if [ ! -e "\$ISCC" ]; then
        echo "ERROR: Inno Setup install failed -- ISCC.exe not found at \$ISCC" >&2
        exit 1
    fi
    iscc_out="\$(xvfb-run -a wine "\$ISCC" /? 2>&1 || true)"
    if ! echo "\$iscc_out" | grep -qi "inno"; then
        echo "ERROR: ISCC.exe is present but did not run correctly under Wine:" >&2
        echo "\$iscc_out" >&2
        exit 1
    fi
    echo "INNO SETUP: ISCC.exe installed and runs under Wine."

    # Take ownership so the prefix survives the chown in cleanup_rootfs.
    chown -R 1000:1000 /home/juliaci/.wine
    """)

    # ------------------------------------------------------------------
    # Final smoke checks for the unambiguous, must-work tools.
    # ------------------------------------------------------------------
    my_chroot("""
    aws --version
    7z --help >/dev/null
    command -v newfs_hfs >/dev/null
    command -v hfsplus >/dev/null
    command -v dmg >/dev/null
    python3 --version
    git --version
    java -version
    """)
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
