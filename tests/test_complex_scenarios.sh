#!/bin/bash

# Cudo 复杂场景测试脚本
# 测试项目拷贝、移动、冲突处理等复杂情况

set -e

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

# 测试目录
TEST_BASE_DIR="/tmp/cudo_complex_test"
PROJECT_ORIGINAL="$TEST_BASE_DIR/original_project"
PROJECT_COPY="$TEST_BASE_DIR/copied_project"
PROJECT_MOVE="$TEST_BASE_DIR/moved_project"
PROJECT_CONFLICT="$TEST_BASE_DIR/conflict_project"
GLOBAL_CONFIG_DIR="${CUDO_GLOBAL_CONFIG_DIR:-/var/lib/cudo-global}"

# 测试计数器
TESTS_PASSED=0
TESTS_FAILED=0

# 辅助函数
run_test() {
    local test_name="$1"
    local test_command="$2"

    log_info "Running: $test_name"
    if eval "$test_command"; then
        log_success "PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "FAIL: $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

get_project_hash() {
    local project_dir="$1"
    if [ -f "$project_dir/.cudo/config" ]; then
        grep "UNIQUE_HASH=" "$project_dir/.cudo/config" | cut -d'=' -f2
    else
        echo ""
    fi
}

get_container_name() {
    local project_dir="$1"
    local hash=$(get_project_hash "$project_dir")
    if [ -n "$hash" ]; then
        echo "cuda-project-$hash-container"
    else
        echo ""
    fi
}

# 环境设置
setup_environment() {
    log_info "设置复杂场景测试环境..."

    # 清理旧环境
    cleanup_environment

    # 创建测试目录
    mkdir -p "$PROJECT_ORIGINAL"
    mkdir -p "$PROJECT_COPY"
    mkdir -p "$PROJECT_MOVE"
    mkdir -p "$PROJECT_CONFLICT"

    # 创建测试文件
    cat > "$PROJECT_ORIGINAL/test_app.py" << 'EOF'
#!/usr/bin/env python3
import torch
print(f"PyTorch version: {torch.__version__}")
print(f"CUDA available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"GPU count: {torch.cuda.device_count()}")
EOF

    # 复制到其他项目
    cp "$PROJECT_ORIGINAL/test_app.py" "$PROJECT_COPY/"
    cp "$PROJECT_ORIGINAL/test_app.py" "$PROJECT_MOVE/"
    cp "$PROJECT_ORIGINAL/test_app.py" "$PROJECT_CONFLICT/"

    log_success "测试环境设置完成"
}

# 环境清理
cleanup_environment() {
    log_info "清理测试环境..."

    # 停止并删除所有测试容器
    docker ps -a --filter "name=cuda-project-" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true

    # 删除测试镜像
    docker images --filter "reference=*original_project*" --format "{{.Repository}}:{{.Tag}}" | xargs -r docker rmi 2>/dev/null || true
    docker images --filter "reference=*copied_project*" --format "{{.Repository}}:{{.Tag}}" | xargs -r docker rmi 2>/dev/null || true
    docker images --filter "reference=*moved_project*" --format "{{.Repository}}:{{.Tag}}" | xargs -r docker rmi 2>/dev/null || true
    docker images --filter "reference=*conflict_project*" --format "{{.Repository}}:{{.Tag}}" | xargs -r docker rmi 2>/dev/null || true

    # 删除测试目录
    rm -rf "$TEST_BASE_DIR" 2>/dev/null || true

    # 清理全局配置
    if [ -d "$GLOBAL_CONFIG_DIR" ]; then
        find "$GLOBAL_CONFIG_DIR" -name "*original_project*" -delete 2>/dev/null || true
        find "$GLOBAL_CONFIG_DIR" -name "*copied_project*" -delete 2>/dev/null || true
        find "$GLOBAL_CONFIG_DIR" -name "*moved_project*" -delete 2>/dev/null || true
        find "$GLOBAL_CONFIG_DIR" -name "*conflict_project*" -delete 2>/dev/null || true
    fi

    log_success "环境清理完成"
}

# 测试1: 项目拷贝检测
test_project_copy_detection() {
    log_info "=== 测试1: 项目拷贝检测 ==="

    cd "$PROJECT_ORIGINAL"

    # 构建原始项目
    run_test "构建原始项目" "cudo build -c 11.8.0 -p 3.10"

    # 获取原始项目哈希
    original_hash=$(get_project_hash "$PROJECT_ORIGINAL")
    log_info "原始项目哈希: $original_hash"

    # 在拷贝项目中构建
    cd "$PROJECT_COPY"
    run_test "在拷贝项目中构建" "cudo build"

    # 获取拷贝项目哈希
    copy_hash=$(get_project_hash "$PROJECT_COPY")
    log_info "拷贝项目哈希: $copy_hash"

    # 验证哈希不同
    if [ "$original_hash" != "$copy_hash" ] && [ -n "$original_hash" ] && [ -n "$copy_hash" ]; then
        log_success "项目拷贝检测成功 - 哈希不同: $original_hash vs $copy_hash"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "项目拷贝检测失败 - 哈希相同或为空"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # 验证两个项目都能独立运行
    cd "$PROJECT_ORIGINAL"
    run_test "原始项目状态检查" "cudo status"

    cd "$PROJECT_COPY"
    run_test "拷贝项目状态检查" "cudo status"
}

# 测试2: 项目移动处理
test_project_move_handling() {
    log_info "=== 测试2: 项目移动处理 ==="

    # 首先在移动目录构建
    cd "$PROJECT_MOVE"
    run_test "在移动目录构建" "cudo build -c 12.4.0 -p 3.11"

    move_hash=$(get_project_hash "$PROJECT_MOVE")
    log_info "移动项目哈希: $move_hash"

    # 模拟移动操作 - 重命名目录
    PROJECT_MOVE_NEW="$TEST_BASE_DIR/moved_project_new"
    mv "$PROJECT_MOVE" "$PROJECT_MOVE_NEW"

    cd "$PROJECT_MOVE_NEW"
    run_test "在移动后目录运行命令" "cudo status"

    # 验证哈希保持不变
    new_hash=$(get_project_hash "$PROJECT_MOVE_NEW")
    if [ "$move_hash" = "$new_hash" ]; then
        log_success "项目移动处理成功 - 哈希保持不变: $move_hash"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "项目移动处理失败 - 哈希改变: $move_hash vs $new_hash"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # 恢复目录名
    mv "$PROJECT_MOVE_NEW" "$PROJECT_MOVE"
}

# 测试3: 名称冲突处理
test_name_conflict_handling() {
    log_info "=== 测试3: 名称冲突处理 ==="

    cd "$PROJECT_CONFLICT"

    # 使用相同的项目名但不同配置构建
    run_test "构建冲突项目1" "cudo build -c 11.8.0 -p 3.9 -i conflict_project"

    conflict_hash1=$(get_project_hash "$PROJECT_CONFLICT")
    log_info "冲突项目1哈希: $conflict_hash1"

    # 清理配置，模拟另一个相同名称的项目
    rm -rf "$PROJECT_CONFLICT/.cudo"

    # 使用相同项目名但不同CUDA版本构建
    run_test "构建冲突项目2" "cudo build -c 12.0.0 -p 3.10 -i conflict_project"

    conflict_hash2=$(get_project_hash "$PROJECT_CONFLICT")
    log_info "冲突项目2哈希: $conflict_hash2"

    # 验证哈希不同（应该生成新的哈希）
    if [ "$conflict_hash1" != "$conflict_hash2" ] && [ -n "$conflict_hash1" ] && [ -n "$conflict_hash2" ]; then
        log_success "名称冲突处理成功 - 生成不同哈希"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "名称冲突处理失败 - 哈希相同"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# 测试4: 多环境管理
test_multi_environment_management() {
    log_info "=== 测试4: 多环境管理 ==="

    # 列出所有环境
    run_test "列出所有环境" "cd /tmp && cudo list"

    # 检查是否能看到所有测试项目
    cd /tmp
    if cudo list | grep -q "original_project" && \
       cudo list | grep -q "copied_project" && \
       cudo list | grep -q "moved_project" && \
       cudo list | grep -q "conflict_project"; then
        log_success "多环境管理成功 - 所有项目可见"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "多环境管理失败 - 部分项目不可见"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # 测试详细列表
    run_test "详细环境列表" "cudo list --details"

    # 测试GPU信息列表
    run_test "GPU信息列表" "cudo list --gpu"
}

# 测试5: 错误恢复测试
test_error_recovery() {
    log_info "=== 测试5: 错误恢复测试 ==="

    cd "$PROJECT_ORIGINAL"

    # 测试镜像丢失恢复
    log_info "模拟镜像丢失..."
    original_image=$(grep "IMAGE_NAME=" "$PROJECT_ORIGINAL/.cudo/config" | cut -d'=' -f2)
    if [ -n "$original_image" ]; then
        docker rmi "$original_image" 2>/dev/null || true

        # 尝试运行命令（应该检测到镜像丢失）
        if ! cudo status 2>&1 | grep -q "Environment is broken"; then
            log_error "镜像丢失检测失败"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        else
            log_success "镜像丢失检测成功"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        fi

        # 重建环境
        run_test "重建丢失的环境" "cudo build"
    fi

    # 测试配置损坏恢复
    log_info "模拟配置损坏..."
    if [ -f "$PROJECT_ORIGINAL/.cudo/config" ]; then
        # 损坏配置文件
        echo "CORRUPTED_CONFIG=1" > "$PROJECT_ORIGINAL/.cudo/config"

        # 尝试运行命令（应该失败）
        if cudo status 2>/dev/null; then
            log_error "配置损坏检测失败"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        else
            log_success "配置损坏检测成功"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        fi

        # 清理损坏的配置
        rm -rf "$PROJECT_ORIGINAL/.cudo"
    fi
}

# 测试6: 资源清理测试
test_resource_cleanup() {
    log_info "=== 测试6: 资源清理测试 ==="

    # 测试清理已删除项目
    run_test "清理已删除项目" "cd /tmp && cudo cleanup"

    # 验证容器和镜像清理
    cd "$PROJECT_ORIGINAL"
    run_test "删除原始项目环境" "echo 'y' | cudo remove"

    # 验证清理是否彻底
    if [ ! -d "$PROJECT_ORIGINAL/.cudo" ] && \
       ! docker ps -a --format "{{.Names}}" | grep -q "$(get_container_name "$PROJECT_ORIGINAL")"; then
        log_success "资源清理彻底"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "资源清理不彻底"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# 主测试函数
main() {
    log_info "开始复杂场景测试套件"

    # 设置环境
    setup_environment

    # 运行测试
    test_project_copy_detection
    test_project_move_handling
    test_name_conflict_handling
    test_multi_environment_management
    test_error_recovery
    test_resource_cleanup

    # 输出结果
    echo
    log_info "=== 复杂场景测试结果 ==="
    log_info "总测试数: $((TESTS_PASSED + TESTS_FAILED))"
    log_success "通过: $TESTS_PASSED"

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "失败: $TESTS_FAILED"
        log_success "🎉 所有复杂场景测试通过！"
    else
        log_error "失败: $TESTS_FAILED"
        log_error "❌ 有复杂场景测试失败，请检查日志"
    fi

    # 最终清理
    cleanup_environment

    # 返回退出码
    if [ $TESTS_FAILED -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# 信号处理
trap cleanup_environment EXIT INT TERM

# 运行主函数
main "$@"
