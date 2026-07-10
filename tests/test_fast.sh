#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CUDO="$ROOT_DIR/cudo"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cudo-fast.XXXXXX")"
FAKE_BIN="$TMP_DIR/bin"
GLOBAL_DIR="$TMP_DIR/global"
PROJECT_DIR="$TMP_DIR/project"
LEGACY_PROJECT_DIR="$TMP_DIR/legacy-project"
DOCKER_LOG="$TMP_DIR/docker.log"

PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

log_info() { printf '[INFO] %s\n' "$1"; }
log_pass() { printf '[PASS] %s\n' "$1"; }
log_fail() { printf '[FAIL] %s\n' "$1"; }

test_case() {
    local name=$1
    shift

    log_info "$name"
    if "$@"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        log_pass "$name"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log_fail "$name"
    fi
}

assert_file_exists() {
    [ -f "$1" ] || {
        printf 'Expected file to exist: %s\n' "$1" >&2
        return 1
    }
}

assert_contains() {
    local file=$1
    local pattern=$2

    grep -Eq "$pattern" "$file" || {
        printf 'Expected %s to match pattern: %s\n' "$file" "$pattern" >&2
        return 1
    }
}

assert_not_contains() {
    local file=$1
    local pattern=$2

    if grep -Eq "$pattern" "$file"; then
        printf 'Expected %s not to match pattern: %s\n' "$file" "$pattern" >&2
        return 1
    fi
}

config_value() {
    local config_file=$1
    local key=$2

    grep -m1 "^${key}=" "$config_file" 2>/dev/null | cut -d'=' -f2-
}

set_config_value() {
    local config_file=$1
    local key=$2
    local value=$3
    local tmp_file="${config_file}.tmp.$$"

    if grep -q "^${key}=" "$config_file"; then
        awk -v key="$key" -v value="$value" '
            BEGIN { prefix = key "=" }
            index($0, prefix) == 1 { print prefix value; next }
            { print }
        ' "$config_file" > "$tmp_file"
        mv "$tmp_file" "$config_file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$config_file"
    fi
}

encode_b64() {
    printf '%s' "$1" | base64 | tr -d '\n'
}

decode_b64() {
    local value=$1

    if base64 --help 2>&1 | grep -q -- '--decode'; then
        printf '%s' "$value" | base64 --decode
    elif base64 -d </dev/null >/dev/null 2>&1; then
        printf '%s' "$value" | base64 -d
    else
        printf '%s' "$value" | base64 -D
    fi
}

cudo_fast() {
    PATH="$FAKE_BIN:$PATH" \
    CUDO_GLOBAL_CONFIG_DIR="$GLOBAL_DIR" \
    CUDO_FAKE_DOCKER_LOG="$DOCKER_LOG" \
    "$CUDO" "$@"
}

make_fake_tools() {
    mkdir -p "$FAKE_BIN"

    cat > "$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log_file="${CUDO_FAKE_DOCKER_LOG:-/tmp/cudo-fake-docker.log}"
printf '%s\n' "$*" >> "$log_file"

if [ "$#" -eq 0 ]; then
    exit 0
fi

case "$1" in
    --version|version)
        echo "Docker version 99.0.0, build cudo-test"
        ;;
    info)
        if [ "${2:-}" = "--format" ]; then
            echo '{"nvidia":{"path":"nvidia-container-runtime"}}'
        else
            echo "Fake Docker daemon"
        fi
        ;;
    compose)
        case "${2:-}" in
            version)
                echo "Docker Compose version v2.99.0"
                ;;
            build|up|stop|restart|down|logs)
                if [ "${2:-}" = "up" ] && [ "${CUDO_FAKE_COMPOSE_FAIL:-false}" = "true" ]; then
                    exit 1
                fi
                ;;
            *)
                ;;
        esac
        ;;
    image)
        if [ "${2:-}" = "inspect" ]; then
            if printf '%s\n' "$*" | grep -q -- '--format'; then
                echo "sha256:cudo-test"
            fi
        fi
        ;;
    pull)
        echo "Pulled ${2:-image}"
        ;;
    ps)
        if printf '%s\n' "$*" | grep -q -- '--format'; then
            if [ "${CUDO_FAKE_CONTAINER_RUNNING:-false}" = "true" ]; then
                printf '%s\tUp 1 minute\n' "${CUDO_FAKE_CONTAINER_NAME:-cudo-container}"
            fi
            exit 0
        fi
        echo "CONTAINER ID   IMAGE   COMMAND   CREATED   STATUS   PORTS   NAMES"
        ;;
    exec)
        if printf '%s\n' "$*" | grep -q 'pgrep -x sshd' && [ "${CUDO_FAKE_SSHD_RUNNING:-false}" = "true" ]; then
            exit 0
        fi
        ;;
    stats|inspect|images|rm|rmi|commit|run)
        ;;
    *)
        ;;
esac
EOF
    chmod +x "$FAKE_BIN/docker"

    cat > "$FAKE_BIN/envsubst" <<'EOF'
#!/usr/bin/env bash
cat
EOF
    chmod +x "$FAKE_BIN/envsubst"

    cat > "$FAKE_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$FAKE_BIN/sleep"
}

global_config_for_hash() {
    local config_file=$1
    local hash

    hash=$(config_value "$config_file" "UNIQUE_HASH")
    find "$GLOBAL_DIR" -name '*.conf' -exec grep -l "^UNIQUE_HASH=${hash}$" {} \; 2>/dev/null | head -1
}

assert_sha512_hash_b64() {
    local hash_b64=$1
    local decoded

    [ -n "$hash_b64" ] || {
        printf 'Expected non-empty password hash\n' >&2
        return 1
    }

    decoded=$(decode_b64 "$hash_b64")
    case "$decoded" in
        \$6\$*)
            return 0
            ;;
        *)
            printf 'Expected SHA-512 crypt hash, got: %s\n' "$decoded" >&2
            return 1
            ;;
    esac
}

syntax_checks() {
    bash -n "$CUDO"
    bash -n "$SCRIPT_DIR/run_all_tests.sh"
    bash -n "$SCRIPT_DIR/test_fast.sh"
    python3 -m py_compile "$ROOT_DIR/scripts/cuda-env-list-simple.py"
    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck "$CUDO" "$SCRIPT_DIR"/*.sh
    fi
}

doctor_is_read_only_without_global_dir() {
    local missing_global="$TMP_DIR/new-global"
    local output="$TMP_DIR/doctor-read-only.out"

    rm -rf "$missing_global"
    (
        cd "$TMP_DIR"
        PATH="$FAKE_BIN:$PATH" \
        CUDO_GLOBAL_CONFIG_DIR="$missing_global" \
        CUDO_FAKE_DOCKER_LOG="$DOCKER_LOG" \
        "$CUDO" doctor
    ) > "$output"

    [ ! -e "$missing_global" ] || {
        printf 'doctor created global config directory: %s\n' "$missing_global" >&2
        return 1
    }
    assert_contains "$output" '^Cudo doctor$'
    assert_contains "$output" 'Global config directory does not exist yet'
}

build_has_no_default_ssh_port() {
    mkdir -p "$GLOBAL_DIR" "$PROJECT_DIR"

    cd "$PROJECT_DIR"
    cudo_fast build --name fast -c 12.4 -p 3.10 > "$TMP_DIR/build.out"

    local config_file="$PROJECT_DIR/.cudo/config"
    assert_file_exists "$config_file"
    assert_contains "$config_file" '^SSH_ENABLED=true$'
    assert_contains "$config_file" '^SSH_PORT=$'
    assert_contains "$config_file" '^SSH_PASSWORD_HASH_B64=$'
    assert_not_contains "$config_file" '^SSH_PASSWORD_B64='

    cudo_fast list > "$TMP_DIR/list-no-ssh.out"
    assert_contains "$TMP_DIR/list-no-ssh.out" '^.*SSH.*$'
    assert_contains "$TMP_DIR/list-no-ssh.out" 'fast'
    assert_contains "$TMP_DIR/list-no-ssh.out" '[[:space:]]-[[:space:]]'
}

runtime_password_is_hashed() {
    local config_file="$PROJECT_DIR/.cudo/config"
    local global_config
    local hash_b64
    local secret="s3cret-pass"
    local secret_b64

    cd "$PROJECT_DIR"
    cudo_fast start --ssh-port 2222 --ssh-password "$secret" > "$TMP_DIR/start-ssh.out"

    assert_contains "$config_file" '^SSH_PORT=2222$'
    assert_not_contains "$config_file" '^SSH_PASSWORD_B64='
    assert_not_contains "$config_file" "$secret"

    secret_b64=$(encode_b64 "$secret")
    assert_not_contains "$config_file" "$secret_b64"

    hash_b64=$(config_value "$config_file" "SSH_PASSWORD_HASH_B64")
    assert_sha512_hash_b64 "$hash_b64"

    global_config=$(global_config_for_hash "$config_file")
    assert_file_exists "$global_config"
    assert_contains "$global_config" '^SSH_PORT=2222$'
    assert_contains "$global_config" '^SSH_PASSWORD_HASH_B64='
}

run_and_enter_can_update_ssh_port() {
    local config_file="$PROJECT_DIR/.cudo/config"

    cd "$PROJECT_DIR"
    cudo_fast run --ssh-port 2223 > "$TMP_DIR/run-ssh.out"
    assert_contains "$config_file" '^SSH_PORT=2223$'

    cudo_fast enter fast --ssh-port 2224 -- true > "$TMP_DIR/enter-ssh.out"
    assert_contains "$config_file" '^SSH_PORT=2224$'
}

list_shows_configured_ssh_port() {
    cudo_fast list > "$TMP_DIR/list-with-ssh.out"
    assert_contains "$TMP_DIR/list-with-ssh.out" '^.*SSH.*$'
    assert_contains "$TMP_DIR/list-with-ssh.out" 'fast'
    assert_contains "$TMP_DIR/list-with-ssh.out" '2224'
}

legacy_password_b64_migrates_to_hash() {
    local config_file="$LEGACY_PROJECT_DIR/.cudo/config"
    local legacy_b64
    local hash_b64

    mkdir -p "$LEGACY_PROJECT_DIR"
    cd "$LEGACY_PROJECT_DIR"
    cudo_fast build --name legacy -c 12.4 -p 3.10 > "$TMP_DIR/legacy-build.out"

    legacy_b64=$(encode_b64 "old-pass")
    set_config_value "$config_file" "SSH_PORT" "2240"
    set_config_value "$config_file" "SSH_PASSWORD_HASH_B64" ""
    set_config_value "$config_file" "SSH_PASSWORD_B64" "$legacy_b64"

    cudo_fast start --ssh-port 2241 > "$TMP_DIR/legacy-start.out"

    assert_contains "$config_file" '^SSH_PORT=2241$'
    assert_not_contains "$config_file" '^SSH_PASSWORD_B64='
    hash_b64=$(config_value "$config_file" "SSH_PASSWORD_HASH_B64")
    assert_sha512_hash_b64 "$hash_b64"
}

doctor_reports_hashed_project_password() {
    local output="$TMP_DIR/doctor-project.out"

    cd "$PROJECT_DIR"
    cudo_fast doctor > "$output"

    assert_contains "$output" '^Cudo doctor$'
    assert_contains "$output" 'SSH password is stored as a SHA-512 hash'
    assert_contains "$output" 'Doctor summary: 0 fail'
}

config_is_not_executed() {
    local config_file="$PROJECT_DIR/.cudo/config"
    local marker="$TMP_DIR/config-executed"

    printf 'UNTRUSTED=$(touch %s)\n' "$marker" >> "$config_file"
    cd "$PROJECT_DIR"
    cudo_fast config > "$TMP_DIR/config-safe.out"
    [ ! -e "$marker" ] || {
        printf 'Configuration file was executed as shell code\n' >&2
        return 1
    }
}

secure_password_inputs_work() {
    local config_file="$PROJECT_DIR/.cudo/config"
    local password_file="$TMP_DIR/ssh-password"
    printf '%s\n' 'stdin-secret' | (cd "$PROJECT_DIR" && cudo_fast start --ssh-port 2250 --ssh-password-stdin) > "$TMP_DIR/stdin-password.out"
    assert_not_contains "$config_file" 'stdin-secret' || return 1

    printf '%s\n' 'file-secret' > "$password_file"
    cd "$PROJECT_DIR"
    cudo_fast ssh passwd --ssh-password-file "$password_file" > "$TMP_DIR/file-password.out"
    assert_not_contains "$config_file" 'file-secret'
}

ssh_lifecycle_commands_work() {
    local config_file="$PROJECT_DIR/.cudo/config"
    local container_name

    cd "$PROJECT_DIR"
    cudo_fast ssh status > "$TMP_DIR/ssh-status.out"
    assert_contains "$TMP_DIR/ssh-status.out" '^SSH: enabled$' || return 1
    container_name="cuda-project-$(config_value "$config_file" "UNIQUE_HASH")-container"
    if CUDO_FAKE_CONTAINER_RUNNING=true CUDO_FAKE_CONTAINER_NAME="$container_name" CUDO_FAKE_SSHD_RUNNING=true \
        cudo_fast ssh disable > "$TMP_DIR/ssh-disable-failed.out" 2>&1; then
        printf 'SSH disable reported success while sshd was still running\n' >&2
        return 1
    fi
    assert_contains "$config_file" '^SSH_ENABLED=true$' || return 1
    assert_contains "$config_file" '^SSH_PASSWORD_HASH_B64=.+$' || return 1
    cudo_fast ssh disable > "$TMP_DIR/ssh-disable.out"
    assert_contains "$config_file" '^SSH_ENABLED=false$' || return 1
    assert_contains "$config_file" '^SSH_PORT=$' || return 1
    assert_not_contains "$config_file" '^SSH_PASSWORD_HASH_B64=' || return 1
    cudo_fast ssh status > "$TMP_DIR/ssh-disabled-status.out"
    assert_contains "$TMP_DIR/ssh-disabled-status.out" '^SSH: disabled$' || return 1
    if cudo_fast ssh enable --port > "$TMP_DIR/ssh-missing-port.out" 2>&1; then
        printf 'SSH enable accepted a missing port value\n' >&2
        return 1
    fi
}

gpu_selection_is_persisted() {
    local config_file="$PROJECT_DIR/.cudo/config"
    local compose_file="$PROJECT_DIR/.cudo/docker-compose.yml"

    cd "$PROJECT_DIR"
    cudo_fast start --gpus 0,1 > "$TMP_DIR/gpus.out"
    assert_contains "$config_file" '^GPUS=0,1$' || return 1
    assert_contains "$compose_file" 'NVIDIA_VISIBLE_DEVICES=0,1' || return 1
    if cudo_fast start --gpus bad > "$TMP_DIR/gpus-invalid.out" 2>&1; then
        printf 'Invalid GPU selection was accepted\n' >&2
        return 1
    fi
}

doctor_json_and_all_work() {
    local config_file="$PROJECT_DIR/.cudo/config"
    local global_config
    global_config=$(global_config_for_hash "$config_file")
    set_config_value "$global_config" "ENV_NAME" $'fast\tjson'
    cd "$PROJECT_DIR"
    cudo_fast doctor --all --json > "$TMP_DIR/doctor.json"
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "checks" in d and isinstance(d["checks"], list)' "$TMP_DIR/doctor.json"
    set_config_value "$global_config" "ENV_NAME" "fast"
}

failed_start_rolls_back_ssh_config() {
    local config_file="$PROJECT_DIR/.cudo/config"

    cd "$PROJECT_DIR"
    if CUDO_FAKE_COMPOSE_FAIL=true cudo_fast start --gpus all --ssh-port 2260 --ssh-password-file "$TMP_DIR/ssh-password" > "$TMP_DIR/start-failed.out" 2>&1; then
        printf 'Expected container startup to fail\n' >&2
        return 1
    fi
    assert_contains "$config_file" '^SSH_ENABLED=false$' || return 1
    assert_contains "$config_file" '^SSH_PORT=$' || return 1
    assert_not_contains "$config_file" '^SSH_PASSWORD_HASH_B64=' || return 1
    assert_contains "$config_file" '^GPUS=0,1$'
}

invalid_config_is_rejected() {
    local config_file="$PROJECT_DIR/.cudo/config"
    set_config_value "$config_file" "SSH_PORT" "invalid"
    cd "$PROJECT_DIR"
    if cudo_fast config > "$TMP_DIR/invalid-config.out" 2>&1; then
        printf 'Invalid configuration was accepted\n' >&2
        return 1
    fi
    set_config_value "$config_file" "SSH_PORT" ""
}

legacy_rollback_restores_global_password() {
    local config_file="$LEGACY_PROJECT_DIR/.cudo/config"
    local global_config
    local legacy_b64

    legacy_b64=$(encode_b64 "rollback-legacy")
    global_config=$(global_config_for_hash "$config_file")
    set_config_value "$config_file" "SSH_PASSWORD_HASH_B64" ""
    set_config_value "$config_file" "SSH_PASSWORD_B64" "$legacy_b64"
    set_config_value "$global_config" "SSH_PASSWORD_HASH_B64" ""
    set_config_value "$global_config" "SSH_PASSWORD_B64" "$legacy_b64"
    cd "$LEGACY_PROJECT_DIR"
    if CUDO_FAKE_COMPOSE_FAIL=true cudo_fast start --ssh-port 2261 > "$TMP_DIR/legacy-rollback.out" 2>&1; then
        printf 'Expected legacy startup to fail\n' >&2
        return 1
    fi
    assert_contains "$config_file" "^SSH_PASSWORD_B64=${legacy_b64}$" || return 1
    assert_contains "$global_config" "^SSH_PASSWORD_B64=${legacy_b64}$" || return 1
    assert_not_contains "$global_config" '^SSH_PASSWORD_HASH_B64=.+$'
}

main() {
    make_fake_tools

    test_case "syntax checks" syntax_checks
    test_case "doctor is read-only without global config dir" doctor_is_read_only_without_global_dir
    test_case "build has no default SSH port" build_has_no_default_ssh_port
    test_case "runtime SSH password is stored as a hash" runtime_password_is_hashed
    test_case "run and enter can update SSH port" run_and_enter_can_update_ssh_port
    test_case "list shows configured SSH port" list_shows_configured_ssh_port
    test_case "legacy SSH_PASSWORD_B64 migrates to hash" legacy_password_b64_migrates_to_hash
    test_case "doctor reports hashed SSH password" doctor_reports_hashed_project_password
    test_case "configuration files are parsed, not executed" config_is_not_executed
    test_case "secure SSH password inputs work" secure_password_inputs_work
    test_case "SSH lifecycle commands work" ssh_lifecycle_commands_work
    test_case "GPU selection is persisted" gpu_selection_is_persisted
    test_case "doctor supports all environments and JSON" doctor_json_and_all_work
    test_case "failed startup rolls back SSH configuration" failed_start_rolls_back_ssh_config
    test_case "invalid configuration is rejected" invalid_config_is_rejected
    test_case "legacy rollback restores global password" legacy_rollback_restores_global_password

    printf '\nFast test summary: %s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
    [ "$FAIL_COUNT" -eq 0 ]
}

main "$@"
