#!/usr/bin/env python3

import argparse
import json
import os
import re
import socket
import struct
import subprocess
from pathlib import Path


DEFAULT_SOCKET = "/run/cudo/gpu-agent.sock"
CONTAINER_PATTERNS = (
    re.compile(r"(?:^|/)([0-9a-f]{64})(?:$|/)", re.I),
    re.compile(r"(?:^|/)docker-([0-9a-f]{12,64})\.scope(?:$|/)", re.I),
    re.compile(r"(?:^|/)cri-containerd-([0-9a-f]{12,64})\.scope(?:$|/)", re.I),
)


def read_text(path):
    try:
        return Path(path).read_text(errors="replace")
    except OSError:
        return ""


def container_id_for_pid(pid):
    cgroup = read_text(f"/proc/{pid}/cgroup")
    for line in cgroup.splitlines():
        path = line.rsplit(":", 1)[-1]
        for pattern in CONTAINER_PATTERNS:
            match = pattern.search(path)
            if match:
                return match.group(1).lower()
    return None


def container_pid(host_pid):
    status = read_text(f"/proc/{host_pid}/status")
    for line in status.splitlines():
        if line.startswith("NSpid:"):
            values = line.split()[1:]
            if len(values) >= 2:
                return int(values[-1])
    return None


def process_command(host_pid, fallback):
    try:
        raw = Path(f"/proc/{host_pid}/cmdline").read_bytes()
        command = raw.replace(b"\0", b" ").decode(errors="replace").strip()
        return command or fallback
    except OSError:
        return fallback


def run_nvidia_smi(*args):
    return subprocess.run(
        ["nvidia-smi", *args],
        check=True,
        capture_output=True,
        text=True,
        timeout=10,
    ).stdout


def gpu_indices():
    output = run_nvidia_smi("--query-gpu=index,uuid", "--format=csv,noheader,nounits")
    result = {}
    for line in output.splitlines():
        fields = [field.strip() for field in line.split(",", 1)]
        if len(fields) == 2:
            result[fields[1]] = int(fields[0])
    return result


def gpu_processes(container_id):
    indices = gpu_indices()
    has_process_name = True
    try:
        output = run_nvidia_smi(
            "--query-compute-apps=pid,used_memory,gpu_uuid,process_name",
            "--format=csv,noheader,nounits",
        )
    except subprocess.CalledProcessError:
        has_process_name = False
        output = run_nvidia_smi(
            "--query-compute-apps=pid,used_memory,gpu_uuid",
            "--format=csv,noheader,nounits",
        )
    processes = []
    for line in output.splitlines():
        fields = [field.strip() for field in line.split(",", 3)]
        expected_fields = 4 if has_process_name else 3
        if len(fields) != expected_fields or not fields[0].isdigit():
            continue
        host_pid = int(fields[0])
        if container_id_for_pid(host_pid) != container_id:
            continue
        namespace_pid = container_pid(host_pid)
        if namespace_pid is None:
            continue
        try:
            memory_mib = int(fields[1])
        except ValueError:
            memory_mib = None
        processes.append(
            {
                "gpu": indices.get(fields[2]),
                "pid": namespace_pid,
                "memory_mib": memory_mib,
                "command": process_command(host_pid, fields[3] if has_process_name else "unknown"),
            }
        )
    return sorted(processes, key=lambda item: (item["gpu"] is None, item["gpu"], item["pid"]))


def response_for_peer(peer_pid):
    container_id = container_id_for_pid(peer_pid)
    if not container_id:
        return {"ok": False, "error": "caller is not running in a supported container cgroup"}
    try:
        return {"ok": True, "processes": gpu_processes(container_id)}
    except FileNotFoundError:
        return {"ok": False, "error": "nvidia-smi is not installed on the host"}
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout or "nvidia-smi failed").strip()
        return {"ok": False, "error": detail}
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "nvidia-smi timed out"}


def serve(socket_path):
    path = Path(socket_path)
    path.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    if path.exists() or path.is_socket():
        path.unlink()

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(socket_path)
    os.chmod(socket_path, 0o666)
    server.listen(32)
    try:
        while True:
            connection, _ = server.accept()
            with connection:
                peer_pid, _, _ = struct.unpack("3i", connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
                response = response_for_peer(peer_pid)
                connection.sendall(json.dumps(response, separators=(",", ":")).encode() + b"\n")
    finally:
        server.close()
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def main():
    parser = argparse.ArgumentParser(description="Cudo host GPU process agent")
    parser.add_argument("--socket", default=DEFAULT_SOCKET)
    args = parser.parse_args()
    serve(args.socket)


if __name__ == "__main__":
    main()
