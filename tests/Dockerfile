# 测试用镜像：指定版本的 bash（官方 bash 镜像）+ 测试所需工具
# 构建: docker build --build-arg BASH_TAG=3.2 -t aibox-test:bash3.2 tests/
#   - awk 换成 nawk（BWK awk，与 macOS 相同）；sed、grep 等是 busybox 版本。两者都不是 GNU 工具
#   - 和 macOS 一样提供 /bin/bash
ARG BASH_TAG=3.2
FROM bash:${BASH_TAG}
RUN apk add --no-cache python3 perl zsh curl nawk \
 && ln -sf /usr/bin/nawk /usr/local/bin/awk \
 && ln -sf /usr/local/bin/bash /bin/bash
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
