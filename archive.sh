#!/usr/bin/env bash
set -euo pipefail

ZIP_METHODS=" deflate store "
SEVENZIP_METHOD="LZMA2"
SEVENZIP_DICTIONARY="4096m"
SEVENZIP_WORD_SIZE="273"
SEVENZIP_SOLID_BLOCK="16g"

declare -A FILES=()

fail() {
    echo "$*" >&2
    exit 1
}

find_7z() {
    local command

    for command in 7z 7zz 7za; do
        if command -v "$command" >/dev/null 2>&1; then
            command -v "$command"
            return 0
        fi
    done

    fail "7-Zip executable not found. Rebuild the base image with the CachyOS/Arch 7zip package."
}

resolve_inside_root() {
    local path="$1"
    local label="$2"
    local resolved

    resolved="$(realpath -m "$path")"
    case "$resolved" in
        "$REPO_ROOT" | "$REPO_ROOT"/*)
            printf '%s\n' "$resolved"
            ;;
        *)
            fail "$label must stay inside the repository root: $resolved"
            ;;
    esac
}

is_excluded() {
    local source="$1"
    local exclude

    for exclude in "${EXCLUDES[@]}"; do
        if [ "$source" = "$exclude" ]; then
            return 0
        fi
    done

    return 1
}

add_file() {
    local arcname="$1"
    local source="$2"
    local existing="${FILES[$arcname]:-}"

    if [ -n "$existing" ] && [ "$existing" != "$source" ]; then
        fail "zip_paths maps multiple files to '$arcname': $existing and $source"
    fi

    FILES["$arcname"]="$source"
}

add_path() {
    local source="$1"
    local resolved
    local child
    local arcname

    resolved="$(resolve_inside_root "$source" "zip_paths entry")"

    if is_excluded "$resolved"; then
        return 0
    fi

    if [ -f "$resolved" ]; then
        add_file "$(basename "$resolved")" "$resolved"
        return 0
    fi

    if [ -d "$resolved" ]; then
        while IFS= read -r -d '' child; do
            child="$(realpath -m "$child")"
            if is_excluded "$child"; then
                continue
            fi
            arcname="${child#"$resolved"/}"
            add_file "$arcname" "$child"
        done < <(find "$resolved" -type f -print0)
        return 0
    fi

    fail "zip_paths entry is not a file or directory: $resolved"
}

load_excludes() {
    local raw_excludes="$1"
    local line

    EXCLUDES=()
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in
            /*)
                ;;
            *)
                EXCLUDES+=("$(resolve_inside_root "$REPO_ROOT/$line" "archive output")")
                ;;
        esac
    done <<< "$raw_excludes"
}

collect_files() {
    local raw_paths="$1"
    local raw_excludes="$2"
    local entry
    local matches
    local match
    local missing=()

    REPO_ROOT="$(pwd -P)"
    load_excludes "$raw_excludes"
    FILES=()

    if ! grep -q '[^[:space:]]' <<< "$raw_paths"; then
        fail "zip_paths is required when creating an archive"
    fi

    shopt -s globstar nullglob dotglob
    while IFS= read -r entry; do
        entry="${entry#"${entry%%[![:space:]]*}"}"
        entry="${entry%"${entry##*[![:space:]]}"}"
        [ -n "$entry" ] || continue

        mapfile -t matches < <(compgen -G "$entry" || true)
        if [ "${#matches[@]}" -eq 0 ]; then
            if [ -e "$entry" ]; then
                matches=("$entry")
            else
                missing+=("$entry")
                continue
            fi
        fi

        for match in "${matches[@]}"; do
            add_path "$match"
        done
    done <<< "$raw_paths"
    shopt -u globstar nullglob dotglob

    if [ "${#missing[@]}" -gt 0 ]; then
        fail "zip_paths entries did not match anything: ${missing[*]}"
    fi

    if [ "${#FILES[@]}" -eq 0 ]; then
        fail "zip_paths did not produce any files to archive"
    fi
}

stage_files() {
    local stage_root="$1"
    local list_file="$2"
    local arcname
    local source
    local target

    : > "$list_file"
    for arcname in "${!FILES[@]}"; do
        source="${FILES[$arcname]}"
        target="$stage_root/$arcname"
        mkdir -p "$(dirname "$target")"
        if ! ln "$source" "$target" 2>/dev/null; then
            cp -p "$source" "$target"
        fi
    done

    printf '%s\n' "${!FILES[@]}" | sort > "$list_file"
}

resolve_archive_output() {
    local archive_name="$1"
    local label="$2"

    case "$archive_name" in
        /*)
            fail "$label must be relative to the repository root"
            ;;
    esac

    ARCHIVE_PATH="$(resolve_inside_root "$REPO_ROOT/$archive_name" "$label")"
    mkdir -p "$(dirname "$ARCHIVE_PATH")"
}

create_zip() {
    local archive_name="$1"
    local raw_paths="$2"
    local method_name="${3,,}"
    local level_text="$4"
    local raw_excludes="$5"
    local sevenzip
    local temp_dir
    local list_file
    local method_arg

    if [[ "$ZIP_METHODS" != *" $method_name "* ]]; then
        fail "Unsupported zip_method '$3'. Supported values: deflate, store. Use sevenzip_name for stronger compression."
    fi

    if ! [[ "$level_text" =~ ^[0-9]+$ ]] || [ "$level_text" -lt 0 ] || [ "$level_text" -gt 9 ]; then
        fail "zip_level must be between 0 and 9, got $level_text"
    fi

    collect_files "$raw_paths" "$raw_excludes"
    resolve_archive_output "$archive_name" "zip_name"
    rm -f "$ARCHIVE_PATH"

    sevenzip="$(find_7z)"
    temp_dir="$(mktemp -d -t cythinst-zip-XXXXXX)"
    list_file="$temp_dir/.cythinst-archive-list.txt"
    stage_files "$temp_dir" "$list_file"

    if [ "$method_name" = "store" ]; then
        method_arg="-mm=Copy"
    else
        method_arg="-mm=Deflate"
    fi

    (
        cd "$temp_dir"
        "$sevenzip" a -tzip "-mx=$level_text" "$method_arg" -bd "$ARCHIVE_PATH" "@$list_file" >/dev/null
    )
    rm -rf "$temp_dir"
    echo "Created ${ARCHIVE_PATH#"$REPO_ROOT"/} with ${#FILES[@]} files using zip/$method_name"
}

create_7z() {
    local archive_name="$1"
    local raw_paths="$2"
    local raw_excludes="$3"
    local sevenzip
    local temp_dir
    local list_file

    collect_files "$raw_paths" "$raw_excludes"
    resolve_archive_output "$archive_name" "sevenzip_name"
    rm -f "$ARCHIVE_PATH"

    sevenzip="$(find_7z)"
    temp_dir="$(mktemp -d -t cythinst-7z-XXXXXX)"
    list_file="$temp_dir/.cythinst-archive-list.txt"
    stage_files "$temp_dir" "$list_file"

    (
        cd "$temp_dir"
        "$sevenzip" a \
            -t7z \
            -mx=9 \
            "-m0=${SEVENZIP_METHOD}" \
            "-md=${SEVENZIP_DICTIONARY}" \
            "-mfb=${SEVENZIP_WORD_SIZE}" \
            "-ms=${SEVENZIP_SOLID_BLOCK}" \
            -mmt=on \
            -bd \
            "$ARCHIVE_PATH" \
            "@$list_file" >/dev/null
    )

    rm -rf "$temp_dir"
    echo "Created ${ARCHIVE_PATH#"$REPO_ROOT"/} with ${#FILES[@]} files using 7z/${SEVENZIP_METHOD} ultra, dictionary ${SEVENZIP_DICTIONARY}, word ${SEVENZIP_WORD_SIZE}, solid block ${SEVENZIP_SOLID_BLOCK}"
}

case "${1:-}" in
    zip)
        [ "$#" -eq 6 ] || fail "usage: archive.sh zip <zip_name> <zip_paths> <zip_method> <zip_level> <exclude_paths>"
        create_zip "$2" "$3" "$4" "$5" "$6"
        ;;
    7z | sevenzip)
        [ "$#" -eq 4 ] || fail "usage: archive.sh 7z <sevenzip_name> <zip_paths> <exclude_paths>"
        create_7z "$2" "$3" "$4"
        ;;
    *)
        fail "usage: archive.sh <zip|7z> ..."
        ;;
esac
