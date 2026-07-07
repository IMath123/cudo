#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
export PATH="$ROOT_DIR:$PATH"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { printf '%b\n' "${BLUE}[INFO] $1${NC}"; }
log_success() { printf '%b\n' "${GREEN}[PASS] $1${NC}"; }
log_warning() { printf '%b\n' "${YELLOW}[WARN] $1${NC}"; }
log_error() { printf '%b\n' "${RED}[FAIL] $1${NC}"; }

SUITES_RUN=0
SUITES_FAILED=0
CREATED_GLOBAL_DIR=""

cleanup() {
    if [ -n "$CREATED_GLOBAL_DIR" ] && [ -d "$CREATED_GLOBAL_DIR" ]; then
        rm -rf "$CREATED_GLOBAL_DIR"
    fi
}
trap cleanup EXIT

run_suite() {
    local suite_name=$1
    shift

    SUITES_RUN=$((SUITES_RUN + 1))
    log_info "Running suite: $suite_name"

    if "$@"; then
        log_success "$suite_name"
    else
        log_error "$suite_name"
        SUITES_FAILED=$((SUITES_FAILED + 1))
    fi
}

check_integration_dependencies() {
    local missing=()

    for cmd in bash docker python3 envsubst openssl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
        missing+=("docker-compose")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing integration dependencies: ${missing[*]}"
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not available"
        return 1
    fi

    if ! docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q 'nvidia'; then
        log_error "NVIDIA Docker runtime is not visible"
        return 1
    fi

    return 0
}

prepare_integration_environment() {
    if [ -z "${CUDO_GLOBAL_CONFIG_DIR:-}" ]; then
        CREATED_GLOBAL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cudo-global.XXXXXX")"
        export CUDO_GLOBAL_CONFIG_DIR="$CREATED_GLOBAL_DIR"
        log_info "Using temporary global config: $CUDO_GLOBAL_CONFIG_DIR"
    else
        mkdir -p "$CUDO_GLOBAL_CONFIG_DIR"
    fi
}

run_fast_tests() {
    run_suite "fast" bash "$SCRIPT_DIR/test_fast.sh"
}

run_basic_tests() {
    check_integration_dependencies
    prepare_integration_environment
    run_suite "basic integration" bash "$SCRIPT_DIR/test_cudo.sh"
}

run_complex_tests() {
    check_integration_dependencies
    prepare_integration_environment
    run_suite "complex integration" bash "$SCRIPT_DIR/test_complex_scenarios.sh"
}

run_python_tests() {
    check_integration_dependencies
    prepare_integration_environment
    run_suite "python integration" python3 "$SCRIPT_DIR/test_utils.py"
}

run_integration_tests() {
    check_integration_dependencies
    prepare_integration_environment
    run_suite "basic integration" bash "$SCRIPT_DIR/test_cudo.sh"
    run_suite "complex integration" bash "$SCRIPT_DIR/test_complex_scenarios.sh"
    run_suite "python integration" python3 "$SCRIPT_DIR/test_utils.py"
}

print_summary() {
    printf '\n'
    log_info "Suites run: $SUITES_RUN"
    if [ "$SUITES_FAILED" -eq 0 ]; then
        log_success "All requested suites passed"
        return 0
    fi

    log_error "$SUITES_FAILED suite(s) failed"
    return 1
}

usage() {
    cat << EOF
Cudo test runner

Usage: $0 [option]

Default:
  $0                 Run fast tests only. No real Docker daemon or GPU is used.

Options:
  --fast            Run fast tests only
  --integration     Run Docker/NVIDIA integration tests
  --all             Run fast tests and integration tests
  --basic-only      Run basic Docker integration tests
  --complex-only    Run complex Docker integration tests
  --python-only     Run Python integration tests
  --smoke-only      Alias for --fast
  -h, --help        Show this help

Integration tests use CUDO_GLOBAL_CONFIG_DIR when set. Otherwise they create a
temporary global config directory under /tmp.
EOF
}

case "${1:---fast}" in
    --fast|--smoke-only)
        run_fast_tests
        ;;
    --integration)
        run_integration_tests
        ;;
    --all)
        run_fast_tests
        run_integration_tests
        ;;
    --basic-only)
        run_basic_tests
        ;;
    --complex-only)
        run_complex_tests
        ;;
    --python-only)
        run_python_tests
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
esac

print_summary
