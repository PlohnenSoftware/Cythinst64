# syntax=docker/dockerfile:1.7

# Rolling CachyOS base for building Windows executables with Wine.
FROM cachyos/cachyos:latest

SHELL ["/usr/bin/bash", "-euxo", "pipefail", "-c"]

ENV WINEARCH=win64 \
    WINEDEBUG=fixme-all \
    WINEPREFIX=/wine \
    PATH="/usr/local/bin:${PATH}"

ENV W_DRIVE_C="${WINEPREFIX}/drive_c" \
    W_WINDIR_UNIX="${WINEPREFIX}/drive_c/windows" \
    W_SYSTEM64_DLLS="${WINEPREFIX}/drive_c/windows/system32" \
    W_TMP="${WINEPREFIX}/drive_c/windows/temp/_" \
    PYTT="${WINEPREFIX}/drive_c/python"

# Bootstrap only what is needed to use paru, then use paru for the actual setup.
RUN pacman -Syu --noconfirm --needed paru sudo \
    && pacman -Scc --noconfirm

RUN useradd --create-home --groups wheel builder \
    && echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/00-wheel-nopasswd \
    && chmod 0440 /etc/sudoers.d/00-wheel-nopasswd

USER builder

RUN paru -Syu --noconfirm --needed --removemake \
        ca-certificates \
        curl \
        git \
        perl \
        unzip \
        wine \
        wine-gecko \
        wine-mono \
        winetricks \
    && paru -Scc --noconfirm

USER root

RUN install -d -m 0755 "$W_TMP" "$PYTT" /src \
    && chown -R root:root "$WINEPREFIX" /src

# Python 3.14.5 is the latest stable Windows release as of 2026-05-26.
ARG PYTHON_VERSION=3.14.5
ARG PYTHON_ZIP_URL=https://www.python.org/ftp/python/${PYTHON_VERSION}/python-${PYTHON_VERSION}-amd64.zip
ARG PYTHON_ZIP_SHA256=c66c6e75aba5cc0434541089127557010da2af9f6ef653abc14bdb694fdf3594
ARG GET_PIP_URL=https://bootstrap.pypa.io/get-pip.py

# WinLibs provides the Windows-native MinGW toolchain used by setuptools/Cython.
ARG WINLIBS_URL=https://github.com/brechtsanders/winlibs_mingw/releases/download/16.1.0posix-14.0.0-msvcrt-r2/winlibs-x86_64-posix-seh-gcc-16.1.0-mingw-w64msvcrt-14.0.0-r2.zip

RUN winetricks -q win10 \
    && while pgrep wineserver >/dev/null; do echo "Waiting for wineserver"; sleep 1; done

RUN curl -fL "$WINLIBS_URL" -o /tmp/winlibs.zip \
    && unzip -q /tmp/winlibs.zip -d "$W_DRIVE_C" \
    && rm /tmp/winlibs.zip \
    && wine reg add "HKEY_CURRENT_USER\\Environment" /v PATH /t REG_SZ /d "C:\\python;C:\\python\\Scripts;C:\\mingw64\\bin;%PATH%" /f \
    && echo "gcc --version" | wine cmd \
    && while pgrep wineserver >/dev/null; do echo "Waiting for wineserver"; sleep 1; done

RUN curl -fsSL "$PYTHON_ZIP_URL" -o /tmp/python.zip \
    && if [[ -n "$PYTHON_ZIP_SHA256" ]]; then echo "${PYTHON_ZIP_SHA256}  /tmp/python.zip" | sha256sum -c -; fi \
    && unzip -q /tmp/python.zip -d "$PYTT" \
    && rm /tmp/python.zip \
    && curl -fsSL "$GET_PIP_URL" -o "$PYTT/get-pip.py" \
    && chmod -R a+rx "$PYTT"

RUN printf '%s\n' '#!/bin/sh' "exec wine 'C:\\python\\python.exe' \"\$@\"" > /usr/local/bin/python \
    && printf '%s\n' '#!/bin/sh' "exec wine 'C:\\python\\Scripts\\pip.exe' \"\$@\"" > /usr/local/bin/pip \
    && printf '%s\n' '#!/bin/sh' "exec wine 'C:\\python\\Scripts\\uv.exe' \"\$@\"" > /usr/local/bin/uv \
    && printf '%s\n' '#!/bin/sh' "exec wine 'C:\\python\\Scripts\\easy_install.exe' \"\$@\"" > /usr/local/bin/easy_install \
    && printf '%s\n' '#!/bin/sh' "exec wine 'C:\\python\\Scripts\\pyinstaller.exe' \"\$@\"" > /usr/local/bin/pyinstaller \
    && printf '%s\n' '#!/bin/sh' "exec wine 'C:\\python\\Scripts\\pyupdater.exe' \"\$@\"" > /usr/local/bin/pyupdater \
    && printf '%s\n' '#!/bin/sh' "exec wine 'C:\\python\\Scripts\\cython.exe' \"\$@\"" > /usr/local/bin/cython \
    && printf '%s\n' '#!/bin/sh' "exec wine 'C:\\python\\Scripts\\cythonize.exe' \"\$@\"" > /usr/local/bin/cythonize \
    && chmod +x /usr/local/bin/python /usr/local/bin/pip /usr/local/bin/uv /usr/local/bin/easy_install /usr/local/bin/pyinstaller /usr/local/bin/pyupdater /usr/local/bin/cython /usr/local/bin/cythonize \
    && wine --version \
    && python -V \
    && python "$PYTT/get-pip.py" \
    && python -m pip install --upgrade pip setuptools wheel uv \
    && uv pip install --system --python 'C:\python\python.exe' --upgrade cython pyinstaller \
    && cython --version \
    && pyinstaller --version \
    && rm -f "$PYTT/get-pip.py" \
    && rm -rf /tmp/.wine-* /root/.cache /home/builder/.cache

COPY py_conf_update.sh /py_conf_update.sh
RUN sed -i 's/\r$//' /py_conf_update.sh \
    && chmod a+rx /py_conf_update.sh \
    && /py_conf_update.sh \
    && rm /py_conf_update.sh

RUN ln -s /src "$W_DRIVE_C/src" \
    && mkdir -p "$W_DRIVE_C/tmp"

VOLUME /src/
WORKDIR /wine/drive_c/src/

COPY entrypoint.sh /entrypoint.sh
COPY cython_build.py /cython_build.py
RUN sed -i 's/\r$//' /entrypoint.sh /cython_build.py \
    && chmod a+rx /entrypoint.sh /cython_build.py

ENTRYPOINT ["/entrypoint.sh"]
