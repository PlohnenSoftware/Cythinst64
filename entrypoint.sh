#!/bin/bash

# Fail on errors.
set -e

# Make sure .bashrc is sourced when the base image provides one.
if [ -f /root/.bashrc ]; then
    . /root/.bashrc
fi

# Set default values from action.yaml
WORKDIR=${1:-/src} # Default to "src" if no argument is provided
PYPI_URL=${2:-"https://pypi.python.org/"}  # Default PyPI URL
PYPI_INDEX_URL=${3:-"https://pypi.python.org/simple"}  # Default PyPI Index URL
SPEC_FILE=${4:-*.spec}  # Default to an empty string for .spec file path
REQUIREMENTS=${5:-"requirements.txt"}  # Default requirements file
CYTHON_OUT=$6 # Default prec folder
WINDOWS_PYTHON='C:\python\python.exe'



# In case the user specified a custom URL for PYPI, then use
# that one, instead of the default one.
UV_INDEX_ARGS=()

if [[ "$PYPI_URL" != "https://pypi.python.org/" ]] || \
   [[ "$PYPI_INDEX_URL" != "https://pypi.python.org/simple" ]]; then
    # the funky looking regexp just extracts the hostname, excluding port
    # to be used as a trusted-host.
    mkdir -p /wine/drive_c/users/root/pip
    echo "[global]" > /wine/drive_c/users/root/pip/pip.ini
    echo "index = $PYPI_URL" >> /wine/drive_c/users/root/pip/pip.ini
    echo "index-url = $PYPI_INDEX_URL" >> /wine/drive_c/users/root/pip/pip.ini
    echo "trusted-host = $(echo $PYPI_URL | perl -pe 's|^.*?://(.*?)(:.*?)?/.*$|$1|')" >> /wine/drive_c/users/root/pip/pip.ini
    echo "Using custom pip.ini: "
    cat /wine/drive_c/users/root/pip/pip.ini
    UV_INDEX_ARGS=(--index-url "$PYPI_INDEX_URL")
fi

cd "$WORKDIR"
echo "Working directory: $WORKDIR"

USE_UV_PROJECT=0
UV_PROJECT_ARGS=(--python "$WINDOWS_PYTHON")

if [ -f "pyproject.toml" ]; then
    USE_UV_PROJECT=1
    echo "Detected uv/pyproject project"

    if [ -f "uv.lock" ]; then
        UV_PROJECT_ARGS+=(--frozen)
        echo "Using existing uv.lock"
    else
        echo "No uv.lock found; uv will resolve and create/update the lockfile"
    fi
elif [ -f "$REQUIREMENTS" ]; then
    echo "No uv project found; installing requirements with uv pip"
    uv pip install --system --python "$WINDOWS_PYTHON" "${UV_INDEX_ARGS[@]}" -r "$REQUIREMENTS"
else
    echo "No uv project or requirements file found; continuing with image defaults"
fi

if [ -n "$CYTHON_OUT" ]; then
    cd ..
    mkdir ./build
    wine reg add "HKEY_CURRENT_USER\Environment" /v PATH /t REG_SZ /d "C:\\mingw64\bin;%PATH%" /f
    echo "gcc --version"| wine cmd
    if [ "$USE_UV_PROJECT" -eq 1 ]; then
        uv run "${UV_INDEX_ARGS[@]}" "${UV_PROJECT_ARGS[@]}" --with cython --with setuptools --with wheel python /cython_build.py
    else
        python /cython_build.py
    fi
    cd "$WORKDIR"
    mkdir -p "$CYTHON_OUT"
    mv ../*.pyd "$CYTHON_OUT/"
fi

if [ "$USE_UV_PROJECT" -eq 1 ]; then
    uv run "${UV_INDEX_ARGS[@]}" "${UV_PROJECT_ARGS[@]}" --with pyinstaller pyinstaller --clean -y --dist ./dist/windows --workpath /tmp $SPEC_FILE
else
    pyinstaller --clean -y --dist ./dist/windows --workpath /tmp $SPEC_FILE
fi
chown -R --reference=. ./dist/windows
