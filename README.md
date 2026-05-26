# Cythinst 64

Cythinst 64 is a Docker-based GitHub Action for building Windows executables from Python projects with PyInstaller. It can also compile Cython modules before packaging.

The builder runs on Linux, but the Python toolchain used for the final executable is Windows Python running under Wine. This is what lets PyInstaller produce Windows-compatible output from a Linux GitHub Actions runner.

## Current Builder

The current base builder is built from `Sources/Dockerfile` and uses:

- `cachyos/cachyos:latest` as a rolling-release base image.
- `paru` for CachyOS/Arch package installation.
- Wine `win64` prefix at `/wine`.
- Windows Python `3.14.5` installed at `C:\python`.
- `uv` installed inside the Windows Python environment with `pip`.
- Cython and PyInstaller installed into the Windows Python environment with `uv pip`.
- WinLibs MinGW-w64 GCC for building Windows C/Cython extensions.

The Linux side intentionally does not install Arch `python`, `python-pip`, or `cython` for the build workflow. The wrappers named `python`, `pip`, `uv`, `cython`, and `pyinstaller` call the Windows executables through Wine.

No AUR packages are currently required. `paru` is present so AUR packages can be added later if there is a specific need.

## Project Support

The action supports two dependency styles.

### uv Projects

If the selected project directory contains `pyproject.toml`, the action treats it as a uv project.

If `uv.lock` is present, the action runs uv with `--frozen`, so the lockfile must already be up to date. If `uv.lock` is absent, uv resolves dependencies during the build and may create/update the lockfile inside the container workspace.

PyInstaller is run through:

```bash
uv run --python 'C:\python\python.exe' --with pyinstaller pyinstaller ...
```

For Cython builds, the action also adds `cython`, `setuptools`, and `wheel` to the uv run environment.

### requirements.txt Projects

If `pyproject.toml` is not present and the configured requirements file exists, dependencies are installed into the Windows Python environment with:

```bash
uv pip install --system --python 'C:\python\python.exe' -r requirements.txt
```

After that, PyInstaller runs from the image's Windows Python environment.

## Preparing Your Project

Your project directory should contain a PyInstaller `.spec` file. By default the action looks for `*.spec`; you can pass a specific filename with the `spec` input.

For a uv project, a typical layout is:

```text
src/
  pyproject.toml
  uv.lock
  app.py
  app.spec
```

For a requirements-based project:

```text
src/
  requirements.txt
  app.py
  app.spec
```

Generate the spec file before running the action. For example:

```bash
uv run pyinstaller --name app --onefile app.py
```

or:

```bash
pyinstaller --name app --onefile app.py
```

Keep the `.spec` file committed. If you use a standard Python `.gitignore`, remove `.spec` from the ignored patterns.

Try to avoid absolute machine-specific paths inside the `.spec` file. Relative paths are much easier to build consistently in the container.

## GitHub Actions Usage

```yaml
name: Package Application with PyInstaller

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Package Application
        uses: PlohnenSoftware/Cythinst64@main
        with:
          path: src

      - name: Upload Packaged Executable
        uses: actions/upload-artifact@v4
        with:
          name: windows-build
          path: src/dist/windows
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `path` | `src` | Directory containing your project. |
| `pypi_url` | `https://pypi.python.org/` | Custom package index base URL for pip compatibility. |
| `pypi_index_url` | `https://pypi.python.org/simple` | Custom package index URL used by pip and uv. |
| `spec` | `*.spec` | PyInstaller spec file to build. |
| `requirements` | `requirements.txt` | Requirements file used when no `pyproject.toml` is present. |
| `cython_out` | empty | Optional output directory, relative to the project directory, for compiled `.pyd` files. |

## Cython Builds

Set `cython_out` when you want the action to compile Cython modules before PyInstaller runs.

Example:

```yaml
- name: Package Application
  uses: PlohnenSoftware/Cythinst64@main
  with:
    path: src
    cython_out: compiled
```

The helper script is `cython_build.py`. It currently uses MinGW through Wine and builds `.pyx` files with `setuptools`.

## Local Docker Workflow

There are two Dockerfiles:

- `Sources/Dockerfile` builds the full CachyOS/Wine/Windows-Python base image.
- `Dockerfile` is the lightweight GitHub Action image that starts from `zamkorus/cythinst64:3.14.5` and copies the current action scripts.

Build and tag the base builder:

```bash
docker build -f Sources/Dockerfile -t zamkorus/cythinst64:3.14.5 .
docker tag zamkorus/cythinst64:3.14.5 zamkorus/cythinst64:latest
```

Build the action wrapper image:

```bash
docker build -f Dockerfile -t cythinst64-action-test .
```

Smoke-test the toolchain:

```bash
docker run --rm --entrypoint /usr/bin/bash zamkorus/cythinst64:3.14.5 -lc "python -V && uv --version && cython --version && pyinstaller --version && wine --version"
```

Push the base image when ready:

```bash
docker login
docker push zamkorus/cythinst64:3.14.5
docker push zamkorus/cythinst64:latest
```

## Updating The Builder

To bump Python, update these args in `Sources/Dockerfile`:

- `PYTHON_VERSION`
- `PYTHON_ZIP_URL`
- `PYTHON_ZIP_SHA256`

Then rebuild the base image and rerun the smoke tests.

To bump WinLibs, update `WINLIBS_URL` in `Sources/Dockerfile`, rebuild, and confirm:

```bash
docker run --rm --entrypoint /usr/bin/bash zamkorus/cythinst64:3.14.5 -lc "echo 'gcc --version' | wine cmd"
```

## Notes For Agents And Maintainers

This repo has a few important conventions that are easy to miss when editing it quickly.

### Dockerfile Roles

`Sources/Dockerfile` is the heavy base image. It installs CachyOS packages, Wine, Windows Python, WinLibs, uv, Cython, and PyInstaller.

`Dockerfile` is the GitHub Action wrapper image. It starts from the published base image, currently `zamkorus/cythinst64:3.14.5`, and only copies the current `entrypoint.sh` and `cython_build.py`.

When changing Wine, Python, uv, Cython, PyInstaller, WinLibs, or system packages, edit `Sources/Dockerfile`.

When changing action behavior, arguments, dependency installation logic, or Cython/PyInstaller invocation, edit `entrypoint.sh` and then rebuild the root `Dockerfile` image if you want to test it as the action sees it.

### Python Location

The build Python is Windows Python under Wine:

```text
C:\python
/wine/drive_c/python
```

The command wrappers in `/usr/local/bin` call Windows executables through Wine. Do not add Arch/CachyOS `python`, `python-pip`, or `cython` just to satisfy the build flow; that creates two Python worlds and makes failures harder to understand.

### Dependency Behavior

The entrypoint chooses dependency mode from files in the selected `path`:

- `pyproject.toml` present: use uv project mode.
- `uv.lock` present too: add `--frozen`.
- no `pyproject.toml`, requirements file present: use `uv pip install --system`.
- neither present: run PyInstaller with image defaults.

For uv project mode, PyInstaller is intentionally run through `uv run` so project dependencies are visible. For requirements mode, packages are installed into the global Windows Python environment inside the container.

### Line Endings

This repo is often edited on Windows. The Dockerfiles normalize copied shell/Python helper files with:

```bash
sed -i 's/\r$//'
```

Keep that unless the repo moves to enforced LF line endings. Bash inside the container will fail on CRLF scripts.

### Package Policy

Prefer official CachyOS/Arch packages from `paru -S` for Linux-side packages. Use AUR only when there is a specific missing package and document why it is needed.

Avoid Chocolatey inside Wine unless there is a strong reason. Direct Python.org artifacts are simpler, smaller, and easier to verify.

### Useful Verification Commands

After changing `Sources/Dockerfile`:

```bash
docker build -f Sources/Dockerfile -t zamkorus/cythinst64:3.14.5 .
docker tag zamkorus/cythinst64:3.14.5 zamkorus/cythinst64:latest
docker run --rm --entrypoint /usr/bin/bash zamkorus/cythinst64:3.14.5 -lc "python -V && uv --version && cython --version && pyinstaller --version && wine --version"
```

After changing `Dockerfile`, `entrypoint.sh`, or `cython_build.py`:

```bash
docker build -f Dockerfile -t cythinst64-action-test .
```

For a real behavior check, create a tiny project with `pyproject.toml`, generate a `.spec`, and run `/entrypoint.sh` inside the image. Also test a plain `requirements.txt` project when dependency installation logic changes.

### Using This Action From Another Repo

For another project, agents should check:

- The action `path` input points to the directory containing the `.spec` file.
- uv projects commit both `pyproject.toml` and, when reproducibility matters, `uv.lock`.
- requirements projects have the expected requirements file path.
- The `.spec` file does not contain absolute paths from a developer machine.
- Output is expected under `<path>/dist/windows`.
- Cython builds set `cython_out` only when `.pyx` compilation is actually needed.

## Troubleshooting

### `OSError: [WinError 123] Invalid name: '/tmp\*'`

Check the `path` input. The default is `src`, and the action expects that directory to exist.

### uv says the lockfile is out of date

If `uv.lock` exists, the action uses `--frozen`. Update the lockfile locally and commit it:

```bash
uv lock
```

### Wine prints graphics or RPC warnings

Headless Wine often prints warnings about missing display, Vulkan, EGL, systray, or RPC services. These are usually harmless if `python`, `uv`, `cython`, and `pyinstaller` exit successfully.

### PyInstaller cannot find files from the spec

Check for absolute paths in the `.spec` file. Prefer paths relative to the project directory.

## External Resources

- [CachyOS Docker image](https://hub.docker.com/r/cachyos/cachyos)
- [Wine](https://www.winehq.org)
- [uv](https://docs.astral.sh/uv/)
- [PyInstaller](https://pyinstaller.org)
- [Cython](https://cython.org)
- [WinLibs](https://github.com/brechtsanders/winlibs_mingw)
- [docker-pyinstaller](https://github.com/cdrx/docker-pyinstaller)
- [pyinstaller-action-windows](https://github.com/JackMcKew/pyinstaller-action-windows)
- [cython_build script source inspiration](https://github.com/PlohnenSoftware/familiada_ZSP)
