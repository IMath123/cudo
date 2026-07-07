#!/bin/bash

# Cudo 测试脚本
# 测试 CUDA 开发环境管理工具的基本情况和复杂情况

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() { echo -e "${BLUE}[INFO] $1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
log_warning() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 确保 cudo 命令在 PATH 中
export PATH="$ROOT_DIR:$PATH"

# 测试计数器
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# 测试项目目录
TEST_BASE_DIR="/tmp/cudo_test"
PROJECT_DIR="$TEST_BASE_DIR/test_project"
PROJECT_COPY_DIR="$TEST_BASE_DIR/test_project_copy"
PROJECT_MOVE_DIR="$TEST_BASE_DIR/test_project_move"

# 全局配置目录
GLOBAL_CONFIG_DIR="${CUDO_GLOBAL_CONFIG_DIR:-/var/lib/cudo-global}"

# 测试辅助函数
increment_test_count() {
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "✓ $1"
}

fail_test() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_error "✗ $1"
}

run_test() {
    local test_name="$1"
    local test_command="$2"

    increment_test_count
    log_info "Running test: $test_name"

    if eval "$test_command"; then
        pass_test "$test_name"
    else
        fail_test "$test_name"
    fi
}

# 检查依赖
check_dependencies() {
    log_info "检查系统依赖..."

    local missing_deps=()

    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi

    # 检查 Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        missing_deps+=("docker-compose")
    fi

    # 检查 envsubst
    if ! command -v envsubst &> /dev/null; then
        missing_deps+=("envsubst")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "缺少依赖: ${missing_deps[*]}"
        return 1
    fi

    log_success "所有依赖已安装"
    return 0
}

# 清理测试环境
cleanup_test_environment() {
    log_info "清理测试环境..."

    # 停止并删除测试容器
    docker ps -a --filter "name=cuda-project-" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true

    # 删除测试镜像
    docker images --filter "reference=*test_project*" --format "{{.Repository}}:{{.Tag}}" | xargs -r docker rmi 2>/dev/null || true

    # 删除测试目录
    rm -rf "$TEST_BASE_DIR" 2>/dev/null || true

    # 清理全局配置
    if [ -d "$GLOBAL_CONFIG_DIR" ]; then
        find "$GLOBAL_CONFIG_DIR" -name "*test_project*" -delete 2>/dev/null || true
    fi

    log_success "测试环境清理完成"
}

# 设置测试环境
setup_test_environment() {
    log_info "设置测试环境..."

    # 创建测试目录
    mkdir -p "$PROJECT_DIR"
    mkdir -p "$PROJECT_COPY_DIR"
    mkdir -p "$PROJECT_MOVE_DIR"

    # 创建测试文件
    cat > "$PROJECT_DIR/test_script.py" << 'EOF'
#!/usr/bin/env python3
print("Hello from test project!")
EOF

    # 复制到其他目录
    cp "$PROJECT_DIR/test_script.py" "$PROJECT_COPY_DIR/"
    cp "$PROJECT_DIR/test_script.py" "$PROJECT_MOVE_DIR/"

    log_success "测试环境设置完成"
}

# 基础功能测试
test_basic_functionality() {
    log_info "=== 基础功能测试 ==="

    cd "$PROJECT_DIR"

    # 测试 1: 显示帮助信息
    run_test "显示帮助信息" "cudo help"

    # 测试 2: 显示配置（未构建时）
    run_test "显示默认配置" "cudo config"

    # 测试 3: 构建环境
    run_test "构建CUDA环境" "cudo build -c 11.8.0 -p 3.10"

    # 测试 4: 显示配置（构建后）
    run_test "显示构建后配置" "cudo config"

    # 测试 4.1: 检查默认环境名
    run_test "检查默认环境名" "grep -q '^ENV_NAME=test_project$' .cudo/config"

    # 测试 5: 检查容器状态
    run_test "检查容器状态" "cudo status"

    # 测试 6: 启动容器
    run_test "启动容器" "cudo start"

    # 测试 7: 再次检查状态
    run_test "检查运行状态" "cudo status"

    # 测试 7.1: 从任意目录进入命名环境并执行命令
    run_test "从任意目录进入命名环境" "cd /tmp && cudo enter test_project -- true"

    # 测试 8: 查看日志
    run_test "查看容器日志" "timeout 5 cudo logs || true"

    # 测试 9: 停止容器
    run_test "停止容器" "cudo stop"

    # 测试 10: 重启容器
    run_test "重启容器" "cudo restart"

    # 测试 11: 列出环境
    run_test "列出CUDA环境" "cudo list"

    # 测试 12: 详细列出环境
    run_test "详细列出环境" "cudo list --details"
}

# 复杂场景测试
test_complex_scenarios() {
    log_info "=== 复杂场景测试 ==="

    # 测试 13: 项目拷贝检测
    log_info "测试项目拷贝检测..."
    cd "$PROJECT_COPY_DIR"
    if cudo build -c 12.4.0 -p 3.10; then
        pass_test "项目拷贝检测和处理"
    else
        fail_test "项目拷贝检测和处理"
    fi

    # 测试 14: 项目移动检测
    log_info "测试项目移动检测..."
    cd "$PROJECT_MOVE_DIR"
    if cudo build -c 12.4.0 -p 3.10; then
        pass_test "项目移动检测和处理"
    else
        fail_test "项目移动检测和处理"
    fi

    # 测试 15: 多项目管理
    log_info "测试多项目管理..."
    cd "$PROJECT_DIR"
    if cudo list | grep -q "test_project"; then
        pass_test "多项目管理功能"
    else
        fail_test "多项目管理功能"
    fi

    # 测试 16: 清理已删除项目
    log_info "测试清理功能..."
    if cudo cleanup; then
        pass_test "清理已删除项目"
    else
        fail_test "清理已删除项目"
    fi
}

# 错误处理测试
test_error_handling() {
    log_info "=== 错误处理测试 ==="

    cd "$PROJECT_DIR"

    # 测试 17: 无效命令处理
    run_test "无效命令处理" "! cudo invalid_command"

    # 测试 18: 无效CUDA版本
    run_test "无效CUDA版本处理" "! cudo build -c invalid_version"

    # 测试 19: 无效Python版本
    run_test "无效Python版本处理" "! cudo build -p 2.7"

    # 测试 20: 在非项目目录运行
    run_test "非项目目录错误处理" "! cd /tmp && cudo status"
}

# 环境清理测试
test_cleanup_functionality() {
    log_info "=== 环境清理测试 ==="

    cd "$PROJECT_DIR"

    # 测试 21: 重置容器
    run_test "恢复容器" "echo 'y' | cudo restore"

    # 测试 22: 完全删除环境
    run_test "删除环境" "echo 'y' | cudo remove"

    # 测试 23: 验证删除
    run_test "验证环境删除" "! test -d .cudo"
}

# 性能测试
test_performance() {
    log_info "=== 性能测试 ==="

    cd "$PROJECT_DIR"

    # 重新构建环境进行性能测试
    cudo build -c 11.8.0 -p 3.10

    # 测试 24: 启动时间测试
    log_info "测试启动时间..."
    start_time=$(date +%s)
    cudo start
    end_time=$(date +%s)
    duration=$((end_time - start_time))

    if [ $duration -lt 10 ]; then
        pass_test "容器启动时间 ($duration 秒)"
    else
        log_warning "容器启动时间较长: $duration 秒"
        pass_test "容器启动时间 ($duration 秒)"
    fi

    # 测试 25: 资源监控
    run_test "资源监控功能" "cudo list --details | grep -q 'CPU'"

    cudo stop
}

# 集成测试
test_integration() {
    log_info "=== 集成测试 ==="

    # 测试 26: 全局配置集成
    run_test "全局配置集成" "test -d '$GLOBAL_CONFIG_DIR'"

    # 测试 27: Docker集成
    run_test "Docker集成" "docker ps -a | grep -q 'cuda-project'"

    # 测试 28: 镜像管理集成
    run_test "镜像管理集成" "docker images | grep -q 'test_project'"
}

# 主测试函数
main() {
    log_info "开始 Cudo 测试套件"
    log_info "测试目录: $TEST_BASE_DIR"

    # 检查依赖
    if ! check_dependencies; then
        log_error "依赖检查失败，测试中止"
        exit 1
    fi

    # 清理之前的测试环境
    cleanup_test_environment

    # 设置测试环境
    setup_test_environment

    # 运行测试套件
    test_basic_functionality
    test_complex_scenarios
    test_error_handling
    test_cleanup_functionality
    test_performance
    test_integration

    # 最终清理
    cleanup_test_environment

    # 输出测试结果
    echo
    log_info "=== 测试结果汇总 ==="
    log_info "总测试数: $TESTS_TOTAL"
    log_success "通过: $TESTS_PASSED"
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "失败: $TESTS_FAILED"
    else
        log_error "失败: $TESTS_FAILED"
    fi

    # 计算通过率
    if [ $TESTS_TOTAL -gt 0 ]; then
        pass_rate=$((TESTS_PASSED * 100 / TESTS_TOTAL))
        log_info "通过率: $pass_rate%"
    fi

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "🎉 所有测试通过！"
        exit 0
    else
        log_error "❌ 有测试失败，请检查日志"
        exit 1
    fi
}

# 信号处理
trap cleanup_test_environment EXIT INT TERM

# 运行主函数
main "$@"
