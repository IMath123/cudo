#!/usr/bin/env python3
"""
Cudo 测试工具库
提供测试辅助函数和工具
"""

import os
import sys
import subprocess
import time
import json
import tempfile
import shutil
from pathlib import Path
from typing import List, Dict, Optional, Tuple


class TestUtils:
    """测试工具类"""

    def __init__(self):
        self.test_base_dir = Path("/tmp/cudo_test")
        self.cudo_path = Path(__file__).parent.parent / "cudo"
        self.global_config_dir = Path(os.environ.get("CUDO_GLOBAL_CONFIG_DIR", "/var/lib/cudo-global"))

        # 颜色代码
        self.COLORS = {
            'RED': '\033[0;31m',
            'GREEN': '\033[0;32m',
            'YELLOW': '\033[1;33m',
            'BLUE': '\033[0;34m',
            'NC': '\033[0m'
        }

    def log_info(self, message: str):
        """信息日志"""
        print(f"{self.COLORS['BLUE']}[INFO] {message}{self.COLORS['NC']}")

    def log_success(self, message: str):
        """成功日志"""
        print(f"{self.COLORS['GREEN']}[SUCCESS] {message}{self.COLORS['NC']}")

    def log_warning(self, message: str):
        """警告日志"""
        print(f"{self.COLORS['YELLOW']}[WARNING] {message}{self.COLORS['NC']}")

    def log_error(self, message: str):
        """错误日志"""
        print(f"{self.COLORS['RED']}[ERROR] {message}{self.COLORS['NC']}")

    def run_command(self, command: str, cwd: str = None, timeout: int = 30) -> Tuple[bool, str]:
        """
        运行命令并返回结果

        Args:
            command: 要运行的命令
            cwd: 工作目录
            timeout: 超时时间（秒）

        Returns:
            (成功状态, 输出内容)
        """
        try:
            result = subprocess.run(
                command,
                shell=True,
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=timeout
            )
            return result.returncode == 0, result.stdout.strip()
        except subprocess.TimeoutExpired:
            return False, f"Command timed out after {timeout} seconds"
        except Exception as e:
            return False, str(e)

    def run_cudo_command(self, command: str, project_dir: str = None, timeout: int = 30) -> Tuple[bool, str]:
        """
        运行 cudo 命令

        Args:
            command: cudo 命令
            project_dir: 项目目录
            timeout: 超时时间

        Returns:
            (成功状态, 输出内容)
        """
        # 确保 cudo 命令在 PATH 中
        os.environ['PATH'] = f"{Path(__file__).parent.parent}:{os.environ.get('PATH', '')}"
        full_command = f"cudo {command}"
        return self.run_command(full_command, project_dir, timeout)

    def setup_test_environment(self) -> Dict[str, Path]:
        """
        设置测试环境

        Returns:
            包含测试目录路径的字典
        """
        self.log_info("设置测试环境...")

        # 创建测试目录
        test_dirs = {
            'base': self.test_base_dir,
            'project1': self.test_base_dir / "test_project_1",
            'project2': self.test_base_dir / "test_project_2",
            'project_copy': self.test_base_dir / "test_project_copy",
            'project_move': self.test_base_dir / "test_project_move"
        }

        for dir_path in test_dirs.values():
            dir_path.mkdir(parents=True, exist_ok=True)

        # 创建测试文件
        test_file_content = '''#!/usr/bin/env python3
print("Hello from test project!")
'''

        for project_dir in [test_dirs['project1'], test_dirs['project2'],
                           test_dirs['project_copy'], test_dirs['project_move']]:
            test_file = project_dir / "test_script.py"
            test_file.write_text(test_file_content)
            test_file.chmod(0o755)

        self.log_success("测试环境设置完成")
        return test_dirs

    def cleanup_test_environment(self):
        """清理测试环境"""
        self.log_info("清理测试环境...")

        try:
            # 停止并删除测试容器
            success, output = self.run_command(
                "docker ps -a --filter 'name=cuda-project-' --format '{{.Names}}'"
            )
            if success and output:
                containers = output.split('\n')
                for container in containers:
                    if container.strip():
                        self.run_command(f"docker rm -f {container}")

            # 删除测试镜像
            success, output = self.run_command(
                "docker images --filter 'reference=*test_project*' --format '{{.Repository}}:{{.Tag}}'"
            )
            if success and output:
                images = output.split('\n')
                for image in images:
                    if image.strip():
                        self.run_command(f"docker rmi {image}")

            # 删除测试目录
            if self.test_base_dir.exists():
                shutil.rmtree(self.test_base_dir)

            # 清理全局配置
            global_config_dir = self.global_config_dir
            if global_config_dir.exists():
                for config_file in global_config_dir.glob("*test_project*"):
                    config_file.unlink()

            self.log_success("测试环境清理完成")
        except Exception as e:
            self.log_error(f"清理测试环境时出错: {e}")

    def check_docker_environment(self) -> bool:
        """检查Docker环境"""
        self.log_info("检查Docker环境...")

        # 检查Docker服务
        success, _ = self.run_command("docker info")
        if not success:
            self.log_error("Docker服务不可用")
            return False

        # 检查NVIDIA Docker支持
        success, output = self.run_command("docker run --rm --runtime=nvidia nvidia/cuda:11.8.0-base nvidia-smi")
        if not success:
            self.log_warning("NVIDIA Docker支持可能不可用")

        self.log_success("Docker环境检查完成")
        return True

    def get_container_info(self, project_dir: str) -> Dict[str, str]:
        """
        获取容器信息

        Args:
            project_dir: 项目目录

        Returns:
            容器信息字典
        """
        # 加载配置获取唯一哈希
        config_file = Path(project_dir) / ".cudo" / "config"
        if not config_file.exists():
            return {}

        config = {}
        with open(config_file, 'r') as f:
            for line in f:
                if '=' in line:
                    key, value = line.strip().split('=', 1)
                    config[key] = value

        unique_hash = config.get('UNIQUE_HASH')
        if not unique_hash:
            return {}

        container_name = f"cuda-project-{unique_hash}-container"

        # 获取容器状态
        success, output = self.run_command(
            f"docker ps -a --filter 'name={container_name}' --format '{{{{.Names}}}}\\t{{{{.Status}}}}'"
        )

        info = {
            'container_name': container_name,
            'unique_hash': unique_hash,
            'image_name': config.get('IMAGE_NAME', ''),
            'status': 'nonexistent'
        }

        if success and output and container_name in output:
            status_line = [line for line in output.split('\n') if container_name in line][0]
            status = status_line.split('\t')[1]
            if status.startswith('Up'):
                info['status'] = 'running'
            else:
                info['status'] = 'stopped'

        return info

    def wait_for_container_status(self, project_dir: str, target_status: str, timeout: int = 30) -> bool:
        """
        等待容器达到指定状态

        Args:
            project_dir: 项目目录
            target_status: 目标状态 ('running', 'stopped')
            timeout: 超时时间

        Returns:
            是否达到目标状态
        """
        start_time = time.time()
        while time.time() - start_time < timeout:
            info = self.get_container_info(project_dir)
            if info.get('status') == target_status:
                return True
            time.sleep(1)
        return False

    def test_build_environment(self, project_dir: str, cuda_version: str = "11.8.0",
                             python_version: str = "3.10") -> bool:
        """
        测试构建环境

        Args:
            project_dir: 项目目录
            cuda_version: CUDA版本
            python_version: Python版本

        Returns:
            构建是否成功
        """
        self.log_info(f"测试构建环境: CUDA {cuda_version}, Python {python_version}")

        command = f"build -c {cuda_version} -p {python_version}"
        success, output = self.run_cudo_command(command, project_dir)

        if success:
            self.log_success("环境构建成功")

            # 验证配置文件和镜像
            config_dir = Path(project_dir) / ".cudo"
            if not config_dir.exists():
                self.log_error("配置目录未创建")
                return False

            config_file = config_dir / "config"
            if not config_file.exists():
                self.log_error("配置文件未创建")
                return False

            # 检查镜像是否存在
            info = self.get_container_info(project_dir)
            image_name = info.get('image_name', '')
            if image_name:
                success, _ = self.run_command(f"docker image inspect {image_name}")
                if not success:
                    self.log_error("Docker镜像不存在")
                    return False

            return True
        else:
            self.log_error(f"环境构建失败: {output}")
            return False

    def test_container_lifecycle(self, project_dir: str) -> bool:
        """
        测试容器生命周期管理

        Args:
            project_dir: 项目目录

        Returns:
            测试是否成功
        """
        self.log_info("测试容器生命周期管理")

        tests_passed = 0
        total_tests = 0

        # 测试启动容器
        total_tests += 1
        success, output = self.run_cudo_command("start", project_dir)
        if success and self.wait_for_container_status(project_dir, "running"):
            self.log_success("容器启动成功")
            tests_passed += 1
        else:
            self.log_error("容器启动失败")

        # 测试状态检查
        total_tests += 1
        success, output = self.run_cudo_command("status", project_dir)
        if success and "running" in output.lower():
            self.log_success("状态检查成功")
            tests_passed += 1
        else:
            self.log_error("状态检查失败")

        # 测试停止容器
        total_tests += 1
        success, output = self.run_cudo_command("stop", project_dir)
        if success and self.wait_for_container_status(project_dir, "stopped"):
            self.log_success("容器停止成功")
            tests_passed += 1
        else:
            self.log_error("容器停止失败")

        # 测试重启容器
        total_tests += 1
        success, output = self.run_cudo_command("restart", project_dir)
        if success and self.wait_for_container_status(project_dir, "running"):
            self.log_success("容器重启成功")
            tests_passed += 1
        else:
            self.log_error("容器重启失败")

        # 最终停止容器
        self.run_cudo_command("stop", project_dir)

        success_rate = tests_passed / total_tests if total_tests > 0 else 0
        self.log_info(f"容器生命周期测试完成: {tests_passed}/{total_tests} 通过")

        return success_rate >= 0.8  # 允许部分失败

    def test_project_copy_detection(self, original_dir: str, copy_dir: str) -> bool:
        """
        测试项目拷贝检测

        Args:
            original_dir: 原始项目目录
            copy_dir: 拷贝项目目录

        Returns:
            测试是否成功
        """
        self.log_info("测试项目拷贝检测")

        # 首先构建原始项目
        if not self.test_build_environment(original_dir):
            return False

        # 然后尝试在拷贝项目中构建
        success, output = self.run_cudo_command("build", copy_dir)

        if success:
            # 检查是否检测到拷贝并生成了新的哈希
            original_info = self.get_container_info(original_dir)
            copy_info = self.get_container_info(copy_dir)

            if (original_info.get('unique_hash') != copy_info.get('unique_hash') and
                original_info.get('unique_hash') and copy_info.get('unique_hash')):
                self.log_success("项目拷贝检测成功 - 生成了新的唯一哈希")
                return True
            else:
                self.log_error("项目拷贝检测失败 - 哈希相同")
                return False
        else:
            self.log_error(f"拷贝项目构建失败: {output}")
            return False

    def test_error_handling(self, project_dir: str) -> bool:
        """
        测试错误处理

        Args:
            project_dir: 项目目录

        Returns:
            测试是否成功
        """
        self.log_info("测试错误处理")

        tests_passed = 0
        total_tests = 0

        # 测试无效命令
        total_tests += 1
        success, output = self.run_cudo_command("invalid_command", project_dir)
        if not success:
            self.log_success("无效命令处理正确")
            tests_passed += 1
        else:
            self.log_error("无效命令处理失败")

        # 测试无效CUDA版本
        total_tests += 1
        success, output = self.run_cudo_command("build -c invalid_version", project_dir)
        if not success:
            self.log_success("无效CUDA版本处理正确")
            tests_passed += 1
        else:
            self.log_error("无效CUDA版本处理失败")

        # 测试无效Python版本
        total_tests += 1
        success, output = self.run_cudo_command("build -p 2.7", project_dir)
        if not success:
            self.log_success("无效Python版本处理正确")
            tests_passed += 1
        else:
            self.log_error("无效Python版本处理失败")

        # 测试在非项目目录运行
        total_tests += 1
        success, output = self.run_cudo_command("status", "/tmp")
        if not success:
            self.log_success("非项目目录错误处理正确")
            tests_passed += 1
        else:
            self.log_error("非项目目录错误处理失败")

        success_rate = tests_passed / total_tests if total_tests > 0 else 0
        self.log_info(f"错误处理测试完成: {tests_passed}/{total_tests} 通过")

        return success_rate >= 0.75  # 允许部分失败


def main():
    """主函数 - 用于独立测试工具库"""
    utils = TestUtils()

    # 检查Docker环境
    if not utils.check_docker_environment():
        sys.exit(1)

    # 设置测试环境
    test_dirs = utils.setup_test_environment()

    try:
        # 测试基本功能
        project1_dir = str(test_dirs['project1'])
        if utils.test_build_environment(project1_dir):
            utils.log_success("基本构建测试通过")
        else:
            utils.log_error("基本构建测试失败")

        # 测试容器生命周期
        if utils.test_container_lifecycle(project1_dir):
            utils.log_success("容器生命周期测试通过")
        else:
            utils.log_error("容器生命周期测试失败")

        # 测试项目拷贝检测
        project_copy_dir = str(test_dirs['project_copy'])
        if utils.test_project_copy_detection(project1_dir, project_copy_dir):
            utils.log_success("项目拷贝检测测试通过")
        else:
            utils.log_error("项目拷贝检测测试失败")

        # 测试错误处理
        if utils.test_error_handling(project1_dir):
            utils.log_success("错误处理测试通过")
        else:
            utils.log_error("错误处理测试失败")

    finally:
        # 清理测试环境
        utils.cleanup_test_environment()


if __name__ == "__main__":
    main()
