#!/usr/bin/env bash
#
# test_stress.sh - Performance & stress benchmarks for Substrata9
#
# Measures real execution time under load. Uses timeout guards to
# prevent hangs. Tests throughput, deep JSON validation, injection
# defense, concurrent execution, snapshot lifecycle, and GPU coverage.
#
# Designed for Colab / CI environments.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(dirname "$TEST_DIR")/bin"
SNAP_DIR=$(mktemp -d)
STRESS_WORK_DIR=$(mktemp -d)
export S9_SNAPSHOT_DIR="$SNAP_DIR"
DUMMY_CPU_PID=""
DUMMY_CPU_FILE=""
REAL_GPU_PID=""
REAL_GPU_ALLOC_MB=""
REAL_GPU_EXPECTED_MIN_MB=""
REAL_GPU_PIDS=()
REAL_GPU_ALLOC_MBS=()
REAL_GPU_EXPECTED_MIN_MBS=()
REAL_GPU_MATCH_MODES=()

stop_real_gpu_workloads() {
    local pid pgid
    for pid in "${REAL_GPU_PIDS[@]:-}"; do
        [[ -n "$pid" ]] || continue
        # Get the process group ID
        pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ') || pgid=""
        if [[ -n "$pgid" && "$pgid" != "$$" ]]; then
            kill -TERM -- "-$pgid" 2>/dev/null || true
            sleep 0.2
            kill -KILL -- "-$pgid" 2>/dev/null || true
        else
            kill -TERM "$pid" 2>/dev/null || true
            sleep 0.2
            kill -KILL "$pid" 2>/dev/null || true
        fi
        wait "$pid" 2>/dev/null || true
    done
    REAL_GPU_PIDS=()
    REAL_GPU_ALLOC_MBS=()
    REAL_GPU_EXPECTED_MIN_MBS=()
    REAL_GPU_MATCH_MODES=()
    REAL_GPU_PID=""
    REAL_GPU_ALLOC_MB=""
    REAL_GPU_EXPECTED_MIN_MB=""
}

cleanup() {
    stop_real_gpu_workloads
    if [[ -n "${DUMMY_CPU_PID:-}" ]]; then
        kill "$DUMMY_CPU_PID" 2>/dev/null || true
        wait "$DUMMY_CPU_PID" 2>/dev/null || true
    fi
    rm -rf "$SNAP_DIR" "$STRESS_WORK_DIR"
}
trap cleanup EXIT

# IST timestamp
ist() { TZ='Asia/Kolkata' date '+%Y-%m-%d %H:%M:%S IST'; }

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
SELF=$$

# Guard timeout for any single command (seconds)
CMD_TIMEOUT=30

pass() { ((TESTS_RUN++)); ((TESTS_PASSED++)); echo "    [OK] $1"; }
fail() { ((TESTS_RUN++)); ((TESTS_FAILED++)); echo "    [FAIL] $1: $2"; }
skip() { ((TESTS_RUN++)); ((TESTS_SKIPPED++)); echo "    [SKIP] $1"; }

json_file_valid() {
    local file="$1"
    if command -v jq >/dev/null 2>&1; then
        jq . "$file" >/dev/null 2>&1
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$file" <<'PYJSON' >/dev/null 2>&1
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    json.load(fh)
PYJSON
    else
        return 2
    fi
}

# Time a command with timeout guard. Fail if exit != 0 or exceeds max_seconds.
bench() {
    local desc="$1" max_s="$2"; shift 2
    local t0 t1 dur rc out
    t0=$(date +%s%N)
    out=$(timeout "$CMD_TIMEOUT" "$@" 2>&1) && rc=0 || rc=$?
    t1=$(date +%s%N)
    dur=$(( (t1 - t0) / 1000000 ))
    if (( rc == 124 )); then
        fail "$desc" "TIMEOUT after ${CMD_TIMEOUT}s"
    elif (( rc != 0 )); then
        fail "$desc" "exit=$rc after ${dur}ms"
    elif (( dur > max_s * 1000 )); then
        fail "$desc" "TOO SLOW: ${dur}ms (limit: ${max_s}s)"
    else
        pass "$desc [${dur}ms]"
    fi
}

# Time a command N times, report avg
bench_repeat() {
    local desc="$1" n="$2" max_s="$3"; shift 3
    local total=0 rc_fail=0
    for (( i=1; i<=n; i++ )); do
        local t0 t1
        t0=$(date +%s%N)
        timeout "$CMD_TIMEOUT" "$@" >/dev/null 2>&1 && true || ((rc_fail++))
        t1=$(date +%s%N)
        total=$(( total + (t1 - t0) / 1000000 ))
    done
    local avg=$(( total / n ))
    if (( rc_fail > 0 )); then
        fail "$desc (${n}x)" "$rc_fail failures, avg=${avg}ms"
    elif (( avg > max_s * 1000 )); then
        fail "$desc (${n}x)" "avg=${avg}ms exceeds limit ${max_s}s"
    else
        pass "$desc (${n}x, avg=${avg}ms, total=${total}ms)"
    fi
}

jq_path_presence_expr() {
    local key="${1#.}"
    local path="["
    local first=true part

    IFS='.' read -ra parts <<< "$key"
    for part in "${parts[@]}"; do
        [[ -n "$part" ]] || continue
        if $first; then
            first=false
        else
            path+=","
        fi
        path+="\"$part\""
    done
    path+="]"

    printf 'def _s9_haspath($p): if ($p|length)==0 then true elif type=="object" and has($p[0]) then .[$p[0]] | _s9_haspath($p[1:]) else false end; _s9_haspath(%s)' "$path"
}

# Run command, validate JSON key exists
json_key() {
    local desc="$1" key="$2"; shift 2
    local out rc err jq_expr
    if ! command -v jq >/dev/null 2>&1; then
        skip "$desc (jq unavailable)"
        return
    fi
    jq_expr=$(jq_path_presence_expr "$key")
    err=$(mktemp)
    if out=$(timeout "$CMD_TIMEOUT" "$@" 2>"$err"); then
        rc=0
    else
        rc=$?
    fi
    if (( rc == 0 )) && echo "$out" | jq -e "$jq_expr" >/dev/null 2>&1; then
        pass "$desc (has $key)"
    else
        local detail="missing $key or exit $rc"
        if [[ -s "$err" ]]; then
            detail="$detail; stderr: $(head -1 "$err")"
        fi
        fail "$desc" "$detail"
    fi
    rm -f "$err"
}

# Expect failure
expect_fail() {
    local desc="$1"; shift
    timeout "$CMD_TIMEOUT" "$@" >/dev/null 2>&1 && fail "$desc" "should have failed" || pass "$desc (rejected)"
}

json_assert_cmd() {
    local desc="$1" expr="$2"; shift 2
    local out rc err
    if ! command -v jq >/dev/null 2>&1; then
        skip "$desc (jq unavailable)"
        return
    fi
    err=$(mktemp)
    if out=$(timeout "$CMD_TIMEOUT" "$@" 2>"$err"); then
        rc=0
    else
        rc=$?
    fi

    if (( rc == 0 )) && echo "$out" | jq -e "$expr" >/dev/null 2>&1; then
        pass "$desc"
    else
        local detail="jq assertion failed or exit $rc"
        if [[ -s "$err" ]]; then
            detail="$detail; stderr: $(head -1 "$err")"
        fi
        fail "$desc" "$detail"
    fi
    rm -f "$err"
}

bench_auto_export_json() {
    local desc="$1" purpose="$2" max_s="$3"; shift 3
    local export_dir out err t0 t1 dur rc exported
    export_dir="$STRESS_WORK_DIR/export_${purpose}_${TESTS_RUN}_$$"
    mkdir -p "$export_dir" || { fail "$desc -e" "cannot create export dir"; return; }
    out="$export_dir/stdout.json"
    err="$export_dir/stderr.txt"

    t0=$(date +%s%N)
    if (cd "$export_dir" && timeout "$CMD_TIMEOUT" "$@") >"$out" 2>"$err"; then
        rc=0
    else
        rc=$?
    fi
    t1=$(date +%s%N)
    dur=$(( (t1 - t0) / 1000000 ))

    if (( rc == 124 )); then
        fail "$desc -e" "TIMEOUT after ${CMD_TIMEOUT}s"
        return
    elif (( rc != 0 )); then
        fail "$desc -e" "exit=$rc after ${dur}ms"
        return
    elif (( dur > max_s * 1000 )); then
        fail "$desc -e" "TOO SLOW: ${dur}ms (limit: ${max_s}s)"
        return
    elif ! json_file_valid "$out"; then
        fail "$desc -e" "stdout is not valid JSON"
        return
    fi

    shopt -s nullglob
    local exported_files=("$export_dir"/s9-"$purpose"_*.json)
    shopt -u nullglob
    exported="${exported_files[0]:-}"

    if [[ -z "$exported" || ! -f "$exported" ]]; then
        fail "$desc -e" "auto export file missing for purpose $purpose"
    elif ! json_file_valid "$exported"; then
        fail "$desc -e" "export file is not valid JSON"
    elif ! grep -q 'JSON exported to s9-' "$err" 2>/dev/null; then
        fail "$desc -e" "export status missing from stderr"
    else
        pass "$desc -e [${dur}ms]"
    fi
}

start_dummy_cpu_workload() {
    DUMMY_CPU_FILE="$STRESS_WORK_DIR/dummy-workload.log"
    : > "$DUMMY_CPU_FILE"

    bash -c '
        file=$1
        fds=()
        for ((i=0; i<80; i++)); do
            if exec {fd}<>"$file"; then
                fds+=("$fd")
            fi
        done
        while :; do :; done
    ' _ "$DUMMY_CPU_FILE" &
    DUMMY_CPU_PID=$!
    sleep 0.5
    [[ -d "/proc/$DUMMY_CPU_PID" ]]
}

start_real_gpu_workload() {
    command -v nvidia-smi >/dev/null 2>&1 || return 2
    nvidia-smi -L >/dev/null 2>&1 || return 2

    local python_bin
    python_bin=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)
    [[ -n "$python_bin" ]] || return 3

    local script
    script="$STRESS_WORK_DIR/real-gpu-workload.py"

    cat > "$script" <<'PY_GPU_WORKLOAD'
import os
import sys
import time

try:
    import torch
except Exception as exc:
    print(f"NO_TORCH: {exc}", file=sys.stderr, flush=True)
    sys.exit(42)

if not torch.cuda.is_available():
    print("NO_CUDA", file=sys.stderr, flush=True)
    sys.exit(43)

device = torch.device("cuda:0")
label = os.environ.get("S9_GPU_WORKLOAD_LABEL", "gpu")

def _float_env(name, default):
    raw = os.environ.get(name, str(default))
    try:
        return float(raw)
    except ValueError:
        return default

def _int_env(name, default):
    raw = os.environ.get(name, str(default))
    try:
        return int(raw)
    except ValueError:
        return default

stress_fraction = _float_env("S9_GPU_STRESS_FRACTION", 0.70)
stress_fraction = min(max(stress_fraction, 0.05), 0.90)
min_stress_mb = max(256, _int_env("S9_GPU_STRESS_MIN_MB", 1024))
chunk_mb = min(max(64, _int_env("S9_GPU_STRESS_CHUNK_MB", 256)), 1024)
min_bytes = min_stress_mb * 1024 * 1024
tensors = []
allocated_bytes = 0

try:
    free_bytes, total_bytes = torch.cuda.mem_get_info(device)
    target_bytes = min(int(total_bytes * stress_fraction), int(free_bytes * 0.90))
    if target_bytes < min_bytes:
        print(
            f"CUDA_INSUFFICIENT_FREE_MEMORY: target_mb={target_bytes // 1024 // 1024} "
            f"min_mb={min_stress_mb} free_mb={free_bytes // 1024 // 1024}",
            file=sys.stderr,
            flush=True,
        )
        sys.exit(45)

    chunk_bytes = chunk_mb * 1024 * 1024
    while allocated_bytes < target_bytes:
        want_bytes = min(chunk_bytes, target_bytes - allocated_bytes)
        elements = max(1, want_bytes // 4)
        tensor = torch.empty(elements, device=device, dtype=torch.float32)
        tensor.uniform_()
        tensors.append(tensor)
        allocated_bytes += tensor.nelement() * tensor.element_size()
        torch.cuda.synchronize()
except RuntimeError as exc:
    if "out of memory" not in str(exc).lower():
        print(f"CUDA_ALLOC_FAILED: {exc}", file=sys.stderr, flush=True)
        sys.exit(44)
    if allocated_bytes < min_bytes:
        print(f"CUDA_ALLOC_FAILED: {exc}", file=sys.stderr, flush=True)
        sys.exit(44)
    torch.cuda.empty_cache()
except Exception as exc:
    print(f"CUDA_ALLOC_FAILED: {exc}", file=sys.stderr, flush=True)
    sys.exit(44)

try:
    torch.cuda.synchronize()
except Exception as exc:
    print(f"CUDA_SYNC_FAILED: {exc}", file=sys.stderr, flush=True)
    sys.exit(44)

allocated_mb = allocated_bytes // 1024 // 1024
assert_min_mb = max(min_stress_mb, int(allocated_mb * 0.80))
print(
    f"READY label={label} pid={os.getpid()} device={torch.cuda.get_device_name(0)} "
    f"allocated_mb={allocated_mb} assert_min_mb={assert_min_mb} "
    f"target_fraction={stress_fraction:.2f}",
    flush=True,
)

deadline = time.time() + int(os.environ.get("S9_GPU_WORKLOAD_SECONDS", "180"))
touch_index = 0
while time.time() < deadline:
    tensors[touch_index].mul_(1.000001).add_(0.000001)
    touch_index = (touch_index + 1) % len(tensors)
    torch.cuda.synchronize()
    time.sleep(0.05)
PY_GPU_WORKLOAD

    start_gpu_worker() {
        local label="$1" fraction="$2" min_mb="$3"
        local log launcher_pid worker_pid i app_rows used_mb alloc_mb expected_min_mb
        log="$STRESS_WORK_DIR/real-gpu-${label}.log"

        # Capture baseline GPU memory usage before launching workload
        local baseline_used_mb
        baseline_used_mb=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
        [[ "$baseline_used_mb" =~ ^[0-9]+$ ]] || baseline_used_mb=0

        S9_GPU_WORKLOAD_SECONDS=180 \
        S9_GPU_WORKLOAD_LABEL="$label" \
        S9_GPU_STRESS_FRACTION="$fraction" \
        S9_GPU_STRESS_MIN_MB="$min_mb" \
            setsid "$python_bin" "$script" >"$log" 2>&1 &
        launcher_pid=$!
        worker_pid="$launcher_pid"

        for (( i=0; i<45; i++ )); do
            if ! kill -0 "$worker_pid" 2>/dev/null && ! kill -0 "$launcher_pid" 2>/dev/null; then
                wait "$launcher_pid" 2>/dev/null || true
                return 4
            fi

            if grep -q '^READY ' "$log" 2>/dev/null; then
                worker_pid=$(sed -n 's/.* pid=\([0-9][0-9]*\).*/\1/p' "$log" | head -1)
                [[ "$worker_pid" =~ ^[0-9]+$ ]] || worker_pid="$launcher_pid"
                alloc_mb=$(sed -n 's/.*allocated_mb=\([0-9][0-9]*\).*/\1/p' "$log" | head -1)
                expected_min_mb=$(sed -n 's/.*assert_min_mb=\([0-9][0-9]*\).*/\1/p' "$log" | head -1)
                [[ -n "$alloc_mb" ]] || alloc_mb=0
                [[ -n "$expected_min_mb" ]] || expected_min_mb="$min_mb"
                app_rows=$(nvidia-smi --query-compute-apps=pid,process_name,gpu_uuid,used_memory --format=csv,noheader,nounits 2>/dev/null || true)
                used_mb=$(echo "$app_rows" | awk -F',' -v pid="$worker_pid" '
                    {
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4)
                        if ($1 == pid) { print int($4); exit }
                    }')
                if [[ -n "$used_mb" ]] && (( used_mb >= expected_min_mb )); then
                    REAL_GPU_PIDS+=("$worker_pid")
                    REAL_GPU_ALLOC_MBS+=("$alloc_mb")
                    REAL_GPU_EXPECTED_MIN_MBS+=("$expected_min_mb")
                    REAL_GPU_MATCH_MODES+=("pid")
                    return 0
                fi

                # Fallback: PID match failed (container isolation)
                # Check if total GPU memory increased by the expected amount
                local current_used_mb
                current_used_mb=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
                [[ "$current_used_mb" =~ ^[0-9]+$ ]] || current_used_mb=0
                local delta_mb=$(( current_used_mb - baseline_used_mb ))
                if (( delta_mb >= expected_min_mb )); then
                    echo "    [WARN] nvidia-smi cannot enumerate GPU process by PID (container isolation); verified by memory delta: +${delta_mb}MB" >&2
                    REAL_GPU_PIDS+=("$worker_pid")
                    REAL_GPU_ALLOC_MBS+=("$alloc_mb")
                    REAL_GPU_EXPECTED_MIN_MBS+=("$expected_min_mb")
                    REAL_GPU_MATCH_MODES+=("aggregate")
                    return 0
                fi
            fi
            sleep 1
        done

        kill "$worker_pid" "$launcher_pid" 2>/dev/null || true
        wait "$launcher_pid" 2>/dev/null || true
        return 5
    }

    stop_real_gpu_workloads

    local primary_fraction="${S9_GPU_PRIMARY_FRACTION:-0.52}"
    local secondary_fraction="${S9_GPU_SECONDARY_FRACTION:-0.18}"
    local primary_min_mb="${S9_GPU_PRIMARY_MIN_MB:-4096}"
    local secondary_min_mb="${S9_GPU_SECONDARY_MIN_MB:-1024}"
    local rc

    start_gpu_worker "primary" "$primary_fraction" "$primary_min_mb"
    rc=$?
    if (( rc != 0 )); then
        stop_real_gpu_workloads
        return "$rc"
    fi

    start_gpu_worker "secondary" "$secondary_fraction" "$secondary_min_mb"
    rc=$?
    if (( rc != 0 )); then
        stop_real_gpu_workloads
        return "$rc"
    fi

    REAL_GPU_PID="${REAL_GPU_PIDS[0]}"
    REAL_GPU_ALLOC_MB="${REAL_GPU_ALLOC_MBS[0]}"
    REAL_GPU_EXPECTED_MIN_MB="${REAL_GPU_EXPECTED_MIN_MBS[0]}"

    return 0
}

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Substrata9 -- Performance & Stress Benchmark                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Started: $(ist)"
echo "  PID:     $SELF"
echo "  Timeout: ${CMD_TIMEOUT}s per command"
echo ""

# =============================================================================
echo "  [1] Single-run benchmarks (timed)"
# =============================================================================
bench "s9-inspect $$"                    10  bash "$BIN_DIR/s9-inspect" $SELF
bench "s9-inspect --full $$"             10  bash "$BIN_DIR/s9-inspect" --full $SELF
bench "s9-inspect --json $$"             10  bash "$BIN_DIR/s9-inspect" --json $SELF
bench "s9-inspect --quiet $$"            10  bash "$BIN_DIR/s9-inspect" --quiet $SELF
bench "s9-tree -d 2"                     15  bash "$BIN_DIR/s9-tree" -d 2
bench "s9-tree --json -d 2"              15  bash "$BIN_DIR/s9-tree" --json -d 2
bench "s9-tree --threads -d 1"           15  bash "$BIN_DIR/s9-tree" --threads -d 1
bench "s9-tree -d 3 (deep)"             20  bash "$BIN_DIR/s9-tree" -d 3
bench "s9-tree --no-memory --no-state"   15  bash "$BIN_DIR/s9-tree" -d 1 --no-memory --no-state
bench "s9-fdmap --top 10"               15  bash "$BIN_DIR/s9-fdmap" --top 10
bench "s9-fdmap --leaks"                15  bash "$BIN_DIR/s9-fdmap" --leaks
bench "s9-fdmap --json --top 20"        15  bash "$BIN_DIR/s9-fdmap" --json --top 20
bench "s9-fdmap --leaks --threshold 0"  15  bash "$BIN_DIR/s9-fdmap" --leaks --threshold 0
bench "s9-fdmap --leaks --threshold 99999" 15 bash "$BIN_DIR/s9-fdmap" --leaks --threshold 99999
bench "s9-anomaly (full scan)"          20  bash "$BIN_DIR/s9-anomaly"
bench "s9-anomaly --json (full)"        20  bash "$BIN_DIR/s9-anomaly" --json
bench "s9-anomaly --zombies"            15  bash "$BIN_DIR/s9-anomaly" --zombies
bench "s9-anomaly --hogs"               15  bash "$BIN_DIR/s9-anomaly" --hogs
bench "s9-anomaly --states"             15  bash "$BIN_DIR/s9-anomaly" --states
bench "s9-anomaly --orphans"            15  bash "$BIN_DIR/s9-anomaly" --orphans
bench "s9-anomaly --gpu"                15  bash "$BIN_DIR/s9-anomaly" --gpu
bench "s9-anomaly all flags"            25  bash "$BIN_DIR/s9-anomaly" --zombies --hogs --states --orphans --gpu
bench "s9-anomaly --json all flags"     25  bash "$BIN_DIR/s9-anomaly" --json --zombies --hogs --states --orphans --gpu
bench "s9-anomaly zero thresholds"      20  bash "$BIN_DIR/s9-anomaly" --mem-threshold 0 --fd-threshold 0 --gpu-threshold 0
bench "s9-anomaly massive thresholds"   20  bash "$BIN_DIR/s9-anomaly" --mem-threshold 100 --fd-threshold 99999 --gpu-threshold 99999
bench "s9-gpu"                          10  bash "$BIN_DIR/s9-gpu"
bench "s9-gpu --json"                   10  bash "$BIN_DIR/s9-gpu" --json
bench "s9-gpu --quiet"                  10  bash "$BIN_DIR/s9-gpu" --quiet
bench "s9-gpu --threshold 0"            10  bash "$BIN_DIR/s9-gpu" --threshold 0
bench "s9-gpu --threshold 1"            10  bash "$BIN_DIR/s9-gpu" --threshold 1
bench "s9-gpu --threshold 1024"         10  bash "$BIN_DIR/s9-gpu" --threshold 1024
bench "s9-gpu --threshold 999999"       10  bash "$BIN_DIR/s9-gpu" --threshold 999999
bench "s9-compare $SELF $SELF"          20  bash "$BIN_DIR/s9-compare" $SELF $SELF
echo "  $(ist) -- single-run benchmarks done"
echo ""

# =============================================================================
echo "  [2] Repeated execution benchmarks (throughput)"
# =============================================================================
bench_repeat "s9-inspect --quiet"     10  5   bash "$BIN_DIR/s9-inspect" --quiet $SELF
bench_repeat "s9-inspect --json"      10  5   bash "$BIN_DIR/s9-inspect" --json $SELF
bench_repeat "s9-tree -d 1"           5   10  bash "$BIN_DIR/s9-tree" -d 1
bench_repeat "s9-fdmap --top 5"       5   10  bash "$BIN_DIR/s9-fdmap" --top 5
bench_repeat "s9-fdmap --json"        5   10  bash "$BIN_DIR/s9-fdmap" --json --top 5
bench_repeat "s9-anomaly --quiet"     5   15  bash "$BIN_DIR/s9-anomaly" --quiet
bench_repeat "s9-anomaly --json"      5   15  bash "$BIN_DIR/s9-anomaly" --json
bench_repeat "s9-gpu --quiet"         10  5   bash "$BIN_DIR/s9-gpu" --quiet
bench_repeat "s9-gpu --json"          5   5   bash "$BIN_DIR/s9-gpu" --json
bench_repeat "anomaly --gpu --quiet"  5   10  bash "$BIN_DIR/s9-anomaly" --gpu --quiet
echo "  $(ist) -- throughput benchmarks done"
echo ""

# =============================================================================
echo "  [3] Snapshot lifecycle stress"
# =============================================================================
SNAP_ITERS=10
snap_t0=$(date +%s%N)
snap_fail=0
for (( i=1; i<=SNAP_ITERS; i++ )); do
    timeout "$CMD_TIMEOUT" bash "$BIN_DIR/s9-snapshot" capture $SELF --name "stress_${i}" >/dev/null 2>&1 || ((snap_fail++))
done
snap_t1=$(date +%s%N)
snap_dur=$(( (snap_t1 - snap_t0) / 1000000 ))
if (( snap_fail == 0 )); then
    pass "Captured $SNAP_ITERS snapshots in ${snap_dur}ms (avg $(( snap_dur / SNAP_ITERS ))ms/snap)"
else
    fail "Snapshot capture loop" "$snap_fail capture(s) failed"
fi

bench "snapshot list (${SNAP_ITERS} snaps)"       5  bash "$BIN_DIR/s9-snapshot" list
bench "snapshot list --json (${SNAP_ITERS} snaps)" 5  bash "$BIN_DIR/s9-snapshot" list --json
bench "snapshot diff stress_1 vs stress_2"         10  bash "$BIN_DIR/s9-snapshot" diff stress_1 stress_2
bench "snapshot diff --json stress_1 vs stress_5"  10  bash "$BIN_DIR/s9-snapshot" diff stress_1 stress_5 --json
bench "snapshot diff stress_1 vs stress_10"        10  bash "$BIN_DIR/s9-snapshot" diff stress_1 "stress_${SNAP_ITERS}"

del_t0=$(date +%s%N)
del_fail=0
for (( i=1; i<=SNAP_ITERS; i++ )); do
    timeout "$CMD_TIMEOUT" bash "$BIN_DIR/s9-snapshot" delete "stress_${i}" --force >/dev/null 2>&1 || ((del_fail++))
done
del_t1=$(date +%s%N)
del_dur=$(( (del_t1 - del_t0) / 1000000 ))
if (( del_fail == 0 )); then
    pass "Deleted $SNAP_ITERS snapshots in ${del_dur}ms"
else
    fail "Snapshot delete loop" "$del_fail delete(s) failed"
fi
echo "  $(ist) -- snapshot stress done"
echo ""

# =============================================================================
echo "  [4] Deep JSON format validation"
# =============================================================================
# s9-inspect
for k in .pid .name .state .rss_kb .fd_count .threads .exe .cmdline .ppid .io_read_chars .io_write_chars .gpu_available; do
    json_key "inspect $k" "$k" bash "$BIN_DIR/s9-inspect" --json $SELF
done

# s9-fdmap
for k in .summary .stats .stats.total_processes .stats.total_fds .stats.system_allocated .stats.system_max; do
    json_key "fdmap $k" "$k" bash "$BIN_DIR/s9-fdmap" --json --top 1
done

# s9-tree
json_key "tree .pid"       ".pid"       bash "$BIN_DIR/s9-tree" --json --pid 1 -d 0
json_key "tree .name"      ".name"      bash "$BIN_DIR/s9-tree" --json --pid 1 -d 0
json_key "tree .children"  ".children"  bash "$BIN_DIR/s9-tree" --json --pid 1 -d 1

# s9-anomaly (each sub-scan)
json_key "anomaly .zombies"        ".zombies"        bash "$BIN_DIR/s9-anomaly" --json --zombies
json_key "anomaly .hogs"           ".hogs"           bash "$BIN_DIR/s9-anomaly" --json --hogs
json_key "anomaly .unusual_states" ".unusual_states" bash "$BIN_DIR/s9-anomaly" --json --states
json_key "anomaly .orphans"        ".orphans"        bash "$BIN_DIR/s9-anomaly" --json --orphans
json_key "anomaly .gpu"            ".gpu"            bash "$BIN_DIR/s9-anomaly" --json --gpu

# s9-snapshot diff
((TESTS_RUN++))
if timeout "$CMD_TIMEOUT" bash "$BIN_DIR/s9-snapshot" capture $SELF --name json_a >/dev/null 2>&1 &&
   timeout "$CMD_TIMEOUT" bash "$BIN_DIR/s9-snapshot" capture $SELF --name json_b >/dev/null 2>&1; then
    ((TESTS_PASSED++)); echo "    [OK] snapshot JSON setup captures created"
else
    ((TESTS_FAILED++)); echo "    [FAIL] snapshot JSON setup captures failed"
fi
for k in .memory.rss_before_kb .memory.rss_after_kb .memory.rss_diff_kb .resources.fd_before .resources.fd_after .assessment.memory_status; do
    json_key "snap diff $k" "$k" bash "$BIN_DIR/s9-snapshot" diff json_a json_b --json
done

# s9-gpu deep JSON
json_key "gpu .gpu_available" ".gpu_available" bash "$BIN_DIR/s9-gpu" --json
json_key "gpu .processes"     ".processes"     bash "$BIN_DIR/s9-gpu" --json
json_key "gpu .count"         ".count"         bash "$BIN_DIR/s9-gpu" --json
json_key "gpu .gpu_memory_used_mb" ".gpu_memory_used_mb" bash "$BIN_DIR/s9-gpu" --json

# If GPU exists, validate per-process fields
if command -v nvidia-smi >/dev/null 2>&1; then
    if ! command -v jq >/dev/null 2>&1; then
        skip "GPU per-process field validation (jq unavailable)"
    else
        gpu_json=$(timeout "$CMD_TIMEOUT" bash "$BIN_DIR/s9-gpu" --json 2>/dev/null)
        gpu_count=$(echo "$gpu_json" | jq -r '.count' 2>/dev/null || echo "0")
        if (( gpu_count > 0 )); then
            for k in .pid .name .gpu_index .gpu_name .gpu_memory_mb .pid_scope .gpu_process_type; do
                ((TESTS_RUN++))
                if echo "$gpu_json" | jq -e ".processes[0]$k" >/dev/null 2>&1; then
                    ((TESTS_PASSED++)); echo "    [OK] gpu process[0] has $k"
                else
                    ((TESTS_FAILED++)); echo "    [FAIL] gpu process[0] missing $k"
                fi
            done
            pass "GPU reports $gpu_count process(es)"
        else
            pass "GPU available but no processes currently using it"
        fi
    fi
fi

# s9-gpu quiet mode validation
((TESTS_RUN++))
gpu_quiet=$(timeout "$CMD_TIMEOUT" bash "$BIN_DIR/s9-gpu" --quiet 2>/dev/null)
if [[ "$gpu_quiet" =~ ^GPU_AVAILABLE= ]]; then
    ((TESTS_PASSED++)); echo "    [OK] gpu quiet has GPU_AVAILABLE="
else
    ((TESTS_FAILED++)); echo "    [FAIL] gpu quiet missing GPU_AVAILABLE="
fi

# s9-inspect GPU field
json_key "inspect .gpu_available" ".gpu_available" bash "$BIN_DIR/s9-inspect" --json $SELF

echo "  $(ist) -- JSON validation done"
echo ""

# =============================================================================
echo "  [5] Controlled CPU + real GPU workload"
# =============================================================================
if start_dummy_cpu_workload; then
    pass "Dummy CPU/FD workload started (PID=$DUMMY_CPU_PID)"
else
    fail "Dummy CPU/FD workload" "process did not stay alive"
fi

export DUMMY_CPU_PID DUMMY_CPU_FILE
if [[ -d "/proc/$DUMMY_CPU_PID" ]]; then
    json_assert_cmd "dummy inspect JSON targets live PID" '.pid == (env.DUMMY_CPU_PID | tonumber)' \
        bash "$BIN_DIR/s9-inspect" --json "$DUMMY_CPU_PID"
    json_assert_cmd "dummy inspect sees elevated FDs" '.fd_count >= 40' \
        bash "$BIN_DIR/s9-inspect" --json "$DUMMY_CPU_PID"
    bench "dummy inspect quiet" 10 bash "$BIN_DIR/s9-inspect" --quiet "$DUMMY_CPU_PID"
    bench_auto_export_json "dummy inspect" "inspect" 10 \
        bash "$BIN_DIR/s9-inspect" -e "$DUMMY_CPU_PID"

    json_assert_cmd "dummy tree JSON targets live PID" '.pid == (env.DUMMY_CPU_PID | tonumber)' \
        bash "$BIN_DIR/s9-tree" --json --pid "$DUMMY_CPU_PID" --depth 0
    bench_auto_export_json "dummy tree" "tree" 15 \
        bash "$BIN_DIR/s9-tree" -e --pid "$DUMMY_CPU_PID" --depth 0

    json_assert_cmd "dummy fdmap file search finds live PID" \
        '.count >= 1 and any(.processes[]; .pid == (env.DUMMY_CPU_PID | tonumber))' \
        bash "$BIN_DIR/s9-fdmap" --json --file "$DUMMY_CPU_FILE"
    bench_auto_export_json "dummy fdmap file search" "fdmap-file" 15 \
        bash "$BIN_DIR/s9-fdmap" -e --file "$DUMMY_CPU_FILE"

    json_assert_cmd "dummy fdmap leak search finds live PID" \
        'any(.leaks[]; .pid == (env.DUMMY_CPU_PID | tonumber) and .fd_count >= 40)' \
        bash "$BIN_DIR/s9-fdmap" --json --leaks --threshold 20
    bench_auto_export_json "dummy fdmap leak search" "fdmap-leaks" 15 \
        bash "$BIN_DIR/s9-fdmap" -e --leaks --threshold 20

    json_assert_cmd "dummy anomaly hog detects FD pressure" \
        'any(.hogs[]; .pid == (env.DUMMY_CPU_PID | tonumber) and (.issues | contains("HIGH-FDS")))' \
        bash "$BIN_DIR/s9-anomaly" --json --hogs --fd-threshold 20 --mem-threshold 100
    bench_auto_export_json "dummy anomaly hog" "anomaly-hogs" 20 \
        bash "$BIN_DIR/s9-anomaly" -e --hogs --fd-threshold 20 --mem-threshold 100

    bench_auto_export_json "dummy snapshot capture" "snapshot-capture" 10 \
        bash "$BIN_DIR/s9-snapshot" capture "$DUMMY_CPU_PID" --name stress_cpu_export -e
    timeout "$CMD_TIMEOUT" bash "$BIN_DIR/s9-snapshot" capture "$DUMMY_CPU_PID" --name stress_cpu_a >/dev/null 2>&1 || true
    timeout "$CMD_TIMEOUT" bash "$BIN_DIR/s9-snapshot" capture "$DUMMY_CPU_PID" --name stress_cpu_b >/dev/null 2>&1 || true
    bench_auto_export_json "dummy snapshot diff" "snapshot-diff" 10 \
        bash "$BIN_DIR/s9-snapshot" diff stress_cpu_a stress_cpu_b -e

    bench_auto_export_json "dummy compare" "compare" 20 \
        bash "$BIN_DIR/s9-compare" -e "$DUMMY_CPU_PID" "$DUMMY_CPU_PID"

    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
        if start_real_gpu_workload; then
            REAL_GPU_PROCESS_COUNT="${#REAL_GPU_PIDS[@]}"
            REAL_GPU_PIDS_STR="${REAL_GPU_PIDS[*]}"
            REAL_GPU_ALLOC_MBS_STR="${REAL_GPU_ALLOC_MBS[*]}"
            REAL_GPU_EXPECTED_MIN_MBS_STR="${REAL_GPU_EXPECTED_MIN_MBS[*]}"
            REAL_GPU_MATCH_MODES_STR="${REAL_GPU_MATCH_MODES[*]}"
            REAL_GPU_EXPECTED_TOTAL_MIN_MB=0
            for _min_mb in "${REAL_GPU_EXPECTED_MIN_MBS[@]}"; do
                REAL_GPU_EXPECTED_TOTAL_MIN_MB=$((REAL_GPU_EXPECTED_TOTAL_MIN_MB + _min_mb))
            done
            pass "Real CUDA GPU RAM stress workloads started (count=$REAL_GPU_PROCESS_COUNT, pids=$REAL_GPU_PIDS_STR, modes=$REAL_GPU_MATCH_MODES_STR, allocated=${REAL_GPU_ALLOC_MBS_STR}MB, mins=${REAL_GPU_EXPECTED_MIN_MBS_STR}MB)"
            export REAL_GPU_PROCESS_COUNT REAL_GPU_PIDS_STR REAL_GPU_ALLOC_MBS_STR REAL_GPU_EXPECTED_MIN_MBS_STR REAL_GPU_MATCH_MODES_STR REAL_GPU_EXPECTED_TOTAL_MIN_MB

            if [[ "$REAL_GPU_MATCH_MODES_STR" == *aggregate* ]]; then
                json_assert_cmd "real gpu aggregate memory visible in s9-gpu" \
                    '.gpu_available == true and (.gpu_memory_used_mb // 0) >= (env.REAL_GPU_EXPECTED_TOTAL_MIN_MB | tonumber)' \
                    bash "$BIN_DIR/s9-gpu" --json
            else
                json_assert_cmd "real gpu reports all stress processes" \
                    '(env.REAL_GPU_PIDS_STR | split(" ") | map(tonumber)) as $pids | ([.processes[]? | select(.pid as $pid | ($pids | index($pid)))] | length) == (env.REAL_GPU_PROCESS_COUNT | tonumber)' \
                    bash "$BIN_DIR/s9-gpu" --json
            fi
            bench_auto_export_json "real gpu workloads" "gpu" 10 bash "$BIN_DIR/s9-gpu" -e

            for gpu_i in "${!REAL_GPU_PIDS[@]}"; do
                REAL_GPU_PID="${REAL_GPU_PIDS[$gpu_i]}"
                REAL_GPU_ALLOC_MB="${REAL_GPU_ALLOC_MBS[$gpu_i]}"
                REAL_GPU_EXPECTED_MIN_MB="${REAL_GPU_EXPECTED_MIN_MBS[$gpu_i]}"
                REAL_GPU_MATCH_MODE="${REAL_GPU_MATCH_MODES[$gpu_i]}"
                export REAL_GPU_PID REAL_GPU_ALLOC_MB REAL_GPU_EXPECTED_MIN_MB

                if [[ "$REAL_GPU_MATCH_MODE" == "pid" ]]; then
                    json_assert_cmd "real gpu stress process $gpu_i visible in s9-gpu" \
                        '.gpu_available == true and any(.processes[]; .pid == (env.REAL_GPU_PID | tonumber) and .gpu_memory_mb >= (env.REAL_GPU_EXPECTED_MIN_MB | tonumber))' \
                        bash "$BIN_DIR/s9-gpu" --json
                    json_assert_cmd "real gpu stress process $gpu_i threshold include" \
                        'any(.processes[]; .pid == (env.REAL_GPU_PID | tonumber) and .gpu_memory_mb >= (env.REAL_GPU_EXPECTED_MIN_MB | tonumber))' \
                        bash "$BIN_DIR/s9-gpu" --json --threshold "$REAL_GPU_EXPECTED_MIN_MB"
                    json_assert_cmd "real gpu inspect maps stress process $gpu_i" \
                        '.gpu_available == true and .gpu_pid == (env.REAL_GPU_PID | tonumber) and .gpu_memory_mb >= (env.REAL_GPU_EXPECTED_MIN_MB | tonumber)' \
                        bash "$BIN_DIR/s9-inspect" --json "$REAL_GPU_PID"
                    json_assert_cmd "real gpu anomaly maps stress process $gpu_i" \
                        'any(.gpu[]; .pid == (env.REAL_GPU_PID | tonumber) and .gpu_memory_mb >= (env.REAL_GPU_EXPECTED_MIN_MB | tonumber))' \
                        bash "$BIN_DIR/s9-anomaly" --json --gpu --gpu-threshold "$REAL_GPU_EXPECTED_MIN_MB"
                else
                    json_assert_cmd "real gpu stress process $gpu_i aggregate memory visible" \
                        '.gpu_available == true and (.gpu_memory_used_mb // 0) >= (env.REAL_GPU_EXPECTED_MIN_MB | tonumber)' \
                        bash "$BIN_DIR/s9-gpu" --json
                    skip "real gpu inspect exact PID map $gpu_i (container GPU PID isolation)"
                    skip "real gpu anomaly exact PID map $gpu_i (container GPU PID isolation)"
                fi
            done

            json_assert_cmd "real gpu threshold excludes stress workloads" \
                '(env.REAL_GPU_PIDS_STR | split(" ") | map(tonumber)) as $pids | ([.processes[]? | select(.pid as $pid | ($pids | index($pid)))] | length) == 0' \
                bash "$BIN_DIR/s9-gpu" --json --threshold 999999
            bench_auto_export_json "real gpu primary inspect" "inspect" 10 \
                bash "$BIN_DIR/s9-inspect" -e "$REAL_GPU_PID"
            bench_auto_export_json "real gpu primary anomaly" "anomaly-gpu" 15 \
                bash "$BIN_DIR/s9-anomaly" -e --gpu --gpu-threshold "$REAL_GPU_EXPECTED_MIN_MB"
        else
            gpu_detail="real GPU workload failed to start"
            for gpu_log in "$STRESS_WORK_DIR"/real-gpu-*.log; do
                [[ -s "$gpu_log" ]] || continue
                gpu_detail="$gpu_detail; $(basename "$gpu_log"): $(head -3 "$gpu_log" | tr '\n' ' ')"
            done
            fail "Real CUDA GPU workload" "$gpu_detail"
        fi
    else
        pass "Real CUDA GPU workload skipped (nvidia-smi unavailable)"
    fi
fi
echo "  $(ist) -- controlled workload done"
echo ""

# =============================================================================
echo "  [6] Injection & defense tests"
# =============================================================================
expect_fail "inspect bad PID"            bash "$BIN_DIR/s9-inspect" 999999999
expect_fail "inspect non-numeric"        bash "$BIN_DIR/s9-inspect" "not-a-pid"
expect_fail "inspect semicolon inject"   bash "$BIN_DIR/s9-inspect" '1;rm -rf /'
expect_fail "inspect path traversal"     bash "$BIN_DIR/s9-inspect" "../../../etc/passwd"
expect_fail "inspect pipe inject"        bash "$BIN_DIR/s9-inspect" '1|cat /etc/shadow'
expect_fail "inspect backtick inject"    bash "$BIN_DIR/s9-inspect" '`whoami`'
expect_fail "tree --depth abc"           bash "$BIN_DIR/s9-tree" --depth abc
expect_fail "tree --pid (empty)"         bash "$BIN_DIR/s9-tree" --pid
expect_fail "fdmap --top abc"            bash "$BIN_DIR/s9-fdmap" --top abc
expect_fail "fdmap --threshold (empty)"  bash "$BIN_DIR/s9-fdmap" --threshold
expect_fail "snapshot diff missing"      bash "$BIN_DIR/s9-snapshot" diff no_1 no_2
expect_fail "snapshot delete missing"    bash "$BIN_DIR/s9-snapshot" delete nonexistent --force
expect_fail "compare bad PIDs"           bash "$BIN_DIR/s9-compare" 999999999 888888888
expect_fail "anomaly --mem-threshold (empty)" bash "$BIN_DIR/s9-anomaly" --mem-threshold
expect_fail "anomaly --fd-threshold abc"  bash "$BIN_DIR/s9-anomaly" --fd-threshold abc
expect_fail "gpu --threshold (empty)"    bash "$BIN_DIR/s9-gpu" --threshold
expect_fail "gpu --threshold abc"        bash "$BIN_DIR/s9-gpu" --threshold abc
expect_fail "gpu --bogus-flag"           bash "$BIN_DIR/s9-gpu" --bogus-flag
expect_fail "anomaly --gpu-threshold (empty)" bash "$BIN_DIR/s9-anomaly" --gpu-threshold
expect_fail "anomaly --gpu-threshold abc" bash "$BIN_DIR/s9-anomaly" --gpu-threshold abc
echo "  $(ist) -- defense tests done"
echo ""

# =============================================================================
echo "  [7] Concurrent execution stress"
# =============================================================================
# Launch tools in parallel, capture their PIDs, wait only on those PIDs
for round in 1 2 3; do
    r_t0=$(date +%s%N)
    timeout "$CMD_TIMEOUT" bash "$BIN_DIR/s9-inspect" --json $SELF  >/dev/null 2>&1 & c1=$!
    timeout "$CMD_TIMEOUT" bash "$BIN_DIR/s9-fdmap" --json --top 5  >/dev/null 2>&1 & c2=$!
    timeout "$CMD_TIMEOUT" bash "$BIN_DIR/s9-anomaly" --json        >/dev/null 2>&1 & c3=$!
    timeout "$CMD_TIMEOUT" bash "$BIN_DIR/s9-tree" --json -d 1      >/dev/null 2>&1 & c4=$!
    timeout "$CMD_TIMEOUT" bash "$BIN_DIR/s9-gpu" --json            >/dev/null 2>&1 & c5=$!
    wait_rc=0
    for child in "$c1" "$c2" "$c3" "$c4" "$c5"; do
        wait "$child" || wait_rc=1
    done
    r_t1=$(date +%s%N)
    r_dur=$(( (r_t1 - r_t0) / 1000000 ))
    if (( wait_rc == 0 )); then
        pass "Concurrent round $round (5 tools): ${r_dur}ms"
    else
        fail "Concurrent round $round" "one or more commands failed after ${r_dur}ms"
    fi
done

# GPU + anomaly concurrent
r_t0=$(date +%s%N)
timeout "$CMD_TIMEOUT" bash "$BIN_DIR/s9-gpu" --json           >/dev/null 2>&1 & c1=$!
timeout "$CMD_TIMEOUT" bash "$BIN_DIR/s9-anomaly" --json --gpu >/dev/null 2>&1 & c2=$!
timeout "$CMD_TIMEOUT" bash "$BIN_DIR/s9-fdmap" --json --top 3 >/dev/null 2>&1 & c3=$!
wait_rc=0
for child in "$c1" "$c2" "$c3"; do
    wait "$child" || wait_rc=1
done
r_t1=$(date +%s%N)
r_dur=$(( (r_t1 - r_t0) / 1000000 ))
if (( wait_rc == 0 )); then
    pass "GPU + anomaly + fdmap concurrent: ${r_dur}ms"
else
    fail "GPU + anomaly + fdmap concurrent" "one or more commands failed after ${r_dur}ms"
fi

echo "  $(ist) -- concurrent stress done"
echo ""

# =============================================================================
echo "────────────────────────────────────────────────────────────────"
echo ""
echo "Stress & Performance Benchmark Complete"
echo "  Finished: $(ist)"
echo "  Total:    $TESTS_RUN"
echo "  Passed:   $TESTS_PASSED"
echo "  Failed:   $TESTS_FAILED"
echo "  Skipped:  $TESTS_SKIPPED"
echo ""

if (( TESTS_FAILED > 0 )); then
    exit 1
elif [[ "${S9_FAIL_ON_SKIP:-0}" == "1" ]] && (( TESTS_SKIPPED > 0 )); then
    echo "Strict skip gate failed: S9_FAIL_ON_SKIP=1 and $TESTS_SKIPPED check(s) were skipped"
    exit 1
else
    exit 0
fi
