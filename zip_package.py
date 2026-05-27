import glob
import pathlib
import sys
import zipfile


METHODS = {
    "store": zipfile.ZIP_STORED,
    "none": zipfile.ZIP_STORED,
    "deflate": zipfile.ZIP_DEFLATED,
    "deflated": zipfile.ZIP_DEFLATED,
    "bzip2": zipfile.ZIP_BZIP2,
    "bz2": zipfile.ZIP_BZIP2,
    "lzma": zipfile.ZIP_LZMA,
}


def fail(message: str) -> None:
    raise SystemExit(message)


def relative_to_root(path: pathlib.Path, root: pathlib.Path, label: str) -> pathlib.Path:
    try:
        return path.relative_to(root)
    except ValueError as exc:
        raise SystemExit(f"{label} must stay inside the repository root: {path}") from exc


def add_file(
    files: dict[str, pathlib.Path],
    archive_name: pathlib.Path,
    source: pathlib.Path,
) -> None:
    arcname = archive_name.as_posix()
    existing = files.get(arcname)
    if existing is not None and existing != source:
        fail(f"zip_paths maps multiple files to '{arcname}': {existing} and {source}")
    files[arcname] = source


def add_path(
    files: dict[str, pathlib.Path],
    source: pathlib.Path,
    root: pathlib.Path,
    zip_path: pathlib.Path,
) -> None:
    source = source.resolve()
    relative_to_root(source, root, "zip_paths entry")

    if source == zip_path:
        return

    if source.is_file():
        add_file(files, pathlib.Path(source.name), source)
        return

    if source.is_dir():
        for child in source.rglob("*"):
            if child.is_file():
                child = child.resolve()
                if child != zip_path:
                    add_file(files, child.relative_to(source), child)
        return

    fail(f"zip_paths entry is not a file or directory: {source}")


def main() -> int:
    if len(sys.argv) != 5:
        fail("usage: zip_package.py <zip_name> <zip_paths> <zip_method> <zip_level>")

    zip_name, raw_paths, method_name, level_text = sys.argv[1:5]

    method_key = method_name.strip().lower()
    if method_key not in METHODS:
        supported = ", ".join(sorted(METHODS))
        fail(f"Unsupported zip_method '{method_name}'. Supported values: {supported}")

    try:
        compresslevel = int(level_text)
    except ValueError as exc:
        raise SystemExit(f"zip_level must be an integer, got '{level_text}'") from exc

    if not 0 <= compresslevel <= 9:
        fail(f"zip_level must be between 0 and 9, got {compresslevel}")

    root = pathlib.Path.cwd().resolve()
    zip_input = pathlib.Path(zip_name)
    if zip_input.is_absolute():
        fail("zip_name must be relative to the repository root")

    zip_path = (root / zip_input).resolve()
    zip_arcname = relative_to_root(zip_path, root, "zip_name")
    zip_path.parent.mkdir(parents=True, exist_ok=True)

    entries = [line.strip() for line in raw_paths.splitlines() if line.strip()]
    if not entries:
        fail("zip_paths is required when zip_name is set")

    files: dict[str, pathlib.Path] = {}
    missing: list[str] = []

    for entry in entries:
        matches = [pathlib.Path(match) for match in glob.glob(entry, recursive=True)]
        if not matches:
            candidate = pathlib.Path(entry)
            if candidate.exists():
                matches = [candidate]
            else:
                missing.append(entry)
                continue

        for match in matches:
            add_path(files, match, root, zip_path)

    if missing:
        fail("zip_paths entries did not match anything: " + ", ".join(missing))

    if not files:
        fail("zip_paths did not produce any files to archive")

    compression = METHODS[method_key]
    kwargs = {"compression": compression}
    if compression in (zipfile.ZIP_DEFLATED, zipfile.ZIP_BZIP2):
        kwargs["compresslevel"] = compresslevel

    with zipfile.ZipFile(zip_path, "w", **kwargs) as archive:
        for arcname in sorted(files):
            archive.write(files[arcname], arcname)

    print(f"Created {zip_arcname.as_posix()} with {len(files)} files using {method_key}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
