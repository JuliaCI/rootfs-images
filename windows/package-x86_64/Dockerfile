# SPDX-License-Identifier: MIT

# See "Full Tag Listing" in https://hub.docker.com/_/microsoft-windows-servercore
ARG WIN_VERSION=ltsc2022
FROM mcr.microsoft.com/windows/servercore:$WIN_VERSION AS MSYS2_download

# We always download x86_64 MSYS2 installer, since our system itself is x86_64.
ARG MSYS2_VERSION=20220904
ARG MSYS2_DOWNLOAD_URL=https://repo.msys2.org/distrib/x86_64/msys2-base-x86_64-${MSYS2_VERSION}.sfx.exe
RUN setx /M PATH "C:\msys64\mingw64\bin;C:\msys64\usr\bin;%PATH%" && \
    powershell -Command "Invoke-WebRequest -Uri %MSYS2_DOWNLOAD_URL% -OutFile C:/windows/temp/msys2-base.sfx.exe"  && \
    C:\windows\temp\msys2-base.sfx.exe x -o"C:"
# NOTE: workaround for "gpg: error reading key: Connection timed out"
RUN bash -l -c "exit 0"
RUN bash -l -c "pacman -Syuu --noconfirm --noprogressbar"  && \
    bash -l -c "pacman -Syu --needed --noconfirm --noprogressbar"  && \
    bash -l -c "pacman -Syu --needed --noconfirm --noprogressbar"  && \
    bash -l -c " \
        pacman -S --needed --noconfirm --noprogressbar \
            cmake diffutils git m4 make patch tar p7zip curl python3 openssl gnupg2 \
            mingw-w64-x86_64-gcc \
        "  && \
    bash -l -c "pacman -Scc --noconfirm"  && \
    echo ---- [%date% %time%] Pkg install done!
# NOTE: If you hang here >10 min. You may want to `zap` temp files.
#   ref: https://github.com/msys2/MSYS2-packages/issues/2305#issuecomment-758162640


# ---- Move to new container, to drop messy build history
ARG WIN_VERSION=ltsc2022
FROM mcr.microsoft.com/windows/servercore:$WIN_VERSION

COPY --from=MSYS2_download C:/msys64 C:/msys64

# Download Windows 10 SDK and install only `signtool.exe`
ARG SDK_URL="https://go.microsoft.com/fwlink/p/?linkid=2196241"
ARG SDK_EXE="C:/windows/temp/winsdksetup.exe"
RUN powershell -Command "\
        Invoke-WebRequest -Uri '%SDK_URL%' -OutFile '%SDK_EXE%' -ErrorAction Stop ; \
        Start-Process '%SDK_EXE%' -Wait -ArgumentList '/features OptionId.SigningTools', '/q', '/ceip off', '/norestart' ; \
        setx /M PATH '%PATH%;' + (Resolve-Path 'C:/Program Files (x86)/Windows Kits/10/bin/*/x64/') ; \
        Remove-Item '%SDK_EXE%'"

#Install AWS CLI
ARG AWS_MSI="C:/windows/temp/AWSCLI64PY3.msi"
RUN powershell -Command "\
    Invoke-WebRequest -UseBasicParsing https://s3.amazonaws.com/aws-cli/AWSCLI64PY3.msi -OutFile '%AWS_MSI%' ; \
    Start-Process 'msiexec.exe' -Wait -ArgumentList '/i', '%AWS_MSI%', '/qn', '/norestart' ; \
    Remove-Item -Force '%AWS_MSI%'"

# Set default environment variables and setup useful symlinks
# Note that we add an entry for `buildkite-agent` here despite it not being within
# the image, because we expect it to be mounted within us in the future.
RUN setx /M PATH "C:\buildkite-agent\bin;C:\msys64\mingw64\bin;C:\msys64\usr\bin;%PATH%" && \
    mklink /J  C:\msys64\home\ContainerUser C:\Users\ContainerUser  && \
    setx /M  HOME C:\msys64\home\ContainerUser
WORKDIR C:/msys64/home/ContainerUser

# Select the mingw64 environment: https://www.msys2.org/docs/environments/
ENV MSYSTEM=MINGW64

# Default to `bash` for interactive builds
CMD ["bash"]
