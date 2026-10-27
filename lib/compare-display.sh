# compare 的紧凑终端视图；真实数据只显示在本机终端，不自动保存。
compare_display_row() {
  local label="$1" host="$2" workspace="$3" mark="${4:-auto}" sensitive="${5:-0}"
  [ "$c_ready" = 1 ] || { workspace=""; mark="—"; }
  if [ "$mark" = auto ]; then
    if [ -z "$host" ] || [ -z "$workspace" ]; then mark="—"
    elif [ "$host" = "$workspace" ]; then mark="⚠ ="
    else mark="✓ ≠"; fi
  fi
  if [ "$sensitive" = id ]; then
    [ -z "$host" ] || host="${host:0:8}…"
    [ -z "$workspace" ] || workspace="${workspace:0:8}…"
  fi
  if [ "$c_redact" = 1 ] && [ "$sensitive" != 0 ]; then
    [ -z "$host" ] || host="***"
    [ -z "$workspace" ] || workspace="***"
  fi
  printf '%s\t%s\t%s\t%s\n' "$label" "${host:-—}" "${workspace:-—}" "$mark"
}

compare_gib() {
  case "$1" in ''|*[!0-9]*) return ;; esac
  LC_ALL=C awk -v kib="$1" 'BEGIN { printf "%.1f GiB", kib / 1048576 }'
}

compare_compact() {
  local columns="${COLUMNS:-80}" ws_files="" ws_sys="" mark="" ws_permissions="" gateway="" paths=""
  case "$columns" in ''|*[!0-9]*) columns=80 ;; esac
  echo "${B}aibox compare${N}"
  {
    printf '项目\t本机\taibox\t对比\n'
    compare_display_row IPv4 "$hip4" "$wip4" auto 1
    if [ -n "$wip6" ]; then mark="⚠ 可连"; else mark="—"; fi
    compare_display_row IPv6 "$hip6" "$wip6" "$mark" 1
    compare_display_row 系统 "${C_H_OS_NAME:-$C_H_OS}" "${C_W_OS_NAME:-$C_W_OS}"
    compare_display_row 内核 "$C_H_KERNEL" "$C_W_KERNEL"
    compare_display_row CPU型号 "$C_H_CPU" "$C_W_CPU"
    compare_display_row CPU架构 "$C_H_ARCH" "$C_W_ARCH"
    compare_display_row CPU核心 "$C_H_CPU_COUNT" "$C_W_CPU_COUNT"
    compare_display_row 内存 "$(compare_gib "$C_H_MEMORY_KIB")" "$(compare_gib "$C_W_MEMORY_KIB")"
    compare_display_row 电脑名 "$C_H_HOSTNAME" "$C_W_HOSTNAME" auto 1
    compare_display_row UID:GID "$C_H_UID:$C_H_GID" "${C_W_UID:+$C_W_UID:$C_W_GID}"
    compare_display_row 机器ID "$C_H_MACHINE_ID" "$C_W_MACHINE_ID" auto id
    if [ -n "$C_W_BOOT_ID" ]; then mark="⚠ 可见"; else mark="—"; fi
    compare_display_row 开机ID "$C_H_BOOT_ID" "$C_W_BOOT_ID" "$mark" id
    if [ "$sys_mask" = yes ] && [ "$C_W_SYSFS" = unavailable ] && [ -z "$C_W_HARDWARE_ID" ]; then
      ws_sys="已遮挡"; mark="✓ 受限"
    elif [ "$C_W_SYSFS" = visible ]; then ws_sys="可读"; mark="⚠ 可见"
    else ws_sys=""; mark="—"; fi
    local host_sys=""
    if [ "$C_H_SYSFS" = visible ] || [ -n "$C_H_HARDWARE_ID" ]; then host_sys="可读"; fi
    compare_display_row 硬件目录 "$host_sys" "$ws_sys" "$mark"
    ws_files="${rw_count} 可写 / ${ro_count} 只读"; mark="✓ 受限"
    if [ "$unsafe" = 1 ] || [ "$privileged" = true ] || [ "$pid_mode" = host ]; then mark="⚠ 范围大"; fi
    compare_display_row 本机文件 当前用户权限 "$ws_files" "$mark"
    if [ "$C_W_HOST_PATH_ENV" = exposed ] || [ "$C_W_MOUNTINFO_HOME" = exposed ]; then paths="可见"; mark="⚠ 可见"
    else paths="未发现"; mark="—"; fi
    compare_display_row 本机路径 可见 "$paths" "$mark"
    if [ "$privileged" = true ] || [ "$net_cap" = 1 ] || [ "$unsafe" = 1 ]; then ws_permissions="可改网络"; mark="⚠ 权限大"
    elif [ "$drop_admin$drop_raw$drop_sys" = 111 ]; then ws_permissions="已移除"; mark="✓ 受限"
    else ws_permissions="未确认"; mark="—"; fi
    compare_display_row 网络权限 当前用户权限 "$ws_permissions" "$mark"
    case "$gw_state" in
      *'|true|healthy')
        if [ "$network" = "container:${gw_state%%|*}" ]; then gateway="healthy"; mark="✓"
        else gateway="未接入"; mark="⚠"; fi ;;
      *) gateway="未确认"; mark="—" ;;
    esac
    compare_display_row 网关 "" "$gateway" "$mark"
  } | LC_ALL=C awk -v columns="$columns" -f "$ROOT/lib/compare-table.awk"
  echo "✓ 不同/受限   ⚠ 相同/可见   — 未验证"
  if [ "$c_ready" != 1 ]; then echo "— aibox：$c_reason"
  elif [ "$sys_mask" != yes ]; then echo "⚠ 当前容器未启用硬件防护"; fi
  if [ -n "$hip4" ] && [ "$hip4" = "$wip4" ]; then echo "⚠ IP 相同 ≠ 直连泄漏（本机可能也在用代理）"; fi
}
