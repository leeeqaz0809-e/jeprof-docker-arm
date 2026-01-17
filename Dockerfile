# --- 第一阶段：编译环境 (Builder) ---
FROM debian:bullseye-slim AS builder

# 替换源以加快速度（可选，但在 Github Actions 中通常不需要）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    git \
    autoconf \
    make \
    ca-certificates \
    wget

# 下载并编译 jemalloc (为了获取 jeprof 和 libjemalloc.so)
WORKDIR /tmp
# 使用 5.3.0 版本，比较稳定
RUN git clone --depth 1 --branch 5.3.0 https://github.com/jemalloc/jemalloc.git
WORKDIR /tmp/jemalloc
RUN ./autogen.sh && \
    ./configure --enable-prof --prefix=/usr/local && \
    make -j$(nproc) && \
    make install

# --- 第二阶段：最终运行镜像 (Runtime) ---
FROM debian:bullseye-slim

# 设置工作目录
WORKDIR /app

# 1. 安装运行时依赖
# graphviz: 生成 SVG 必须
# perl: jeprof 脚本依赖
# binutils: 包含 nm, objdump (jeprof 解析符号必须)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    graphviz \
    perl \
    binutils \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

# 2. 从编译阶段复制 jemalloc 结果
COPY --from=builder /usr/local/lib/libjemalloc.so.2 /usr/local/lib/libjemalloc.so.2
COPY --from=builder /usr/local/bin/jeprof /usr/local/bin/jeprof

# 3. 准备 Java 环境
# 注意：为了让 jeprof 完美工作，Java 二进制文件必须与生成 heap 的完全一致。
# 这里我们下载 Temurin OpenJDK 8 (与截图中的 openjdk-8 路径结构最接近) 作为一个"保底"
# 建议运行时通过 -v 挂载宿主机的 Java 目录
ENV JAVA_HOME=/usr/local/openjdk-8
ENV PATH=$JAVA_HOME/bin:$PATH

RUN wget -qO- https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u332-b09/OpenJDK8U-jdk_aarch64_linux_hotspot_8u332b09.tar.gz | tar -xz -C /usr/local/ && \
    mv /usr/local/jdk8u332-b09 /usr/local/openjdk-8

# 4. 路径兼容处理 (解决 /ust/ 拼写问题)
# 截图中有 /usr/local/openjdk-8，你的命令里有 /ust/local/openjdk-8
# 创建软链，让两者都指向同一个真实的 Java
RUN mkdir -p /ust/local && \
    ln -s /usr/local/openjdk-8 /ust/local/openjdk-8 && \
    ln -s /usr/local/lib/libjemalloc.so.2 /usr/lib/libjemalloc.so.2 && \
    chmod +x /usr/local/bin/jeprof

# 验证
RUN java -version && dot -V && jeprof --version

CMD ["/bin/bash"]
