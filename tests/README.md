# Cudo 测试套件

这个目录包含了 Cudo CUDA 开发环境管理工具的完整测试套件。

## 测试文件说明

### 主要测试脚本

- **`test_cudo.sh`** - 基础功能测试
  - 测试基本命令功能（build, run, status, start, stop, restart, logs, remove）
  - 测试配置管理
  - 测试错误处理
  - 测试性能监控

- **`test_complex_scenarios.sh`** - 复杂场景测试
  - 测试项目拷贝检测和处理
  - 测试项目移动处理
  - 测试名称冲突处理
  - 测试多环境管理
  - 测试错误恢复机制
  - 测试资源清理

- **`test_utils.py`** - Python测试工具库
  - 提供测试辅助函数
  - 容器生命周期管理测试
  - 项目拷贝检测测试
  - 错误处理测试

- **`run_all_tests.sh`** - 完整测试套件运行器
  - 运行所有测试套件
  - 生成测试报告
  - 管理测试环境
  - 提供多种运行模式

## 测试覆盖范围

### 基础功能测试
- [x] 命令验证（help, config, build, run, status, start, stop, restart, logs, remove）
- [x] 配置检查（默认配置、构建后配置）
- [x] 容器生命周期管理
- [x] 镜像构建和验证
- [x] 日志查看功能

### 复杂场景测试
- [x] 项目拷贝检测和自动处理
- [x] 项目移动检测和路径更新
- [x] 名称冲突处理和唯一哈希生成
- [x] 多项目管理（list, list --details, list --gpu）
- [x] 错误恢复（镜像丢失、配置损坏）
- [x] 资源清理（cleanup, remove）

### 集成测试
- [x] Docker集成验证
- [x] 全局配置管理
- [x] 多用户环境支持
- [x] 资源监控集成

### 性能测试
- [x] 容器启动时间
- [x] 构建性能
- [x] 资源使用监控

## 运行测试

### 运行完整测试套件

```bash
cd tests
./run_all_tests.sh
```

### 运行特定测试套件

```bash
# 只运行基础功能测试
./run_all_tests.sh --basic-only

# 只运行复杂场景测试
./run_all_tests.sh --complex-only

# 只运行Python工具测试
./run_all_tests.sh --python-only

# 只运行快速冒烟测试
./run_all_tests.sh --smoke-only
```

### 单独运行测试脚本

```bash
# 基础功能测试
./test_cudo.sh

# 复杂场景测试
./test_complex_scenarios.sh

# Python工具测试
python3 test_utils.py
```

## 测试环境要求

### 系统依赖
- Docker
- Docker Compose (或 Docker Compose V2)
- Python 3.6+
- envsubst (gettext包)
- bash

### 权限要求
- 当前用户需要在docker组中
- 需要写入 `/var/lib/cudo-global` 目录的权限
- 需要创建临时目录的权限

### 环境设置
测试脚本会自动：
1. 创建临时测试目录 (`/tmp/cudo_test`, `/tmp/cudo_complex_test`)
2. 设置测试项目文件
3. 清理之前的测试环境
4. 运行测试套件
5. 生成测试报告和日志
6. 清理测试环境

## 测试报告

测试运行后会生成：
- **日志文件**: `tests/logs/` 目录下
- **测试报告**: `tests/reports/` 目录下
- **控制台输出**: 实时显示测试进度和结果

## 测试用例详情

### 基础功能测试用例 (28个测试)

1. **命令验证**
   - 显示帮助信息
   - 显示默认配置
   - 构建CUDA环境
   - 显示构建后配置
   - 检查容器状态
   - 启动容器
   - 检查运行状态
   - 查看容器日志
   - 停止容器
   - 重启容器
   - 列出CUDA环境
   - 详细列出环境

2. **复杂场景**
   - 项目拷贝检测和处理
   - 项目移动检测和处理
   - 多项目管理功能
   - 清理已删除项目

3. **错误处理**
   - 无效命令处理
   - 无效CUDA版本处理
   - 无效Python版本处理
   - 非项目目录错误处理

4. **环境清理**
   - 重置容器
   - 完全删除环境
   - 验证删除

5. **性能测试**
   - 容器启动时间
   - 资源监控功能

6. **集成测试**
   - 全局配置集成
   - Docker集成
   - 镜像管理集成

### 复杂场景测试用例

1. **项目拷贝检测**
   - 构建原始项目
   - 在拷贝项目中构建
   - 验证生成新的唯一哈希
   - 验证两个项目独立运行

2. **项目移动处理**
   - 构建项目
   - 模拟移动操作（重命名目录）
   - 验证哈希保持不变
   - 验证移动后功能正常

3. **名称冲突处理**
   - 使用相同项目名构建多个环境
   - 验证生成不同的唯一哈希
   - 验证冲突处理正确

4. **多环境管理**
   - 列出所有环境
   - 验证所有项目可见
   - 测试详细列表功能
   - 测试GPU信息列表

5. **错误恢复**
   - 模拟镜像丢失
   - 验证镜像丢失检测
   - 模拟配置损坏
   - 验证配置损坏检测

6. **资源清理**
   - 清理已删除项目
   - 删除项目环境
   - 验证清理彻底性

## 故障排除

### 常见问题

1. **权限错误**
   ```bash
   # 添加用户到docker组
   sudo usermod -aG docker $USER
   # 重新登录或重启
   ```

2. **全局配置目录权限**
   ```bash
   # 创建并设置权限
   sudo mkdir -p /var/lib/cudo-global
   sudo chmod 777 /var/lib/cudo-global
   ```

3. **Docker服务不可用**
   ```bash
   # 启动Docker服务
   sudo systemctl start docker
   sudo systemctl enable docker
   ```

4. **测试环境清理不彻底**
   ```bash
   # 手动清理
   docker ps -a --filter "name=cuda-project-" --format "{{.Names}}" | xargs -r docker rm -f
   docker images --filter "reference=*test_project*" --format "{{.Repository}}:{{.Tag}}" | xargs -r docker rmi
   rm -rf /tmp/cudo_test /tmp/cudo_complex_test
   ```

### 测试失败处理

如果测试失败，请检查：
1. 查看对应的日志文件了解详细错误
2. 确认所有依赖已正确安装
3. 验证Docker服务正常运行
4. 检查权限设置是否正确
5. 查看测试报告中的系统信息

## 开发新测试

要添加新的测试用例：

1. **基础功能测试**: 编辑 `test_cudo.sh`
2. **复杂场景测试**: 编辑 `test_complex_scenarios.sh`
3. **测试工具**: 编辑 `test_utils.py`
4. **运行逻辑**: 编辑 `run_all_tests.sh`

遵循现有的测试模式和结构，确保：
- 包含适当的错误处理
- 提供清晰的日志输出
- 实现完整的环境清理
- 更新测试文档

## 贡献指南

欢迎贡献测试用例！请确保：
1. 测试用例覆盖新的功能或边界情况
2. 遵循现有的代码风格和结构
3. 包含适当的文档
4. 验证测试在干净环境中通过
5. 更新此README文档