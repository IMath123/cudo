#!/usr/bin/env python3

import importlib.util
import importlib.machinery
import json
import socket
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]


def load_module(name, filename):
    path = ROOT / "scripts" / filename
    spec = importlib.util.spec_from_loader(name, importlib.machinery.SourceFileLoader(name, str(path)))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


agent = load_module("cudo_gpu_agent", "cudo-gpu-agent.py")
client = load_module("cudo_smi", "cudo-smi.py")
wrapper = load_module("cudo_nvidia_smi", "nvidia-smi")


class AgentTests(unittest.TestCase):
    def test_container_id_supports_docker_systemd_scope(self):
        value = "a" * 64
        with mock.patch.object(agent, "read_text", return_value=f"0::/system.slice/docker-{value}.scope\n"):
            self.assertEqual(agent.container_id_for_pid(10), value)

    def test_container_pid_uses_innermost_namespace(self):
        with mock.patch.object(agent, "read_text", return_value="Name:\tpython\nNSpid:\t48120\t317\n"):
            self.assertEqual(agent.container_pid(48120), 317)

    def test_gpu_processes_filter_and_translate(self):
        gpu_output = "0, GPU-one\n"
        process_output = "48120, 8124, GPU-one, python\n90000, 100, GPU-one, other\n"

        def fake_smi(*args):
            return gpu_output if args[0].startswith("--query-gpu") else process_output

        with mock.patch.object(agent, "run_nvidia_smi", side_effect=fake_smi), \
             mock.patch.object(agent, "container_id_for_pid", side_effect=lambda pid: "mine" if pid == 48120 else "other"), \
             mock.patch.object(agent, "container_pid", return_value=317), \
             mock.patch.object(agent, "process_command", return_value="python train.py"):
            self.assertEqual(
                agent.gpu_processes("mine"),
                [{"gpu": 0, "pid": 317, "host_pid": 48120, "memory_mib": 8124, "command": "python train.py"}],
            )


class ClientTests(unittest.TestCase):
    def test_fetch_reads_agent_response(self):
        with tempfile.TemporaryDirectory() as directory:
            socket_path = str(Path(directory) / "agent.sock")
            ready = threading.Event()

            def server():
                listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                listener.bind(socket_path)
                listener.listen(1)
                ready.set()
                connection, _ = listener.accept()
                connection.sendall(json.dumps({"ok": True, "processes": [{"pid": 7, "host_pid": 70}]}).encode() + b"\n")
                connection.close()
                listener.close()

            thread = threading.Thread(target=server)
            thread.start()
            ready.wait(2)
            self.assertEqual(client.fetch(socket_path), [{"pid": 7}])
            thread.join(2)


class NvidiaSmiWrapperTests(unittest.TestCase):
    def test_default_process_table_filters_and_translates_pids(self):
        output = (
            "| Processes:                                                                  |\n"
            "|  GPU   GI   CI        PID   Type   Process name                  GPU Memory |\n"
            "|    0   N/A  N/A     48120      C   python                         8124MiB |\n"
            "|    0   N/A  N/A     90000      C   other                           100MiB |\n"
            "+-----------------------------------------------------------------------------+\n"
        )
        processes = [{"host_pid": 48120, "pid": 317, "gpu": 0, "memory_mib": 8124, "command": "python train.py"}]
        rewritten = wrapper.rewrite_default_output(output, processes)
        self.assertIn("317", rewritten)
        self.assertNotIn("48120", rewritten)
        self.assertNotIn("90000", rewritten)

    def test_default_empty_table_is_populated_from_agent(self):
        output = "| Processes: |\n|================|\n+----------------+\n"
        processes = [{"host_pid": 48120, "pid": 317, "gpu": 0, "memory_mib": 8124, "command": "python train.py"}]
        rewritten = wrapper.rewrite_default_output(output, processes)
        self.assertIn("317", rewritten)
        self.assertIn("8124MiB", rewritten)

    def test_compute_query_filters_and_translates_pid_column(self):
        output = "python, 48120, 8124 MiB\nother, 90000, 100 MiB\n"
        rewritten = wrapper.rewrite_query_output(output, ["process_name", "pid", "used_memory"], {48120: 317})
        self.assertEqual(rewritten, "python, 317, 8124 MiB\n")


if __name__ == "__main__":
    unittest.main()
