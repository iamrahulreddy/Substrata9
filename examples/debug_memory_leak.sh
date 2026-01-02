#!/usr/bin/env bash
#
# debug_memory_leak.sh - Monitor a process for memory growth over time
# Substrata9 Example
#
# Author: Muskula Rahul
#
# This script captures memory metrics at regular intervals and detects
# potential memory leaks by analyzing growth patterns.

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
        
        # Check bc dependency manually
        command -v bc &>/dev/null || { echo "Error: bc is required"; exit 1; }
    fi
fi

#------------------------------------------------------------------------------
# Usage
#------------------------------------------------------------------------------
usage() {
    cat << EOF
${S9_BOLD}debug_memory_leak.sh${S9_NC} - Monitor a process for memory growth

${S9_BOLD}USAGE:${S9_NC}
    $0 <PID|process_name> [duration_seconds] [interval_seconds]

${S9_BOLD}ARGUMENTS:${S9_NC}
    PID/name     Process ID or name to monitor
    duration     How long to monitor in seconds (default: 3600 = 1 hour)
    interval     How often to sample in seconds (default: 60 = 1 minute)

${S9_BOLD}EXAMPLES:${S9_NC}
    $0 1234 3600 60       # Monitor PID 1234 for 1 hour, sample every minute
    $0 python 7200 300    # Monitor python for 2 hours, sample every 5 minutes
    $0 nginx              # Monitor nginx with defaults (1 hour, 1 min intervals)

${S9_BOLD}OUTPUT:${S9_NC}
    Creates a CSV log file in /tmp with timestamp, RSS, VmSize, and FD count.
    At the end, provides analysis of memory growth.

EOF
    exit 1
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

[[ $# -lt 1 ]] && usage

TARGET="$1"
DURATION="${2:-3600}"  # Default: 1 hour
INTERVAL="${3:-60}"    # Default: 1 minute

# Resolve PID
if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
    PID="$TARGET"
else
    PID=$(pgrep -n "$TARGET" 2>/dev/null || true)
    if [[ -z "$PID" ]]; then
        printf "%bError:%b No process found matching '%s'\n" "${S9_RED}" "${S9_NC}" "$TARGET"
        exit 1
    fi
fi

# Validate process exists
if [[ ! -d "/proc/$PID" ]]; then
    printf "%bError:%b Process %s does not exist\n" "${S9_RED}" "${S9_NC}" "$PID"
    exit 1
fi

PROC_NAME=$(cat "/proc/$PID/comm" 2>/dev/null || echo "unknown")

# Create log file
LOG_FILE="/tmp/substrata9_memleak_${PID}_$(date +%Y%m%d_%H%M%S).csv"

echo ""
printf "%b╔════════════════════════════════════════════════════════════════════╗%b\n" "${S9_BOLD}" "${S9_NC}"
printf "%b║  Substrata9 — Memory Leak Monitor                                  ║%b\n" "${S9_BOLD}" "${S9_NC}"
printf "%b╚════════════════════════════════════════════════════════════════════╝%b\n" "${S9_BOLD}" "${S9_NC}"
echo ""
printf "  %b%-12s%b %b%s%b (%s)\n" "${S9_BOLD}" "Target:" "${S9_NC}" "${S9_CYAN}" "$PID" "${S9_NC}" "$PROC_NAME"
printf "  %b%-12s%b %s minutes\n" "${S9_BOLD}" "Duration:" "${S9_NC}" "$(( DURATION / 60 ))"
printf "  %b%-12s%b %s seconds\n" "${S9_BOLD}" "Interval:" "${S9_NC}" "$INTERVAL"
printf "  %b%-12s%b %s\n" "${S9_BOLD}" "Log:" "${S9_NC}" "$LOG_FILE"
echo ""

# Take initial snapshot if s9-snapshot is available
if command -v s9-snapshot &>/dev/null || [[ -x "${SCRIPT_DIR}/../bin/s9-snapshot" ]]; then
    SNAPSHOT_CMD="${SCRIPT_DIR}/../bin/s9-snapshot"
    [[ -x "$SNAPSHOT_CMD" ]] || SNAPSHOT_CMD="s9-snapshot"
    
    printf "%bTaking initial snapshot...%b\n" "${S9_DIM}" "${S9_NC}"
    "$SNAPSHOT_CMD" capture "$PID" --name "leak_start_$$" 2>/dev/null || true
fi

# Write CSV header
echo "Timestamp,RSS_KB,VmSize_KB,VmSwap_KB,FD_Count,Threads" | tee "$LOG_FILE"

# Get initial values for comparison
INITIAL_RSS=$(grep "^VmRSS:" "/proc/$PID/status" 2>/dev/null | awk '{print $2}' || echo "0")
INITIAL_FDS=$(ls -1 "/proc/$PID/fd" 2>/dev/null | wc -l || echo "0")

echo ""
printf "%bMonitoring started. Press Ctrl+C to stop early.%b\n" "${S9_DIM}" "${S9_NC}"
echo ""

# Trap Ctrl+C for clean exit
trap 'echo ""; printf "%bMonitoring interrupted%b\n" "${S9_YELLOW}" "${S9_NC}"; INTERRUPTED=true' INT
INTERRUPTED=false

# Monitor loop
END_TIME=$(($(date +%s) + DURATION))
SAMPLE_COUNT=0

while (( $(date +%s) < END_TIME )) && [[ "$INTERRUPTED" != "true" ]]; do
    # Check if process still exists
    if [[ ! -d "/proc/$PID" ]]; then
        echo ""
        printf "%bProcess %s terminated during monitoring%b\n" "${S9_YELLOW}" "$PID" "${S9_NC}"
        break
    fi
    
    # Get current metrics
    RSS=$(grep "^VmRSS:" "/proc/$PID/status" 2>/dev/null | awk '{print $2}' || echo "0")
    VMSIZE=$(grep "^VmSize:" "/proc/$PID/status" 2>/dev/null | awk '{print $2}' || echo "0")
    VMSWAP=$(grep "^VmSwap:" "/proc/$PID/status" 2>/dev/null | awk '{print $2}' || echo "0")
    FDS=$(ls -1 "/proc/$PID/fd" 2>/dev/null | wc -l || echo "0")
    THREADS=$(grep "^Threads:" "/proc/$PID/status" 2>/dev/null | awk '{print $2}' || echo "1")
    
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to file
    echo "$TIMESTAMP,$RSS,$VMSIZE,$VMSWAP,$FDS,$THREADS" >> "$LOG_FILE"
    
    # Calculate change from initial
    RSS_CHANGE=$((RSS - INITIAL_RSS))
    FD_CHANGE=$((FDS - INITIAL_FDS))
    
    # Display with color coding
    rss_color="$S9_NC"
    if (( RSS_CHANGE > 100000 )); then
        rss_color="$S9_RED"
    elif (( RSS_CHANGE > 10000 )); then
        rss_color="$S9_YELLOW"
    fi
    
    printf "%s  RSS: ${rss_color}%8s KB${S9_NC} (%+d)  FDs: %d (%+d)\n" \
        "$TIMESTAMP" "$RSS" "$RSS_CHANGE" "$FDS" "$FD_CHANGE"
    
    # Increment counter first, then check for alerts
    ((SAMPLE_COUNT++))
    
    # Alert on significant growth (every 10 samples after the first)
    if (( RSS > 1000000 )) && (( SAMPLE_COUNT > 1 )) && (( SAMPLE_COUNT % 10 == 0 )); then
        printf "  %b⚠ Memory exceeded 1GB%b\n" "${S9_YELLOW}" "${S9_NC}"
    fi
    sleep "$INTERVAL"
done

echo ""
printf "%bMonitoring complete!%b\n" "${S9_BOLD}" "${S9_NC}"
echo ""

# Take final snapshot
if [[ -n "${SNAPSHOT_CMD:-}" ]]; then
    printf "%bTaking final snapshot...%b\n" "${S9_DIM}" "${S9_NC}"
    "$SNAPSHOT_CMD" capture "$PID" --name "leak_end_$$" 2>/dev/null || true
    
    echo ""
    printf "%bComparing snapshots:%b\n" "${S9_BOLD}" "${S9_NC}"
    "$SNAPSHOT_CMD" diff "leak_start_$$" "leak_end_$$" 2>/dev/null || true
fi

echo ""
printf "%b═══ Analysis ═══%b\n" "${S9_BOLD}" "${S9_NC}"
echo ""
echo "Log file: $LOG_FILE"
echo "Samples collected: $SAMPLE_COUNT"
echo ""

# Analyze the log
# Validate we have actual data rows (not just header)
DATA_LINES=$(grep -cv "^Timestamp," "$LOG_FILE" 2>/dev/null || echo "0")
if (( DATA_LINES < 1 )); then
    printf "%b⚠ No data samples collected - analysis skipped%b\n" "${S9_YELLOW}" "${S9_NC}"
elif (( SAMPLE_COUNT > 1 )); then
    FIRST_RSS=$(grep -v "^Timestamp," "$LOG_FILE" | head -1 | cut -d, -f2)
    LAST_RSS=$(grep -v "^Timestamp," "$LOG_FILE" | tail -1 | cut -d, -f2)
    
    # Validate extracted values are numeric
    if ! [[ "$FIRST_RSS" =~ ^[0-9]+$ ]] || ! [[ "$LAST_RSS" =~ ^[0-9]+$ ]]; then
        printf "%b⚠ Invalid data in log file - analysis skipped%b\n" "${S9_YELLOW}" "${S9_NC}"
    else
        GROWTH=$((LAST_RSS - FIRST_RSS))
        
        FIRST_FDS=$(grep -v "^Timestamp," "$LOG_FILE" | head -1 | cut -d, -f5)
        LAST_FDS=$(grep -v "^Timestamp," "$LOG_FILE" | tail -1 | cut -d, -f5)
        FD_GROWTH=$((LAST_FDS - FIRST_FDS))
        
        echo "Memory:"
        echo "  Initial RSS: $FIRST_RSS KB"
        echo "  Final RSS:   $LAST_RSS KB"
        echo -n "  Growth:      $GROWTH KB "
        
        if (( GROWTH > 100000 )); then
            printf "%b🔴 LEAK LIKELY: Grew >100MB%b\n" "${S9_RED}" "${S9_NC}"
        elif (( GROWTH > 10000 )); then
            printf "%b🟡 POSSIBLE LEAK: Grew >10MB%b\n" "${S9_YELLOW}" "${S9_NC}"
        elif (( GROWTH > 1000 )); then
            printf "%b🟡 Minor growth: >1MB%b\n" "${S9_YELLOW}" "${S9_NC}"
        else
            printf "%b🟢 Normal variation%b\n" "${S9_GREEN}" "${S9_NC}"
        fi
        
        echo ""
        echo "File Descriptors:"
        echo "  Initial: $FIRST_FDS"
        echo "  Final:   $LAST_FDS"
        echo -n "  Growth:  $FD_GROWTH "
        
        if (( FD_GROWTH > 100 )); then
            printf "%b🔴 FD LEAK LIKELY%b\n" "${S9_RED}" "${S9_NC}"
        elif (( FD_GROWTH > 10 )); then
            printf "%b🟡 FD growth detected%b\n" "${S9_YELLOW}" "${S9_NC}"
        else
            printf "%b🟢 FD count stable%b\n" "${S9_GREEN}" "${S9_NC}"
        fi
    fi
fi

echo ""
printf "%bTo visualize the data:%b\n" "${S9_DIM}" "${S9_NC}"
echo "  column -t -s, $LOG_FILE | less"
echo ""
