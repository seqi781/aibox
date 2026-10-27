#!/bin/sh
# aibox compare 的只读探针（宿主机和容器共用）。不联网，不读取工具凭据。
# 含原始机器标识的结果仅交给本机 compare 进程比较，不落盘、不发送给对方环境。
# AIBOX_ENVIRONMENT_PROBE_V1
set -u
emit() { printf '%s=' "$1"; printf '%s' "$2" | LC_ALL=C tr -d '\000-\037\177'; printf '\n'; }
read_value() { if [ -r "$1" ]; then cat "$1" 2>/dev/null; fi; return 0; }
os="$(uname -s 2>/dev/null || true)"
os_name="$os"
case "$os" in
  Darwin) os_name="macOS $(sw_vers -productVersion 2>/dev/null || true)" ;;
  Linux) os_name="$(awk -F= '/^PRETTY_NAME=/{value=substr($0,index($0,"=")+1);gsub(/^"|"$/,"",value);print value;exit}' /etc/os-release 2>/dev/null)" ;;
esac
arch="$(uname -m 2>/dev/null || true)"
case "$arch" in arm64) arch=aarch64 ;; amd64) arch=x86_64 ;; esac
emit OS "$os"
emit OS_NAME "$os_name"
emit KERNEL "$(uname -r 2>/dev/null || true)"
emit ARCH "$arch"
emit HOSTNAME "$(hostname 2>/dev/null || true)"
emit UID "$(id -u 2>/dev/null || true)"
emit GID "$(id -g 2>/dev/null || true)"
emit USERNAME "$(id -un 2>/dev/null || true)"
emit MACHINE_ID "$(read_value /etc/machine-id)"
emit BOOT_ID "$(read_value /proc/sys/kernel/random/boot_id)"
hardware_id=""; cpu=""; count=""; memory=""
case "$os" in
  Darwin)
    cpu="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
    count="$(sysctl -n hw.logicalcpu 2>/dev/null || true)"
    memory="$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f", $1/1024}')"
    hardware_id="$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F '"' '/"IOPlatformUUID"/{print $(NF-1); exit}')"
    ;;
  Linux)
    cpu="$(awk -F ': *' '/^(model name|Hardware|Model)[[:space:]]*:/{print $2; exit}' /proc/cpuinfo 2>/dev/null)"
    count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
    memory="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)"
    hardware_id="$(read_value /sys/devices/virtual/dmi/id/product_uuid)"
    [ -n "$hardware_id" ] || hardware_id="$(read_value /sys/devices/virtual/dmi/id/board_serial)"
    ;;
esac
emit CPU "$cpu"
emit CPU_COUNT "$count"
emit MEMORY_KIB "$memory"
emit HARDWARE_ID "$hardware_id"
if [ -d /sys/devices ]; then emit SYSFS visible; else emit SYSFS unavailable; fi
case "${AIBOX_MOUNTS:-}" in *' -> '*) emit HOST_PATH_ENV exposed ;; *) emit HOST_PATH_ENV absent ;; esac
if [ -r /proc/self/mountinfo ] && awk '$4 ~ /(^|\/)(Users|home)\/[^/]+/ || $4 ~ /(^|\/)root(\/|$)/ {found=1} END {exit !found}' /proc/self/mountinfo; then
  emit MOUNTINFO_HOME exposed
else
  emit MOUNTINFO_HOME absent
fi
emit PROBE_VERSION 1
