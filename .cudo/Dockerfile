FROM nvidia/cuda:12.4.0-base-ubuntu20.04

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PATH /opt/conda/bin:$PATH

# 安装基础工具
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    bzip2 \
    ca-certificates \
    libglib2.0-0 \
    libxext6 \
    libsm6 \
    libxrender1 \
    libgl1-mesa-glx \
    git \
    build-essential \
    mercurial \
    subversion \
    tmux \
    vim \
    curl \
    sudo \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 安装 Miniconda
RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh

# 设置conda环境
RUN conda config --set always_yes yes --set changeps1 no && \
    conda clean -ya && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r && \
    conda install python=3.10 && \
    conda config --set always_yes false --set changeps1 yes

# 创建工作目录
WORKDIR /workspace

# 创建用户并设置权限（在安装完所有软件后切换用户）
RUN groupadd -g 1000 omnispace && \
    useradd -m -u 1000 -g 1000 -s /bin/bash omnispace && \
    echo "omnispace ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/omnispace && \
    chmod 0440 /etc/sudoers.d/omnispace && \
    chown -R omnispace:omnispace /opt/conda && \
    chown -R omnispace:omnispace /workspace

# 切换用户
USER omnispace

# 为用户配置 conda
RUN echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo "conda activate base" >> ~/.bashrc

CMD ["/bin/bash"]
