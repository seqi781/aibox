# aibox 工作区：Debian 13 + Node 24 LTS + 常用开发工具 + tmux
# AI 工具（Claude Code / Codex）不打进镜像，首次启动时经网关安装到持久化 home，可自动更新
FROM node:24-trixie-slim

ARG USER_UID=1000
ARG USER_GID=1000
ARG USERNAME=dev
ARG APT_MIRROR=
ARG EXTRA_PACKAGES=

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    TERM=xterm-256color COLORTERM=truecolor \
    EDITOR=vim \
    NPM_CONFIG_PREFIX=/home/${USERNAME}/.npm-global \
    PATH=/home/${USERNAME}/.local/bin:/home/${USERNAME}/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN set -eux; \
    if [ -n "$APT_MIRROR" ]; then sed -i "s|http://deb.debian.org|$APT_MIRROR|g" /etc/apt/sources.list.d/debian.sources; fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      bash-completion ca-certificates curl wget gnupg git git-lfs openssh-client \
      tmux vim nano less ncurses-term \
      procps psmisc htop lsof iproute2 iputils-ping dnsutils netcat-openbsd \
      ripgrep fd-find jq tree unzip zip xz-utils bzip2 file patch rsync \
      python3 python3-pip python3-venv build-essential pkg-config \
      sudo tzdata $EXTRA_PACKAGES; \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd; \
    rm -rf /var/lib/apt/lists/*

# 与宿主机 UID/GID 对齐，保证挂载目录里新建的文件归属正确（macOS 常见 501:20）
RUN set -eux; \
    userdel -r node 2>/dev/null || true; groupdel node 2>/dev/null || true; \
    if ! getent group "$USER_GID" >/dev/null; then groupadd -g "$USER_GID" "$USERNAME"; fi; \
    useradd -o -m -s /bin/bash -u "$USER_UID" -g "$USER_GID" "$USERNAME"; \
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/aibox; chmod 440 /etc/sudoers.d/aibox; \
    mkdir -p /workspace "/home/$USERNAME/.npm-global" "/home/$USERNAME/.local/bin"; \
    chown -R "$USER_UID:$USER_GID" /workspace "/home/$USERNAME"

COPY rootfs/ /
RUN chmod +x /usr/local/bin/aibox-*; \
    echo '[ -f /etc/aibox/bashrc ] && . /etc/aibox/bashrc' >> /etc/bash.bashrc

USER ${USERNAME}
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/aibox-entrypoint"]
CMD ["sleep", "infinity"]
