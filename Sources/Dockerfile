# Use the Debian testing image as the base
FROM debian:testing

# Set the frontend to noninteractive to prevent interactive prompts during installations
ENV DEBIAN_FRONTEND=noninteractive

# Add i386 architecture support, WineHQ repository for Trixie, and update package list
RUN set -x \
    && dpkg --add-architecture i386 \
    && echo 'deb http://deb.debian.org/debian bookworm main' | tee /etc/apt/sources.list.d/bookworm.list \
    && apt update -qy \
    && apt clean

# Install essential tools, dependencies, and WineHQ development version without unnecessary recommended packages
RUN apt install --no-install-recommends -qfy \
    apt-transport-https \
    git \
    gpg-agent \
    rename \
    software-properties-common \
    unzip \
    wget \
    && apt clean

    # insltall winehq-devel to support newest python versions
    RUN mkdir -pm755 /etc/apt/keyrings\
    && wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key\
    && wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/trixie/winehq-trixie.sources \
    && apt update -qy \
    && apt install --no-install-recommends -qfy \
    cabextract \
    fonts-wine \
    libwine \
    libwine:i386 \
    winbind \
    winehq-devel \
    && apt clean


# Download and set up Winetricks for further configuration of Wine
RUN wget -nv https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
    && chmod +x winetricks \
    && mv winetricks /usr/local/bin

# Set up Wine environment variables for 64-bit architecture and Wine configuration
ENV WINEARCH=win64
ENV WINEDEBUG=fixme-all
ENV WINEPREFIX=/wine

# Set up various environment variables related to Wine drive C, windows directory, and temporary directories
ENV W_DRIVE_C="$WINEPREFIX/drive_c"
ENV W_WINDIR_UNIX="$W_DRIVE_C/windows"
ENV W_SYSTEM64_DLLS="$W_WINDIR_UNIX/system32"
ENV W_TMP="$W_DRIVE_C/windows/temp/_"

# Install Microsoft Visual C++ Redistributable for Visual Studio 2017 dll files and configure Wine using Winetricks
RUN set -x \
    && winetricks win7\
    && rm -f "$W_TMP"/* \
    && wget -P "$W_TMP" https://download.visualstudio.microsoft.com/download/pr/11100230/15ccb3f02745c7b206ad10373cbca89b/VC_redist.x64.exe \
    && cabextract -q --directory="$W_TMP" "$W_TMP"/VC_redist.x64.exe \
    && cabextract -q --directory="$W_TMP" "$W_TMP/a10" \
    && cabextract -q --directory="$W_TMP" "$W_TMP/a11" \
    && cd "$W_TMP" \
    && rename 's/_/\-/g' *.dll \
    && cp "$W_TMP"/*.dll "$W_SYSTEM64_DLLS"/


# Set working directory to Wine drive C
WORKDIR "$W_DRIVE_C"

# Download GCC to set up a cross-compiling environment
# MSVCRT 64bit runtime https://winlibs.com/#download-release
ADD https://github.com/brechtsanders/winlibs_mingw/releases/download/14.2.0posix-19.1.1-12.0.0-msvcrt-r2/winlibs-x86_64-posix-seh-gcc-14.2.0-llvm-19.1.1-mingw-w64msvcrt-12.0.0-r2.zip "winlibs.zip"
RUN unzip "winlibs.zip" -d './' \
    && ls\
    && rm winlibs.zip\
    && wine reg add "HKEY_CURRENT_USER\Environment" /v PATH /t REG_SZ /d "C:\\mingw64\bin;%PATH%" /f \
    && wine reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH /t REG_SZ /d "C:\\mingw64\\bin;%PATH%" /f\
    && echo "gcc --version"| wine cmd


# Set working directory to Wine drive C
WORKDIR "$W_DRIVE_C"

# Create python folder and set environment variable
ENV PYTT="$W_DRIVE_C/python"
RUN mkdir -p "${PYTT}"

# Define the Python FTP repository for MSI installation files
ARG PYTHON_VERSION=3.13.0
ARG PY_FTP_REPO=https://www.python.org/ftp/python/$PYTHON_VERSION/amd64

# Add all Python MSI files into the container
ADD ${PY_FTP_REPO}/core.msi /tmppy/core.msi
ADD ${PY_FTP_REPO}/dev.msi /tmppy/dev.msi
ADD ${PY_FTP_REPO}/exe.msi /tmppy/exe.msi
ADD ${PY_FTP_REPO}/lib.msi /tmppy/lib.msi
ADD ${PY_FTP_REPO}/path.msi /tmppy/path.msi
ADD ${PY_FTP_REPO}/tcltk.msi /tmppy/tcltk.msi
#no more tools in repo 

# Install each Python MSI file using Wine
RUN ls /tmppy \
    && for msifile in `echo core dev exe lib path tcltk`; do \
    wine msiexec /i "/tmppy/${msifile}.msi" /qb TARGETDIR=C:/python && echo "DONE:${msifile}"; \  
    done\
    && rm -rf "/tmppy/"


## Alternatively, copy python from the host
# COPY ../Python313 "${PYTT}/"

# Make the python folder executable recursively
RUN chmod -R a+rx "$PYTT" && ls "$PYTT/include"

# Update PyConfig.h file to use MS_WIN64 as a compiler flag
ARG PYTHON_CONFIG_FILE_PATH="${PYTT}/include/pyconfig.h"
ARG TEXT_TO_ADD='#ifdef __MINGW32__\n#ifdef _WIN64\n#define MS_WIN64\n#endif\n#endif'
RUN if [[ ! -f "$PYTHON_CONFIG_FILE_PATH" ]]; then \
    echo "Error: File $PYTHON_CONFIG_FILE_PATH not found." && \
    exit 1; \
    fi && \
    sed -i "/\/\* Compiler specific defines \*\//a $TEXT_TO_ADD" "$PYTHON_CONFIG_FILE_PATH" && \
    echo "Text added successfully to $PYTHON_CONFIG_FILE_PATH." && \
    cat "$PYTHON_CONFIG_FILE_PATH"



# Add get-pip script for installing pip
ADD https://bootstrap.pypa.io/get-pip.py "${PYTT}/get-pip.py"

# Create wrapper scripts for Python, pip, and other tools to run via Wine
RUN echo 'wine '\''C:\python\python.exe'\'' "$@"' > /usr/bin/python \
    && echo 'wine '\''C:\python\Scripts\easy_install.exe'\'' "$@"' > /usr/bin/easy_install \
    && echo 'wine '\''C:\python\Scripts\pip.exe'\'' "$@"' > /usr/bin/pip \
    && echo 'wine '\''C:\python\Scripts\pyinstaller.exe'\'' "$@"' > /usr/bin/pyinstaller \
    && echo 'wine '\''C:\python\Scripts\pyupdater.exe'\'' "$@"' > /usr/bin/pyupdater \
    && echo 'wine '\''C:\python\Scripts\cython.exe'\'' "$@"' > /usr/bin/cython \
    && echo 'wine '\''C:\python\Scripts\cythonize.exe'\'' "$@"' > /usr/bin/cythonize \
    && wine --version \  
    && echo 'assoc .py=PythonScript' | wine cmd \
    && echo 'ftype PythonScript=c:\python\python.exe "%1" %*' | wine cmd \
    && while pgrep wineserver >/dev/null; do echo "Waiting for wineserver"; sleep 1; done \
    && chmod -R a+rx /usr/bin \
    && cd "$W_DRIVE_C"\
    && python "${PYTT}/get-pip.py"\
    && (pip install -U pip || true) \
    && rm -rf /tmp/.wine-*

# Install essential Python libraries such as Cython and PyInstaller
RUN pip install cython pyinstaller

# debug command
RUN python -c "import sys; print(sys.path)"

# Create /src directory and link it to Wine's C drive
RUN mkdir /src/ && ln -s /src /wine/drive_c/src

# Create a volume for the source directory
VOLUME /src/

# Set the working directory inside the Wine environment to /src
WORKDIR /wine/drive_c/src/

# Create temporary directory within the Wine environment
RUN mkdir -p /wine/drive_c/tmp

# Copy entrypoint and Cython build scripts into the container
COPY ../entrypoint.sh /entrypoint.sh
COPY ../cython_build.py /cython_build.py

# Make the entrypoint and build scripts executable
RUN chmod a+rx /entrypoint.sh /cython_build.py

# Set the container's entrypoint to the entrypoint script
ENTRYPOINT ["/entrypoint.sh"]
