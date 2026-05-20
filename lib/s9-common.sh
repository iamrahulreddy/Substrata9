#!/usr/bin/env bash
#
# s9-common.sh - Shared functions for Substrata9 tools
# Substrata9
#
# Author: Muskula Rahul
#
# Usage: source this file at the start of each tool
#   source "${BASH_SOURCE%/*}/../lib/s9-common.sh" 2>/dev/null || \
#   source "/usr/local/lib/substrata9/s9-common.sh" 2>/dev/null || \
#   { echo "Error: Cannot find s9-common.sh"; exit 1; }
#

# Prevent double-sourcing
[[ -n "${S9_COMMON_LOADED:-}" ]] && return 0
S9_COMMON_LOADED=1
S9_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd || echo "")"
# Project root (one level up from this lib directory)
if [[ -n "$S9_COMMON_DIR" ]]; then
    S9_ROOT="$(cd "$S9_COMMON_DIR/.." >/dev/null 2>&1 && pwd || echo "")"
else
    S9_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd || echo "")"
fi

#------------------------------------------------------------------------------
# Version
#------------------------------------------------------------------------------
# shellcheck disable=SC2034
S9_VERSION="1.3.1"

#------------------------------------------------------------------------------
# Colors (with terminal detection)
#------------------------------------------------------------------------------
s9_should_use_color() {
    [[ -z "${NO_COLOR:-}" ]] || return 1

    # Explicit force flags take priority over terminal checks
    [[ -n "${FORCE_COLOR:-}"    && "${FORCE_COLOR}"    != "0" ]] && return 0
    [[ -n "${CLICOLOR_FORCE:-}" && "${CLICOLOR_FORCE}" != "0" ]] && return 0
    [[ -n "${S9_FORCE_COLOR:-}" && "${S9_FORCE_COLOR}" != "0" ]] && return 0

    # Now check terminal environment
    [[ "${TERM:-}" != "dumb" ]] || return 1
    [[ -t 1 ]] && return 0

    return 1
}

if s9_should_use_color; then
    export S9_RED=$'\033[0;31m'
    export S9_GREEN=$'\033[0;32m'
    export S9_YELLOW=$'\033[1;33m'
    export S9_BLUE=$'\033[0;34m'
    export S9_CYAN=$'\033[0;36m'
    export S9_MAGENTA=$'\033[0;35m'
    export S9_BOLD=$'\033[1m'
    export S9_DIM=$'\033[2m'
    export S9_NC=$'\033[0m'
else
    export S9_RED='' S9_GREEN='' S9_YELLOW='' S9_BLUE=''
    export S9_CYAN='' S9_MAGENTA='' S9_BOLD='' S9_DIM='' S9_NC=''
fi

#------------------------------------------------------------------------------
# Output Functions
#------------------------------------------------------------------------------

s9_die() {
    printf "%bError:%b %s\n" "${S9_RED}" "${S9_NC}" "$1" >&2
    exit "${2:-1}"
}

s9_info() {
    printf "%b►%b %s\n" "${S9_CYAN}" "${S9_NC}" "$1"
}

s9_success() {
    printf "%b✓%b %s\n" "${S9_GREEN}" "${S9_NC}" "$1"
}

s9_warn() {
    printf "%bWarning:%b %s\n" "${S9_YELLOW}" "${S9_NC}" "$1" >&2
}

s9_debug() {
    [[ -n "${S9_DEBUG:-}" ]] && printf "%b[DEBUG] %s%b\n" "${S9_DIM}" "$1" "${S9_NC}" >&2
}

s9_header() {
    local title="$1"
    local width=66
    local title_len=${#title}
    local padding=$(( (width - title_len - 4) / 2 ))
    local pad_left pad_right
    pad_left=$(printf '─%.0s' $(seq 1 $padding))
    pad_right=$(printf '─%.0s' $(seq 1 $((width - title_len - 4 - padding))))

    echo ""
    printf "%b%b┌%s %s %s┐%b\n" "${S9_BOLD}" "${S9_BLUE}" "$pad_left" "$title" "$pad_right" "${S9_NC}"
    echo ""
}

s9_rule() {
    printf "%b────────────────────────────────────────────────────────────────%b\n" "${S9_DIM}" "${S9_NC}"
}

s9_kv() {
    local label="$1"
    local value="$2"
    local width="${3:-18}"
    local color="${4:-}"

    # Guard: ensure width is numeric to prevent printf format string issues
    [[ "$width" =~ ^[0-9]+$ ]] || width=18

    if [[ -n "$color" ]]; then
        printf "  %b%-${width}s%b %b%s%b\n" "${S9_BOLD}" "$label:" "${S9_NC}" "$color" "$value" "${S9_NC}"
    else
        printf "  %b%-${width}s%b %s\n" "${S9_BOLD}" "$label:" "${S9_NC}" "$value"
    fi
}

s9_box_title() {
    local title="$1"
    local subtitle="${2:-}"
    local width=68
    local inner_width=$((width - 2))

    echo ""
    printf "%b╔" "${S9_BOLD}"
    printf '═%.0s' $(seq 1 $width)
    printf "╗%b\n" "${S9_NC}"

    local title_len=${#title}
    local title_pad=$((inner_width - title_len))
    printf "%b║%b  %s%*s%b║%b\n" "${S9_BOLD}" "${S9_CYAN}" "$title" "$title_pad" "" "${S9_BOLD}" "${S9_NC}"

    if [[ -n "$subtitle" ]]; then
        local sub_len=${#subtitle}
        local sub_pad=$((inner_width - sub_len))
        printf "%b║%b  %s%*s%b║%b\n" "${S9_BOLD}" "${S9_DIM}" "$subtitle" "$sub_pad" "" "${S9_BOLD}" "${S9_NC}"
    fi

    printf "%b╚" "${S9_BOLD}"
    printf '═%.0s' $(seq 1 $width)
    printf "╝%b\n" "${S9_NC}"
    echo ""
}

#------------------------------------------------------------------------------
# JSON Helper Functions
#------------------------------------------------------------------------------

s9_sanitize_json() {
    local input="$1"
    input="${input//\\/\\\\}"
    input="${input//\"/\\\"}"
    input="${input//$'\n'/\\n}"
    input="${input//$'\r'/\\r}"
    input="${input//$'\t'/\\t}"
    input="${input//$'\f'/\\f}"
    input="${input//$'\b'/\\b}"
    echo "$input" | tr -d '\000-\007\013\016-\037'
}

s9_json_kv() {
    local key="$1"
    local val="$2"
    local last="${3:-}"
    local indent="${4:-}"
    local sanitized_val

    if [[ "$val" == "true" ]] || [[ "$val" == "false" ]] || [[ "$val" == "null" ]]; then
        sanitized_val="$val"
    elif [[ "$val" =~ ^-?(0|[1-9][0-9]*)(\.[0-9]+)?$ ]]; then
        sanitized_val="$val"
    else
        sanitized_val="\"$(s9_sanitize_json "$val")\""
    fi

    if [[ "$last" == "last" ]]; then
        printf "%s  \"%s\": %s\n" "$indent" "$key" "$sanitized_val"
    else
        printf "%s  \"%s\": %s,\n" "$indent" "$key" "$sanitized_val"
    fi
}

s9_auto_export_path() {
    local purpose="$1"
    local safe_purpose timestamp export_tz base path suffix

    safe_purpose=$(printf "%s" "$purpose" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-][^a-z0-9_-]*/-/g; s/^-//; s/-$//')
    [[ -n "$safe_purpose" ]] || safe_purpose="report"

    export_tz="${S9_EXPORT_TZ:-}"
    if [[ -n "$export_tz" ]]; then
        timestamp=$(TZ="$export_tz" date '+%Y-%m-%d_%H-%M-%S_%Z' 2>/dev/null) || {
            s9_warn "Invalid S9_EXPORT_TZ '$export_tz'; using system timezone"
            timestamp=$(date '+%Y-%m-%d_%H-%M-%S_%Z')
        }
    else
        timestamp=$(date '+%Y-%m-%d_%H-%M-%S_%Z')
    fi
    timestamp=$(printf "%s" "$timestamp" | sed 's/[^a-zA-Z0-9_-]/-/g')

    base="s9-${safe_purpose}_${timestamp}"
    path="${base}.json"
    suffix=1

    while [[ -e "$path" ]]; do
        path="${base}_${suffix}.json"
        suffix=$((suffix + 1))
    done

    printf "%s\n" "$path"
}

s9_export_json_output() {
    local export_file="$1"
    shift

    [[ -n "$export_file" ]] || s9_die "Export file path is required"
    (( $# > 0 )) || s9_die "Export command is required"

    local capture_file
    capture_file=$(mktemp) || s9_die "Cannot create temp file"

    if "$@" | tee "$capture_file"; then
        cp "$capture_file" "$export_file" || {
            rm -f "$capture_file"
            s9_die "Cannot write export file: $export_file"
        }
        rm -f "$capture_file"
        s9_info "JSON exported to $export_file" >&2
    else
        rm -f "$capture_file"
        s9_die "Failed to generate JSON export"
    fi
}

#------------------------------------------------------------------------------
# Formatting Functions
#------------------------------------------------------------------------------

s9_human_bytes() {
    local bytes=${1:-0}

    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        echo "0 B"
        return
    fi

    if (( bytes >= 1073741824 )); then
        local int_val=$(( bytes / 1073741824 ))
        local dec_val=$(( (bytes * 100 / 1073741824) % 100 ))
        printf "%d.%02d GB" "$int_val" "$dec_val"
    elif (( bytes >= 1048576 )); then
        local int_val=$(( bytes / 1048576 ))
        local dec_val=$(( (bytes * 100 / 1048576) % 100 ))
        printf "%d.%02d MB" "$int_val" "$dec_val"
    elif (( bytes >= 1024 )); then
        local int_val=$(( bytes / 1024 ))
        local dec_val=$(( (bytes * 100 / 1024) % 100 ))
        printf "%d.%02d KB" "$int_val" "$dec_val"
    else
        printf "%d B" "$bytes"
    fi
}

s9_human_kb() {
    local kb=${1:-0}
    [[ "$kb" =~ ^[0-9]+$ ]] || kb=0
    s9_human_bytes $((kb * 1024))
}

s9_human_duration() {
    local seconds=${1:-0}

    (( seconds < 0 )) && seconds=0

    local days=$((seconds / 86400))
    local hours=$(( (seconds % 86400) / 3600 ))
    local mins=$(( (seconds % 3600) / 60 ))
    local secs=$((seconds % 60))

    if (( days > 0 )); then
        printf "%dd %dh %dm" "$days" "$hours" "$mins"
    elif (( hours > 0 )); then
        printf "%dh %dm %ds" "$hours" "$mins" "$secs"
    elif (( mins > 0 )); then
        printf "%dm %ds" "$mins" "$secs"
    else
        printf "%ds" "$secs"
    fi
}

#------------------------------------------------------------------------------
# Validation Functions
#------------------------------------------------------------------------------

s9_check_bash_version() {
    if (( BASH_VERSINFO[0] < 4 )); then
        s9_die "This script requires bash 4.0 or later (found $BASH_VERSION)"
    fi
}

s9_check_linux() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        s9_die "This tool only works on Linux (detected: $(uname -s))"
    fi
}

s9_check_proc() {
    if [[ ! -d "/proc" ]]; then
        s9_die "/proc filesystem not found. Is this a Linux system?"
    fi
}

s9_find_bc() {
    local bc_path
    bc_path=$(command -v bc 2>/dev/null || true)
    if [[ -n "$bc_path" && -x "$bc_path" ]]; then
        printf "%s\n" "$bc_path"
        return 0
    fi

    local fallback
    for fallback in "${S9_ROOT:-}/bin/bc" "${S9_ROOT:-}/bc" "${S9_COMMON_DIR:-}/bin/bc" "${S9_COMMON_DIR:-}/bc"; do
        if [[ -f "$fallback" ]]; then
            printf "%s\n" "$fallback"
            return 0
        fi
    done

    return 1
}

s9_check_bc() {
    local bc_path
    if bc_path=$(s9_find_bc); then
        if [[ "${bc_path##*/}" == "bc" && "$bc_path" == "${S9_ROOT:-}"* && "$bc_path" != "$(command -v bc 2>/dev/null || true)" ]]; then
            # s9_warn "system 'bc' not found; using local fallback via bash: $bc_path"
            :
        fi
        return 0
    fi

    s9_die "bc is required but not installed. Install with: sudo apt install bc"
}

s9_calc() {
    local bc_path
    if bc_path=$(s9_find_bc); then
        if [[ "$bc_path" == "${S9_ROOT:-}/bin/bc" || "$bc_path" == "${S9_ROOT:-}/bc" || "$bc_path" == "${S9_COMMON_DIR:-}/bin/bc" || "$bc_path" == "${S9_COMMON_DIR:-}/bc" ]]; then
            bash "$bc_path" "$@"
        else
            "$bc_path" "$@"
        fi
        return
    fi

    s9_die "bc is required but not installed. Install with: sudo apt install bc"
}

s9_init() {
    s9_check_bash_version
    s9_check_linux
    s9_check_proc
    s9_check_bc
}

#------------------------------------------------------------------------------
# Process Functions
#------------------------------------------------------------------------------

s9_process_exists() {
    [[ -d "/proc/$1" ]]
}

declare -g -A S9_UID_CACHE=()

_s9_get_status_field() {
    local pid="$1"
    local target_key="$2"
    local fallback="${3:-}"
    local key val

    [[ -r "/proc/$pid/status" ]] || { echo "$fallback"; return 1; }

    while IFS=: read -r key val; do
        key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
        if [[ "$key" == "$target_key" ]]; then
            val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
            echo "${val%%[[:space:]]*}"
            return 0
        fi
    done < "/proc/$pid/status"

    echo "$fallback"
    return 1
}

s9_get_comm() {
    local name
    if read -r -t 2 name < "/proc/$1/comm" 2>/dev/null; then
        s9_sanitize_display "$name"
    else
        echo "unknown"
    fi
}

s9_get_state() {
    _s9_get_status_field "$1" "State" ""
}

s9_get_state_desc() {
    local state
    state=$(s9_get_state "$1")
    case "$state" in
        R) echo "R (running)" ;;
        S) echo "S (sleeping)" ;;
        D) echo "D (disk sleep)" ;;
        Z) echo "Z (zombie)" ;;
        T) echo "T (stopped)" ;;
        t) echo "t (tracing)" ;;
        X) echo "X (dead)" ;;
        *) echo "$state" ;;
    esac
}

s9_get_ppid() {
    _s9_get_status_field "$1" "PPid" ""
}

s9_get_rss() {
    _s9_get_status_field "$1" "VmRSS" "0"
}

s9_get_threads() {
    _s9_get_status_field "$1" "Threads" "1"
}

s9_uid_to_user() {
    local uid="$1"
    [[ -n "$uid" ]] || return 1

    if [[ -n "${S9_UID_CACHE[$uid]:-}" ]]; then
        echo "${S9_UID_CACHE[$uid]}"
        return 0
    fi

    local user
    if command -v getent >/dev/null 2>&1; then
        user=$(getent passwd "$uid" 2>/dev/null | cut -d: -f1) || user="$uid"
    else
        user="$uid"
    fi
    if [[ "$user" == "$uid" ]] && command -v id >/dev/null 2>&1; then
        user=$(id -nu "$uid" 2>/dev/null || printf "%s" "$uid")
    fi
    [[ -n "$user" ]] || user="$uid"
    S9_UID_CACHE[$uid]="$user"
    echo "$user"
}

s9_get_fd_count() {
    local pid=$1
    if [[ -r "/proc/$pid/fd" ]]; then
        local fds=(/proc/"$pid"/fd/*)
        if [[ "${fds[0]:-}" == "/proc/$pid/fd/*" ]] && [[ ! -e "${fds[0]:-}" ]]; then
            echo "0"
        else
            echo "${#fds[@]}"
        fi
    else
        echo "0"
    fi
}

s9_fd_type() {
    local target="$1"

    case "$target" in
        socket:*) echo "socket" ;;
        pipe:*) echo "pipe" ;;
        /dev/*) echo "device" ;;
        anon_inode:*) echo "anon" ;;
        *) echo "file" ;;
    esac
}

s9_nvidia_smi_cmd() {
    local smi="${S9_NVIDIA_SMI:-nvidia-smi}"
    command -v "$smi" >/dev/null 2>&1 || return 1
    printf "%s\n" "$smi"
}

s9_gpu_available() {
    local smi gpu_rows
    smi=$(s9_nvidia_smi_cmd) || return 1
    gpu_rows=$("$smi" --query-gpu=index --format=csv,noheader,nounits 2>/dev/null) || return 1
    [[ -n "$(s9_trim "$gpu_rows")" ]]
}

s9_trim() {
    local input="$1"
    input="${input#"${input%%[![:space:]]*}"}"
    input="${input%"${input##*[![:space:]]}"}"
    printf "%s\n" "$input"
}

s9_gpu_process_rows() {
    local smi
    smi=$(s9_nvidia_smi_cmd) || return 1

    local gpu_rows app_rows
    gpu_rows=$("$smi" --query-gpu=index,uuid,name --format=csv,noheader,nounits 2>/dev/null) || return 1
    [[ -n "$(s9_trim "$gpu_rows")" ]] || return 1
    app_rows=$("$smi" --query-compute-apps=pid,process_name,gpu_uuid,used_memory --format=csv,noheader,nounits 2>/dev/null) || return 1
    [[ -n "$app_rows" ]] || return 0

    local -A gpu_index=()
    local -A gpu_name=()
    local idx uuid gpu_name_raw i

    local gpu_line
    local -a gpu_cols
    while IFS= read -r gpu_line; do
        IFS=',' read -ra gpu_cols <<< "$gpu_line"
        (( ${#gpu_cols[@]} >= 3 )) || continue
        idx="${gpu_cols[0]}"
        uuid="${gpu_cols[1]}"
        gpu_name_raw=""
        for (( i=2; i<${#gpu_cols[@]}; i++ )); do
            [[ -n "$gpu_name_raw" ]] && gpu_name_raw+=","
            gpu_name_raw+="${gpu_cols[$i]}"
        done

        idx=$(s9_trim "${idx:-}")
        uuid=$(s9_trim "${uuid:-}")
        gpu_name_raw=$(s9_trim "${gpu_name_raw:-}")
        gpu_name_raw="${gpu_name_raw//|/ }"
        [[ -n "$uuid" ]] || continue
        gpu_index[$uuid]="$idx"
        gpu_name[$uuid]="$gpu_name_raw"
    done <<< "$gpu_rows"

    local pid proc_name gpu_uuid used_memory
    local app_line col_count
    local -a app_cols
    while IFS= read -r app_line; do
        IFS=',' read -ra app_cols <<< "$app_line"
        col_count=${#app_cols[@]}
        (( col_count >= 4 )) || continue

        pid="${app_cols[0]}"
        gpu_uuid="${app_cols[$((col_count - 2))]}"
        used_memory="${app_cols[$((col_count - 1))]}"
        proc_name=""
        for (( i=1; i<col_count-2; i++ )); do
            [[ -n "$proc_name" ]] && proc_name+=","
            proc_name+="${app_cols[$i]}"
        done

        pid=$(s9_trim "${pid:-}")
        proc_name=$(s9_trim "${proc_name:-}")
        gpu_uuid=$(s9_trim "${gpu_uuid:-}")
        used_memory=$(s9_trim "${used_memory:-}")
        proc_name="${proc_name//|/ }"

        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        [[ -n "$gpu_uuid" ]] || gpu_uuid="unknown"
        [[ "$used_memory" =~ ^[0-9]+$ ]] || used_memory=0

        printf "%s|%s|%s|%s|%s|compute\n" \
            "$pid" \
            "$(s9_sanitize_display "$proc_name")" \
            "${gpu_index[$gpu_uuid]:-$gpu_uuid}" \
            "$(s9_sanitize_display "${gpu_name[$gpu_uuid]:-$gpu_uuid}")" \
            "$used_memory"
    done <<< "$app_rows"
}

s9_gpu_process_for_pid() {
    local pid="$1"
    s9_gpu_process_rows 2>/dev/null | awk -F'|' -v target="$pid" '
        $1 == target {
            print
            found = 1
        }
        END {
            exit(found ? 0 : 1)
        }
    '
}

s9_gpu_pid_scope() {
    local pid="$1"
    local reported_name="${2:-}"
    local reported_base="${reported_name##*/}"
    local comm cmdline

    [[ "$pid" =~ ^[0-9]+$ ]] || { echo "unknown"; return 0; }
    if [[ ! -d "/proc/$pid" ]]; then
        echo "host"
        return 0
    fi

    comm=$(s9_get_comm "$pid" 2>/dev/null || echo "")
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || echo "")

    if [[ "$pid" == "1" ]] &&
       { [[ "$comm" == "dumb-init" || "$comm" == "tini" || "$comm" == "init" ]] ||
         [[ "$cmdline" == *"dumb-init"* || "$cmdline" == *"tini"* ]]; }; then
        echo "container_proxy"
    elif [[ -n "$reported_base" && -n "$comm" && "$reported_base" != "$comm"* && "$comm" != "$reported_base"* ]]; then
        echo "name_mismatch"
    else
        echo "visible"
    fi
}

s9_gpu_process_count() {
    local count
    count=$(s9_gpu_process_rows 2>/dev/null | awk 'NF {count++} END {print count + 0}') || count=0
    printf "%s\n" "$count"
}

s9_gpu_memory_used_mb() {
    local smi
    smi=$(s9_nvidia_smi_cmd) || { echo 0; return 0; }
    local used
    used=$("$smi" --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null |
        awk '
            {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
                if ($1 ~ /^[0-9]+$/) total += $1
            }
            END { print total + 0 }
        ')
    used=$(s9_trim "${used:-0}")
    printf "%s\n" "$used"
}

s9_get_stat_field() {
    local pid="$1"
    local field_number="$2"
    local stat_content rest idx

    stat_content=$(s9_read_proc_file "/proc/$pid/stat") || return 1
    rest="${stat_content##*) }"
    idx=$((field_number - 3))

    (( idx >= 0 )) || return 1

    local -a fields
    read -ra fields <<< "$rest"
    (( idx < ${#fields[@]} )) || return 1

    echo "${fields[$idx]}"
}

s9_validate_number() {
    local value="$1"
    local name="${2:-value}"
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        s9_die "$name must be a positive integer"
    fi
}

s9_sanitize_filename() {
    local input="$1"
    echo "${input//[^a-zA-Z0-9_-]/}"
}

s9_sanitize_display() {
    local input="$1"
    # Fast path: check if the string contains any control characters or ESC (ASCII 1-31 or 127)
    # If not, return the string immediately to avoid expensive sed/tr fork pipelines
    if [[ "$input" != *[$'\001'-$'\037'$'\177']* ]]; then
        echo "$input"
        return
    fi

    # Slow path: only run when control characters/ANSI sequences are actually present
    local esc=$'\033'
    echo "$input" | sed "s/${esc}\[[0-9;]*[a-zA-Z]//g" | tr -d '\000-\011\013-\037'
}

s9_read_proc_file() {
    local file="$1"
    local timeout_sec="${2:-2}"

    if command -v timeout &>/dev/null; then
        timeout "$timeout_sec" cat "$file" 2>/dev/null
    else
        cat "$file" 2>/dev/null
    fi
}

s9_validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        s9_die "Invalid port number: $port (must be 1-65535)"
    fi

    local port_num=$((10#$port))
    if (( port_num < 1 || port_num > 65535 )); then
        s9_die "Invalid port number: $port (must be 1-65535)"
    fi
}

s9_validate_safe_dir() {
    local dir="$1"
    local resolved

    if command -v realpath &>/dev/null; then
        resolved=$(realpath -m "$dir" 2>/dev/null) || resolved=""
    else
        resolved=$(cd "$dir" 2>/dev/null && pwd -P) || resolved=""
    fi

    [[ -z "$resolved" ]] && resolved="$dir"

    # Fallback path traversal validation: reject paths containing '..' to prevent directory traversal
    if [[ "$resolved" == *"/.."* || "$resolved" == "../"* || "$resolved" == ".." ]]; then
        s9_warn "Path traversal attempt detected in snapshot directory: $dir"
        return 1
    fi

    local home_dir="${HOME:-}"
    local under_home=false
    local under_tmp=false

    if [[ -n "$home_dir" ]] && { [[ "$resolved" == "$home_dir" ]] || [[ "$resolved" == "$home_dir/"* ]]; }; then
        under_home=true
    fi
    if [[ "$resolved" == "/tmp" ]] || [[ "$resolved" == "/tmp/"* ]]; then
        under_tmp=true
    fi

    if ! $under_home && ! $under_tmp; then
        s9_warn "Directory '$dir' is outside safe locations (HOME or /tmp)"
        return 1
    fi

    if [[ -d "$resolved" ]] && [[ ! -w "$resolved" ]]; then
        s9_warn "Directory '$resolved' is not writable"
        return 1
    fi

    return 0
}

s9_resolve_pid() {
    local input="$1"
    local quiet="${2:-false}"

    local sanitized="${input//[^a-zA-Z0-9_.-]/}"
    if [[ "$sanitized" != "$input" ]]; then
        [[ "$quiet" != "true" ]] && s9_warn "Invalid characters in process identifier"
        return 1
    fi

    if [[ "$input" =~ ^[0-9]+$ ]]; then
        if s9_process_exists "$input"; then
            echo "$input"
            return 0
        else
            [[ "$quiet" != "true" ]] && s9_warn "Process $input does not exist"
            return 1
        fi
    fi

    local pids
    pids=$(pgrep -x -- "$input" 2>/dev/null) || true

    if [[ -z "$pids" ]]; then
        [[ "$quiet" != "true" ]] && s9_warn "No process found with exact name '$input'"
        return 1
    fi

    local count
    count=$(echo "$pids" | wc -l)

    if (( count > 1 )); then
        if [[ "$quiet" != "true" ]]; then
            s9_warn "Multiple processes found matching '$input':"
            echo "$pids" | while read -r p; do
                echo "  $p ($(s9_get_comm "$p"))" >&2
            done
            s9_warn "Please specify exact PID"
        fi
        return 1
    fi

    echo "$pids"
}

#------------------------------------------------------------------------------
# Comparison Display Functions
#------------------------------------------------------------------------------

s9_diff_indicator() {
    local diff=$1
    local reverse="${2:-}"
    local arrow color sign

    if (( diff > 0 )); then
        arrow="↑"; sign="+"
        color=$( [[ -n "$reverse" ]] && echo "$S9_RED" || echo "$S9_GREEN" )
    elif (( diff < 0 )); then
        arrow="↓"; sign=""
        color=$( [[ -n "$reverse" ]] && echo "$S9_GREEN" || echo "$S9_RED" )
    else
        arrow="→"; sign=""; color="$S9_DIM"
    fi

    printf "%b%s %s%d%b" "$color" "$arrow" "$sign" "$diff" "$S9_NC"
}

s9_compare_row() {
    local label="$1"
    local val1="${2:-0}"
    local val2="${3:-0}"
    local unit="${4:-}"
    local human_func="${5:-}"

    [[ "$val1" =~ ^-?[0-9]+$ ]] || val1=0
    [[ "$val2" =~ ^-?[0-9]+$ ]] || val2=0

    local diff=$((val2 - val1))
    local abs_diff=${diff#-}
    local percent="—"

    if (( val1 > 0 )); then
        local int_val=$(( (abs_diff * 100) / val1 ))
        local dec_val=$(( ((abs_diff * 1000) / val1) % 10 ))
        percent="${int_val}.${dec_val}"
        if (( diff < 0 )); then
            percent="-${percent}"
        fi
        percent="${percent}%"
    elif (( val2 > 0 )); then
        percent="new"
    fi

    local display1="$val1" display2="$val2" diff_display
    if [[ "$human_func" == "kb" ]]; then
        display1=$(s9_human_kb "$val1")
        display2=$(s9_human_kb "$val2")
        diff_display=$(s9_human_kb "$abs_diff")
    elif [[ "$human_func" == "bytes" ]]; then
        display1=$(s9_human_bytes "$val1")
        display2=$(s9_human_bytes "$val2")
        diff_display=$(s9_human_bytes "$abs_diff")
    else
        display1="$val1 $unit"
        display2="$val2 $unit"
        diff_display="$abs_diff $unit"
    fi

    local change_color="$S9_DIM"
    local arrow="→"
    local sign=""
    if (( diff > 0 )); then
        change_color="$S9_RED"; arrow="↑"; sign="+"
    elif (( diff < 0 )); then
        change_color="$S9_GREEN"; arrow="↓"; sign="-"
    fi

    printf "  ${S9_BOLD}%-16s${S9_NC} %-14s  %-14s  %b%s %s%-10s (%s)%b\n" \
        "$label" "$display1" "$display2" "$change_color" "$arrow" "$sign" "$diff_display" "$percent" "$S9_NC"
}

s9_compare_header() {
    local col1="${1:-Before}"
    local col2="${2:-After}"
    printf "  ${S9_DIM}%-16s %-14s  %-14s  %-24s${S9_NC}\n" "Metric" "$col1" "$col2" "Change"
    printf "  ${S9_DIM}──────────────── ──────────────  ──────────────  ────────────────────────${S9_NC}\n"
}

#------------------------------------------------------------------------------
# Signal Handling
#------------------------------------------------------------------------------

declare -gA S9_SIGNALS=(
    [1]="SIGHUP"  [2]="SIGINT"    [3]="SIGQUIT"  [4]="SIGILL"
    [5]="SIGTRAP" [6]="SIGABRT"   [7]="SIGBUS"   [8]="SIGFPE"
    [9]="SIGKILL" [10]="SIGUSR1"  [11]="SIGSEGV" [12]="SIGUSR2"
    [13]="SIGPIPE" [14]="SIGALRM" [15]="SIGTERM" [16]="SIGSTKFLT"
    [17]="SIGCHLD" [18]="SIGCONT" [19]="SIGSTOP" [20]="SIGTSTP"
    [21]="SIGTTIN" [22]="SIGTTOU" [23]="SIGURG"  [24]="SIGXCPU"
    [25]="SIGXFSZ" [26]="SIGVTALRM" [27]="SIGPROF" [28]="SIGWINCH"
    [29]="SIGIO"  [30]="SIGPWR"   [31]="SIGSYS"
)

s9_decode_signals() {
    local mask=${1:-0}
    local result=""

    if [[ -z "$mask" ]] || [[ "$mask" =~ ^0+$ ]]; then
        echo "none"
        return
    fi

    local num
    mask="${mask#0x}"
    mask="${mask#0X}"
    # Signal masks from /proc are 16 hex chars (64-bit). We only decode signals
    # 1-31 (standard POSIX), which all fit in the low 32 bits (8 hex chars).
    # Real-time signals (32-64) in the upper bits are intentionally not decoded
    # since the S9_SIGNALS table only covers 1-31.
    [[ ${#mask} -gt 8 ]] && mask="${mask: -8}"
    num=$((16#$mask)) 2>/dev/null || num=0

    for i in {1..31}; do
        if (( (num >> (i-1)) & 1 )); then
            result+="${S9_SIGNALS[$i]:-SIG$i} "
        fi
    done

    echo "${result:-none}"
}

#------------------------------------------------------------------------------
# System Information
#------------------------------------------------------------------------------

s9_get_total_mem() {
    # Check cgroup total memory limit
    local limit=0
    local cg_path
    for cg_path in "/sys/fs/cgroup/memory.max" "/sys/fs/cgroup/memory/memory.limit_in_bytes"; do
        if [[ -r "$cg_path" ]]; then
            local val
            val=$(head -n 1 "$cg_path" 2>/dev/null | tr -d '[:space:]')
            if [[ "$val" =~ ^[0-9]+$ ]] && (( val > 0 && val < 9000000000000000000 )); then
                limit=$(( val / 1024 ))  # convert to KB
                break
            fi
        fi
    done

    local host_mem=0
    local key val
    while read -r key val _; do
        if [[ "$key" == "MemTotal:" ]]; then
            host_mem="$val"
            break
        fi
    done < /proc/meminfo

    # If cgroup limit is active and less than host memory, return cgroup limit
    if (( limit > 0 && limit < host_mem )); then
        echo "$limit"
    else
        echo "${host_mem:-0}"
    fi
}

s9_get_avail_mem() {
    local limit=0
    local usage=0
    local cg_path
    
    # 1. Resolve cgroup limit
    for cg_path in "/sys/fs/cgroup/memory.max" "/sys/fs/cgroup/memory/memory.limit_in_bytes"; do
        if [[ -r "$cg_path" ]]; then
            local val
            val=$(head -n 1 "$cg_path" 2>/dev/null | tr -d '[:space:]')
            if [[ "$val" =~ ^[0-9]+$ ]] && (( val > 0 && val < 9000000000000000000 )); then
                limit="$val"
                break
            fi
        fi
    done
    
    # 2. Resolve cgroup current usage
    if (( limit > 0 )); then
        for cg_path in "/sys/fs/cgroup/memory.current" "/sys/fs/cgroup/memory/memory.usage_in_bytes"; do
            if [[ -r "$cg_path" ]]; then
                local val
                val=$(head -n 1 "$cg_path" 2>/dev/null | tr -d '[:space:]')
                if [[ "$val" =~ ^[0-9]+$ ]]; then
                    usage="$val"
                    break
                fi
            fi
        done
    fi

    local cgroup_avail=0
    if (( limit > 0 && usage >= 0 && limit > usage )); then
        cgroup_avail=$(( (limit - usage) / 1024 ))  # convert to KB
    fi

    # 3. Resolve host MemAvailable
    local host_avail=0
    local key val
    while read -r key val _; do
        if [[ "$key" == "MemAvailable:" ]]; then
            host_avail="$val"
            break
        fi
    done < /proc/meminfo

    # 4. If cgroup available memory is active and less than host available memory, return cgroup available memory
    if (( cgroup_avail > 0 && cgroup_avail < host_avail )); then
        echo "$cgroup_avail"
    else
        echo "${host_avail:-0}"
    fi
}

s9_get_uptime() {
    local uptime_val
    if read -r uptime_val _ < /proc/uptime; then
        echo "${uptime_val%%.*}"
    else
        echo "0"
    fi
}

s9_get_kernel() {
    uname -r
}
