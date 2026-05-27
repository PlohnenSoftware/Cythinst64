# Cythinst 64

Cythinst 64 is a Docker-based GitHub Action for building Windows executables from Python projects with PyInstaller. It can also compile Cython modules before packaging.

The builder runs on Linux, but the Python toolchain used for the final executable is Windows Python running under Wine. This is what lets PyInstaller produce Windows-compatible output from a Linux GitHub Actions runner.

## Current Builder

The current base builder is built from `Sources/Dockerfile` and uses:

- `cachyos/cachyos:latest` as a rolling-release base image.
- `paru` for CachyOS/Arch package installation.
- Wine `win64` prefix at `/wine`.
- Windows Python `3.13.13` installed at `C:\python`.
- `uv` installed inside the Windows Python environment with `pip`.
- Cython and PyInstaller installed into the Windows Python environment with `uv pip`.
- WinLibs MinGW-w64 GCC for building Windows C/Cython extensions.
- 7-Zip for optional `.7z` packages with maximum compression.

The Linux side intentionally does not install Arch `python`, `python-pip`, or `cython` for the build workflow. The wrappers named `python`, `pip`, `uv`, `cython`, and `pyinstaller` call the Windows executables through Wine.

No AUR packages are currently required. `paru` is present so AUR packages can be added later if there is a specific need.

## Dependency Support

The action installs project dependencies into the Windows Python environment that is already inside the image. It does not create a uv virtual environment during the action run.

### pyproject.toml Projects

If the selected project directory or one of its parent directories contains `pyproject.toml`, the action uses it for project metadata. This supports repositories where `pyproject.toml` lives at the repository root while the PyInstaller spec lives in a nested `src/` directory.

If the selected `path` also contains the configured requirements file, the requirements file wins and is installed with:

```bash
uv pip install --system --python 'C:\python\python.exe' -r requirements.txt
```

If there is no requirements file, the action extracts `[project].dependencies` from `pyproject.toml` and installs those dependencies into `C:\python` with `uv pip`.

`uv.lock` is not used by the action at runtime. This is intentional: the action keeps one Python environment, the image's Windows Python, so projects do not need to list PyInstaller or Cython just to make them visible inside a uv-created virtual environment.

The action uses the Windows Python already installed in the image. It does not let uv download a separate Python interpreter during the build. If `.python-version` or `requires-python` pins a different Python version, the action exits with a clear error so you can choose a matching builder tag or update the project pin.

PyInstaller is run through:

```bash
pyinstaller ...
```

For Cython builds, the action uses the globally installed Cython, setuptools, wheel, and WinLibs toolchain from the image.

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

Projects with config at the repository root are also supported:

```text
pyproject.toml
uv.lock
src/
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
          zip_name: app.zip
          sevenzip_name: app.7z
          zip_paths: |
            src/dist/windows
            README.md

      - name: Upload ZIP Package
        uses: actions/upload-artifact@v7
        with:
          name: app.zip
          path: app.zip
          archive: false

      - name: Upload 7z Package
        uses: actions/upload-artifact@v7
        with:
          name: app.7z
          path: app.7z
          archive: false
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `path` | `src` | Directory containing your project. |
| `pypi_url` | `https://pypi.python.org/` | Custom package index base URL for pip compatibility. |
| `pypi_index_url` | `https://pypi.python.org/simple` | Custom package index URL used by pip and uv. |
| `spec` | `*.spec` | PyInstaller spec file to build. |
| `requirements` | `requirements.txt` | Requirements file relative to `path`. When present, it is installed before `pyproject.toml` dependencies are considered. |
| `cython_out` | empty | Optional output directory, relative to the project directory, for compiled `.pyd` files. |
| `zip_name` | empty | Optional `.zip` package to create after a successful build, relative to the repository root. Empty disables ZIP creation. |
| `sevenzip_name` | empty | Optional `.7z` package to create after a successful build, relative to the repository root. Use the same base name as `zip_name`, for example `app.zip` and `app.7z`. |
| `zip_paths` | empty | Newline-separated repository-root-relative files, directories, or glob patterns. Each selected path is placed at the archive root in both `.zip` and `.7z` packages. Required when either package output is set. |
| `zip_method` | `deflate` | ZIP compression method: `deflate` or `store`. Use `sevenzip_name` for stronger compression. |
| `zip_level` | `9` | ZIP compression level from `0` to `9`. Used by `deflate`; accepted for `store` for a stable interface. |

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

## Archive Packages

Set `zip_name` to create a compatibility-focused `.zip` after PyInstaller finishes. ZIP output uses Deflate by default because Windows Explorer and older unzip tools handle it reliably.

Set `sevenzip_name` to create a maximum-compression `.7z` package using system 7-Zip. Modern Windows Explorer can open `.7z`, and this is where stronger compression belongs.

Both archive formats use the same `zip_paths` resolver. Each entry is resolved from the repository root, then placed at the archive root. A selected file is stored as its basename, and a selected directory stores its contents relative to that selected directory. If both outputs are enabled, `zip_name` and `sevenzip_name` must use the same base name, such as `familiada.zip` and `familiada.7z`.

Example:

```yaml
- name: Package Application
  uses: PlohnenSoftware/Cythinst64@main
  with:
    path: src
    cython_out: prec
    zip_name: familiada.zip
    sevenzip_name: familiada.7z
    zip_paths: |
      src/dist/windows
      dane.csv
```

This creates `familiada.zip` and `familiada.7z` with identical entries such as `Familiada.exe` and `dane.csv`. If you pass a parent directory, both archives keep the path below that selected directory. For example, `zip_paths: src/dist` would store `windows/Familiada.exe` in both outputs.

Generated archive files are automatically excluded from both packages. That prevents broad inputs such as `zip_paths: .` from creating a ZIP that contains the 7z or a 7z that contains the ZIP.

The `.7z` settings intentionally match 7-Zip's high-compression desktop profile:

- Level: Ultra
- Method: LZMA2
- Dictionary: 4096 MB
- Word size: 273
- Solid block size: 16 GB

Those settings favor smallest package size and may need more memory than a default GitHub runner has for very large inputs. If 7-Zip exits with a memory error, reduce the selected `zip_paths` set or rebuild the action with lighter 7z settings.

The default `zip_method` is `deflate`:

```yaml
zip_method: deflate
zip_level: 9
```

Supported ZIP methods are `deflate` and `store`.

## Local Docker Workflow

There are two Dockerfiles:

- `Sources/Dockerfile` builds the full CachyOS/Wine/Windows-Python base image.
- `Dockerfile` is the lightweight GitHub Action image that starts from `zamkorus/cythinst64:3.13.13` and copies the current action scripts.

Build and tag the base builder:

```bash
docker build -f Sources/Dockerfile -t zamkorus/cythinst64:3.13.13 .
docker tag zamkorus/cythinst64:3.13.13 zamkorus/cythinst64:latest
```

Build the action wrapper image:

```bash
docker build -f Dockerfile -t cythinst64-action-test .
```

Smoke-test the toolchain:

```bash
docker run --rm --entrypoint /usr/bin/bash zamkorus/cythinst64:3.13.13 -lc "python -V && uv --version && cython --version && pyinstaller --version && wine --version && (command -v 7z || command -v 7zz || command -v 7za)"
```

Push the base image when ready:

```bash
docker login
docker push zamkorus/cythinst64:3.13.13
docker push zamkorus/cythinst64:latest
```

## Publishing To GitHub Marketplace

The Marketplace listing at `https://github.com/marketplace/actions/cythinst-64` depends on the action metadata in the root `action.yml`.

Keep this metadata name stable:

```yaml
name: 'Cythinst 64'
```

Changing the action name can make GitHub treat it as a different Marketplace action. Update the description, README, Docker image tag, and release notes freely, but keep the name as `Cythinst 64` when publishing to the existing listing.

To publish an update, create a GitHub release from the repository and select **Publish this Action to the GitHub Marketplace**. Use a Git tag such as `v1.1.0` or `v1.2.0`, then users can pin the action with:

```yaml
- uses: PlohnenSoftware/Cythinst64@v1.2.0
```

## Updating The Builder

To bump Python, update these args in `Sources/Dockerfile`:

- `PYTHON_VERSION`
- `PYTHON_ZIP_URL`
- `PYTHON_ZIP_SHA256`

Then rebuild the base image and rerun the smoke tests.

To bump WinLibs, update `WINLIBS_URL` in `Sources/Dockerfile`, rebuild, and confirm:

```bash
docker run --rm --entrypoint /usr/bin/bash zamkorus/cythinst64:3.13.13 -lc "echo 'gcc --version' | wine cmd"
```

## Notes For Agents And Maintainers

This repo has a few important conventions that are easy to miss when editing it quickly.

### Dockerfile Roles

`Sources/Dockerfile` is the heavy base image. It installs CachyOS packages, Wine, Windows Python, WinLibs, uv, Cython, PyInstaller, and 7-Zip.

`Dockerfile` is the GitHub Action wrapper image. It starts from the published base image, currently `zamkorus/cythinst64:3.13.13`, and only copies the current `entrypoint.sh`, `cython_build.py`, and `archive.sh`.

When changing Wine, Python, uv, Cython, PyInstaller, WinLibs, or system packages, edit `Sources/Dockerfile`.

When changing action behavior, arguments, dependency installation logic, or Cython/PyInstaller invocation, edit `entrypoint.sh` and then rebuild the root `Dockerfile` image if you want to test it as the action sees it.

### Cython Artifact Handoff

When `cython_out` is set, the action runs `cython_build.py` from the parent of the selected project directory. For a typical `path: src` build, that means Cython runs from the repository root while the source files still live under `src/`.

Setuptools may place the compiled `.pyd` in either location depending on the project layout and extension path:

- the selected project directory, for example `/github/workspace/src/helpers.cp313-win_amd64.pyd`;
- the parent repository directory, for example `/github/workspace/helpers.cp313-win_amd64.pyd`.

The entrypoint must collect `.pyd` files from both places before moving them into `cython_out`. If a GitHub Actions log shows Cython finishing successfully with a line like `copying ... -> src`, followed by `mv: cannot stat '../*.pyd'`, the Cython compile did not fail. The handoff path was too narrow and only looked in the parent directory.

For this class of bug, check the log order carefully:

- `Cythonizing`, `building '<module>' extension`, and `Setup build successful` means compilation worked.
- `mv: cannot stat ...*.pyd` after that means the action failed while moving the compiled artifact.
- Wine messages about `XDG_RUNTIME_DIR`, Vulkan, EGL, systray, or RPC services are usually unrelated noise unless the actual Python command exits unsuccessfully.

### Python Location

The build Python is Windows Python under Wine:

```text
C:\python
/wine/drive_c/python
```

The command wrappers in `/usr/local/bin` call Windows executables through Wine. Do not add Arch/CachyOS `python`, `python-pip`, or `cython` just to satisfy the build flow; that creates two Python worlds and makes failures harder to understand.

### Dependency Behavior

The entrypoint chooses dependency mode from files in the selected `path`:

- requirements file present in `path`: install it into global Windows Python with `uv pip install --system`.
- no requirements file, `pyproject.toml` present in `path` or a parent directory: extract `[project].dependencies` and install them into global Windows Python with `uv pip install --system`.
- neither present: run PyInstaller with image defaults.

The image Windows Python must satisfy `.python-version` or an exact `requires-python` project pin. The action does not use `uv run`, does not create `.venv`, and does not consume `uv.lock` during the build.

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
docker build -f Sources/Dockerfile -t zamkorus/cythinst64:3.13.13 .
docker tag zamkorus/cythinst64:3.13.13 zamkorus/cythinst64:latest
docker run --rm --entrypoint /usr/bin/bash zamkorus/cythinst64:3.13.13 -lc "python -V && uv --version && cython --version && pyinstaller --version && wine --version && (command -v 7z || command -v 7zz || command -v 7za)"
```

After changing `Dockerfile`, `entrypoint.sh`, or `cython_build.py`:

```bash
docker build -f Dockerfile -t cythinst64-action-test .
```

For a real behavior check, create a tiny project with `pyproject.toml`, generate a `.spec`, and run `/entrypoint.sh` inside the image. Also test a plain `requirements.txt` project when dependency installation logic changes.

### Using This Action From Another Repo

For another project, agents should check:

- The action `path` input points to the directory containing the `.spec` file.
- `pyproject.toml` may live in that directory or a parent directory.
- `uv.lock` may exist for local development, but this action installs into the image's global Windows Python.
- requirements projects have the expected requirements file path.
- The `.spec` file does not contain absolute paths from a developer machine.
- Output is expected under `<path>/dist/windows`.
- Cython builds set `cython_out` only when `.pyx` compilation is actually needed.
- Archive packages set `zip_name`, `sevenzip_name`, or both, and list every included repository-relative file, directory, or glob in `zip_paths`. Select the deepest useful directory when you want flatter archive entries. Use the same base name for paired outputs, such as `app.zip` and `app.7z`.

## Troubleshooting

### `OSError: [WinError 123] Invalid name: '/tmp\*'`

Check the `path` input. The default is `src`, and the action expects that directory to exist.

### uv.lock is ignored

The action currently installs dependencies into the image's global Windows Python. It does not create a uv project environment, so it does not use `uv.lock` at build time.

### Wine prints graphics or RPC warnings

Headless Wine often prints warnings about missing display, Vulkan, EGL, systray, or RPC services. These are usually harmless if `python`, `uv`, `cython`, and `pyinstaller` exit successfully.

### PyInstaller cannot find files from the spec

Check for absolute paths in the `.spec` file. Prefer paths relative to the project directory.

### zip_paths did not match anything

`zip_paths` entries are resolved from the repository root, not from the action `path`. Use paths like `src/dist/windows` or `dane.csv`.

### Archive package has duplicate file names

Each selected file or directory is placed at the archive root. If two selected paths map to the same archive name, the action exits instead of silently overwriting one file. Select a parent directory to preserve enough folder structure.

### Downloaded artifact contains a zip inside another zip

Cythinst creates the files named by `zip_name` and `sevenzip_name` directly in the workspace. GitHub's `actions/upload-artifact@v7` archives uploads by default, so uploading `familiada.zip` without extra options produces an artifact download that contains `familiada.zip` inside GitHub's artifact zip.

Use `archive: false` when uploading a ZIP that Cythinst already created:

```yaml
- name: Upload artifact
  uses: actions/upload-artifact@v7
  with:
    name: familiada.zip
    path: familiada.zip
    archive: false
```

Do the same for `familiada.7z` if you upload it as a workflow artifact. Release uploads through `softprops/action-gh-release` do not need this option; they attach the archive files as release assets directly.

## External Resources

- [CachyOS Docker image](https://hub.docker.com/r/cachyos/cachyos)
- [Wine](https://www.winehq.org)
- [uv](https://docs.astral.sh/uv/)
- [PyInstaller](https://pyinstaller.org)
- [Cython](https://cython.org)
- [7-Zip](https://www.7-zip.org/)
- [WinLibs](https://github.com/brechtsanders/winlibs_mingw)
- [docker-pyinstaller](https://github.com/cdrx/docker-pyinstaller)
- [pyinstaller-action-windows](https://github.com/JackMcKew/pyinstaller-action-windows)
- [cython_build script source inspiration](https://github.com/PlohnenSoftware/familiada_ZSP)
