#!/bin/bash

# CUDA 环境管理脚本
# 用法: ./cuda-env.sh [命令] [选项]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"

# 默认配置
DEFAULT_CUDA_VERSION="12.4.0"
DEFAULT_UBUNTU_VERSION="20.04"
DEFAULT_WITH_TOOLKIT="false"
DEFAULT_PYTHON_VERSION="3.10"
DEFAULT_IMAGE_NAME="cuda-project-$(basename "$PROJECT_ROOT" | tr '[:upper:]' '[:lower:]')"

# 配置文件
CONFIG_DIR="$PROJECT_ROOT/.cuda-docker-config"
mkdir -p $CONFIG_DIR

CONFIG_FILE="$CONFIG_DIR/config"
DOCKERFILE="$CONFIG_DIR/Dockerfile"
DOCKER_COMPOSE_FILE="$CONFIG_DIR/docker-compose.yml"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# 保存配置
save_config() {
    cat > "$CONFIG_FILE" << EOF
CUDA_VERSION=$CUDA_VERSION
UBUNTU_VERSION=$UBUNTU_VERSION
WITH_TOOLKIT=$WITH_TOOLKIT
PYTHON_VERSION=$PYTHON_VERSION
IMAGE_NAME=$IMAGE_NAME
CUDA_VARIANT=$CUDA_VARIANT
EOF
    log_success "配置已保存"
}

# 加载配置
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

# 检查依赖
check_dependencies() {
    local missing=()
    
    if ! command -v docker &> /dev/null; then
        missing+=("docker")
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        missing+=("docker-compose")
    fi
    
    if ! command -v envsubst &> /dev/null; then
        missing+=("envsubst (gettext)")
    fi
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "缺少依赖: ${missing[*]}"
        echo "请安装以下软件:"
        for dep in "${missing[@]}"; do
            case $dep in
                "docker")
                    echo "  Docker: https://docs.docker.com/get-docker/"
                    ;;
                "docker-compose")
                    echo "  Docker Compose: https://docs.docker.com/compose/install/"
                    ;;
                "envsubst (gettext)")
                    echo "  envsubst:"
                    echo "    Ubuntu/Debian: sudo apt-get install gettext"
                    echo "    CentOS/RHEL: sudo yum install gettext"
                    ;;
            esac
        done
        exit 1
    fi
}

# 生成 Dockerfile
generate_dockerfile() {
    local cuda_version=$1
    local ubuntu_version=$2
    local cuda_variant=$3
    local python_version=$4
    
    # 获取当前用户信息
    local current_user=$(id -un)
    local current_uid=$(id -u)
    local current_gid=$(id -g)
    
    cat > "$DOCKERFILE" << EOF
FROM nvidia/cuda:${cuda_version}-${cuda_variant}-ubuntu${ubuntu_version}

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PATH /opt/conda/bin:\$PATH

# 安装基础工具
RUN apt-get update && apt-get install -y --no-install-recommends \\
    wget \\
    bzip2 \\
    ca-certificates \\
    libglib2.0-0 \\
    libxext6 \\
    libsm6 \\
    libxrender1 \\
    libgl1-mesa-glx \\
    git \\
    build-essential \\
    mercurial \\
    subversion \\
    vim \\
    curl \\
    sudo \\
    && apt-get clean \\
    && rm -rf /var/lib/apt/lists/*

# 安装 Miniconda
RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh && \\
    /bin/bash ~/miniconda.sh -b -p /opt/conda && \\
    rm ~/miniconda.sh && \\
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh

# 设置conda环境
RUN conda config --set always_yes yes --set changeps1 no && \\
    conda clean -ya && \\
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \\
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r && \\
    conda install python=${python_version} && \\
    conda config --set always_yes false --set changeps1 yes

# 创建工作目录
WORKDIR /workspace

# 创建用户并设置权限（在安装完所有软件后切换用户）
RUN groupadd -g ${current_gid} ${current_user} && \\
    useradd -m -u ${current_uid} -g ${current_gid} -s /bin/bash ${current_user} && \\
    echo "${current_user} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/${current_user} && \\
    chmod 0440 /etc/sudoers.d/${current_user} && \\
    chown -R ${current_user}:${current_user} /opt/conda && \\
    chown -R ${current_user}:${current_user} /workspace

# 切换用户
USER ${current_user}

# 为用户配置 conda
RUN echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \\
    echo "conda activate base" >> ~/.bashrc

CMD ["/bin/bash"]
EOF
    log_success "Dockerfile 已生成"
}

# 生成 docker-compose.yml
generate_docker_compose() {
    local image_name=$1
    
    cat > "$DOCKER_COMPOSE_FILE" << EOF
version: '3.8'

services:
  cuda-environment:
    build:
      context: .
      dockerfile: Dockerfile
    image: ${image_name}
    network_mode: host
    container_name: ${image_name}-container
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
    volumes:
      - ..:/workspace
      - /tmp/.X11-unix:/tmp/.X11-unix
    working_dir: /workspace
    stdin_open: true
    tty: true
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
    log_success "docker-compose.yml 已生成"
}

# 构建镜像
build_image() {
    log_info "开始构建镜像..."
    cd "$CONFIG_DIR"
    
    if docker-compose build; then
        log_success "镜像构建成功!"
        log_info "镜像名称: $IMAGE_NAME"
        log_info "工作目录: $PROJECT_ROOT"
    else
        log_error "镜像构建失败!"
        exit 1
    fi
}

# 检查镜像是否存在
check_image_exists() {
    docker image inspect "$1" > /dev/null 2>&1
}

# 检查容器状态
check_container_status() {
    if docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep -q "$1-container"; then
        local status=$(docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep "$1-container" | awk '{print $2}')
        if [[ "$status" == Up* ]]; then
            echo "running"
        else
            echo "stopped"
        fi
    else
        echo "nonexistent"
    fi
}

# 构建命令
build_command() {
    # 解析构建参数
    local cuda_version=$DEFAULT_CUDA_VERSION
    local ubuntu_version=$DEFAULT_UBUNTU_VERSION
    local with_toolkit=$DEFAULT_WITH_TOOLKIT
    local python_version=$DEFAULT_PYTHON_VERSION
    local image_name=$DEFAULT_IMAGE_NAME
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--cuda-version)
                cuda_version="$2"
                shift 2
                ;;
            -u|--ubuntu-version)
                ubuntu_version="$2"
                shift 2
                ;;
            -t|--with-toolkit)
                with_toolkit="$2"
                shift 2
                ;;
            -p|--python-version)
                python_version="$2"
                shift 2
                ;;
            -i|--image-name)
                image_name="$2"
                shift 2
                ;;
            *)
                log_error "未知选项: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # 根据是否包含 toolkit 设置变体
    if [ "$with_toolkit" = "true" ]; then
        local cuda_variant="devel"
    else
        local cuda_variant="base"
    fi
    
    # 设置全局变量用于保存配置
    CUDA_VERSION=$cuda_version
    UBUNTU_VERSION=$ubuntu_version
    WITH_TOOLKIT=$with_toolkit
    PYTHON_VERSION=$python_version
    IMAGE_NAME=$image_name
    CUDA_VARIANT=$cuda_variant
    
    echo "构建配置:"
    echo "  CUDA 版本: $CUDA_VERSION"
    echo "  Ubuntu 版本: $UBUNTU_VERSION"
    echo "  CUDA 变体: $CUDA_VARIANT"
    echo "  Python 版本: $PYTHON_VERSION"
    echo "  镜像名称: $IMAGE_NAME"
    echo "  项目路径: $PROJECT_ROOT"
    
    # 检查依赖
    check_dependencies
    
    # 生成配置文件
    generate_dockerfile "$CUDA_VERSION" "$UBUNTU_VERSION" "$CUDA_VARIANT" "$PYTHON_VERSION"
    generate_docker_compose "$IMAGE_NAME"
    save_config
    
    # 构建镜像
    build_image
}

# 运行命令
run_command() {
    if ! load_config; then
        log_error "未找到配置文件，请先运行构建命令: $0 build"
        exit 1
    fi
    
    if ! check_image_exists "$IMAGE_NAME"; then
        log_error "镜像 '$IMAGE_NAME' 不存在，请先运行构建命令: $0 build"
        exit 1
    fi
    
    local command=${1:-exec}
    
    case $command in
        "status")
            local status=$(check_container_status "$IMAGE_NAME")
            case $status in
                "running")
                    log_success "容器正在运行"
                    ;;
                "stopped")
                    log_warning "容器已停止"
                    ;;
                "nonexistent")
                    log_info "容器不存在"
                    ;;
            esac
            ;;
        "start")
            log_info "启动容器..."
            cd "$CONFIG_DIR"
            docker-compose up -d
            ;;
        "stop")
            log_info "停止容器..."
            cd "$CONFIG_DIR"
            docker-compose down
            ;;
        "restart")
            log_info "重启容器..."
            cd "$CONFIG_DIR"
            docker-compose down
            docker-compose up -d
            ;;
        "logs")
            cd "$CONFIG_DIR"
            docker-compose logs -f
            ;;
        "exec"|"bash")
            local status=$(check_container_status "$IMAGE_NAME")
            case $status in
                "running")
                    log_info "进入容器..."
                    docker exec -it "${IMAGE_NAME}-container" bash
                    ;;
                "stopped")
                    log_info "启动容器并进入..."
                    cd "$CONFIG_DIR"
                    docker-compose up -d
                    sleep 2
                    docker exec -it "${IMAGE_NAME}-container" bash
                    ;;
                "nonexistent")
                    log_info "创建并启动容器..."
                    cd "$CONFIG_DIR"
                    docker-compose up -d
                    sleep 2
                    docker exec -it "${IMAGE_NAME}-container" bash
                    ;;
            esac
            ;;
        "remove")
            log_info "清理容器和镜像..."
            cd "$CONFIG_DIR"
            docker-compose down 2>/dev/null || true
            docker rmi "$IMAGE_NAME" 2>/dev/null || true
            rm -rf "$CONFIG_DIR" 2>/dev/null || true
            log_success "已清理所有容器、镜像和配置文件"
            ;;
        *)
            log_error "未知运行命令: $command"
            usage
            exit 1
            ;;
    esac
}

# 配置命令
config_command() {
    if load_config; then
        echo "当前配置:"
        echo "  CUDA 版本: $CUDA_VERSION"
        echo "  Ubuntu 版本: $UBUNTU_VERSION"
        echo "  CUDA 变体: $CUDA_VARIANT"
        echo "  Python 版本: $PYTHON_VERSION"
        echo "  镜像名称: $IMAGE_NAME"
    else
        log_info "暂无配置，使用默认配置:"
        echo "  CUDA 版本: $DEFAULT_CUDA_VERSION"
        echo "  Ubuntu 版本: $DEFAULT_UBUNTU_VERSION"
        echo "  CUDA 变体: runtime"
        echo "  Python 版本: $DEFAULT_PYTHON_VERSION"
        echo "  镜像名称: $DEFAULT_IMAGE_NAME"
    fi
}

# 显示用法
usage() {
    cat << EOF
CUDA 环境管理脚本

用法: $0 <命令> [选项]

命令:
  build [选项]    构建 CUDA 环境镜像
  run [子命令]    运行和管理容器
  config          显示当前配置
  help            显示此帮助信息

构建选项:
  -c, --cuda-version     CUDA 版本 (默认: $DEFAULT_CUDA_VERSION)
  -u, --ubuntu-version   Ubuntu 版本 (默认: $DEFAULT_UBUNTU_VERSION)
  -t, --with-toolkit     是否包含 CUDA Toolkit (true/false) (默认: $DEFAULT_WITH_TOOLKIT)
  -p, --python-version   Python 版本 (默认: $DEFAULT_PYTHON_VERSION)
  -i, --image-name       镜像名称 (默认: 基于项目名称)

运行子命令:
  (无子命令)      启动并进入容器
  status         查看容器状态
  start          启动容器
  stop           停止容器
  restart        重启容器
  logs           查看容器日志
  exec           进入容器
  remove         删除容器、镜像和配置文件

示例:
  $0 build -c 11.8.0 -p 3.8
  $0 run
  $0 run status
  $0 run logs
  $0 config
  $0 run remove
EOF
}

# 主函数
main() {
    local command=$1
    shift
    
    case $command in
        "build")
            build_command "$@"
            ;;
        "run")
            run_command "$@"
            ;;
        "logs")
            run_command logs
            ;;
        "remove")
            run_command remove
            ;;
        "restart")
            run_command restart
            ;;
        "status")
            run_command status
            ;;
        "exec")
            run_command exec
            ;;
        "config")
            config_command
            ;;
        "help"|"-h"|"--help"|"")
            usage
            ;;
        *)
            log_error "未知命令: $command"
            usage
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
