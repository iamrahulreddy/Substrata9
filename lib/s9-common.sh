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
S9_VERSION="1.1.0"

#------------------------------------------------------------------------------
# Colors (with terminal detection)
#------------------------------------------------------------------------------
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]] && [[ -z "${NO_COLOR:-}" ]]; then
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
    # No colors for non-interactive or dumb terminals
    export S9_RED='' S9_GREEN='' S9_YELLOW='' S9_BLUE=''
    export S9_CYAN='' S9_MAGENTA='' S9_BOLD='' S9_DIM='' S9_NC=''
fi

#------------------------------------------------------------------------------
# Output Functions
#------------------------------------------------------------------------------

# Print error and exit
s9_die() {
    printf "%bError:%b %s\n" "${S9_RED}" "${S9_NC}" "$1" >&2
    exit "${2:-1}"
}

# Print info message
s9_info() {
    printf "%b►%b %s\n" "${S9_CYAN}" "${S9_NC}" "$1"
}

# Print success message
s9_success() {
    printf "%b✓%b %s\n" "${S9_GREEN}" "${S9_NC}" "$1"
}

# Print warning
s9_warn() {
    printf "%bWarning:%b %s\n" "${S9_YELLOW}" "${S9_NC}" "$1" >&2
}

# Print debug (only if S9_DEBUG is set)
s9_debug() {
    [[ -n "${S9_DEBUG:-}" ]] && printf "%b[DEBUG] %s%b\n" "${S9_DIM}" "$1" "${S9_NC}" >&2
}

# Print section header with visual separation
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

# Print sub-header with underline
s9_subheader() {
    echo ""
    printf "%b%s%b\n" "${S9_BOLD}" "$1" "${S9_NC}"
    printf "%b%s%b\n" "${S9_DIM}" "$(printf '─%.0s' $(seq 1 ${#1}))" "${S9_NC}"
}

# Print section separator (blank line)
s9_separator() {
    echo ""
}

# Print a horizontal rule
s9_rule() {
    printf "%b────────────────────────────────────────────────────────────────%b\n" "${S9_DIM}" "${S9_NC}"
}

# Print a key-value pair with aligned formatting
# Usage: s9_kv "Label" "Value" [width] [color]
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

# Print a status indicator
# Usage: s9_status "ok|warn|error|info" "message"
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

# Print a progress/metric bar
# Usage: s9_bar "label" current max [width]
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

# Print boxed title (for main headers)
s9_box_title() {
    local title="$1"
    local subtitle="${2:-}"
    local width=68
    local inner_width=$((width - 2))  # Account for left padding "  "
    
    echo ""
    printf "%b╔" "${S9_BOLD}"
    printf '═%.0s' $(seq 1 $width)
    printf "╗%b\n" "${S9_NC}"
    
    # Calculate padding needed for title
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

# Sanitize string for JSON (escape quotes and backslashes)
s9_sanitize_json() {
    local input="$1"
    # Escape backslash first, then double quotes, then newlines, tabs, etc.
    # Using python or jq would be safer but we want zero dependencies
    # This is a basic implementation for common cases
    input="${input//\\/\\\\}"
    input="${input//\"/\\\"}"
    input="${input//$'\n'/\\n}"
    input="${input//$'\r'/\\r}"
    input="${input//$'\t'/\\t}"
    echo "$input"
}

# Output JSON key-value pair
# Usage: s9_json_kv "key" "value" [last] [indent]
# If 'last' is set to "last", no trailing comma is added
# 'indent' is an optional prefix for additional indentation (e.g., "    " for nested objects)
s9_json_kv() {
    local key="$1"
    local val="$2"
    local last="${3:-}"
    local indent="${4:-}"
    local sanitized_val
    
    # Check if value looks like a number or boolean or null, otherwise quote it
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

# Convert bytes to human readable
s9_human_bytes() {
    local bytes=${1:-0}
    
    # Validate input is numeric
    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        echo "0 B"
        return
    fi
    
    if (( bytes >= 1073741824 )); then
        printf "%.2f GB" "$(echo "scale=2; $bytes/1073741824" | bc)"
    elif (( bytes >= 1048576 )); then
        printf "%.2f MB" "$(echo "scale=2; $bytes/1048576" | bc)"
    elif (( bytes >= 1024 )); then
        printf "%.2f KB" "$(echo "scale=2; $bytes/1024" | bc)"
    else
        printf "%d B" "$bytes"
    fi
}

# Convert kB to human readable
s9_human_kb() {
    local kb=${1:-0}
    [[ "$kb" =~ ^[0-9]+$ ]] || kb=0
    s9_human_bytes $((kb * 1024))
}

# Format duration in seconds to human readable
s9_human_duration() {
    local seconds=${1:-0}
    
    # Handle negative values (can occur with clock adjustments)
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

# Check if running as root
s9_require_root() {
    if [[ $EUID -ne 0 ]]; then
        s9_die "This operation requires root privileges. Try: sudo $0 $*"
    fi
}

# Check bash version (require 4.0+)
s9_check_bash_version() {
    if (( BASH_VERSINFO[0] < 4 )); then
        s9_die "This script requires bash 4.0 or later (found $BASH_VERSION)"
    fi
}

# Check if on Linux
s9_check_linux() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        s9_die "This tool only works on Linux (detected: $(uname -s))"
    fi
}

# Check if /proc exists
s9_check_proc() {
    if [[ ! -d "/proc" ]]; then
        s9_die "/proc filesystem not found. Is this a Linux system?"
    fi
}

# Check if bc is available
s9_check_bc() {
    if command -v bc &>/dev/null; then
        return 0
    fi

    # If a repo-local fallback exists (./bin/bc), prefer that by prepending to PATH
    if [[ -n "$S9_ROOT" && -x "$S9_ROOT/bin/bc" ]]; then
        export PATH="$S9_ROOT/bin:$PATH"
        s9_warn "system 'bc' not found; using local fallback: $S9_ROOT/bin/bc"
        return 0
    fi

    s9_die "bc is required but not installed. Install with: sudo apt install bc"
}

# Run all standard checks
s9_init() {
    s9_check_bash_version
    s9_check_linux
    s9_check_proc
    s9_check_bc
}

#------------------------------------------------------------------------------
# Process Functions
#------------------------------------------------------------------------------

# Check if process exists
s9_process_exists() {
    [[ -d "/proc/$1" ]]
}

# Get process name (comm) - sanitized for safe display
s9_get_comm() {
    local name
    name=$(s9_read_proc_file "/proc/$1/comm") || name="unknown"
    s9_sanitize_display "$name"
}

# Get process state
s9_get_state() {
    awk '/^State:/ {print $2}' "/proc/$1/status" 2>/dev/null
}

# Get process state with description
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

# Get parent PID
s9_get_ppid() {
    awk '/^PPid:/ {print $2}' "/proc/$1/status" 2>/dev/null
}

# Get process RSS in kB
s9_get_rss() {
    awk '/^VmRSS:/ {print $2}' "/proc/$1/status" 2>/dev/null || echo "0"
}

# Get process VmSize in kB
s9_get_vmsize() {
    awk '/^VmSize:/ {print $2}' "/proc/$1/status" 2>/dev/null || echo "0"
}

# Get thread count
s9_get_threads() {
    awk '/^Threads:/ {print $2}' "/proc/$1/status" 2>/dev/null || echo "1"
}

# Get UID of process
s9_get_uid() {
    awk '/^Uid:/ {print $2}' "/proc/$1/status" 2>/dev/null
}

# Get username from UID
s9_uid_to_user() {
    getent passwd "$1" 2>/dev/null | cut -d: -f1 || echo "$1"
}

# Get FD count for process
s9_get_fd_count() {
    local pid=$1
    if [[ -r "/proc/$pid/fd" ]]; then
        ls -1 -- "/proc/$pid/fd" 2>/dev/null | wc -l
    else
        echo "0"
    fi
}

# Check if process is in a container/namespace
s9_check_namespace() {
    local pid=$1
    local init_pid=1
    
    # If /proc/1/cgroup and /proc/$pid/cgroup differ significantly, likely containerized
    # This is a heuristic
    
    if [[ -f "/proc/$pid/cgroup" ]]; then
        if grep -q "docker" "/proc/$pid/cgroup" 2>/dev/null; then
            echo "docker"
            return 0
        elif grep -q "lxc" "/proc/$pid/cgroup" 2>/dev/null; then
            echo "lxc"
            return 0
        elif grep -q "kubepods" "/proc/$pid/cgroup" 2>/dev/null; then
            echo "k8s"
            return 0
        fi
    fi
    
    # Check namespace inodes if possible (requires root usually)
    if [[ -r "/proc/$pid/ns/mnt" ]] && [[ -r "/proc/1/ns/mnt" ]]; then
        local pid_ns init_ns
        pid_ns=$(readlink "/proc/$pid/ns/mnt" 2>/dev/null || echo "")
        init_ns=$(readlink "/proc/1/ns/mnt" 2>/dev/null || echo "")
        
        if [[ "$pid_ns" != "$init_ns" ]]; then
            echo "namespace"
            return 0
        fi
    fi
    
    echo ""
}

# Validate numeric input
s9_validate_number() {
    local value="$1"
    local name="${2:-value}"
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        s9_die "$name must be a positive integer"
    fi
}

# Sanitize string for use in filenames
s9_sanitize_filename() {
    local input="$1"
    # Only allow alphanumeric, dash, underscore
    echo "${input//[^a-zA-Z0-9_-]/}"
}

# Sanitize string for safe terminal display (strip ANSI escape sequences)
s9_sanitize_display() {
    local input="$1"
    # Remove ANSI escape sequences and control characters
    echo "$input" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\000-\011\013-\037'
}

# Read /proc file with timeout to handle D-state processes
# Usage: s9_read_proc_file <file_path> [timeout_seconds]
s9_read_proc_file() {
    local file="$1"
    local timeout_sec="${2:-2}"
    
    if command -v timeout &>/dev/null; then
        timeout "$timeout_sec" cat "$file" 2>/dev/null
    else
        # Fallback if timeout command not available
        cat "$file" 2>/dev/null
    fi
}

# Validate port number (1-65535)
s9_validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        s9_die "Invalid port number: $port (must be 1-65535)"
    fi
}

# Validate directory path is safe (under home or /tmp)
s9_validate_safe_dir() {
    local dir="$1"
    local resolved
    
    # Resolve to absolute path
    resolved=$(cd "$dir" 2>/dev/null && pwd) || resolved="$dir"
    
    # Check if under HOME or /tmp
    if [[ "$resolved" != "$HOME"* ]] && [[ "$resolved" != "/tmp"* ]]; then
        s9_warn "Directory '$dir' is outside safe locations (HOME or /tmp)"
        return 1
    fi
    return 0
}

# Resolve PID from name or validate existing PID
s9_resolve_pid() {
    local input="$1"
    local quiet="${2:-false}"
    
    # Sanitize input - only allow alphanumeric, dash, underscore, dot
    local sanitized="${input//[^a-zA-Z0-9_.-]/}"
    if [[ "$sanitized" != "$input" ]]; then
        [[ "$quiet" != "true" ]] && s9_warn "Invalid characters in process identifier"
        return 1
    fi
    
    # If it's already a number, validate it exists
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        if s9_process_exists "$input"; then
            echo "$input"
            return 0
        else
            [[ "$quiet" != "true" ]] && s9_warn "Process $input does not exist"
            return 1
        fi
    fi
    
    # Search by exact name first, then partial match
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

# Get difference indicator with arrow and color
# Usage: s9_diff_indicator <diff_value> [reverse]
# If reverse is set, negative is good (e.g., memory decrease)
s9_diff_indicator() {
    local diff=$1
    local reverse="${2:-}"
    local arrow color sign
    
    if (( diff > 0 )); then
        arrow="↑"
        sign="+"
        if [[ -n "$reverse" ]]; then
            color="$S9_RED"
        else
            color="$S9_GREEN"
        fi
    elif (( diff < 0 )); then
        arrow="↓"
        sign=""
        if [[ -n "$reverse" ]]; then
            color="$S9_GREEN"
        else
            color="$S9_RED"
        fi
    else
        arrow="→"
        sign=""
        color="$S9_DIM"
    fi
    
    printf "%b%s %s%d%b" "$color" "$arrow" "$sign" "$diff" "$S9_NC"
}

# Print a comparison row with before/after values
# Usage: s9_compare_row <label> <val1> <val2> <unit> [human_func]
# human_func can be "kb" or "bytes" for automatic human-readable conversion
s9_compare_row() {
    local label="$1"
    local val1="${2:-0}"
    local val2="${3:-0}"
    local unit="${4:-}"
    local human_func="${5:-}"
    
    # Ensure numeric values
    [[ "$val1" =~ ^-?[0-9]+$ ]] || val1=0
    [[ "$val2" =~ ^-?[0-9]+$ ]] || val2=0
    
    local diff=$((val2 - val1))
    local abs_diff=${diff#-}  # Absolute value for display
    local percent="—"
    
    if (( val1 > 0 )); then
        # Calculate percentage and ensure proper formatting (add leading zero if needed)
        percent=$(echo "scale=1; ($diff * 100) / $val1" | bc 2>/dev/null || echo "0")
        # Fix leading zero for decimals like -.1 → -0.1 or .5 → 0.5
        if [[ "$percent" == .* ]]; then
            percent="0$percent"
        elif [[ "$percent" == -.* ]]; then
            percent="-0${percent#-}"
        fi
        percent="${percent}%"
    elif (( val2 > 0 )); then
        percent="new"
    fi
    
    # Format values with human-readable versions if requested
    # Always use absolute value for diff display (arrow indicates direction)
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
    
    # Color and arrow for change direction
    local change_color="$S9_DIM"
    local arrow="→"
    local sign=""
    if (( diff > 0 )); then
        change_color="$S9_RED"
        arrow="↑"
        sign="+"
    elif (( diff < 0 )); then
        change_color="$S9_GREEN"
        arrow="↓"
        sign="-"
    fi
    
    printf "  ${S9_BOLD}%-16s${S9_NC} %-14s  %-14s  %b%s %s%-10s (%s)%b\n" \
        "$label" "$display1" "$display2" "$change_color" "$arrow" "$sign" "$diff_display" "$percent" "$S9_NC"
}

# Print comparison table header
s9_compare_header() {
    local col1="${1:-Before}"
    local col2="${2:-After}"
    printf "  ${S9_DIM}%-16s %-14s  %-14s  %-24s${S9_NC}\n" "Metric" "$col1" "$col2" "Change"
    printf "  ${S9_DIM}──────────────── ──────────────  ──────────────  ────────────────────────${S9_NC}\n"
}

#------------------------------------------------------------------------------
# Signal Handling
#------------------------------------------------------------------------------

# Signal name lookup table
declare -gA S9_SIGNALS=(
    [1]="SIGHUP" [2]="SIGINT" [3]="SIGQUIT" [4]="SIGILL"
    [5]="SIGTRAP" [6]="SIGABRT" [7]="SIGBUS" [8]="SIGFPE"
    [9]="SIGKILL" [10]="SIGUSR1" [11]="SIGSEGV" [12]="SIGUSR2"
    [13]="SIGPIPE" [14]="SIGALRM" [15]="SIGTERM" [16]="SIGSTKFLT"
    [17]="SIGCHLD" [18]="SIGCONT" [19]="SIGSTOP" [20]="SIGTSTP"
    [21]="SIGTTIN" [22]="SIGTTOU" [23]="SIGURG" [24]="SIGXCPU"
    [25]="SIGXFSZ" [26]="SIGVTALRM" [27]="SIGPROF" [28]="SIGWINCH"
    [29]="SIGIO" [30]="SIGPWR" [31]="SIGSYS"
)

# Decode signal mask (hex) to signal names
s9_decode_signals() {
    local mask=${1:-0}
    local result=""
    
    # Handle empty or all-zeros mask
    if [[ -z "$mask" ]] || [[ "$mask" =~ ^0+$ ]]; then
        echo "none"
        return
    fi
    
    # Convert hex to decimal safely
    local num
    num=$((16#${mask##0x})) 2>/dev/null || num=0
    
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

# Get total system memory in kB
s9_get_total_mem() {
    awk '/^MemTotal:/ {print $2}' /proc/meminfo
}

# Get available system memory in kB
s9_get_avail_mem() {
    awk '/^MemAvailable:/ {print $2}' /proc/meminfo
}

# Get system uptime in seconds
s9_get_uptime() {
    awk '{print int($1)}' /proc/uptime
}

# Get kernel version
s9_get_kernel() {
    uname -r
}
