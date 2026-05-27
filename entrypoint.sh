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
ZIP_NAME=${7:-}
ZIP_PATHS=${8:-}
ZIP_METHOD=${9:-bzip2}
ZIP_LEVEL=${10:-9}
WINDOWS_PYTHON='C:\python\python.exe'

find_upwards() {
    local name="$1"
    local dir="$PWD"

    while true; do
        if [ -f "$dir/$name" ]; then
            printf '%s\n' "$dir"
            return 0
        fi

        if [ "$dir" = "/" ]; then
            return 1
        fi

        dir="$(dirname "$dir")"
    done
}

read_first_line() {
    local file="$1"
    sed -n '1{s/[[:space:]]*$//;p;q;}' "$file"
}

read_requires_python() {
    local pyproject="$1"
    sed -n 's/^[[:space:]]*requires-python[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$pyproject" | head -n 1
}

write_pyproject_requirements() {
    local pyproject="$1"
    local requirements_out="$2"

    python - "$pyproject" "$requirements_out" <<'PY'
import pathlib
import sys
import tomllib

pyproject = pathlib.Path(sys.argv[1])
requirements_out = pathlib.Path(sys.argv[2])

with pyproject.open("rb") as handle:
    data = tomllib.load(handle)

dependencies = data.get("project", {}).get("dependencies", [])
if not isinstance(dependencies, list):
    raise SystemExit(f"{pyproject}: [project].dependencies must be a list")

with requirements_out.open("w", encoding="utf-8", newline="\n") as handle:
    for dependency in dependencies:
        if not isinstance(dependency, str):
            raise SystemExit(f"{pyproject}: dependency entries must be strings")
        handle.write(dependency)
        handle.write("\n")
PY
}

python_request_from_requires() {
    local requirement="$1"

    case "$requirement" in
        ==[0-9].[0-9].\*)
            printf '%s\n' "${requirement#==}" | sed 's/[.][*]$//'
            ;;
        ==[0-9].[0-9][0-9].\*)
            printf '%s\n' "${requirement#==}" | sed 's/[.][*]$//'
            ;;
        ==[0-9].[0-9].[0-9]*)
            printf '%s\n' "${requirement#==}"
            ;;
        ==[0-9].[0-9][0-9].[0-9]*)
            printf '%s\n' "${requirement#==}"
            ;;
    esac
}

normalize_python_request() {
    local request="$1"

    printf '%s\n' "$request" | sed 's/^==//; s/[.][*]$//'
}

container_python_version() {
    python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')"
}

python_request_matches_container() {
    local request="$1"
    local actual="$2"

    [[ "$actual" == "$request" || "$actual" == "$request".* ]]
}



# In case the user specified a custom URL for PYPI, then use
# that one, instead of the default one.
UV_INDEX_ARGS=()
REPO_ROOT="$(pwd -P)"

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
WORKDIR="$(pwd -P)"
echo "Working directory: $WORKDIR"

UV_PROJECT_ROOT=""
PYTHON_VERSION_ROOT=""
CONTAINER_PYTHON_VERSION="$(container_python_version)"

if UV_PROJECT_ROOT="$(find_upwards pyproject.toml)"; then
    echo "Detected pyproject.toml at: $UV_PROJECT_ROOT"

    if PYTHON_VERSION_ROOT="$(find_upwards .python-version)"; then
        PROJECT_PYTHON_REQUEST="$(read_first_line "$PYTHON_VERSION_ROOT/.python-version")"
        PROJECT_PYTHON_REQUEST="$(normalize_python_request "$PROJECT_PYTHON_REQUEST")"
        if [ -n "$PROJECT_PYTHON_REQUEST" ]; then
            if ! python_request_matches_container "$PROJECT_PYTHON_REQUEST" "$CONTAINER_PYTHON_VERSION"; then
                echo "Error: project .python-version requests Python $PROJECT_PYTHON_REQUEST, but this image provides Windows Python $CONTAINER_PYTHON_VERSION."
                echo "Use a matching zamkorus/cythinst64 builder tag, or update the project Python pin."
                exit 2
            fi
            echo "Project .python-version matches image Python: $PROJECT_PYTHON_REQUEST"
        fi
    else
        PROJECT_REQUIRES_PYTHON="$(read_requires_python "$UV_PROJECT_ROOT/pyproject.toml")"
        PROJECT_PYTHON_REQUEST="$(python_request_from_requires "$PROJECT_REQUIRES_PYTHON")"
        if [ -n "$PROJECT_PYTHON_REQUEST" ]; then
            if ! python_request_matches_container "$PROJECT_PYTHON_REQUEST" "$CONTAINER_PYTHON_VERSION"; then
                echo "Error: pyproject.toml requires Python $PROJECT_REQUIRES_PYTHON, but this image provides Windows Python $CONTAINER_PYTHON_VERSION."
                echo "Use a matching zamkorus/cythinst64 builder tag, or update the project Python requirement."
                exit 2
            fi
            echo "Project Python requirement matches image Python: $PROJECT_REQUIRES_PYTHON"
        elif [ -n "$PROJECT_REQUIRES_PYTHON" ]; then
            echo "Project requires Python: $PROJECT_REQUIRES_PYTHON; using image Windows Python $CONTAINER_PYTHON_VERSION"
        else
            echo "No project Python pin found; using image Windows Python $CONTAINER_PYTHON_VERSION"
        fi
    fi
elif [ -f "$REQUIREMENTS" ]; then
    if PYTHON_VERSION_ROOT="$(find_upwards .python-version)"; then
        REQUIREMENTS_PYTHON_REQUEST="$(read_first_line "$PYTHON_VERSION_ROOT/.python-version")"
        REQUIREMENTS_PYTHON_REQUEST="$(normalize_python_request "$REQUIREMENTS_PYTHON_REQUEST")"
        if [ -n "$REQUIREMENTS_PYTHON_REQUEST" ] && ! python_request_matches_container "$REQUIREMENTS_PYTHON_REQUEST" "$CONTAINER_PYTHON_VERSION"; then
            echo "Error: requirements.txt mode installs into the image Windows Python ($CONTAINER_PYTHON_VERSION), but .python-version requests $REQUIREMENTS_PYTHON_REQUEST."
            echo "Use a matching zamkorus/cythinst64 builder tag, or update the project Python pin."
            exit 2
        fi
    fi
fi

if [ -f "$REQUIREMENTS" ]; then
    echo "Installing requirements into image Windows Python with uv pip: $REQUIREMENTS"
    uv pip install --system --python "$WINDOWS_PYTHON" "${UV_INDEX_ARGS[@]}" -r "$REQUIREMENTS"
elif [ -n "$UV_PROJECT_ROOT" ]; then
    PYPROJECT_REQUIREMENTS=/tmp/cythinst-pyproject-requirements.txt
    write_pyproject_requirements "$UV_PROJECT_ROOT/pyproject.toml" "$PYPROJECT_REQUIREMENTS"

    if [ -s "$PYPROJECT_REQUIREMENTS" ]; then
        if [ -f "$UV_PROJECT_ROOT/uv.lock" ]; then
            echo "uv.lock found, but this action installs into the image Windows Python instead of creating a uv venv; using pyproject dependencies directly."
        fi
        echo "Installing pyproject dependencies into image Windows Python with uv pip"
        uv pip install --system --python "$WINDOWS_PYTHON" "${UV_INDEX_ARGS[@]}" -r "$PYPROJECT_REQUIREMENTS"
    else
        echo "pyproject.toml has no [project].dependencies; continuing with image defaults"
    fi
else
    echo "No pyproject.toml or requirements file found; continuing with image defaults"
fi

if [ -n "$CYTHON_OUT" ]; then
    cd "$WORKDIR/.."
    mkdir -p ./build
    wine reg add "HKEY_CURRENT_USER\Environment" /v PATH /t REG_SZ /d "C:\\mingw64\bin;%PATH%" /f
    echo "gcc --version"| wine cmd
    python /cython_build.py
    cd "$WORKDIR"
    mkdir -p "$CYTHON_OUT"
    mapfile -t CYTHON_ARTIFACTS < <(find "$WORKDIR" "$WORKDIR/.." -maxdepth 1 -type f -name '*.pyd' -print)
    if [ "${#CYTHON_ARTIFACTS[@]}" -eq 0 ]; then
        echo "Error: Cython build completed, but no .pyd files were found in $WORKDIR or $WORKDIR/.."
        exit 1
    fi
    for artifact in "${CYTHON_ARTIFACTS[@]}"; do
        mv "$artifact" "$CYTHON_OUT/"
    done
fi

pyinstaller --clean -y --dist ./dist/windows --workpath /tmp $SPEC_FILE
chown -R --reference=. ./dist/windows

if [ -n "$ZIP_NAME" ]; then
    cd "$REPO_ROOT"
    echo "Creating zip package: $ZIP_NAME"
    python /zip_package.py "$ZIP_NAME" "$ZIP_PATHS" "$ZIP_METHOD" "$ZIP_LEVEL"
    chown --reference=. "$ZIP_NAME"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    if [ -n "$ZIP_NAME" ]; then
        echo "output=$ZIP_NAME" >> "$GITHUB_OUTPUT"
    else
        echo "output=$WORKDIR/dist/windows" >> "$GITHUB_OUTPUT"
    fi
fi
