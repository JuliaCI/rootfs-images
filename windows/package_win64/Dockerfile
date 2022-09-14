# SPDX-License-Identifier: MIT

# See "Full Tag Listing" in https://hub.docker.com/_/microsoft-windows-servercore
ARG WIN_VERSION=ltsc2022
FROM mcr.microsoft.com/windows/servercore:$WIN_VERSION AS MSYS2_download

ARG MSYS2_VERSION=20220904
ARG MSYS2_DOWNLOAD_URL=https://repo.msys2.org/distrib/x86_64/msys2-base-x86_64-${MSYS2_VERSION}.sfx.exe
RUN setx /M  PATH C:\msys64\mingw64\bin;C:\msys64\usr\bin;%PATH%  && \
    powershell -Command "Invoke-WebRequest -Uri %MSYS2_DOWNLOAD_URL% -OutFile C:/windows/temp/msys2-base.sfx.exe"  && \
    C:\windows\temp\msys2-base.sfx.exe x -o"C:"
# NOTE: workaround for "gpg: error reading key: Connection timed out"
RUN bash -l -c "exit 0"
RUN bash -l -c "pacman -Syuu --noconfirm --noprogressbar"  && \
    bash -l -c "pacman -Syu --needed --noconfirm --noprogressbar"  && \
    bash -l -c "pacman -Syu --needed --noconfirm --noprogressbar"  && \
    bash -l -c " \
        pacman -S --needed --noconfirm --noprogressbar \
            cmake diffutils git m4 make patch tar p7zip curl python3 \
            mingw-w64-x86_64-gcc mingw-w64-x86_64-gcc-fortran \
        "  && \
    bash -l -c "pacman -Scc --noconfirm"  && \
    echo ---- [%date% %time%] Pkg install done!
# NOTE: If you hang here >10 min. You may want to `zap` temp files.
#   ref: https://github.com/msys2/MSYS2-packages/issues/2305#issuecomment-758162640


# ---- Move to new container
ARG WIN_VERSION=ltsc2022
FROM mcr.microsoft.com/windows/servercore:$WIN_VERSION

COPY --from=MSYS2_download C:/msys64 C:/msys64
RUN setx /M  PATH C:\msys64\mingw64\bin;C:\msys64\usr\bin;%PATH%  && \
    mklink /J  C:\msys64\home\ContainerUser C:\Users\ContainerUser  && \
    setx /M  HOME C:\msys64\home\ContainerUser

WORKDIR C:/msys64/home/ContainerUser
ENV MSYSTEM=MINGW64
CMD ["bash", "-l"]
