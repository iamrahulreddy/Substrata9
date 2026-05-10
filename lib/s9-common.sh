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
# Project root (one level up from this lib directory)
S9_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd || echo "")"

#------------------------------------------------------------------------------
# Version
#------------------------------------------------------------------------------
S9_VERSION="1.2.1"

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
    local pad_left=$(printf '─%.0s' $(seq 1 $padding))
    local pad_right=$(printf '─%.0s' $(seq 1 $((width - title_len - 4 - padding))))

    echo ""
    printf "%b%b┌%s %s %s┐%b\n" "${S9_BOLD}" "${S9_BLUE}" "$pad_left" "$title" "$pad_right" "${S9_NC}"
    echo ""
}

s9_subheader() {
    echo ""
    printf "%b%s%b\n" "${S9_BOLD}" "$1" "${S9_NC}"
    printf "%b%s%b\n" "${S9_DIM}" "$(printf '─%.0s' $(seq 1 ${#1}))" "${S9_NC}"
}

s9_separator() {
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

    if [[ -n "$color" ]]; then
        printf "  %b%-${width}s%b %b%s%b\n" "${S9_BOLD}" "$label:" "${S9_NC}" "$color" "$value" "${S9_NC}"
    else
        printf "  %b%-${width}s%b %s\n" "${S9_BOLD}" "$label:" "${S9_NC}" "$value"
    fi
}

s9_status() {
    local type="$1"
    local msg="$2"

    case "$type" in
        ok|success)
            printf "  %b✓%b %s\n" "${S9_GREEN}" "${S9_NC}" "$msg"
            ;;
        warn|warning)
            printf "  %b⚠%b %s\n" "${S9_YELLOW}" "${S9_NC}" "$msg"
            ;;
        error|fail)
            printf "  %b✗%b %s\n" "${S9_RED}" "${S9_NC}" "$msg"
            ;;
        info)
            printf "  %b●%b %s\n" "${S9_CYAN}" "${S9_NC}" "$msg"
            ;;
        *)
            printf "  %b·%b %s\n" "${S9_DIM}" "${S9_NC}" "$msg"
            ;;
    esac
}

s9_bar() {
    local label="$1"
    local current="$2"
    local max="$3"
    local width="${4:-20}"

    local percent=0
    if (( max > 0 )); then
        percent=$(( (current * 100) / max ))
    fi

    local filled=$(( (percent * width) / 100 ))
    local empty=$(( width - filled ))

    local bar=""
    local color="$S9_GREEN"
    if (( percent > 80 )); then
        color="$S9_RED"
    elif (( percent > 60 )); then
        color="$S9_YELLOW"
    fi

    bar+=$(printf '%b' "$color")
    bar+=$(printf '█%.0s' $(seq 1 $filled) 2>/dev/null || true)
    bar+=$(printf '%b' "${S9_DIM}")
    bar+=$(printf '░%.0s' $(seq 1 $empty) 2>/dev/null || true)
    bar+=$(printf '%b' "${S9_NC}")

    printf "  %-12s [%s] %3d%%\n" "$label" "$bar" "$percent"
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

    if [[ "$val" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || [[ "$val" == "true" ]] || [[ "$val" == "false" ]] || [[ "$val" == "null" ]]; then
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
        printf "%.2f GB" "$(echo "scale=2; $bytes/1073741824" | s9_calc)"
    elif (( bytes >= 1048576 )); then
        printf "%.2f MB" "$(echo "scale=2; $bytes/1048576" | s9_calc)"
    elif (( bytes >= 1024 )); then
        printf "%.2f KB" "$(echo "scale=2; $bytes/1024" | s9_calc)"
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

s9_require_root() {
    if [[ $EUID -ne 0 ]]; then
        s9_die "This operation requires root privileges. Try: sudo $0 $*"
    fi
}

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
    return 1
}

s9_check_bc() {
    if s9_find_bc >/dev/null; then
        return 0
    fi

    if [[ -n "${S9_ROOT:-}" && -f "$S9_ROOT/bin/bc" ]]; then
        s9_warn "system 'bc' not found; using local fallback via bash: $S9_ROOT/bin/bc"
        return 0
    fi

    s9_die "bc is required but not installed. Install with: sudo apt install bc"
}

s9_calc() {
    local bc_path
    if bc_path=$(s9_find_bc); then
        "$bc_path" "$@"
        return
    fi

    if [[ -n "${S9_ROOT:-}" && -f "$S9_ROOT/bin/bc" ]]; then
        bash "$S9_ROOT/bin/bc" "$@"
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

s9_get_comm() {
    local name
    name=$(s9_read_proc_file "/proc/$1/comm") || name="unknown"
    s9_sanitize_display "$name"
}

s9_get_state() {
    awk '/^State:/ {print $2}' "/proc/$1/status" 2>/dev/null
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
    awk '/^PPid:/ {print $2}' "/proc/$1/status" 2>/dev/null
}

s9_get_rss() {
    awk '/^VmRSS:/ {print $2}' "/proc/$1/status" 2>/dev/null || echo "0"
}

s9_get_vmsize() {
    awk '/^VmSize:/ {print $2}' "/proc/$1/status" 2>/dev/null || echo "0"
}

s9_get_threads() {
    awk '/^Threads:/ {print $2}' "/proc/$1/status" 2>/dev/null || echo "1"
}

s9_get_uid() {
    awk '/^Uid:/ {print $2}' "/proc/$1/status" 2>/dev/null
}

s9_uid_to_user() {
    getent passwd "$1" 2>/dev/null | cut -d: -f1 || echo "$1"
}

s9_get_fd_count() {
    local pid=$1
    if [[ -r "/proc/$pid/fd" ]]; then
        ls -1 -- "/proc/$pid/fd" 2>/dev/null | wc -l
    else
        echo "0"
    fi
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

s9_check_namespace() {
    local pid=$1

    if [[ -f "/proc/$pid/cgroup" ]]; then
        local cgroup_content
        cgroup_content=$(cat "/proc/$pid/cgroup" 2>/dev/null) || cgroup_content=""

        if [[ "$cgroup_content" == *"docker"* ]]; then
            echo "docker"; return 0
        elif [[ "$cgroup_content" == *"containerd"* ]]; then
            echo "containerd"; return 0
        elif [[ "$cgroup_content" == *"lxc"* ]]; then
            echo "lxc"; return 0
        elif [[ "$cgroup_content" == *"kubepods"* ]] || [[ "$cgroup_content" == *"kubelet"* ]]; then
            echo "k8s"; return 0
        elif [[ "$cgroup_content" == *"podman"* ]]; then
            echo "podman"; return 0
        fi
    fi

    if [[ -r "/proc/$pid/ns/pid" ]] && [[ -r "/proc/1/ns/pid" ]]; then
        local pid_ns init_ns
        pid_ns=$(readlink "/proc/$pid/ns/pid" 2>/dev/null || echo "")
        init_ns=$(readlink "/proc/1/ns/pid" 2>/dev/null || echo "")

        if [[ -n "$pid_ns" ]] && [[ -n "$init_ns" ]] && [[ "$pid_ns" != "$init_ns" ]]; then
            echo "namespace"; return 0
        fi
    fi

    if [[ -r "/proc/$pid/ns/mnt" ]] && [[ -r "/proc/1/ns/mnt" ]]; then
        local mnt_ns init_mnt_ns
        mnt_ns=$(readlink "/proc/$pid/ns/mnt" 2>/dev/null || echo "")
        init_mnt_ns=$(readlink "/proc/1/ns/mnt" 2>/dev/null || echo "")

        if [[ -n "$mnt_ns" ]] && [[ -n "$init_mnt_ns" ]] && [[ "$mnt_ns" != "$init_mnt_ns" ]]; then
            echo "namespace"; return 0
        fi
    fi

    echo ""
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
    echo "$input" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\000-\011\013-\037'
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
    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
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
    pids=$(pgrep -x -- "$input" 2>/dev/null) || pids=$(pgrep -- "$input" 2>/dev/null) || true

    if [[ -z "$pids" ]]; then
        [[ "$quiet" != "true" ]] && s9_warn "No process found matching '$input'"
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
        percent=$(echo "scale=1; ($diff * 100) / $val1" | s9_calc 2>/dev/null || echo "0")
        if [[ "$percent" =~ ^\\. ]]; then
            percent="0$percent"
        elif [[ "$percent" =~ ^-\\. ]]; then
            percent="-0${percent#-}"
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
    awk '/^MemTotal:/ {print $2}' /proc/meminfo
}

s9_get_avail_mem() {
    awk '/^MemAvailable:/ {print $2}' /proc/meminfo
}

s9_get_uptime() {
    awk '{print int($1)}' /proc/uptime
}

s9_get_kernel() {
    uname -r
}