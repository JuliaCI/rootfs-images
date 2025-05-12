# SPDX-License-Identifier: MIT

# See "Full Tag Listing" in https://hub.docker.com/_/microsoft-windows-servercore
ARG WIN_VERSION=ltsc2022
FROM mcr.microsoft.com/windows/servercore:$WIN_VERSION AS MSYS2_download

# We always download x86_64 MSYS2 installer, since our system itself is x86_64.
ARG MSYS2_VERSION=20240507
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
    bash -l -c "git config --system core.longpaths true" && \
    bash -l -c "pacman -Scc --noconfirm"  && \
    echo ---- [%date% %time%] Pkg install done!
# NOTE: If you hang here >10 min. You may want to `zap` temp files.
#   ref: https://github.com/msys2/MSYS2-packages/issues/2305#issuecomment-758162640


# ---- Move to new container, to drop messy build history
ARG WIN_VERSION=ltsc2022
FROM mcr.microsoft.com/windows/servercore:$WIN_VERSION

COPY --from=MSYS2_download C:/msys64 C:/msys64

# Install .NET runtime for x86_64
ARG DOTNET_URL="https://download.visualstudio.microsoft.com/download/pr/cc913baa-9bce-482e-bdfc-56c4b6fafd10/e3f24f2ab2fc02b395c1b67f5193b8d1/dotnet-runtime-8.0.8-win-x64.exe"
ARG DOTNET_EXE="C:/windows/temp/dotnet-runtime.exe"
RUN powershell -Command "\
    Invoke-WebRequest -Uri '%DOTNET_URL%' -OutFile '%DOTNET_EXE%' -ErrorAction Stop ; \
    Start-Process '%DOTNET_EXE%' -Wait -ArgumentList '/install', '/quiet', '/norestart' ; \
    Remove-Item '%DOTNET_EXE%'"

# Install trusted signing dlib
ARG TS_URL="https://www.nuget.org/api/v2/package/Microsoft.Trusted.Signing.Client/1.0.60"
ARG TS_ZIP="C:/windows/temp/ts_client.zip"
ARG TS_DIR="C:/Program Files/TrustedSigning"
RUN powershell -Command "\
    Invoke-WebRequest -Uri '%TS_URL%' -OutFile '%TS_ZIP%' -ErrorAction Stop ; \
    Expand-Archive -Path '%TS_ZIP%' -DestinationPath '%TS_DIR%' -Force ; \
    Remove-Item '%TS_ZIP%'"

# Download Windows 11 SDK (10.0.22621.2428) and install only `signtool.exe`
ARG SDK_URL="https://go.microsoft.com/fwlink/?linkid=2250105"
ARG SDK_EXE="C:/windows/temp/winsdksetup.exe"
RUN powershell -Command "\
        Invoke-WebRequest -Uri '%SDK_URL%' -OutFile '%SDK_EXE%' -ErrorAction Stop ; \
        Start-Process '%SDK_EXE%' -Wait -ArgumentList '/features OptionId.SigningTools', '/q', '/ceip off', '/norestart' ; \
        setx /M PATH ('%PATH%;' + (Resolve-Path 'C:/Program Files (x86)/Windows Kits/10/bin/*/x64/')) ; \
        Remove-Item '%SDK_EXE%'"

RUN powershell -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://vcredist.com/install.ps1'))"

# Install AWS CLI
RUN msiexec.exe /i "https://awscli.amazonaws.com/AWSCLIV2.msi" /quiet /qn && \
    setx /M PATH "%PATH%;C:\Program Files\Amazon\AWSCLIV2"

# Install `TrustedSigning` powershell module
RUN powershell -Command "Install-Module -Name TrustedSigning" 

# Set default environment variables and setup useful symlinks
# Note that we add an entry for `buildkite-agent` here despite it not being within
# the image, because we expect it to be mounted within us in the future.
RUN setx /M PATH "C:\buildkite-agent\bin;C:\msys64\mingw64\bin;C:\msys64\usr\bin;%PATH%" && \
    mklink /J C:\msys64\home\ContainerUser C:\Users\ContainerUser && \
    setx /M HOME C:\msys64\home\ContainerUser
WORKDIR C:/msys64/home/ContainerUser

# Select the mingw64 environment: https://www.msys2.org/docs/environments/
ENV MSYSTEM=MINGW64

# Default to `bash` for interactive builds
CMD ["bash"]
