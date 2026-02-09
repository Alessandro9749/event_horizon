#!/usr/bin/env bash

SCRIPT_VERSION="EventHorizon 1.1.2"

# Require bash (associative arrays, [[ ]], etc.)
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "This script must be run with bash (e.g. 'bash event_horizon_linux.sh')." >&2
    exit 1
fi

# ---------------- CLI flags ----------------
ASSUME_YES=0
ALLOW_ROOT=0
PROMPT_RENAME_DEST=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            echo "$SCRIPT_VERSION"
            exit 0
            ;;
        -y|--yes)
            ASSUME_YES=1
            shift
            ;;
        --allow-root)
            # Allow writing extracted output owned by root.
            # Default is to avoid root so extracted files are owned by the real user.
            ALLOW_ROOT=1
            shift
            ;;
        --rename)
            # Ask at the end if the destination folder should be renamed.
            # Default: do not prompt (avoids redundant questions).
            PROMPT_RENAME_DEST=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

# ---------------- Safety: avoid root-owned extracted files ----------------
# If launched via `sudo ./script.sh`, extracted files/folders become owned by root,
# which often looks like "wrong permissions" to the user.
# Re-exec as the original user so output is created with normal ownership.
if [[ "$ALLOW_ROOT" -ne 1 ]] && [[ "$(id -u)" -eq 0 ]]; then
    if [[ -n "${SUDO_USER:-}" ]] && [[ "${EH_REEXEC:-0}" -ne 1 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            echo "Running as root via sudo. Re-running as user '$SUDO_USER' to avoid root-owned extracted files." >&2
            exec sudo -u "$SUDO_USER" -H env EH_REEXEC=1 bash "$0" "$@"
        else
            echo "Running as root. Please run without sudo (or use --allow-root)." >&2
            exit 1
        fi
    else
        echo "Running as root. Please run without sudo (or use --allow-root)." >&2
        exit 1
    fi
fi

# ---------------- Variables ----------------
FILE=""
DEST_FOLDER=""
TEMP=""
TEMP_CREATED=0
TEMP_DIR=""
TEMP_DIR_CREATED=0

is_termux() {
    # Heuristic: Termux has pkg and its typical prefix path.
    command -v pkg >/dev/null 2>&1 && [[ -d "/data/data/com.termux/files/usr" ]]
}

choose_tmp_dir() {
    # Prefer existing project-local temp directories on Debian/Ubuntu/Linux.
    # Only use these on non-Termux as requested.
    # Order: ./temp then ./templates
    if is_termux; then
        echo "."
        return 0
    fi

    if [[ -d "./temp" ]]; then
        echo "./temp"
        return 0
    fi

    if [[ -d "./templates" ]]; then
        echo "./templates"
        return 0
    fi

    echo "."
}

make_temp_file() {
    # Creates a unique temp file path (does not write content itself).
    # Prints the path.
    local dir
    dir="$(choose_tmp_dir)"
    local prefix="__tmp_extract_"

    if command -v mktemp >/dev/null 2>&1; then
        mktemp -p "$dir" "${prefix}XXXXXX" 2>/dev/null && return 0
    fi

    local candidate
    local i
    for i in 1 2 3 4 5; do
        candidate="$dir/${prefix}${RANDOM}_${RANDOM}"
        if ( set -o noclobber; : >"$candidate" ) 2>/dev/null; then
            echo "$candidate"
            return 0
        fi
    done

    abort "Cannot create temporary file in '$dir'."
}

make_temp_dir() {
    # Creates a unique temp directory.
    # Prints the path.
    local dir
    dir="$(choose_tmp_dir)"
    local prefix="__tmp_extract_dir_"

    if command -v mktemp >/dev/null 2>&1; then
        mktemp -d -p "$dir" "${prefix}XXXXXX" 2>/dev/null && return 0
    fi

    local candidate
    local i
    for i in 1 2 3 4 5; do
        candidate="$dir/${prefix}${RANDOM}_${RANDOM}"
        if mkdir "$candidate" 2>/dev/null; then
            echo "$candidate"
            return 0
        fi
    done

    abort "Cannot create temporary directory in '$dir'."
}

cleanup() {
    # Always stop spinner if running
    stop_spinner 2>/dev/null || true

    # Remove temporary decompressed file on any exit (success or error)
    if [[ "${TEMP_CREATED:-0}" -eq 1 ]] && [[ -n "${TEMP:-}" ]] && [[ -f "$TEMP" ]]; then
        # Safety: only remove our own temp naming pattern, and only in allowed locations.
        local bn
        bn="$(basename -- "$TEMP")"
        if [[ "$bn" == __tmp_extract_* ]]; then
            case "$TEMP" in
                ./__tmp_extract_*|./temp/__tmp_extract_*|./templates/__tmp_extract_*)
                    rm -f "$TEMP" 2>/dev/null || true
                    ;;
            esac
        fi
    fi

    # Remove temporary directory on any exit (success or error)
    if [[ "${TEMP_DIR_CREATED:-0}" -eq 1 ]] && [[ -n "${TEMP_DIR:-}" ]] && [[ -d "$TEMP_DIR" ]]; then
        # Safety: only remove our own temp naming pattern, and only in allowed locations.
        local bn_dir
        bn_dir="$(basename -- "$TEMP_DIR")"
        if [[ "$bn_dir" == __tmp_extract_dir_* ]]; then
            case "$TEMP_DIR" in
                ./__tmp_extract_dir_*|./temp/__tmp_extract_dir_*|./templates/__tmp_extract_dir_*)
                    rm -rf "$TEMP_DIR" 2>/dev/null || true
                    ;;
            esac
        fi
    fi
}

abort() {
    # Usage: abort "message"
    local msg="$*"
    [[ -n "$msg" ]] && echo "$msg"
    echo "Abort."
    exit 1
}

cmd_to_pkg() {
    # Map commands to packages depending on the distro/package manager.
    # NOTE: this script is intended to work on Debian/Ubuntu (apt) and Termux.
    local cmd="$1"

    # Detect Termux reliably (pkg exists + Termux root path)
    if command -v pkg >/dev/null 2>&1 && [[ -d "/data/data/com.termux/files/usr" ]]; then
        case "$cmd" in
            7z) echo "p7zip" ;;
            wimlib-imagex) echo "wimlib" ;;
            zipinfo) echo "unzip" ;;
            *) echo "$cmd" ;;
        esac
        return 0
    fi

    # Debian/Ubuntu (apt)
    if command -v apt-get >/dev/null 2>&1; then
        case "$cmd" in
            7z) echo "p7zip-full" ;;
            zipinfo) echo "unzip" ;;
            unzip) echo "unzip" ;;
            file) echo "file" ;;
            tar) echo "tar" ;;
            gzip) echo "gzip" ;;
            bzip2) echo "bzip2" ;;
            xz) echo "xz-utils" ;;
            zstd) echo "zstd" ;;
            lz4) echo "lz4" ;;
            wimlib-imagex) echo "wimtools" ;;
            *) echo "$cmd" ;;
        esac
        return 0
    fi

    # Fallback: best-effort
    echo "$cmd"
}

abs_path() {
    # Print absolute path for an existing path.
    # Tries: realpath -> readlink -f -> python3 -> basic join.
    local p="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath -- "$p" 2>/dev/null && return 0
    fi
    if command -v readlink >/dev/null 2>&1; then
        readlink -f -- "$p" 2>/dev/null && return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 - <<'PY' "$p" 2>/dev/null && return 0
import os,sys
print(os.path.abspath(sys.argv[1]))
PY
        return 0
    fi

    # Fallback (best-effort): doesn't resolve symlinks.
    case "$p" in
        /*) printf '%s\n' "$p" ;;
        *) printf '%s\n' "$(pwd)/$p" ;;
    esac
}

install_missing_deps() {
    # Usage: install_missing_deps pkg1 pkg2 ...
    # Installs packages using Termux pkg or Debian apt-get.
    local pkgs=("$@")
    if ((${#pkgs[@]}==0)); then
        return 0
    fi

    # Termux
    if command -v pkg >/dev/null 2>&1 && [[ -d "/data/data/com.termux/files/usr" ]]; then
        pkg install -y "${pkgs[@]}"
        return $?
    fi

    # Debian/Ubuntu
    if command -v apt-get >/dev/null 2>&1; then
        local SUDO=""
        if [[ "$(id -u)" -ne 0 ]]; then
            command -v sudo >/dev/null 2>&1 || {
                echo "Missing 'sudo'. Re-run as root or install sudo, then retry." >&2
                return 1
            }
            SUDO="sudo"

            # Prompt for sudo password up-front (so it doesn't get hidden by spinners)
            # and fail fast if the user can't authenticate.
            if is_interactive; then
                echo "Sudo password may be required to install packages." >&2
                $SUDO -v || return 1
            else
                echo "Need sudo to install packages, but no interactive TTY is available." >&2
                return 1
            fi
        fi

        # Show apt output (users expect progress + prompts if any)
        $SUDO apt-get update || return 1
        $SUDO apt-get install -y "${pkgs[@]}"
        return $?
    fi

    echo "No supported package manager found (need Termux pkg or apt-get)." >&2
    return 1
}

prompt_overwrite_rename_abort_file() {
    # Usage: prompt_overwrite_rename_abort_file "path" -> prints final path
    local path="$1"
    local dir
    local name
    dir="$(dirname -- "$path")"
    name="$(basename -- "$path")"
    local stem="$name"
    local ext=""
    local candidate="$path"
    local i=1

    # Split last extension for rename convenience
    if [[ "$name" == *.* ]]; then
        ext=".${name##*.}"
        stem="${name%.*}"
    fi

    if [[ ! -e "$candidate" ]]; then
        printf '%s' "$candidate"
        return 0
    fi

    # IMPORTANT: this function is used in command-substitution:
    #   OUT_PATH="$(prompt_overwrite_rename_abort_file ...)"
    # So any informational text MUST go to stderr, otherwise it contaminates
    # the returned path (leading to filenames containing newlines/spaces from prompts).
    echo "Output file already exists: $candidate" >&2
    read_char_prompt ACT "Choose: (o) overwrite, (r) rename, (a) abort: "
    case "$ACT" in
        o|O)
            printf '%s' "$candidate"
            return 0
            ;;
        r|R)
            while [[ -e "$candidate" ]]; do
                candidate="$dir/${stem}_$i$ext"
                ((i++))
            done
            read_line_prompt NEW "New file name (Enter for '$(basename -- "$candidate")'): "
            if [[ -n "$NEW" ]]; then
                candidate="$dir/$NEW"
            fi
            [[ -e "$candidate" ]] && abort "File already exists: $candidate"
            printf '%s' "$candidate"
            return 0
            ;;
        a|A)
            abort
            ;;
        *)
            abort "Invalid choice."
            ;;
    esac
}

suggest_unique_dest() {
    # Usage: suggest_unique_dest "base"
    local base="$1"
    local candidate="$base"
    local i=1
    while [[ -e "$candidate" ]]; do
        candidate="${base}_$i"
        ((i++))
    done
    echo "$candidate"
}

ensure_dest_folder() {
    # Ensures DEST_FOLDER is a usable directory.
    # If a file/folder already exists with the same name, ask what to do.
    # Sets globals:
    #   DEST_FOLDER (may change if renamed)
    #   OVERWRITE=1 if user chose overwrite
    local dest="$1"
    OVERWRITE=0

    while true; do
        if [[ ! -e "$dest" ]]; then
            mkdir -p "$dest" || abort "Cannot create folder: $dest"
            DEST_FOLDER="$dest"
            return 0
        fi

        if [[ -d "$dest" ]]; then
            echo "Destination folder already exists: $dest"
            read_char_prompt ACT "Choose: (o) overwrite, (r) rename, (a) abort: "
            case "$ACT" in
                o|O)
                    OVERWRITE=1
                    DEST_FOLDER="$dest"
                    return 0
                    ;;
                r|R)
                    suggested="$(suggest_unique_dest "$dest")"
                    read_line_prompt NEW "New folder name (Enter for '$suggested'): "
                    [[ -z "$NEW" ]] && dest="$suggested" || dest="$NEW"
                    ;;
                a|A)
                    abort
                    ;;
                *)
                    echo "Please choose o, r, or a."
                    ;;
            esac
        else
            echo "Destination name is already used by a file: $dest"
            read_char_prompt ACT "Choose: (o) overwrite (delete file), (r) rename, (a) abort: "
            case "$ACT" in
                o|O)
                    read_char_prompt CONF "This will delete '$dest'. Continue? (y/n) "
                    case "$CONF" in
                        y|Y)
                            rm -f "$dest" 2>/dev/null || abort "Cannot delete file: $dest"
                            mkdir -p "$dest" || abort "Cannot create folder: $dest"
                            OVERWRITE=1
                            DEST_FOLDER="$dest"
                            return 0
                            ;;
                        *)
                            echo
                            ;;
                    esac
                    ;;
                r|R)
                    suggested="$(suggest_unique_dest "$dest")"
                    read_line_prompt NEW "New folder name (Enter for '$suggested'): "
                    [[ -z "$NEW" ]] && dest="$suggested" || dest="$NEW"
                    ;;
                a|A)
                    abort
                    ;;
                *)
                    echo "Please choose o, r, or a."
                    ;;
            esac
        fi
    done
}

# Ensure cleanup runs even if the script exits early due to an error
trap cleanup EXIT INT TERM

# ---------------- Input source (avoid extra-Enter issues) ----------------
# On some Windows terminals (Git Bash/MSYS), `read` may behave oddly when
# stdin isn't the real TTY, causing prompts to feel like they need extra Enter.
# Reading from /dev/tty makes interactive prompts deterministic.
READ_FROM="/dev/stdin"
if [[ -r /dev/tty ]]; then
    READ_FROM="/dev/tty"
fi

read_char_prompt() {
    # Usage: read_char_prompt VAR "Prompt: "
    local __var="$1"; shift
    local __prompt="$*"
    local __c=""
    printf '%s' "$__prompt" >&2
    if ! IFS= read -r -n 1 __c <"$READ_FROM"; then
        # Ensure caller doesn't accidentally reuse a previous env value
        printf -v "$__var" '%s' ""
        return 1
    fi
    # Consume the rest of the line (including newline) to avoid leftover Enter
    IFS= read -r _rest <"$READ_FROM" 2>/dev/null || true
    __c="${__c%$'\r'}"
    printf -v "$__var" '%s' "$__c"
}

is_interactive() {
    # True if we can prompt the user.
    [[ -r /dev/tty ]] || [[ -t 0 ]] || [[ -t 1 ]] || [[ -t 2 ]]
}

read_line_prompt() {
    # Usage: read_line_prompt VAR "Prompt: "
    local __var="$1"; shift
    local __prompt="$*"
    local __line=""
    printf '%s' "$__prompt" >&2
    IFS= read -r __line <"$READ_FROM" || return 1
    __line="${__line%$'\r'}"
    printf -v "$__var" '%s' "$__line"
}

read_secret_prompt() {
    # Usage: read_secret_prompt VAR "Prompt: "
    local __var="$1"; shift
    local __prompt="$*"
    local __line=""
    printf '%s' "$__prompt" >&2
    IFS= read -r -s __line <"$READ_FROM" || return 1
    __line="${__line%$'\r'}"
    printf '\n' >&2
    printf -v "$__var" '%s' "$__line"
}

# ---------------- Spinner function ----------------
spinner() {
    while :; do
        printf "." >&2
        sleep 0.4
    done
}

start_spinner() {
    # Usage: start_spinner "Message"
    local msg="$*"
    [[ -n "$msg" ]] && printf '%s' "$msg" >&2
    spinner &
    SPIN_PID=$!
}

stop_spinner() {
    if [[ -n "${SPIN_PID:-}" ]]; then
        kill "$SPIN_PID" 2>/dev/null || true
        wait "$SPIN_PID" 2>/dev/null || true
        unset SPIN_PID
        printf '\n' >&2
    fi
}

flatten_single_top_dir() {
    # If DEST_FOLDER contains exactly ONE entry and it is a directory,
    # move its contents up one level and remove the now-empty directory.
    # Example:
    #   DEST_FOLDER/metadata/*  => DEST_FOLDER/*
    local dest="$1"
    local entries=()
    local p

    while IFS= read -r -d '' p; do
        entries+=("$p")
    done < <(find "$dest" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)

    if (( ${#entries[@]} == 1 )) && [[ -d "${entries[0]}" ]]; then
        local inner="${entries[0]}"
        (
            shopt -s dotglob nullglob
            mv -- "$inner"/* "$dest"/ 2>/dev/null || true
        )
        rmdir -- "$inner" 2>/dev/null || true
    fi
}

detect_single_top_file() {
    # If the archive contains exactly ONE top-level file (not a directory),
    # print its name and return 0. Otherwise return 1.
    local ext="$1"
    local real_type="$2"
    local temp="$3"
    local lines=()
    local p

    # Prefer extension-based detection for multi-extension formats (e.g. .tar.gz)
    case "$ext" in
        tar.gz|tar.gzip)
            while IFS= read -r p; do
                [[ -z "$p" ]] && continue
                [[ "$p" == */ ]] && continue
                lines+=("$p")
            done < <(tar -tzf "$temp" 2>/dev/null)
            ;;
        tar.bz2|tar.bzip2)
            while IFS= read -r p; do
                [[ -z "$p" ]] && continue
                [[ "$p" == */ ]] && continue
                lines+=("$p")
            done < <(tar -tjf "$temp" 2>/dev/null)
            ;;
        tar.xz)
            while IFS= read -r p; do
                [[ -z "$p" ]] && continue
                [[ "$p" == */ ]] && continue
                lines+=("$p")
            done < <(tar -tJf "$temp" 2>/dev/null)
            ;;
        tar.lzma)
            while IFS= read -r p; do
                [[ -z "$p" ]] && continue
                [[ "$p" == */ ]] && continue
                lines+=("$p")
            done < <(tar --lzma -tf "$temp" 2>/dev/null)
            ;;
        tar.zst|tar.zstd)
            while IFS= read -r p; do
                [[ -z "$p" ]] && continue
                [[ "$p" == */ ]] && continue
                lines+=("$p")
            done < <(tar --zstd -tf "$temp" 2>/dev/null)
            ;;
    esac

    if (( ${#lines[@]} == 1 )); then
        if [[ "${lines[0]}" != */* ]]; then
            printf '%s' "${lines[0]}"
            return 0
        fi
    fi

    lines=()

    case "$real_type" in
        *7-zip*|*7-Zip*)
            if command -v 7z >/dev/null 2>&1; then
                local in_list=0
                local current=""
                local attrs=""
                while IFS= read -r p; do
                    [[ "$in_list" -eq 0 ]] && [[ "$p" == "----------" ]] && { in_list=1; continue; }
                    [[ "$in_list" -eq 0 ]] && continue

                    if [[ "$p" == "Path = "* ]]; then
                        current="${p#Path = }"
                    elif [[ "$p" == "Attributes = "* ]]; then
                        attrs="${p#Attributes = }"
                        # If not a directory, count it
                        if [[ -n "$current" ]] && [[ "$attrs" != *D* ]]; then
                            lines+=("$current")
                        fi
                    fi
                done < <(7z l -ba -slt "$temp" 2>/dev/null)
            else
                return 1
            fi
            ;;
        *Zip*)
            if command -v zipinfo >/dev/null 2>&1; then
                while IFS= read -r p; do
                    [[ -z "$p" ]] && continue
                    [[ "$p" == */ ]] && continue
                    lines+=("$p")
                done < <(zipinfo -1 "$temp" 2>/dev/null)
            else
                return 1
            fi
            ;;
        *RAR*)
            # Debian may not have unrar; fall back to 7z listing.
            if command -v unrar >/dev/null 2>&1; then
                while IFS= read -r p; do
                    [[ -z "$p" ]] && continue
                    [[ "$p" == */ ]] && continue
                    lines+=("$p")
                done < <(unrar lb "$temp" 2>/dev/null)
            elif command -v 7z >/dev/null 2>&1; then
                local in_list=0
                local current=""
                local attrs=""
                while IFS= read -r p; do
                    [[ "$in_list" -eq 0 ]] && [[ "$p" == "----------" ]] && { in_list=1; continue; }
                    [[ "$in_list" -eq 0 ]] && continue

                    if [[ "$p" == "Path = "* ]]; then
                        current="${p#Path = }"
                    elif [[ "$p" == "Attributes = "* ]]; then
                        attrs="${p#Attributes = }"
                        # If not a directory, count it
                        if [[ -n "$current" ]] && [[ "$attrs" != *D* ]]; then
                            lines+=("$current")
                        fi
                    fi
                done < <(7z l -ba -slt "$temp" 2>/dev/null)
            else
                return 1
            fi
            ;;
        *tar*)
            while IFS= read -r p; do
                [[ -z "$p" ]] && continue
                [[ "$p" == */ ]] && continue
                lines+=("$p")
            done < <(tar -tf "$temp" 2>/dev/null)
            ;;
        *)
            return 1
            ;;
    esac

    if (( ${#lines[@]} == 1 )); then
        # Only if it's truly top-level (no path separators)
        if [[ "${lines[0]}" != */* ]]; then
            printf '%s' "${lines[0]}"
            return 0
        fi
    fi

    return 1
}

# ---------------- Find archives ----------------
FILES=()
declare -A _SEEN_FILES=()
for f in \
    *.zip *.rar *.rar4 *.tar *.7z *.wim \
    *.gz *.gzip *.gx *.bz2 *.bzip2 *.xz *.zst *.zstd *.lzma \
    *.lz4 \
    *.zip.lz4 *.tar.lz4 *.rar.lz4 \
    *.tar.gz *.tar.gzip *.tar.bz2 *.tar.bzip2 *.tar.xz *.tar.zst *.tar.zstd *.tar.lzma \
; do
    [ -f "$f" ] || continue
    rp="$(abs_path "$f")"
    # De-duplicate while preserving spaces in file names
    if [[ -z "${_SEEN_FILES["$rp"]+x}" ]]; then
        FILES+=("$rp")
        _SEEN_FILES["$rp"]=1
    fi
done
unset _SEEN_FILES

# ---------------- Choose input method ----------------
# a) choose from files found in current directory (as before)
# b) paste full/relative path to an archive
while true; do
    read_char_prompt MODE "Choose input: (a) select found file, (b) paste file path: "
    case "$MODE" in
        a|A)
            if [ "${#FILES[@]}" -eq 0 ]; then
                abort "No supported archive found in current folder."
            fi

            # ---------------- Select file (found list) ----------------
            if [ "${#FILES[@]}" -eq 1 ]; then
                FILE="${FILES[0]}"
                echo "Found archive: $FILE"
                while true; do
                    read_char_prompt CONFIRM "Is this correct? (y/n) "
                    case "$CONFIRM" in
                        y|Y) echo; break ;;
                        n|N) echo; echo "Abort."; exit 1 ;;
                        *) echo; echo "Please type y or n." ;;
                    esac
                done
            else
                echo "Multiple archives found:"
                for i in "${!FILES[@]}"; do
                    echo "$((i+1))) ${FILES[$i]}"
                done

                while true; do
                    read_line_prompt NUM "Select file number: "
                    # Skip empty input silently
                    [[ -z "$NUM" ]] && continue
                    if [[ "$NUM" =~ ^[0-9]+$ ]] && (( NUM >= 1 && NUM <= ${#FILES[@]} )); then
                        FILE="${FILES[$((NUM-1))]}"
                        break
                    else
                        echo "Invalid selection. Choose a number between 1 and ${#FILES[@]}."
                    fi
                done
            fi

            break
            ;;
        b|B)
            read_line_prompt PPATH "Paste archive path: "
            # Trim surrounding quotes (common when copying paths)
            PPATH="${PPATH%$'\r'}"
            PPATH="${PPATH%\"}"
            PPATH="${PPATH#\"}"

            [[ -z "$PPATH" ]] && abort "No path provided."
            [[ -f "$PPATH" ]] || abort "File not found: $PPATH"
            FILE="$(abs_path "$PPATH")"
            break
            ;;
        *)
            echo "Please choose a or b."
            ;;
    esac
done

echo "Selected: $FILE"

# ---------------- Detect extension ----------------
NAME="$(basename "$FILE")"
case "$NAME" in
    *.tar.zstd) EXT="tar.zstd" ;;
    *.tar.zst) EXT="tar.zst" ;;
    *.tar.lzma) EXT="tar.lzma" ;;
    *.tar.xz) EXT="tar.xz" ;;
    *.tar.bzip2) EXT="tar.bzip2" ;;
    *.tar.bz2) EXT="tar.bz2" ;;
    *.tar.gzip) EXT="tar.gzip" ;;
    *.tar.gz) EXT="tar.gz" ;;
    *.zip.lz4) EXT="zip.lz4" ;;
    *.tar.lz4) EXT="tar.lz4" ;;
    *.rar.lz4) EXT="rar.lz4" ;;
    *.7z) EXT="7z" ;;
    *.wim) EXT="wim" ;;
    *.rar4) EXT="rar4" ;;
    *.zip) EXT="zip" ;;
    *.rar) EXT="rar" ;;
    *.tar) EXT="tar" ;;
    *.zstd) EXT="zstd" ;;
    *.zst) EXT="zst" ;;
    *.lzma) EXT="lzma" ;;
    *.xz) EXT="xz" ;;
    *.bzip2) EXT="bzip2" ;;
    *.bz2) EXT="bz2" ;;
    *.gzip) EXT="gzip" ;;
    *.gx) EXT="gx" ;;
    *.gz) EXT="gz" ;;
    *.lz4) EXT="lz4" ;;
    *)
        echo "Unsupported file type."
        exit 1
        ;;
esac

# ---------------- Destination folder based on base filename ----------------
strip_archive_ext() {
    # Remove ONLY the archive-related suffix, preserving other dots.
    # Examples:
    #   cat.photo.zip      -> cat.photo
    #   file.backup.tar    -> file.backup
    #   file.backup.zip.lz4 -> file.backup
    local n="$1"
    case "$n" in
        *.tar.zstd) echo "${n%.tar.zstd}" ;;
        *.tar.zst) echo "${n%.tar.zst}" ;;
        *.tar.lzma) echo "${n%.tar.lzma}" ;;
        *.tar.xz) echo "${n%.tar.xz}" ;;
        *.tar.bzip2) echo "${n%.tar.bzip2}" ;;
        *.tar.bz2) echo "${n%.tar.bz2}" ;;
        *.tar.gzip) echo "${n%.tar.gzip}" ;;
        *.tar.gz) echo "${n%.tar.gz}" ;;
        *.zip.lz4) echo "${n%.zip.lz4}" ;;
        *.tar.lz4) echo "${n%.tar.lz4}" ;;
        *.rar.lz4) echo "${n%.rar.lz4}" ;;
        *.rar4) echo "${n%.rar4}" ;;
        *.7z) echo "${n%.7z}" ;;
        *.wim) echo "${n%.wim}" ;;
        *.zip) echo "${n%.zip}" ;;
        *.rar) echo "${n%.rar}" ;;
        *.tar) echo "${n%.tar}" ;;
        *.zstd) echo "${n%.zstd}" ;;
        *.zst) echo "${n%.zst}" ;;
        *.lzma) echo "${n%.lzma}" ;;
        *.xz) echo "${n%.xz}" ;;
        *.bzip2) echo "${n%.bzip2}" ;;
        *.bz2) echo "${n%.bz2}" ;;
        *.gzip) echo "${n%.gzip}" ;;
        *.gx) echo "${n%.gx}" ;;
        *.gz) echo "${n%.gz}" ;;
        *.lz4) echo "${n%.lz4}" ;;
        *) echo "$n" ;;
    esac
}

BASE_NAME="$(strip_archive_ext "$NAME")"
DEST_FOLDER="$BASE_NAME"

# ---------------- Dependencies ----------------
declare -A DEPS=(
    ["zip"]="unzip file"
    # Debian often doesn't ship 'unrar' by default (may require non-free).
    # We can extract RAR with 7z, so we depend on 7z instead.
    ["rar"]="7z file"
    ["rar4"]="7z file"
    ["tar"]="tar file"
    ["lz4"]="lz4 file"
    ["zip.lz4"]="lz4 unzip file"
    ["tar.lz4"]="lz4 tar file"
    ["rar.lz4"]="lz4 7z file"
    ["tar.gz"]="gzip tar file"
    ["tar.gzip"]="gzip tar file"
    ["tar.bz2"]="bzip2 tar file"
    ["tar.bzip2"]="bzip2 tar file"
    ["tar.xz"]="xz tar file"
    ["tar.lzma"]="xz tar file"
    ["tar.zst"]="zstd tar file"
    ["tar.zstd"]="zstd tar file"
    ["gz"]="gzip file"
    ["gzip"]="gzip file"
    ["gx"]="gzip file"
    ["bz2"]="bzip2 file"
    ["bzip2"]="bzip2 file"
    ["xz"]="xz file"
    ["lzma"]="xz file"
    ["zst"]="zstd file"
    ["zstd"]="zstd file"
    ["7z"]="7z file"
    ["wim"]="wimlib-imagex file"
)

IFS=' ' read -r -a REQUIRED <<< "${DEPS[$EXT]}"
MISSING=()

for cmd in "${REQUIRED[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || MISSING+=("$cmd")
done

if [ "${#MISSING[@]}" -ne 0 ]; then
    missing_list="$(printf '%s, ' "${MISSING[@]}")"
    missing_list="${missing_list%, }"
    echo "Missing dependencies: ${missing_list}."

    PKGS=()
    declare -A _SEEN_PKGS=()
    for c in "${MISSING[@]}"; do
        p="$(cmd_to_pkg "$c")"
        if [[ -z "${_SEEN_PKGS["$p"]+x}" ]]; then
            PKGS+=("$p")
            _SEEN_PKGS["$p"]=1
        fi
    done
    unset _SEEN_PKGS

    if [[ "${ASSUME_YES:-0}" -eq 1 ]]; then
        # In auto-yes mode we still need an interactive TTY for sudo password.
        if ! is_interactive && [[ "$(id -u)" -ne 0 ]]; then
            abort "Need sudo to install dependencies, but no interactive TTY is available."
        fi

        echo "Installing packages: ${PKGS[*]}" >&2
        # Don't redirect: sudo/apt prompts and progress must be visible.
        install_missing_deps "${PKGS[@]}"
        STATUS=$?
        [[ $STATUS -ne 0 ]] && { echo "Dependency installation failed."; exit 1; }
        echo "Dependencies installed successfully."
    else
        if ! is_interactive; then
            abort "Missing dependencies (${missing_list}) but no interactive TTY is available. Re-run with --yes to auto-install."
        fi

        while true; do
            ANSWER=""
            read_line_prompt ANSWER "Install them? (y/n) [y/yes] " || abort "Cannot read input. Re-run with --yes to auto-install."
            ANSWER="${ANSWER,,}"
            case "$ANSWER" in
                y|yes)
                    # Don't use a spinner here: sudo/apt prompts and progress must be visible.
                    echo "Installing packages: ${PKGS[*]}" >&2
                    install_missing_deps "${PKGS[@]}"
                    STATUS=$?
                    if [ $STATUS -ne 0 ]; then
                        echo "Dependency installation failed."
                        exit 1
                    fi
                    echo "Dependencies installed successfully."
                    break
                    ;;
                n|no)
                    echo; echo "Abort."
                    exit 1
                    ;;
                *)
                    echo; echo "Please type y or n."
                    ;;
            esac
        done
    fi
fi

# ---------------- Prepare temporary file ----------------
TEMP="$FILE"

if [[ "$EXT" == zip.lz4 || "$EXT" == tar.lz4 || "$EXT" == rar.lz4 ]]; then
    start_spinner "Decompressing LZ4"
    # Decompress into a unique temporary file to avoid collisions like:
    # "archive.zip already exists; not overwritten" when both
    # archive.zip and archive.zip.lz4 are present.
    TEMP="$(make_temp_file)"
    TEMP_CREATED=1
    lz4 -d -q "$FILE" "$TEMP" || {
        stop_spinner
        echo "LZ4 decompression failed."
        exit 1
    }
    stop_spinner
fi

# ---------------- Verify real file type ----------------
start_spinner "Inspecting archive"
REAL_TYPE="$(file -b "$TEMP")"
stop_spinner

# Force archive family for multi-extension TAR formats (tar can extract directly)
if [[ "$EXT" == tar.gz || "$EXT" == tar.gzip || "$EXT" == tar.bz2 || "$EXT" == tar.bzip2 || "$EXT" == tar.xz || "$EXT" == tar.lzma || "$EXT" == tar.zst || "$EXT" == tar.zstd ]]; then
    REAL_TYPE="tar"
fi

# ---------------- Single-file compressor formats ----------------
# These are not archives (no folders). We treat them as producing one output file.
if [[ "$EXT" == gz || "$EXT" == gzip || "$EXT" == gx || "$EXT" == bz2 || "$EXT" == bzip2 || "$EXT" == xz || "$EXT" == lzma || "$EXT" == zst || "$EXT" == zstd || "$EXT" == lz4 ]]; then
    OUT_NAME="$(strip_archive_ext "$NAME")"
    echo "Compressed file will output: $OUT_NAME"

    read_char_prompt SF_MODE "Extract (h) here or (c) classic into folder '$DEST_FOLDER'? "
    case "$SF_MODE" in
        h|H)
            DEST_FOLDER="."
            OUT_PATH="./$OUT_NAME"
            ;;
        *)
            ensure_dest_folder "$DEST_FOLDER"
            OUT_PATH="$DEST_FOLDER/$OUT_NAME"
            ;;
    esac

    OUT_PATH="$(prompt_overwrite_rename_abort_file "$OUT_PATH")"

    start_spinner "Decompressing"
    case "$EXT" in
        gz|gzip|gx) gzip -dc "$FILE" >"$OUT_PATH" 2>/dev/null || { stop_spinner; abort "Gzip decompression failed."; } ;;
        bz2|bzip2) bzip2 -dc "$FILE" >"$OUT_PATH" 2>/dev/null || { stop_spinner; abort "Bzip2 decompression failed."; } ;;
        xz|lzma) xz -dc "$FILE" >"$OUT_PATH" 2>/dev/null || { stop_spinner; abort "XZ decompression failed."; } ;;
        zst|zstd) zstd -dc -q "$FILE" >"$OUT_PATH" 2>/dev/null || { stop_spinner; abort "Zstd decompression failed."; } ;;
        lz4) lz4 -d -q "$FILE" "$OUT_PATH" 2>/dev/null || { stop_spinner; abort "LZ4 decompression failed."; } ;;
    esac
    stop_spinner

    # Optional rename destination folder (only for classic)
    if [[ "$DEST_FOLDER" != "." && "$DEST_FOLDER" != "./" ]]; then
        if [[ "${PROMPT_RENAME_DEST:-0}" -eq 1 ]] && is_interactive; then
            read_line_prompt NEW_NAME "Rename destination folder (Enter to keep '$DEST_FOLDER'): "
            if [[ -n "$NEW_NAME" ]] && [[ "$NEW_NAME" != "$DEST_FOLDER" ]]; then
                [[ -e "$NEW_NAME" ]] && abort "Cannot rename: target already exists: $NEW_NAME"
                mv -- "$DEST_FOLDER" "$NEW_NAME" || abort "Rename failed."
                DEST_FOLDER="$NEW_NAME"
            fi
        fi
        echo "Extraction completed in folder '$DEST_FOLDER'."
    else
        echo "Extraction completed."
    fi
    exit 0
fi

# ---------------- Optional: extract single file directly ----------------
SINGLE_TOP_FILE=""
SINGLE_TOP_FILE="$(detect_single_top_file "$EXT" "$REAL_TYPE" "$TEMP" 2>/dev/null)" || SINGLE_TOP_FILE=""

if [[ -n "$SINGLE_TOP_FILE" ]]; then
    echo "Archive contains a single file: $SINGLE_TOP_FILE"
    read_char_prompt SF_MODE "Extract (h) here or (c) classic into folder '$DEST_FOLDER'? "
    case "$SF_MODE" in
        h|H)
            DEST_FOLDER="."
            ;;
        *)
            :
            ;;
    esac
fi

# ---------------- Safety UX: warn when extracting "here" but archive is elsewhere ----------------
# Common Termux scenario: script installed in $PREFIX/bin, user selects an archive from ~/downloads.
# If the user chooses "Extract here", output will go into the *current directory* (e.g. $PREFIX/bin),
# which can look like the script "saved in the wrong place".
if [[ "$DEST_FOLDER" == "." || "$DEST_FOLDER" == "./" ]]; then
    FILE_ABS="$(abs_path "$FILE" 2>/dev/null || printf '%s' "$FILE")"
    ARCHIVE_DIR="$(dirname -- "$FILE_ABS" 2>/dev/null || printf '.')"
    CWD_ABS="$(pwd 2>/dev/null || printf '.')"

    if [[ -n "$ARCHIVE_DIR" ]] && [[ -n "$CWD_ABS" ]] && [[ "$ARCHIVE_DIR" != "$CWD_ABS" ]]; then
        echo "Warning: archive is in '$ARCHIVE_DIR' but current directory is '$CWD_ABS'." >&2
        echo "         'Extract here' will write into the current directory." >&2
    fi
fi

# ---------------- Single-top-file safety: prompt before overwriting when extracting "here" ----------------
# If the archive contains exactly one file and the user extracts "here", some tools may overwrite an
# existing file with the same name without prompting. To provide consistent UX, extract into a temp
# directory first, then move into place using the same overwrite/rename/abort prompt used elsewhere.
if [[ -n "${SINGLE_TOP_FILE:-}" ]] && [[ "$DEST_FOLDER" == "." || "$DEST_FOLDER" == "./" ]]; then
    OUT_PATH="./$SINGLE_TOP_FILE"
    OUT_PATH="$(prompt_overwrite_rename_abort_file "$OUT_PATH")"

    TEMP_DIR="$(make_temp_dir)"
    TEMP_DIR_CREATED=1

    case "$REAL_TYPE" in
        # Put 7-zip BEFORE Zip because the string "7-Zip" contains "Zip",
        # and a "*Zip*" pattern would shadow it (ShellCheck SC2221/SC2222).
        *7-zip*|*7-Zip*)
            start_spinner "Extracting 7z"
            if 7z x -y -p"" -o"$TEMP_DIR" "$TEMP" "$SINGLE_TOP_FILE" >/dev/null 2>&1; then
                stop_spinner
            else
                stop_spinner
                MAX_TRIES=3
                for (( try=1; try<=MAX_TRIES; try++ )); do
                    read_secret_prompt PASS "7z password (attempt $try/$MAX_TRIES): "
                    start_spinner "Extracting 7z"
                    if 7z x -y -p"$PASS" -o"$TEMP_DIR" "$TEMP" "$SINGLE_TOP_FILE" >/dev/null 2>&1; then
                        stop_spinner
                        PASS=""
                        break
                    fi
                    stop_spinner
                    if (( try < MAX_TRIES )); then
                        echo "Wrong password. Retry."
                    else
                        abort "Wrong password too many times. Please run the script again."
                    fi
                done
            fi
            ;;
        *Zip*)
            # Avoid interactive password prompts: try empty password first (-P "").
            start_spinner "Extracting ZIP"
            if unzip -q -P "" "$TEMP" "$SINGLE_TOP_FILE" -d "$TEMP_DIR" </dev/null >/dev/null 2>&1; then
                stop_spinner
            else
                stop_spinner
                MAX_TRIES=3
                for (( try=1; try<=MAX_TRIES; try++ )); do
                    read_secret_prompt PASS "ZIP password (attempt $try/$MAX_TRIES): "
                    start_spinner "Extracting ZIP"
                    if unzip -q -P "$PASS" "$TEMP" "$SINGLE_TOP_FILE" -d "$TEMP_DIR" </dev/null >/dev/null 2>&1; then
                        stop_spinner
                        PASS=""
                        break
                    fi
                    stop_spinner
                    if (( try < MAX_TRIES )); then
                        echo "Wrong password. Retry."
                    else
                        abort "Wrong password too many times. Please run the script again."
                    fi
                done
            fi
            ;;
        *tar*)
            start_spinner "Extracting TAR"
            tar -xf "$TEMP" -C "$TEMP_DIR" "$SINGLE_TOP_FILE" >/dev/null 2>&1 || { stop_spinner; abort "TAR extraction failed."; }
            stop_spinner
            ;;
        *)
            abort "Unsupported or corrupted archive."
            ;;
    esac

    [[ -f "$TEMP_DIR/$SINGLE_TOP_FILE" ]] || abort "Extraction failed: '$SINGLE_TOP_FILE' not found."
    mv -- "$TEMP_DIR/$SINGLE_TOP_FILE" "$OUT_PATH" 2>/dev/null || abort "Cannot write output file: $OUT_PATH"

    echo "Extraction completed."
    exit 0
fi

# ---------------- Extract archive ----------------
if [[ "$DEST_FOLDER" != "." && "$DEST_FOLDER" != "./" ]]; then
    ensure_dest_folder "$DEST_FOLDER"
else
    OVERWRITE=0
fi

# Overwrite behavior per tool
ZIP_OVERWRITE_OPT="-n"
UNRAR_OVERWRITE_OPT="-o-"
TAR_OVERWRITE_OPT="--skip-old-files"
if [[ "${OVERWRITE:-0}" -eq 1 ]]; then
    ZIP_OVERWRITE_OPT="-o"
    UNRAR_OVERWRITE_OPT="-o+"
    TAR_OVERWRITE_OPT="--overwrite"
fi

case "$REAL_TYPE" in
    *7-zip*|*7-Zip*)
        ZIP7_OVERWRITE_OPT="-aos"
        if [[ "${OVERWRITE:-0}" -eq 1 ]]; then
            ZIP7_OVERWRITE_OPT="-aoa"
        fi

        # Try without password first to avoid interactive prompts
        start_spinner "Extracting 7z"
        if 7z x -y "$ZIP7_OVERWRITE_OPT" -p"" -o"$DEST_FOLDER" "$TEMP" >/dev/null 2>&1; then
            stop_spinner
        else
            stop_spinner
            MAX_TRIES=3
            for (( try=1; try<=MAX_TRIES; try++ )); do
                read_secret_prompt PASS "7z password (attempt $try/$MAX_TRIES): "
                start_spinner "Extracting 7z"
                if 7z x -y "$ZIP7_OVERWRITE_OPT" -p"$PASS" -o"$DEST_FOLDER" "$TEMP" >/dev/null 2>&1; then
                    stop_spinner
                    PASS=""
                    break
                fi
                stop_spinner
                if (( try < MAX_TRIES )); then
                    echo "Wrong password. Retry."
                else
                    abort "Wrong password too many times. Please run the script again."
                fi
            done
        fi
        ;;
    *Zip*)
        # Important (Termux): avoid commands that may *block* waiting for a password.
        # Instead, try extracting with an explicit empty password (-P "") so unzip
        # will NOT prompt. If it fails, then ask the user and retry.
        start_spinner "Extracting ZIP"
        if unzip -q "$ZIP_OVERWRITE_OPT" -P "" "$TEMP" -d "$DEST_FOLDER" </dev/null >/dev/null 2>&1; then
            stop_spinner
        else
            stop_spinner
            MAX_TRIES=3
            for (( try=1; try<=MAX_TRIES; try++ )); do
                read_secret_prompt PASS "ZIP password (attempt $try/$MAX_TRIES): "
                start_spinner "Extracting ZIP"
                if unzip -q "$ZIP_OVERWRITE_OPT" -P "$PASS" "$TEMP" -d "$DEST_FOLDER" </dev/null >/dev/null 2>&1; then
                    stop_spinner
                    PASS=""
                    break
                fi
                stop_spinner
                if (( try < MAX_TRIES )); then
                    echo "Wrong password. Retry."
                else
                    abort "Wrong password too many times. Please run the script again."
                fi
            done
        fi
        ;;
    *RAR*)
        # Prefer unrar if present, otherwise fall back to 7z (works on Debian without non-free unrar).
        if command -v unrar >/dev/null 2>&1; then
            # Avoid interactive password prompts: -p- disables any prompt.
            start_spinner "Extracting RAR"
            if unrar x -inul "$UNRAR_OVERWRITE_OPT" -p- "$TEMP" "$DEST_FOLDER/" >/dev/null 2>&1; then
                stop_spinner
            else
                stop_spinner
                MAX_TRIES=3
                for (( try=1; try<=MAX_TRIES; try++ )); do
                    read_secret_prompt PASS "RAR password (attempt $try/$MAX_TRIES): "
                    start_spinner "Extracting RAR"
                    if unrar x -inul "$UNRAR_OVERWRITE_OPT" -p"$PASS" "$TEMP" "$DEST_FOLDER/" >/dev/null 2>&1; then
                        stop_spinner
                        PASS=""
                        break
                    fi
                    stop_spinner
                    if (( try < MAX_TRIES )); then
                        echo "Wrong password. Retry."
                    else
                        abort "Wrong password too many times. Please run the script again."
                    fi
                done
            fi
        else
            ZIP7_OVERWRITE_OPT="-aos"
            if [[ "${OVERWRITE:-0}" -eq 1 ]]; then
                ZIP7_OVERWRITE_OPT="-aoa"
            fi

            # Try without password first to avoid interactive prompts
            start_spinner "Extracting RAR (7z)"
            if 7z x -y "$ZIP7_OVERWRITE_OPT" -p"" -o"$DEST_FOLDER" "$TEMP" >/dev/null 2>&1; then
                stop_spinner
            else
                stop_spinner
                MAX_TRIES=3
                for (( try=1; try<=MAX_TRIES; try++ )); do
                    read_secret_prompt PASS "RAR password (attempt $try/$MAX_TRIES): "
                    start_spinner "Extracting RAR (7z)"
                    if 7z x -y "$ZIP7_OVERWRITE_OPT" -p"$PASS" -o"$DEST_FOLDER" "$TEMP" >/dev/null 2>&1; then
                        stop_spinner
                        PASS=""
                        break
                    fi
                    stop_spinner
                    if (( try < MAX_TRIES )); then
                        echo "Wrong password. Retry."
                    else
                        abort "Wrong password too many times. Please run the script again."
                    fi
                done
            fi
        fi
        ;;
    *tar*)
        case "$EXT" in
            tar.gz|tar.gzip)
                tar "$TAR_OVERWRITE_OPT" -xzf "$TEMP" -C "$DEST_FOLDER" || abort "TAR.GZ extraction failed."
                ;;
            tar.bz2|tar.bzip2)
                tar "$TAR_OVERWRITE_OPT" -xjf "$TEMP" -C "$DEST_FOLDER" || abort "TAR.BZ2 extraction failed."
                ;;
            tar.xz)
                tar "$TAR_OVERWRITE_OPT" -xJf "$TEMP" -C "$DEST_FOLDER" || abort "TAR.XZ extraction failed."
                ;;
            tar.lzma)
                tar "$TAR_OVERWRITE_OPT" --lzma -xf "$TEMP" -C "$DEST_FOLDER" || abort "TAR.LZMA extraction failed."
                ;;
            tar.zst|tar.zstd)
                tar "$TAR_OVERWRITE_OPT" --zstd -xf "$TEMP" -C "$DEST_FOLDER" || abort "TAR.ZST extraction failed."
                ;;
            *)
                tar "$TAR_OVERWRITE_OPT" -xf "$TEMP" -C "$DEST_FOLDER" || abort "TAR extraction failed."
                ;;
        esac
        ;;
    *Windows*Imaging*|*WIM*)
        WIM_INDEX="1"
        read_line_prompt WIM_INDEX "WIM image index to extract (default 1): "
        [[ -z "$WIM_INDEX" ]] && WIM_INDEX="1"
        [[ "$WIM_INDEX" =~ ^[0-9]+$ ]] || abort "Invalid WIM index."

        start_spinner "Extracting WIM"
        wimlib-imagex extract "$TEMP" "$WIM_INDEX" --dest-dir="$DEST_FOLDER" >/dev/null 2>&1 || { stop_spinner; abort "WIM extraction failed."; }
        stop_spinner
        ;;
    *)
        echo "Unsupported or corrupted archive."
        exit 1
        ;;
esac

# ---------------- Optional flatten: single top-level folder ----------------
if [[ "$DEST_FOLDER" != "." && "$DEST_FOLDER" != "./" ]]; then
    flatten_single_top_dir "$DEST_FOLDER"
fi

# ---------------- Optional rename destination folder ----------------
# Disabled by default to avoid redundant prompts (the script already handles name
# collisions via overwrite/rename decisions earlier).
if [[ "${PROMPT_RENAME_DEST:-0}" -eq 1 ]] && is_interactive; then
    if [[ "$DEST_FOLDER" != "." && "$DEST_FOLDER" != "./" ]]; then
        read_line_prompt NEW_NAME "Rename destination folder (Enter to keep '$DEST_FOLDER'): "
        if [[ -n "$NEW_NAME" ]] && [[ "$NEW_NAME" != "$DEST_FOLDER" ]]; then
            if [[ -e "$NEW_NAME" ]]; then
                abort "Cannot rename: target already exists: $NEW_NAME"
            fi
            mv -- "$DEST_FOLDER" "$NEW_NAME" || abort "Rename failed."
            DEST_FOLDER="$NEW_NAME"
        fi
    fi
fi

# ---------------- Final message ----------------
if [[ "$DEST_FOLDER" == "." || "$DEST_FOLDER" == "./" ]]; then
    echo "Extraction completed."
else
    echo "Extraction completed in folder '$DEST_FOLDER'."
fi
