#!/usr/bin/env bash
#
# find_fd_leak.sh - Investigate file descriptor leaks interactively
# Substrata9 Example
#
# Author: Muskula Rahul
#
# This script helps identify and monitor file descriptor leaks by:
# 1. Finding processes with high FD counts
# 2. Analyzing FD types (files, sockets, pipes)
# 3. Monitoring FD growth in real-time

set -euo pipefail

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library (required for full functionality)
if ! source "${SCRIPT_DIR}/../lib/s9-common.sh" 2>/dev/null; then
    if ! source "/usr/local/lib/substrata9/s9-common.sh" 2>/dev/null; then
        # Minimal fallback for standalone use
        S9_RED=$'\033[0;31m'
        S9_GREEN=$'\033[0;32m'
        S9_YELLOW=$'\033[1;33m'
        S9_CYAN=$'\033[0;36m'
        S9_BOLD=$'\033[1m'
        S9_DIM=$'\033[2m'
        S9_NC=$'\033[0m'
    fi
fi

THRESHOLD=${1:-100}  # Default threshold for "high" FD count
if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]]; then
    printf "%bError:%b threshold must be a non-negative integer\n" "${S9_RED}" "${S9_NC}"
    exit 1
fi
THRESHOLD=$((10#$THRESHOLD))

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

echo ""
printf "%b╔════════════════════════════════════════════════════════════════════╗%b\n" "${S9_BOLD}" "${S9_NC}"
printf "%b║  Substrata9 — FD Leak Investigation                                ║%b\n" "${S9_BOLD}" "${S9_NC}"
printf "%b╚════════════════════════════════════════════════════════════════════╝%b\n" "${S9_BOLD}" "${S9_NC}"
echo ""

# Step 1: Find suspects
printf "%bStep 1: Identifying suspects with high FD counts (>%s)...%b\n" "${S9_BOLD}" "$THRESHOLD" "${S9_NC}"
echo ""

# Check if s9-fdmap is available
FDMAP_CMD="${SCRIPT_DIR}/../bin/s9-fdmap"
if [[ -x "$FDMAP_CMD" ]]; then
    "$FDMAP_CMD" --leaks --threshold "$THRESHOLD"
else
    # Manual scan
    printf "%b(s9-fdmap not found, using manual scan)%b\n" "${S9_DIM}" "${S9_NC}"
    echo ""
    printf "  %b%-8s %-25s %-8s %s%b\n" "${S9_BOLD}" "PID" "PROCESS" "FDs" "USER" "${S9_NC}"
    printf "  %b────────────────────────────────────────────────────────%b\n" "${S9_DIM}" "${S9_NC}"
    
    for proc_dir in /proc/[0-9]*; do
        pid="${proc_dir##*/}"
        [[ -r "$proc_dir/fd" ]] || continue
        
        fd_count=$(ls -1 -- "$proc_dir/fd" 2>/dev/null | wc -l)
        if (( fd_count > THRESHOLD )); then
            name=$(cat "$proc_dir/comm" 2>/dev/null || echo "unknown")
            uid=$(grep "^Uid:" "$proc_dir/status" 2>/dev/null | awk '{print $2}')
            if command -v getent >/dev/null 2>&1; then
                user=$(getent passwd "$uid" 2>/dev/null | cut -d: -f1 || echo "$uid")
            else
                user=$(id -nu "$uid" 2>/dev/null || echo "$uid")
            fi
            printf "  %b%-8s%b %-25s %b%-8s%b %b%s%b\n" \
                "${S9_YELLOW}" "$pid" "${S9_NC}" "${name:0:25}" "${S9_RED}" "$fd_count" "${S9_NC}" "${S9_DIM}" "$user" "${S9_NC}"
        fi
    done
fi

echo ""
read -p "Enter PID to investigate (or press Enter to auto-select highest): " TARGET_PID

# Auto-select if not provided
if [[ -z "$TARGET_PID" ]]; then
    printf "%bAuto-selecting process with most FDs...%b\n" "${S9_DIM}" "${S9_NC}"
    
    max_fds=0
    max_pid=""
    for proc_dir in /proc/[0-9]*; do
        pid="${proc_dir##*/}"
        [[ -r "$proc_dir/fd" ]] || continue
        fd_count=$(ls -1 -- "$proc_dir/fd" 2>/dev/null | wc -l)
        if (( fd_count > max_fds )); then
            max_fds=$fd_count
            max_pid=$pid
        fi
    done
    
    if [[ -z "$max_pid" ]]; then
        printf "%bError:%b No accessible processes found (permission denied?)\n" "${S9_RED}" "${S9_NC}"
        printf "%bTry running with sudo for full access.%b\n" "${S9_DIM}" "${S9_NC}"
        exit 1
    fi
    
    TARGET_PID="$max_pid"
    printf "  Selected: PID %b%s%b (%d FDs)\n" "${S9_CYAN}" "$TARGET_PID" "${S9_NC}" "$max_fds"
fi

if ! [[ "$TARGET_PID" =~ ^[0-9]+$ ]]; then
    printf "%bError:%b PID must be a number\n" "${S9_RED}" "${S9_NC}"
    exit 1
fi

# Validate PID
if [[ ! -d "/proc/$TARGET_PID" ]]; then
    printf "%bError:%b PID %s not found\n" "${S9_RED}" "${S9_NC}" "$TARGET_PID"
    exit 1
fi

NAME=$(cat "/proc/$TARGET_PID/comm" 2>/dev/null || echo "unknown")

echo ""
printf "%bStep 2: Analyzing PID %s (%s)...%b\n" "${S9_BOLD}" "$TARGET_PID" "$NAME" "${S9_NC}"
echo ""

# Count FD types
files=0 sockets=0 pipes=0 devices=0 eventfds=0 other=0

for fd in "/proc/$TARGET_PID/fd"/*; do
    [[ -e "$fd" ]] || continue
    target=$(readlink "$fd" 2>/dev/null || echo "")
    
    case "$target" in
        socket:*) ((sockets++)) ;;
        pipe:*) ((pipes++)) ;;
        /dev/*) ((devices++)) ;;
        anon_inode:*eventfd*) ((eventfds++)) ;;
        anon_inode:*) ((other++)) ;;
        *) ((files++)) ;;
    esac
done

total=$((files + sockets + pipes + devices + eventfds + other))

echo ""
printf "  %bFD Type Breakdown%b\n" "${S9_BOLD}" "${S9_NC}"
echo "  ┌─────────────────────────────────────┐"
printf "  │ %-12s %6d  " "Files:" "$files"
(( total > 0 && (files * 20 / total) > 0 )) && printf "%-15s" "$(printf '█%.0s' $(seq 1 $((files * 20 / total))))" || printf "%-15s" ""
echo "│"
printf "  │ %-12s %6d  " "Sockets:" "$sockets"
(( total > 0 && (sockets * 20 / total) > 0 )) && printf "%-15s" "$(printf '█%.0s' $(seq 1 $((sockets * 20 / total))))" || printf "%-15s" ""
echo "│"
printf "  │ %-12s %6d  " "Pipes:" "$pipes"
(( total > 0 && (pipes * 20 / total) > 0 )) && printf "%-15s" "$(printf '█%.0s' $(seq 1 $((pipes * 20 / total))))" || printf "%-15s" ""
echo "│"
printf "  │ %-12s %6d  " "Devices:" "$devices"
(( total > 0 && (devices * 20 / total) > 0 )) && printf "%-15s" "$(printf '█%.0s' $(seq 1 $((devices * 20 / total))))" || printf "%-15s" ""
echo "│"
printf "  │ %-12s %6d  " "Event FDs:" "$eventfds"
(( total > 0 && (eventfds * 20 / total) > 0 )) && printf "%-15s" "$(printf '█%.0s' $(seq 1 $((eventfds * 20 / total))))" || printf "%-15s" ""
echo "│"
printf "  │ %-12s %6d  " "Other:" "$other"
(( total > 0 && (other * 20 / total) > 0 )) && printf "%-15s" "$(printf '█%.0s' $(seq 1 $((other * 20 / total))))" || printf "%-15s" ""
echo "│"
echo "  ├─────────────────────────────────────┤"
printf "  │ %-12s %b%6d%b                  │\n" "TOTAL:" "${S9_BOLD}" "$total" "${S9_NC}"
echo "  └─────────────────────────────────────┘"

echo ""
printf "%bTop 10 Most Common Targets:%b\n" "${S9_BOLD}" "${S9_NC}"
echo ""

for fd in "/proc/$TARGET_PID/fd"/*; do
    [[ -e "$fd" ]] || continue
    readlink "$fd" 2>/dev/null || echo "unknown"
done | sort | uniq -c | sort -rn | head -10 | while read -r count target; do
    # Truncate long targets
    if (( ${#target} > 50 )); then
        target="${target:0:47}..."
    fi
    printf "  %6d  %s\n" "$count" "$target"
done

echo ""

# Check for obvious leak patterns
printf "%bLeak Pattern Analysis:%b\n" "${S9_BOLD}" "${S9_NC}"
echo ""

# Check for duplicate file opens
dup_files=$(for fd in "/proc/$TARGET_PID/fd"/*; do
    [[ -e "$fd" ]] || continue
    target=$(readlink "$fd" 2>/dev/null || echo "")
    [[ "$target" == /* ]] && echo "$target"
done | sort | uniq -c | sort -rn | head -1)

dup_count=$(echo "$dup_files" | awk '{print $1}')
dup_file=$(echo "$dup_files" | awk '{$1=""; print $0}' | xargs)
[[ "$dup_count" =~ ^[0-9]+$ ]] || dup_count=0

if (( dup_count > 10 )); then
    printf "  %b⚠ Same file opened %d times:%b\n" "${S9_RED}" "$dup_count" "${S9_NC}"
    printf "    %s\n" "$dup_file"
    printf "    %bThis often indicates a file handle leak (missing close())%b\n" "${S9_DIM}" "${S9_NC}"
elif (( sockets > 500 )); then
    printf "  %b⚠ Very high socket count (%d)%b\n" "${S9_RED}" "$sockets" "${S9_NC}"
    printf "    %bCheck for connection pool leaks or missing socket.close()%b\n" "${S9_DIM}" "${S9_NC}"
elif (( pipes > 200 )); then
    printf "  %b⚠ High pipe count (%d)%b\n" "${S9_YELLOW}" "$pipes" "${S9_NC}"
    printf "    %bCheck for subprocess/popen leaks%b\n" "${S9_DIM}" "${S9_NC}"
else
    printf "  %b✓ No obvious leak patterns detected%b\n" "${S9_GREEN}" "${S9_NC}"
fi

echo ""
printf "%bStep 3: Real-time monitoring...%b\n" "${S9_BOLD}" "${S9_NC}"
printf "%bPress Ctrl+C to stop%b\n" "${S9_DIM}" "${S9_NC}"
echo ""

trap 'echo ""; printf "%bMonitoring stopped.%b\n" "${S9_YELLOW}" "${S9_NC}"; exit 0' INT

prev_count=$total
echo "$(date '+%H:%M:%S') - Initial FD count: $prev_count"

while true; do
    sleep 5
    
    [[ -d "/proc/$TARGET_PID" ]] || { printf "%bProcess terminated%b\n" "${S9_RED}" "${S9_NC}"; break; }
    
    curr_count=$(ls -1 -- "/proc/$TARGET_PID/fd" 2>/dev/null | wc -l)
    diff=$((curr_count - prev_count))
    
    if (( diff != 0 )); then
        if (( diff > 0 )); then
            printf "%s - FDs: %d %b(+%d)%b\n" "$(date '+%H:%M:%S')" "$curr_count" "${S9_RED}" "$diff" "${S9_NC}"
        else
            printf "%s - FDs: %d %b(%d)%b\n" "$(date '+%H:%M:%S')" "$curr_count" "${S9_GREEN}" "$diff" "${S9_NC}"
        fi
        prev_count=$curr_count
    fi
done
