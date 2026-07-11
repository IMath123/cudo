#!/usr/bin/env python3

import argparse
import json
import socket
import sys
import time


DEFAULT_SOCKET = "/run/cudo/gpu-agent.sock"


def fetch(socket_path):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        client.settimeout(10)
        client.connect(socket_path)
        stream = client.makefile("rb")
        line = stream.readline(1024 * 1024)
        if not line:
            raise RuntimeError("GPU agent returned an empty response")
        response = json.loads(line)
    except FileNotFoundError as exc:
        raise RuntimeError("Cudo GPU agent socket is unavailable; run 'cudo doctor' on the host") from exc
    except (ConnectionError, OSError) as exc:
        raise RuntimeError(f"cannot connect to Cudo GPU agent: {exc}") from exc
    finally:
        client.close()
    if not response.get("ok"):
        raise RuntimeError(response.get("error", "GPU agent request failed"))
    return response["processes"]


def format_table(processes):
    headers = ("GPU", "PID", "GPU MEMORY", "COMMAND")
    rows = []
    for process in processes:
        gpu = "-" if process["gpu"] is None else str(process["gpu"])
        memory = "N/A" if process["memory_mib"] is None else f'{process["memory_mib"]} MiB'
        rows.append((gpu, str(process["pid"]), memory, process["command"]))
    widths = [len(header) for header in headers]
    for row in rows:
        for index, value in enumerate(row):
            widths[index] = max(widths[index], len(value))
    print("  ".join(header.ljust(widths[index]) for index, header in enumerate(headers)))
    if not rows:
        print("No GPU processes are running in this container.")
        return
    for row in rows:
        print("  ".join(value.ljust(widths[index]) for index, value in enumerate(row)))


def main():
    parser = argparse.ArgumentParser(description="Show GPU processes owned by this Cudo container")
    parser.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    parser.add_argument("--watch", type=float, metavar="SECONDS", help="refresh repeatedly")
    parser.add_argument("--socket", default=DEFAULT_SOCKET, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.watch is not None and args.watch <= 0:
        parser.error("--watch must be greater than zero")

    try:
        while True:
            processes = fetch(args.socket)
            if args.json:
                print(json.dumps({"processes": processes}, separators=(",", ":")))
            else:
                format_table(processes)
            if args.watch is None:
                return 0
            time.sleep(args.watch)
            if not args.json:
                print()
    except KeyboardInterrupt:
        return 0
    except (RuntimeError, json.JSONDecodeError) as exc:
        print(f"cudo-smi: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
