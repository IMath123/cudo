# Cudo Test Suite

This directory contains the formal Cudo test entry points.

## Test Files

- `run_all_tests.sh`: main runner. Defaults to fast tests and exposes opt-in integration modes.
- `test_fast.sh`: no real Docker daemon or GPU. Uses fake `docker` and `envsubst` commands plus real `openssl`.
- `test_cudo.sh`: Docker/NVIDIA integration coverage for core commands and lifecycle behavior.
- `test_complex_scenarios.sh`: Docker/NVIDIA integration coverage for copy, move, conflict, cleanup, and multi-environment cases.
- `test_utils.py`: Python integration helpers and subprocess-based lifecycle checks.

## Default Fast Tests

Run from the repository root:

```bash
./tests/run_all_tests.sh
```

Or from `tests/`:

```bash
./run_all_tests.sh
```

The default suite checks:

- shell and Python syntax
- `cudo doctor` read-only behavior
- no default SSH port after `build`
- SSH password hash storage with `SSH_PASSWORD_HASH_B64`
- migration from legacy `SSH_PASSWORD_B64`
- dynamic SSH port updates through `run`, `start`, and `enter`
- `cudo list` SSH column output

Fast test requirements:

- `bash`
- `python3`
- `openssl` with `openssl passwd -6`
- `base64`

Fast tests do not require Docker, Docker Compose, NVIDIA runtime, or access to `/var/lib/cudo-global`.

## Integration Tests

Run integration tests explicitly:

```bash
./tests/run_all_tests.sh --integration
```

Available runner options:

```bash
./tests/run_all_tests.sh --fast
./tests/run_all_tests.sh --integration
./tests/run_all_tests.sh --all
./tests/run_all_tests.sh --basic-only
./tests/run_all_tests.sh --complex-only
./tests/run_all_tests.sh --python-only
./tests/run_all_tests.sh --smoke-only
```

Integration requirements:

- Docker daemon
- Docker Compose v2 or `docker-compose`
- NVIDIA Docker runtime visible in `docker info`
- `envsubst`
- `openssl`
- `python3`

The runner uses `CUDO_GLOBAL_CONFIG_DIR` when set. If it is unset, integration tests create a temporary global config directory under `/tmp`, so they do not need write access to `/var/lib/cudo-global`.

## Direct Script Runs

You can run individual scripts directly:

```bash
./tests/test_fast.sh
CUDO_GLOBAL_CONFIG_DIR=/tmp/cudo-test-global ./tests/test_cudo.sh
CUDO_GLOBAL_CONFIG_DIR=/tmp/cudo-test-global ./tests/test_complex_scenarios.sh
CUDO_GLOBAL_CONFIG_DIR=/tmp/cudo-test-global python3 ./tests/test_utils.py
```

The integration scripts create and remove temporary project directories under `/tmp`.
