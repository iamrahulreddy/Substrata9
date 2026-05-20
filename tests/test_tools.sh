#!/usr/bin/env bash
#
# test_tools.sh - CLI matrix tests for Substrata9 tools
#
# Covers success paths, error paths, JSON/quiet/export modes, removed flags,
# snapshot isolation, and mocked GPU states. Helpers are array-safe so flags and
# values are never re-parsed through an unquoted string.
#

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$TEST_DIR")"
BIN_DIR="$ROOT_DIR/bin"
WORK_DIR=$(mktemp -d)
SNAPSHOT_TEST_DIR="$WORK_DIR/snapshots"
EXPORT_TEST_DIR="$WORK_DIR/exports"
mkdir -p "$SNAPSHOT_TEST_DIR" "$EXPORT_TEST_DIR"
export S9_SNAPSHOT_DIR="$SNAPSHOT_TEST_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

TEST_PID=$$
TEST_USER=$(id -un 2>/dev/null || whoami 2>/dev/null || echo root)
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

stdout_file="$WORK_DIR/stdout.txt"
stderr_file="$WORK_DIR/stderr.txt"

pass() {
    echo "    [OK] $1"
    ((TESTS_PASSED++))
}

fail() {
    echo "    [FAIL] $1"
    [[ -s "$stderr_file" ]] && sed 's/^/      stderr: /' "$stderr_file" | head -5
    [[ -s "$stdout_file" ]] && sed 's/^/      stdout: /' "$stdout_file" | head -5
    ((TESTS_FAILED++))
}

run_success() {
    local desc="$1"
    shift
    ((TESTS_RUN++))
    : > "$stdout_file"
    : > "$stderr_file"
    if "$@" >"$stdout_file" 2>"$stderr_file"; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

run_failure() {
    local desc="$1"
    shift
    ((TESTS_RUN++))
    : > "$stdout_file"
    : > "$stderr_file"
    if "$@" >"$stdout_file" 2>"$stderr_file"; then
        fail "$desc should have failed"
    else
        pass "$desc rejected"
    fi
}

assert_file() {
    local desc="$1"
    local file="$2"
    local min_bytes="${3:-1}"
    ((TESTS_RUN++))
    if [[ -f "$file" ]] && (( $(wc -c < "$file") >= min_bytes )); then
        pass "$desc"
    else
        fail "$desc missing or too small"
    fi
}

assert_no_ansi() {
    local desc="$1"
    local file="$2"
    ((TESTS_RUN++))
    local esc
    esc=$(printf '\033')
    if [[ -f "$file" ]] && ! grep -q "$esc" "$file" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc contains ANSI escapes"
    fi
}

assert_match() {
    local desc="$1"
    local regex="$2"
    local file="$3"
    ((TESTS_RUN++))
    if grep -Eq "$regex" "$file" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc did not match $regex"
    fi
}

run_auto_export_json() {
    local desc="$1"
    local purpose="$2"
    shift 2

    rm -f "$EXPORT_TEST_DIR"/s9-"$purpose"_*.json 2>/dev/null || true
    run_success "$desc" bash -c 'cd "$1" || exit 1; shift; "$@"' _ "$EXPORT_TEST_DIR" "$@"
    assert_match "$desc stdout is JSON" '^\{' "$stdout_file"

    local exported
    exported=$(ls "$EXPORT_TEST_DIR"/s9-"$purpose"_*.json 2>/dev/null | head -1 || true)
    assert_file "$desc auto export file" "$exported" 2
    assert_match "$desc export stderr" 'JSON exported to s9-' "$stderr_file"
}

write_fake_nvidia_smi() {
    FAKE_NVIDIA_SMI="$WORK_DIR/nvidia-smi"
    cat > "$FAKE_NVIDIA_SMI" <<'FAKE_NVIDIA_SMI'
#!/usr/bin/env bash
set -u
case "${1:-}" in
    --query-gpu=index)
        [[ "${S9_FAKE_GPU_BROKEN:-0}" == "1" ]] && exit 1
        if [[ "${S9_FAKE_GPU_MULTIPLE:-0}" == "1" ]]; then
            printf "0\n1\n"
        else
            echo "0"
        fi
        ;;
    --query-gpu=index,uuid,name)
        [[ "${S9_FAKE_GPU_BROKEN:-0}" == "1" ]] && exit 1
        if [[ "${S9_FAKE_GPU_MULTIPLE:-0}" == "1" ]]; then
            printf "0, GPU-fake-0, Substrata Test GPU\n1, GPU-fake-1, Substrata Backup GPU\n"
        elif [[ "${S9_FAKE_GPU_COMMAS:-0}" == "1" ]]; then
            echo "0, GPU-fake-0, Substrata, Test GPU | Pipe"
        else
            echo "0, GPU-fake-0, Substrata Test GPU"
        fi
        ;;
    --query-compute-apps=pid,process_name,gpu_uuid,used_memory)
        [[ "${S9_FAKE_GPU_BROKEN:-0}" == "1" ]] && exit 1
        [[ "${S9_FAKE_GPU_EMPTY:-0}" == "1" ]] && exit 0
        if [[ "${S9_FAKE_GPU_MALFORMED:-0}" == "1" ]]; then
            printf "not-a-pid, broken, GPU-fake-0, 999\n12345, missing-memory, GPU-fake-0\n"
        elif [[ "${S9_FAKE_GPU_MULTIPLE:-0}" == "1" ]]; then
            printf "%s, fake_gpu_process, GPU-fake-0, %s\n67890, second_gpu_process, GPU-fake-1, 512\n" "${S9_FAKE_GPU_PID:-12345}" "${S9_FAKE_GPU_MEM:-1536}"
        elif [[ "${S9_FAKE_GPU_COMMAS:-0}" == "1" ]]; then
            echo "${S9_FAKE_GPU_PID:-12345}, fake,worker|gpu, GPU-fake-0, ${S9_FAKE_GPU_MEM:-1536}"
        else
            echo "${S9_FAKE_GPU_PID:-12345}, fake_gpu_process, GPU-fake-0, ${S9_FAKE_GPU_MEM:-1536}"
        fi
        ;;
    --query-gpu=memory.used,memory.total)
        [[ "${S9_FAKE_GPU_BROKEN:-0}" == "1" ]] && exit 1
        echo "100, 16384"
        ;;
    --query-gpu=memory.used)
        [[ "${S9_FAKE_GPU_BROKEN:-0}" == "1" ]] && exit 1
        if [[ "${S9_FAKE_GPU_EMPTY:-0}" == "1" ]]; then
            echo "0"
        else
            echo "${S9_FAKE_GPU_MEM:-1536}"
        fi
        ;;
    *)
        exit 1
        ;;
esac
FAKE_NVIDIA_SMI
    chmod +x "$FAKE_NVIDIA_SMI"
}

echo ""
echo "CLI Matrix Tests"
echo ""

write_fake_nvidia_smi

echo "  [1] Help flags"
for tool in s9-inspect s9-tree s9-fdmap s9-snapshot s9-anomaly s9-compare s9-gpu; do
    run_success "$tool --help" bash "$BIN_DIR/$tool" --help
done

echo "  [2] s9-inspect"
run_success "inspect default" bash "$BIN_DIR/s9-inspect" "$TEST_PID"
assert_match "inspect default has identity section" 'PROCESS IDENTITY' "$stdout_file"
assert_match "inspect default has memory section" 'MEMORY' "$stdout_file"
assert_match "inspect default has fd section" 'FILE DESCRIPTORS' "$stdout_file"
assert_match "inspect default has signals section" 'SIGNALS' "$stdout_file"
assert_match "inspect default has limits section" 'RESOURCE LIMITS' "$stdout_file"
assert_match "inspect default has io section" 'I/O STATISTICS' "$stdout_file"
run_success "inspect --full" bash "$BIN_DIR/s9-inspect" --full "$TEST_PID"
assert_match "inspect --full has maps detail" 'Memory Regions' "$stdout_file"
run_success "inspect -f short flag" bash "$BIN_DIR/s9-inspect" -f "$TEST_PID"
run_success "inspect --json" bash "$BIN_DIR/s9-inspect" --json "$TEST_PID"
assert_match "inspect JSON has pid" '"pid"[[:space:]]*:' "$stdout_file"
assert_match "inspect JSON has rss" '"rss_kb"[[:space:]]*:' "$stdout_file"
assert_match "inspect JSON has fd count" '"fd_count"[[:space:]]*:' "$stdout_file"
run_success "inspect -j short flag" bash "$BIN_DIR/s9-inspect" -j "$TEST_PID"
assert_match "inspect -j JSON has pid" '"pid"[[:space:]]*:' "$stdout_file"
run_success "inspect --full --json combination" bash "$BIN_DIR/s9-inspect" --full --json "$TEST_PID"
assert_match "inspect --full --json has pid" '"pid"[[:space:]]*:' "$stdout_file"
run_success "inspect --quiet" bash "$BIN_DIR/s9-inspect" --quiet "$TEST_PID"
assert_match "inspect quiet shape" '^PID=[0-9]+ RSS=[0-9]+kB FDs=[0-9]+ STATE=.* THREADS=[0-9]+ GPU_MEM=[0-9]+MB$' "$stdout_file"
run_success "inspect -q short flag" bash "$BIN_DIR/s9-inspect" -q "$TEST_PID"
assert_match "inspect -q quiet shape" '^PID=[0-9]+ RSS=[0-9]+kB FDs=[0-9]+ STATE=.* THREADS=[0-9]+ GPU_MEM=[0-9]+MB$' "$stdout_file"
inspect_export="$EXPORT_TEST_DIR/inspect.txt"
run_success "inspect --export text" bash "$BIN_DIR/s9-inspect" "$TEST_PID" --export "$inspect_export"
assert_file "inspect export created" "$inspect_export" 100
assert_no_ansi "inspect export has no ANSI" "$inspect_export"
inspect_json_export="$EXPORT_TEST_DIR/inspect.json"
run_success "inspect --json --export" bash "$BIN_DIR/s9-inspect" --json "$TEST_PID" --export "$inspect_json_export"
assert_file "inspect JSON export created" "$inspect_json_export" 10
run_auto_export_json "inspect -e auto JSON export" "inspect" bash "$BIN_DIR/s9-inspect" -e "$TEST_PID"
run_failure "inspect missing export value" bash "$BIN_DIR/s9-inspect" "$TEST_PID" --export
run_failure "inspect multiple targets" bash "$BIN_DIR/s9-inspect" "$TEST_PID" "$TEST_PID"
run_failure "inspect -e conflicts with --export" bash "$BIN_DIR/s9-inspect" -e "$TEST_PID" --export "$EXPORT_TEST_DIR/conflict.json"
run_failure "inspect -e conflicts with quiet" bash "$BIN_DIR/s9-inspect" -e --quiet "$TEST_PID"
run_failure "inspect invalid PID" bash "$BIN_DIR/s9-inspect" 999999999
run_failure "inspect invalid name" bash "$BIN_DIR/s9-inspect" "not-a-pid-that-exists"
run_failure "inspect removed --env" bash "$BIN_DIR/s9-inspect" --env "$TEST_PID"

if [[ -x "$BIN_DIR/s9-inspect" ]]; then
    run_success "inspect direct executable" "$BIN_DIR/s9-inspect" "$TEST_PID"
    assert_match "inspect direct executable has identity" 'PROCESS IDENTITY' "$stdout_file"
    run_success "inspect direct executable --quiet" "$BIN_DIR/s9-inspect" --quiet "$TEST_PID"
    assert_match "inspect direct executable quiet shape" '^PID=[0-9]+ RSS=[0-9]+kB FDs=[0-9]+ STATE=.* THREADS=[0-9]+ GPU_MEM=[0-9]+MB$' "$stdout_file"
else
    echo "    [SKIP] inspect direct executable tests (not executable in this checkout)"
fi

echo "  [3] s9-tree"
run_success "tree default depth" bash "$BIN_DIR/s9-tree" --depth 1
run_success "tree --pid" bash "$BIN_DIR/s9-tree" --pid "$TEST_PID" --depth 0
run_success "tree --user" bash "$BIN_DIR/s9-tree" --user "$TEST_USER" --depth 1
run_success "tree --threads" bash "$BIN_DIR/s9-tree" --threads --depth 1
run_success "tree --no-memory" bash "$BIN_DIR/s9-tree" --no-memory --depth 1
run_success "tree --no-state" bash "$BIN_DIR/s9-tree" --no-state --depth 1
run_success "tree --json" bash "$BIN_DIR/s9-tree" --json --pid "$TEST_PID" --depth 0
tree_export="$EXPORT_TEST_DIR/tree.txt"
run_success "tree --export" bash "$BIN_DIR/s9-tree" --pid "$TEST_PID" --depth 0 --export "$tree_export"
assert_file "tree export created" "$tree_export" 10
assert_no_ansi "tree export has no ANSI" "$tree_export"
run_auto_export_json "tree -e auto JSON export" "tree" bash "$BIN_DIR/s9-tree" -e --pid "$TEST_PID" --depth 0
run_failure "tree -e conflicts with --export" bash "$BIN_DIR/s9-tree" -e --pid "$TEST_PID" --export "$EXPORT_TEST_DIR/conflict-tree.json"
run_failure "tree missing --pid value" bash "$BIN_DIR/s9-tree" --pid
run_failure "tree nonnumeric --pid" bash "$BIN_DIR/s9-tree" --pid abc
run_failure "tree missing --depth value" bash "$BIN_DIR/s9-tree" --depth
run_failure "tree nonnumeric --depth" bash "$BIN_DIR/s9-tree" --depth abc
run_failure "tree json user unsupported" bash "$BIN_DIR/s9-tree" --json --user "$TEST_USER"

echo "  [4] s9-fdmap"
run_success "fdmap default" bash "$BIN_DIR/s9-fdmap" --top 5
run_success "fdmap --quiet" bash "$BIN_DIR/s9-fdmap" --quiet
assert_match "fdmap quiet shape" '^PROCESSES=[0-9]+ TOTAL_FDS=[0-9]+' "$stdout_file"
run_failure "fdmap -e conflicts with quiet" bash "$BIN_DIR/s9-fdmap" -e --quiet
run_success "fdmap --json" bash "$BIN_DIR/s9-fdmap" --json --top 5
run_auto_export_json "fdmap -e auto JSON export" "fdmap-summary" bash "$BIN_DIR/s9-fdmap" -e --top 5
run_success "fdmap --leaks" bash "$BIN_DIR/s9-fdmap" --leaks --threshold 999999
run_success "fdmap --socket unused" bash "$BIN_DIR/s9-fdmap" --socket 65535
run_success "fdmap leading-zero socket" bash "$BIN_DIR/s9-fdmap" --json --socket 080
tmp_file="$WORK_DIR/open-file.txt"
: > "$tmp_file"
(sleep 5 > "$tmp_file") &
bg_pid=$!
sleep 0.2
run_success "fdmap --file" bash "$BIN_DIR/s9-fdmap" --file "$tmp_file"
kill "$bg_pid" 2>/dev/null || true
wait "$bg_pid" 2>/dev/null || true
run_failure "fdmap missing --top value" bash "$BIN_DIR/s9-fdmap" --top
run_failure "fdmap bad --top value" bash "$BIN_DIR/s9-fdmap" --top abc
run_failure "fdmap missing --threshold value" bash "$BIN_DIR/s9-fdmap" --threshold
run_failure "fdmap bad --threshold value" bash "$BIN_DIR/s9-fdmap" --threshold abc
run_failure "fdmap missing --socket value" bash "$BIN_DIR/s9-fdmap" --socket
run_failure "fdmap bad --socket value" bash "$BIN_DIR/s9-fdmap" --socket 70000

echo "  [5] s9-snapshot"
run_success "snapshot list empty/available" bash "$BIN_DIR/s9-snapshot" list
snap_a="tool_a_${TEST_PID}"
snap_b="tool_b_${TEST_PID}"
snap_c="tool_c_${TEST_PID}"
run_success "snapshot capture A" bash "$BIN_DIR/s9-snapshot" capture "$TEST_PID" --name "$snap_a"
run_success "snapshot capture B json" bash "$BIN_DIR/s9-snapshot" capture "$TEST_PID" --name "$snap_b" --json
run_auto_export_json "snapshot capture -e auto JSON export" "snapshot-capture" bash "$BIN_DIR/s9-snapshot" capture "$TEST_PID" --name "$snap_c" -e
((TESTS_RUN++))
if ls "$SNAPSHOT_TEST_DIR/${snap_a}"_*.snap >/dev/null 2>&1 && ls "$SNAPSHOT_TEST_DIR/${snap_b}"_*.snap >/dev/null 2>&1; then
    pass "snapshot files created"
else
    fail "snapshot files were not created"
fi
run_success "snapshot list json" bash "$BIN_DIR/s9-snapshot" list --json
run_auto_export_json "snapshot list -e auto JSON export" "snapshot-list" bash "$BIN_DIR/s9-snapshot" list -e
run_auto_export_json "snapshot leading -e list auto JSON export" "snapshot-list" bash "$BIN_DIR/s9-snapshot" -e list
run_success "snapshot diff text" bash "$BIN_DIR/s9-snapshot" diff "$snap_a" "$snap_b"
run_success "snapshot diff json" bash "$BIN_DIR/s9-snapshot" diff "$snap_a" "$snap_b" --json
run_auto_export_json "snapshot diff -e auto JSON export" "snapshot-diff" bash "$BIN_DIR/s9-snapshot" diff "$snap_a" "$snap_b" -e
run_success "snapshot delete force" bash "$BIN_DIR/s9-snapshot" delete "$snap_a" --force
run_success "snapshot delete json" bash "$BIN_DIR/s9-snapshot" delete "$snap_b" --force --json
run_failure "snapshot capture missing name" bash "$BIN_DIR/s9-snapshot" capture "$TEST_PID"
run_failure "snapshot capture bad pid" bash "$BIN_DIR/s9-snapshot" capture 999999999 --name bad
run_failure "snapshot empty sanitized name" bash "$BIN_DIR/s9-snapshot" capture "$TEST_PID" --name "///..."
run_failure "snapshot diff missing" bash "$BIN_DIR/s9-snapshot" diff missing_a missing_b
run_failure "snapshot delete missing" bash "$BIN_DIR/s9-snapshot" delete missing --force

echo "  [6] s9-anomaly"
run_success "anomaly full" bash "$BIN_DIR/s9-anomaly"
run_success "anomaly --quiet" bash "$BIN_DIR/s9-anomaly" --quiet
assert_match "anomaly quiet shape" '^ZOMBIES=[0-9]+ HOGS=[0-9]+ UNUSUAL_STATES=[0-9]+ ORPHANS=[0-9]+ GPU_PROCESSES=[0-9]+$' "$stdout_file"
run_failure "anomaly -e conflicts with quiet" bash "$BIN_DIR/s9-anomaly" -e --quiet
run_success "anomaly --json" bash "$BIN_DIR/s9-anomaly" --json
run_auto_export_json "anomaly -e auto JSON export" "anomaly-all" bash "$BIN_DIR/s9-anomaly" -e
run_success "anomaly --zombies" bash "$BIN_DIR/s9-anomaly" --zombies
run_success "anomaly --hogs" bash "$BIN_DIR/s9-anomaly" --hogs --mem-threshold 100 --fd-threshold 999999
run_success "anomaly --states" bash "$BIN_DIR/s9-anomaly" --states
run_success "anomaly --orphans" bash "$BIN_DIR/s9-anomaly" --orphans
run_success "anomaly --gpu" bash "$BIN_DIR/s9-anomaly" --gpu --gpu-threshold 999999
run_success "anomaly all selective json" bash "$BIN_DIR/s9-anomaly" --json --zombies --hogs --states --orphans --gpu
run_failure "anomaly missing mem threshold" bash "$BIN_DIR/s9-anomaly" --mem-threshold
run_failure "anomaly bad mem threshold" bash "$BIN_DIR/s9-anomaly" --mem-threshold abc
run_failure "anomaly missing fd threshold" bash "$BIN_DIR/s9-anomaly" --fd-threshold
run_failure "anomaly bad fd threshold" bash "$BIN_DIR/s9-anomaly" --fd-threshold abc
run_failure "anomaly missing gpu threshold" bash "$BIN_DIR/s9-anomaly" --gpu-threshold
run_failure "anomaly bad gpu threshold" bash "$BIN_DIR/s9-anomaly" --gpu-threshold abc

echo "  [7] s9-compare"
run_success "compare same pid" bash "$BIN_DIR/s9-compare" "$TEST_PID" "$TEST_PID"
run_success "compare same pid json" bash "$BIN_DIR/s9-compare" --json "$TEST_PID" "$TEST_PID"
run_auto_export_json "compare -e auto JSON export" "compare" bash "$BIN_DIR/s9-compare" -e "$TEST_PID" "$TEST_PID"
run_failure "compare missing args" bash "$BIN_DIR/s9-compare" "$TEST_PID"
run_failure "compare extra args" bash "$BIN_DIR/s9-compare" "$TEST_PID" "$TEST_PID" "$TEST_PID"
run_failure "compare bad pids" bash "$BIN_DIR/s9-compare" 999999999 888888888

echo "  [8] s9-gpu"
export S9_NVIDIA_SMI="$WORK_DIR/no-such-nvidia-smi"
run_success "gpu unavailable text" bash "$BIN_DIR/s9-gpu"
run_success "gpu unavailable json" bash "$BIN_DIR/s9-gpu" --json
assert_match "gpu unavailable json false" '"gpu_available"[[:space:]]*:[[:space:]]*false' "$stdout_file"
run_success "gpu unavailable quiet" bash "$BIN_DIR/s9-gpu" --quiet
assert_match "gpu unavailable quiet shape" '^GPU_AVAILABLE=false GPU_PROCESSES=0 GPU_MEMORY_USED_MB=0$' "$stdout_file"

export S9_NVIDIA_SMI="$FAKE_NVIDIA_SMI"
export S9_FAKE_GPU_PID="$TEST_PID"
export S9_FAKE_GPU_MEM=1536
unset S9_FAKE_GPU_EMPTY
unset S9_FAKE_GPU_BROKEN
unset S9_FAKE_GPU_MULTIPLE
unset S9_FAKE_GPU_COMMAS
unset S9_FAKE_GPU_MALFORMED
run_success "gpu fake text" bash "$BIN_DIR/s9-gpu"
run_success "gpu fake json" bash "$BIN_DIR/s9-gpu" --json
assert_match "gpu fake json available" '"gpu_available"[[:space:]]*:[[:space:]]*true' "$stdout_file"
assert_match "gpu fake json count" '"count"[[:space:]]*:[[:space:]]*1' "$stdout_file"
run_auto_export_json "gpu -e auto JSON export" "gpu" bash "$BIN_DIR/s9-gpu" -e
run_success "gpu fake quiet" bash "$BIN_DIR/s9-gpu" --quiet
assert_match "gpu fake quiet shape" '^GPU_AVAILABLE=true GPU_PROCESSES=1 GPU_MEMORY_USED_MB=[0-9]+$' "$stdout_file"
run_failure "gpu -e conflicts with quiet" bash "$BIN_DIR/s9-gpu" -e --quiet
run_success "anomaly fake gpu quiet threshold exclude" bash "$BIN_DIR/s9-anomaly" --gpu --quiet --gpu-threshold 999999
assert_match "anomaly fake gpu quiet threshold shape" '^ZOMBIES=0 HOGS=0 UNUSUAL_STATES=0 ORPHANS=0 GPU_PROCESSES=0$' "$stdout_file"
run_success "gpu threshold include" bash "$BIN_DIR/s9-gpu" --threshold 1000 --json
assert_match "gpu threshold include count" '"count"[[:space:]]*:[[:space:]]*1' "$stdout_file"
run_success "gpu threshold exclude" bash "$BIN_DIR/s9-gpu" --threshold 999999 --json
assert_match "gpu threshold exclude count" '"count"[[:space:]]*:[[:space:]]*0' "$stdout_file"
run_success "anomaly fake gpu text" bash "$BIN_DIR/s9-anomaly" --gpu --gpu-threshold 1000
run_success "anomaly fake gpu json" bash "$BIN_DIR/s9-anomaly" --json --gpu --gpu-threshold 1000
assert_match "anomaly fake gpu json section" '"gpu"[[:space:]]*:' "$stdout_file"

if [[ -x "$BIN_DIR/s9-gpu" ]]; then
    run_success "gpu direct executable json" "$BIN_DIR/s9-gpu" --json
    assert_match "gpu direct executable count" '"count"[[:space:]]*:[[:space:]]*1' "$stdout_file"
else
    echo "    [SKIP] gpu direct executable tests (not executable in this checkout)"
fi

export S9_FAKE_GPU_MULTIPLE=1
run_success "gpu fake multiple json" bash "$BIN_DIR/s9-gpu" --json
assert_match "gpu fake multiple count" '"count"[[:space:]]*:[[:space:]]*2' "$stdout_file"
assert_match "gpu fake multiple second process" 'second_gpu_process' "$stdout_file"
run_success "gpu fake multiple threshold filters" bash "$BIN_DIR/s9-gpu" --threshold 1000 --json
assert_match "gpu fake multiple threshold count" '"count"[[:space:]]*:[[:space:]]*1' "$stdout_file"
run_success "anomaly fake multiple gpu quiet threshold include" bash "$BIN_DIR/s9-anomaly" --gpu --quiet --gpu-threshold 1000
assert_match "anomaly fake multiple gpu quiet count" '^ZOMBIES=0 HOGS=0 UNUSUAL_STATES=0 ORPHANS=0 GPU_PROCESSES=1$' "$stdout_file"
unset S9_FAKE_GPU_MULTIPLE

export S9_FAKE_GPU_COMMAS=1
run_success "gpu comma/pipe names json" bash "$BIN_DIR/s9-gpu" --json
assert_match "gpu comma process name preserved" 'fake,worker gpu' "$stdout_file"
assert_match "gpu comma gpu name preserved" 'Substrata, Test GPU' "$stdout_file"
run_success "inspect comma/pipe fake GPU" bash "$BIN_DIR/s9-inspect" --json "$TEST_PID"
assert_match "inspect comma process name preserved" 'fake,worker gpu' "$stdout_file"
assert_match "inspect comma gpu name preserved" 'Substrata, Test GPU' "$stdout_file"
unset S9_FAKE_GPU_COMMAS

export S9_FAKE_GPU_MALFORMED=1
run_success "gpu malformed rows ignored" bash "$BIN_DIR/s9-gpu" --json
assert_match "gpu malformed rows count" '"count"[[:space:]]*:[[:space:]]*0' "$stdout_file"
run_success "gpu malformed rows quiet" bash "$BIN_DIR/s9-gpu" --quiet
assert_match "gpu malformed rows quiet shape" '^GPU_AVAILABLE=true GPU_PROCESSES=0 GPU_MEMORY_USED_MB=[0-9]+$' "$stdout_file"
unset S9_FAKE_GPU_MALFORMED

export S9_FAKE_GPU_BROKEN=1
run_success "gpu broken smi json" bash "$BIN_DIR/s9-gpu" --json
assert_match "gpu broken smi unavailable" '"gpu_available"[[:space:]]*:[[:space:]]*false' "$stdout_file"
assert_match "gpu broken smi count" '"count"[[:space:]]*:[[:space:]]*0' "$stdout_file"
unset S9_FAKE_GPU_BROKEN

export S9_FAKE_GPU_EMPTY=1
run_success "gpu fake no processes" bash "$BIN_DIR/s9-gpu" --json
assert_match "gpu fake no process count" '"count"[[:space:]]*:[[:space:]]*0' "$stdout_file"
run_failure "gpu missing threshold" bash "$BIN_DIR/s9-gpu" --threshold
run_failure "gpu bad threshold" bash "$BIN_DIR/s9-gpu" --threshold abc
run_failure "gpu bogus flag" bash "$BIN_DIR/s9-gpu" --bogus
unset S9_NVIDIA_SMI S9_FAKE_GPU_PID S9_FAKE_GPU_MEM S9_FAKE_GPU_EMPTY S9_FAKE_GPU_BROKEN S9_FAKE_GPU_MULTIPLE S9_FAKE_GPU_COMMAS S9_FAKE_GPU_MALFORMED

echo "  [9] bin/bc fallback"
run_success "bc arithmetic" bash "$BIN_DIR/bc" <<< "1+1"
assert_match "bc arithmetic output" '^2$' "$stdout_file"
run_success "bc scale" bash "$BIN_DIR/bc" <<< "scale=2; 3/2"
assert_match "bc scale output" '^1\.50$' "$stdout_file"
run_success "bc comparison" bash "$BIN_DIR/bc" <<< "5>=3"
assert_match "bc comparison output" '^1$' "$stdout_file"
run_success "bc whitespace" bash "$BIN_DIR/bc" <<< $'1\n+\n1'
assert_match "bc whitespace output" '^2$' "$stdout_file"
run_success "bc negative result" bash "$BIN_DIR/bc" <<< "2-5"
assert_match "bc negative output" '^-3$' "$stdout_file"
run_failure "bc rejects command expression" bash "$BIN_DIR/bc" <<< 'system("id")'
run_failure "bc rejects letters" bash "$BIN_DIR/bc" <<< "sqrt(4)"
run_failure "bc rejects semicolon command" bash "$BIN_DIR/bc" <<< '1; system("id")'

echo ""
echo "CLI Matrix Complete"
echo "  Total:  $TESTS_RUN"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo ""

if (( TESTS_FAILED > 0 )); then
    exit 1
else
    exit 0
fi
