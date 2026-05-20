#!/usr/bin/env bash
#
# test_json.sh - Strict JSON output validation for Substrata9
#

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$TEST_DIR")"
BIN_DIR="$ROOT_DIR/bin"
WORK_DIR=$(mktemp -d)
SNAPSHOT_TEST_DIR="$WORK_DIR/snapshots"
mkdir -p "$SNAPSHOT_TEST_DIR"
export S9_SNAPSHOT_DIR="$SNAPSHOT_TEST_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

TEST_PID=$$
export TEST_PID
# shellcheck disable=SC2034
TEST_USER=$(id -un 2>/dev/null || whoami 2>/dev/null || echo root)
TESTS_RUN=0
TESTS_FAILED=0
TESTS_PASSED=0
SKIPPED=0
LAST_JSON="$WORK_DIR/last.json"
LAST_ERR="$WORK_DIR/last.err"

if command -v jq >/dev/null 2>&1; then
    JSON_VALIDATOR=(jq .)
    HAVE_JQ=true
elif command -v python3 >/dev/null 2>&1; then
    JSON_VALIDATOR=(python3 -m json.tool)
    HAVE_JQ=false
elif command -v python >/dev/null 2>&1; then
    JSON_VALIDATOR=(python -m json.tool)
    HAVE_JQ=false
else
    JSON_VALIDATOR=()
    HAVE_JQ=false
fi

pass() {
    echo "    [OK] $1"
    ((TESTS_PASSED++))
}

fail() {
    echo "    [FAIL] $1"
    [[ -s "$LAST_ERR" ]] && sed 's/^/      stderr: /' "$LAST_ERR" | head -5
    [[ -s "$LAST_JSON" ]] && sed 's/^/      json: /' "$LAST_JSON" | head -8
    ((TESTS_FAILED++))
}

skip() {
    echo "    [SKIP] $1"
    ((SKIPPED++))
}

validate_json() {
    local desc="$1"
    shift
    ((TESTS_RUN++))
    : > "$LAST_JSON"
    : > "$LAST_ERR"

    if ! "$@" > "$LAST_JSON" 2>"$LAST_ERR"; then
        fail "$desc command failed"
        return 1
    fi

    if (( ${#JSON_VALIDATOR[@]} == 0 )); then
        skip "$desc (no JSON validator available)"
        return 0
    fi

    if "${JSON_VALIDATOR[@]}" < "$LAST_JSON" >/dev/null 2>&1; then
        pass "$desc valid JSON"
    else
        fail "$desc invalid JSON"
        return 1
    fi
}

jq_assert() {
    local desc="$1"
    local expr="$2"
    ((TESTS_RUN++))
    if ! $HAVE_JQ; then
        skip "$desc (jq unavailable)"
        return 0
    fi
    if jq -e "$expr" "$LAST_JSON" >/dev/null 2>&1; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

validate_auto_export_json() {
    local desc="$1"
    local purpose="$2"
    shift 2
    local exported

    ((TESTS_RUN++))
    : > "$LAST_JSON"
    : > "$LAST_ERR"
    rm -f "$WORK_DIR"/s9-"$purpose"_*.json 2>/dev/null || true

    if ! (cd "$WORK_DIR" && "$@") > "$LAST_JSON" 2>"$LAST_ERR"; then
        fail "$desc command failed"
        return 1
    fi

    if (( ${#JSON_VALIDATOR[@]} == 0 )); then
        skip "$desc stdout (no JSON validator available)"
    elif "${JSON_VALIDATOR[@]}" < "$LAST_JSON" >/dev/null 2>&1; then
        pass "$desc stdout valid JSON"
    else
        fail "$desc stdout invalid JSON"
        return 1
    fi

    ((TESTS_RUN++))
    exported=$(ls "$WORK_DIR"/s9-"$purpose"_*.json 2>/dev/null | head -1 || true)
    if [[ -z "$exported" || ! -f "$exported" ]]; then
        fail "$desc export file missing"
        return 1
    fi

    if (( ${#JSON_VALIDATOR[@]} == 0 )); then
        skip "$desc export file (no JSON validator available)"
    elif "${JSON_VALIDATOR[@]}" < "$exported" >/dev/null 2>&1; then
        pass "$desc export file valid JSON"
    else
        fail "$desc export file invalid JSON"
        return 1
    fi
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
echo "JSON Tests"
echo ""

write_fake_nvidia_smi

echo "  [1] s9-inspect JSON"
validate_json "inspect" bash "$BIN_DIR/s9-inspect" --json "$TEST_PID"
jq_assert "inspect has pid" '.pid | type == "number"'
jq_assert "inspect has process identity" 'has("name") and has("state") and has("ppid") and has("threads")'
jq_assert "inspect has resource fields" 'has("rss_kb") and has("fd_count") and has("io_read_chars") and has("io_write_chars")'
jq_assert "inspect omits removed container field" 'has("container") | not'
jq_assert "inspect has GPU status fields" 'has("gpu_available") and has("gpu_memory_mb") and has("gpu_pid_scope") and has("gpu_memory_used_mb")'
validate_auto_export_json "inspect auto export" "inspect" bash "$BIN_DIR/s9-inspect" -e "$TEST_PID"
jq_assert "inspect auto export has pid" '.pid == (env.TEST_PID | tonumber)'

echo "  [2] s9-tree JSON"
validate_json "tree" bash "$BIN_DIR/s9-tree" --json --pid "$TEST_PID" --depth 0
jq_assert "tree has root fields" 'has("pid") and has("name") and has("state") and has("children")'
jq_assert "tree omits removed container field" 'has("container") | not'
validate_json "tree threads/no-memory/no-state" bash "$BIN_DIR/s9-tree" --json --pid "$TEST_PID" --depth 0 --threads --no-memory --no-state
validate_auto_export_json "tree auto export" "tree" bash "$BIN_DIR/s9-tree" -e --pid "$TEST_PID" --depth 0
jq_assert "tree auto export has root pid" '.pid == (env.TEST_PID | tonumber)'

echo "  [3] s9-fdmap JSON"
validate_json "fdmap summary" bash "$BIN_DIR/s9-fdmap" --json --top 5
jq_assert "fdmap summary shape" 'has("summary") and has("stats") and (.summary | type == "array")'
jq_assert "fdmap stats shape" '.stats | has("total_processes") and has("total_fds") and has("system_allocated") and has("system_max")'
validate_auto_export_json "fdmap auto export" "fdmap-summary" bash "$BIN_DIR/s9-fdmap" -e --top 5
jq_assert "fdmap auto export shape" 'has("summary") and has("stats")'
validate_json "fdmap file search" bash "$BIN_DIR/s9-fdmap" --json --file "$WORK_DIR/no-open-file"
jq_assert "fdmap file shape" 'has("target_file") and has("processes") and has("count")'
validate_json "fdmap socket search" bash "$BIN_DIR/s9-fdmap" --json --socket 65535
jq_assert "fdmap socket shape" 'has("target_port") and has("processes") and has("count")'
validate_json "fdmap socket leading zero" bash "$BIN_DIR/s9-fdmap" --json --socket 080
jq_assert "fdmap leading-zero port remains valid JSON" '.target_port == "080"'
validate_json "fdmap leaks" bash "$BIN_DIR/s9-fdmap" --json --leaks --threshold 999999
jq_assert "fdmap leaks shape" 'has("threshold") and has("leaks") and has("count")'

echo "  [4] s9-snapshot JSON"
snap_a="json_a_${TEST_PID}"
snap_b="json_b_${TEST_PID}"
validate_json "snapshot capture A" bash "$BIN_DIR/s9-snapshot" capture "$TEST_PID" --name "$snap_a" --json
jq_assert "snapshot capture has file" '.status == "success" and has("file") and has("pid")'
validate_json "snapshot capture B" bash "$BIN_DIR/s9-snapshot" capture "$TEST_PID" --name "$snap_b" --json
validate_json "snapshot list" bash "$BIN_DIR/s9-snapshot" list --json
jq_assert "snapshot list shape" 'has("snapshots") and (.snapshots | type == "array")'
validate_auto_export_json "snapshot list auto export" "snapshot-list" bash "$BIN_DIR/s9-snapshot" list -e
jq_assert "snapshot list auto export shape" 'has("snapshots") and (.snapshots | type == "array")'
validate_auto_export_json "snapshot leading auto export" "snapshot-list" bash "$BIN_DIR/s9-snapshot" -e list
jq_assert "snapshot leading auto export shape" 'has("snapshots") and (.snapshots | type == "array")'
validate_json "snapshot diff" bash "$BIN_DIR/s9-snapshot" diff "$snap_a" "$snap_b" --json
jq_assert "snapshot diff shape" 'has("memory") and has("resources") and has("assessment")'
validate_json "snapshot delete A" bash "$BIN_DIR/s9-snapshot" delete "$snap_a" --force --json
jq_assert "snapshot delete status" '.status == "deleted" and (.count >= 1)'
validate_json "snapshot delete B" bash "$BIN_DIR/s9-snapshot" delete "$snap_b" --force --json

echo "  [5] s9-anomaly JSON"
validate_json "anomaly all" bash "$BIN_DIR/s9-anomaly" --json
jq_assert "anomaly all shape" 'has("zombies") and has("hogs") and has("unusual_states") and has("orphans") and has("gpu")'
validate_auto_export_json "anomaly auto export" "anomaly-all" bash "$BIN_DIR/s9-anomaly" -e
jq_assert "anomaly auto export shape" 'has("zombies") and has("hogs") and has("unusual_states") and has("orphans") and has("gpu")'
validate_json "anomaly zombies" bash "$BIN_DIR/s9-anomaly" --json --zombies
jq_assert "anomaly zombies shape" 'has("zombies") and (has("hogs") | not)'
validate_json "anomaly hogs" bash "$BIN_DIR/s9-anomaly" --json --hogs --mem-threshold 100 --fd-threshold 999999
jq_assert "anomaly hogs shape" 'has("hogs")'
validate_json "anomaly states" bash "$BIN_DIR/s9-anomaly" --json --states
jq_assert "anomaly states shape" 'has("unusual_states")'
validate_json "anomaly orphans" bash "$BIN_DIR/s9-anomaly" --json --orphans
jq_assert "anomaly orphans shape" 'has("orphans")'
validate_json "anomaly gpu" bash "$BIN_DIR/s9-anomaly" --json --gpu --gpu-threshold 999999
jq_assert "anomaly gpu shape" 'has("gpu") and (.gpu | type == "array")'

echo "  [6] s9-gpu JSON"
export S9_NVIDIA_SMI="$WORK_DIR/no-such-nvidia-smi"
validate_json "gpu unavailable" bash "$BIN_DIR/s9-gpu" --json
jq_assert "gpu unavailable shape" '.gpu_available == false and (.processes | type == "array") and .count == 0'

export S9_NVIDIA_SMI="$FAKE_NVIDIA_SMI"
export S9_FAKE_GPU_PID="$TEST_PID"
export S9_FAKE_GPU_MEM=1536
unset S9_FAKE_GPU_EMPTY
unset S9_FAKE_GPU_BROKEN
unset S9_FAKE_GPU_MULTIPLE
unset S9_FAKE_GPU_COMMAS
unset S9_FAKE_GPU_MALFORMED
validate_json "gpu fake process" bash "$BIN_DIR/s9-gpu" --json
jq_assert "gpu fake process shape" '.gpu_available == true and .count == 1 and .processes[0].pid == (env.S9_FAKE_GPU_PID | tonumber)'
jq_assert "gpu fake process fields" '.processes[0] | has("name") and has("gpu_index") and has("gpu_name") and has("gpu_memory_mb") and has("pid_scope") and has("gpu_process_type")'
jq_assert "gpu fake aggregate memory field" 'has("gpu_memory_used_mb") and .gpu_memory_used_mb >= (env.S9_FAKE_GPU_MEM | tonumber)'
validate_auto_export_json "gpu auto export" "gpu" bash "$BIN_DIR/s9-gpu" -e
jq_assert "gpu auto export shape" '.gpu_available == true and .count == 1'
validate_json "gpu fake threshold excludes" bash "$BIN_DIR/s9-gpu" --json --threshold 999999
jq_assert "gpu fake threshold excludes" '.gpu_available == true and .count == 0 and (.processes | length == 0)'

export S9_FAKE_GPU_MULTIPLE=1
validate_json "gpu fake multiple processes" bash "$BIN_DIR/s9-gpu" --json
jq_assert "gpu fake multiple shape" '.gpu_available == true and .count == 2 and (.processes | length == 2) and .processes[1].pid == 67890 and .processes[1].gpu_index == 1'
validate_json "gpu fake multiple threshold filters" bash "$BIN_DIR/s9-gpu" --json --threshold 1000
jq_assert "gpu fake multiple threshold shape" '.gpu_available == true and .count == 1 and (.processes | length == 1) and .processes[0].gpu_memory_mb >= 1000'
validate_json "anomaly fake multiple gpu threshold" bash "$BIN_DIR/s9-anomaly" --json --gpu --gpu-threshold 1000
jq_assert "anomaly fake multiple gpu threshold shape" 'has("gpu") and has("gpu_memory_used_mb") and (.gpu | length == 1) and (.gpu[0] | has("pid_scope")) and .gpu[0].gpu_memory_mb >= 1000'
unset S9_FAKE_GPU_MULTIPLE

export S9_FAKE_GPU_COMMAS=1
validate_json "gpu fake comma names" bash "$BIN_DIR/s9-gpu" --json
jq_assert "gpu fake comma names shape" '.gpu_available == true and .count == 1 and .processes[0].name == "fake,worker gpu" and (.processes[0].gpu_name | contains("Substrata, Test GPU")) and ((.processes[0].name | contains("|")) | not) and ((.processes[0].gpu_name | contains("|")) | not)'
validate_json "inspect fake comma GPU" bash "$BIN_DIR/s9-inspect" --json "$TEST_PID"
jq_assert "inspect fake comma GPU fields" '.gpu_available == true and .gpu_process_name == "fake,worker gpu" and (.gpu_name | contains("Substrata, Test GPU"))'
unset S9_FAKE_GPU_COMMAS

export S9_FAKE_GPU_MALFORMED=1
validate_json "gpu malformed rows ignored" bash "$BIN_DIR/s9-gpu" --json
jq_assert "gpu malformed rows ignored shape" '.gpu_available == true and .count == 0 and (.processes | length == 0)'
unset S9_FAKE_GPU_MALFORMED

export S9_FAKE_GPU_BROKEN=1
validate_json "gpu broken smi" bash "$BIN_DIR/s9-gpu" --json
jq_assert "gpu broken smi shape" '.gpu_available == false and .count == 0 and (.processes | length == 0)'
unset S9_FAKE_GPU_BROKEN

export S9_FAKE_GPU_EMPTY=1
validate_json "gpu fake no processes" bash "$BIN_DIR/s9-gpu" --json
jq_assert "gpu fake no processes shape" '.gpu_available == true and .count == 0 and (.processes | length == 0)'

echo "  [7] s9-inspect with mocked GPU"
unset S9_FAKE_GPU_EMPTY
export S9_FAKE_GPU_PID="$TEST_PID"
export S9_FAKE_GPU_MEM=2048
validate_json "inspect fake GPU" bash "$BIN_DIR/s9-inspect" --json "$TEST_PID"
jq_assert "inspect fake GPU fields" '.gpu_available == true and .gpu_pid == (env.S9_FAKE_GPU_PID | tonumber) and .gpu_memory_mb == 2048 and has("gpu_pid_scope") and .gpu_memory_used_mb >= 2048'
unset S9_NVIDIA_SMI S9_FAKE_GPU_PID S9_FAKE_GPU_MEM S9_FAKE_GPU_EMPTY S9_FAKE_GPU_BROKEN S9_FAKE_GPU_MULTIPLE S9_FAKE_GPU_COMMAS S9_FAKE_GPU_MALFORMED

echo ""
echo "JSON Tests Complete"
echo "  Total:   $TESTS_RUN"
echo "  Passed:  $TESTS_PASSED"
echo "  Failed:  $TESTS_FAILED"
echo "  Skipped: $SKIPPED"
echo ""

if (( TESTS_FAILED > 0 )); then
    exit 1
elif [[ "${S9_FAIL_ON_SKIP:-0}" == "1" ]] && (( SKIPPED > 0 )); then
    echo "Strict skip gate failed: S9_FAIL_ON_SKIP=1 and $SKIPPED check(s) were skipped"
    exit 1
else
    exit 0
fi
