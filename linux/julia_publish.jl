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
#   * libdmg-hfsplus    -- build the macOS `.dmg` on Linux: the `mkfshfs`
#     (`mkfshfs`/        (create the HFS+ filesystem), `hfsplus` (populate it)
#     `hfsplus`/`dmg`)    and `dmg` (convert to a compressed UDIF) tools, the
#                          same ones Mozilla uses for Firefox DMGs. (Debian's
#                          `hfsprogs`/`mkfs.hfsplus` was dropped after bullseye
#                          and is not in trixie, so we use libdmg-hfsplus's own
#                          `mkfshfs` instead.)
#   * wine64 + JRE      -- run the Windows Inno Setup compiler (`ISCC.exe`) to
#                          build the `.exe` installer.  The Inno Setup 6 Wine
#                          prefix IS provisioned here and the build hard-fails
#                          if it doesn't take; see the comment at the Wine
#                          install below.
#   * jsign + JRE       -- Authenticode-sign the Windows binaries via Azure
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
    "default-jre-headless",  # JRE for jsign and the Inno Setup compiler
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
    # libdmg-hfsplus: Mozilla's `hfsplus` / `dmg` / `mkfshfs` CLI tools for
    # assembling a macOS `.dmg` on Linux.  Small CMake project, built from
    # source in the chroot and installed into /usr/local/bin.
    # ------------------------------------------------------------------
    my_chroot("""
    tmpdir="\$(mktemp -d)"
    git clone --depth 1 https://github.com/mozilla/libdmg-hfsplus "\$tmpdir/libdmg-hfsplus"
    cd "\$tmpdir/libdmg-hfsplus"
    mkdir -p build && cd build
    cmake ..
    make -j"\$(nproc)"
    # The build produces `dmg/dmg`, `hfs/hfsplus` and `hfs/mkfshfs`. Locate
    # them by name rather than hardcoding paths, so the install is robust to
    # small layout changes in the project.
    for tool in dmg hfsplus mkfshfs; do
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
    # jsign (Authenticode signing via Azure Trusted Signing).  We install the
    # standalone JAR and a tiny `/usr/local/bin/jsign` wrapper so that `jsign`
    # is on PATH and uses the image's JRE.  (We deliberately avoid the upstream
    # `.deb`, whose JRE dependency name is less predictable across Debian
    # releases.)
    # ------------------------------------------------------------------
    my_chroot("""
    mkdir -p /usr/local/lib /usr/local/bin
    curl -fsSL "https://github.com/ebourg/jsign/releases/download/$(JSIGN_VERSION)/jsign-$(JSIGN_VERSION).jar" -o /usr/local/lib/jsign.jar
    printf '%s\\n' '#!/bin/sh' 'exec java -jar /usr/local/lib/jsign.jar "\$@"' > /usr/local/bin/jsign
    chmod +x /usr/local/bin/jsign
    jsign --version
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
    # flaky, so this is hardened: WINEDLLOVERRIDES disables the Mono/Gecko
    # first-run downloads, and `wineserver -w` blocks on the async
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
    command -v mkfshfs >/dev/null
    command -v hfsplus >/dev/null
    command -v dmg >/dev/null
    python3 --version
    git --version
    java -version
    """)
end

upload_gha(tarball_path)
test_sandbox(artifact_hash)
