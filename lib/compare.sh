# aibox compare：只读比较当前终端和正在运行的 workspace；兼容 bash 3.2。
# 数据只在宿主机比较和显示；不写报告文件，不把宿主机探测结果传进容器。
. "$ROOT/lib/compare-display.sh"

compare_parse() {
  local side="$1" line key value
  while IFS= read -r line; do
    key="${line%%=*}"; value="${line#*=}"
    case "$key" in
      OS|OS_NAME|KERNEL|ARCH|HOSTNAME|UID|GID|USERNAME|MACHINE_ID|BOOT_ID|CPU|CPU_COUNT|MEMORY_KIB|HARDWARE_ID|SYSFS|HOST_PATH_ENV|MOUNTINFO_HOME|PROBE_VERSION)
        printf -v "C_${side}_$key" '%s' "$value" ;;
    esac
  done
}

compare_json_string() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

compare_row() {
  local key="$1" label="$2" host="$3" workspace="$4" result="$5" word=""
  case "$result" in
    improved) c_improved=$((c_improved + 1)); word="暴露减少" ;;
    warning) c_warnings=$((c_warnings + 1)); word="需要注意" ;;
    same) word="仍然可见" ;;
    unknown) c_unknown=$((c_unknown + 1)); word="未验证" ;;
  esac
  if [ "$c_json" = 1 ]; then
    printf '%s{"id":' "$c_comma"; compare_json_string "$key"
    printf ',"label":'; compare_json_string "$label"
    printf ',"host":'; compare_json_string "$host"
    printf ',"aibox":'; compare_json_string "$workspace"
    printf ',"result":'; compare_json_string "$result"; printf '}'
    c_comma=,
  else
    printf '\n%s%s%s  [%s]\n  直接使用：%s\n  使用 aibox：%s\n' "$B" "$label" "$N" "$word" "$host" "$workspace"
  fi
}

compare_identifier() {
  local key="$1" label="$2" host="$3" workspace="$4" base="可读取（具体值已隐藏）" host_text="本次未读到"
  [ -z "$host" ] || host_text="$base"
  if [ "$c_ready" != 1 ]; then
    compare_row "$key" "$label" "$host_text" "未验证：$c_reason" unknown
  elif [ -z "$workspace" ]; then
    compare_row "$key" "$label" "$host_text" "本次未读到；不代表所有读取方法都被阻止" unknown
  elif [ -z "$host" ]; then
    compare_row "$key" "$label" "本次未读到，无法比较" "可读取；无法确认是否与本机相同" unknown
  elif [ "$host" = "$workspace" ]; then
    compare_row "$key" "$label" "$base" "与本机相同，仍可用于关联环境" warning
  else
    compare_row "$key" "$label" "$base" "与本机不同（具体值已隐藏）" improved
  fi
}

compare_ip_valid() {
  case "$1" in
    4) printf '%s\n' "$2" | awk -F. 'NF!=4{exit 1} {for(i=1;i<=4;i++) if($i!~/^[0-9]+$/ || $i>255) exit 1}' ;;
    6) case "$2" in *[!0-9a-fA-F:]*|'') return 1 ;; *:*) return 0 ;; *) return 1 ;; esac ;;
  esac
}

cmd_compare() {
  local c_json=0 c_offline=0 c_redact=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) c_json=1 ;;
      --offline) c_offline=1 ;;
      --redact) c_redact=1 ;;
      -h|--help)
        echo "用法: aibox compare [--offline] [--redact] [--json]"
        echo "只读比较本机与正在运行的 aibox，不启动或重启环境，不读取 Claude 凭据。"
        echo "默认向 api.ipify.org / api6.ipify.org 查询两边出口 IP；--offline 跳过联网查询。"
        echo "默认用表格显示实际 IP、电脑名和系统数据；机器/开机 ID 只显示前 8 位。"
        echo "--redact 隐藏 IP、电脑名和 ID；--json 保持脱敏结构化输出。不自动保存报告。"
        echo "返回码: 0 已完成（含主动跳过项），2 环境不可用或检测不完整；暴露项见报告。"
        return 0 ;;
      *) echo "未知参数: $1（用法: aibox compare [--offline] [--redact] [--json]）" >&2; return 2 ;;
    esac
    shift
  done
  local side key
  for side in H W; do
    for key in OS OS_NAME KERNEL ARCH HOSTNAME UID GID USERNAME MACHINE_ID BOOT_ID CPU CPU_COUNT MEMORY_KIB HARDWARE_ID SYSFS HOST_PATH_ENV MOUNTINFO_HOME PROBE_VERSION; do
      local "C_${side}_$key="
    done
  done
  local probe="$ROOT/lib/environment-probe.sh" output="" c_ready=0 c_reason="Docker 不可用"
  output="$(sh "$probe" 2>/dev/null)" || { echo "本机信息读取失败" >&2; return 2; }
  compare_parse H <<< "$output"
  [ "$C_H_PROBE_VERSION" = 1 ] || { echo "本机信息读取失败" >&2; return 2; }

  local meta="" value="" running="" network="" privileged="" pid_mode="" sys_mask=""
  local bind_count=0 rw_count=0 ro_count=0 unsafe=0 net_cap=0 drop_admin=0 drop_raw=0 drop_sys=0
  # 只检查实际运行的容器，绝不调用 ensure_up / load_env / gen_override。
  if find_docker 2>/dev/null; then
    c_reason="aibox 未运行或 Docker 无法访问"
    meta="$(docker inspect --format '{{printf "RUNNING=%t\n" .State.Running}}{{printf "NETWORK=%s\n" .HostConfig.NetworkMode}}{{printf "PRIVILEGED=%t\n" .HostConfig.Privileged}}{{printf "PID_MODE=%s\n" .HostConfig.PidMode}}{{range .HostConfig.CapDrop}}{{printf "DROP=%s\n" .}}{{end}}{{range .HostConfig.CapAdd}}{{printf "ADD=%s\n" .}}{{end}}{{if index .HostConfig.Tmpfs "/sys"}}{{printf "SYS_MASK=yes\n"}}{{end}}{{range .Mounts}}{{printf "MOUNT=%s|%t|%s|%s\n" .Type .RW .Source .Destination}}{{end}}' "$WS" 2>/dev/null)" || meta=""
    local line mtype mrw msource mtarget
    while IFS= read -r line; do
      key="${line%%=*}"; value="${line#*=}"
      case "$key" in
        RUNNING) running="$value" ;; NETWORK) network="$value" ;; PRIVILEGED) privileged="$value" ;;
        PID_MODE) pid_mode="$value" ;; SYS_MASK) sys_mask="$value" ;;
        DROP) value="${value#CAP_}"; case "$value" in ALL) drop_admin=1; drop_raw=1; drop_sys=1 ;; NET_ADMIN) drop_admin=1 ;; NET_RAW) drop_raw=1 ;; SYS_ADMIN) drop_sys=1 ;; esac ;;
        ADD) value="${value#CAP_}"; case "$value" in ALL|NET_ADMIN|NET_RAW|SYS_ADMIN) net_cap=1 ;; esac ;;
        MOUNT)
          IFS='|' read -r mtype mrw msource mtarget <<< "$value"
          [ "$mtype" = bind ] || continue
          bind_count=$((bind_count + 1))
          if [ "$mrw" = true ]; then rw_count=$((rw_count + 1)); else ro_count=$((ro_count + 1)); fi
          case "$msource/" in //|"$USER_HOME/"|/Users/|/home/|/root/|*/.ssh/*|*/.aws/*|*/.kube/*|*/.config/*) unsafe=1 ;; esac
          case "$USER_HOME/" in "$msource"/*) unsafe=1 ;; esac
          case "$msource|$mtarget" in *docker.sock*|*podman.sock*) unsafe=1 ;; esac
          ;;
      esac
    done <<< "$meta"
    if [ "$running" = true ]; then
      c_reason="容器内信息读取失败"
      if output="$(docker exec -i "$WS" sh < "$probe" 2>/dev/null)"; then
        compare_parse W <<< "$output"
        if [ "$C_W_PROBE_VERSION" = 1 ] && [ -n "$C_W_OS$C_W_HOSTNAME" ]; then c_ready=1; c_reason=""; fi
      fi
    fi
  fi

  local hip4="" hip6="" wip4="" wip6="" c_partial=0
  [ "$c_ready" = 1 ] || c_partial=1
  if [ "$c_offline" = 0 ]; then
    hip4="$(curl -4 -fsS --connect-timeout 3 --max-time 6 https://api.ipify.org 2>/dev/null || true)"
    hip6="$(curl -6 -fsS --connect-timeout 3 --max-time 4 https://api6.ipify.org 2>/dev/null || true)"
    if [ "$c_ready" = 1 ]; then
      wip4="$(docker exec "$WS" curl -4 -fsS --connect-timeout 3 --max-time 6 https://api.ipify.org 2>/dev/null || true)"
      wip6="$(docker exec "$WS" curl -6 -fsS --connect-timeout 3 --max-time 4 https://api6.ipify.org 2>/dev/null || true)"
    fi
    compare_ip_valid 4 "$hip4" || hip4=""
    compare_ip_valid 4 "$wip4" || wip4=""
    compare_ip_valid 6 "$hip6" || hip6=""
    compare_ip_valid 6 "$wip6" || wip6=""
    [ -n "$hip4" ] && [ -n "$wip4" ] || c_partial=1
  fi

  local gw_state=""
  if [ "$c_ready" = 1 ]; then
    gw_state="$(docker inspect --format '{{.Id}}|{{.State.Running}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$GW" 2>/dev/null || true)"
  fi
  if [ "$c_json" = 0 ]; then
    compare_compact
    [ "$c_partial" = 0 ] || return 2
    return 0
  fi
  local c_comma="" c_improved=0 c_warnings=0 c_unknown=0 host="" workspace="" result=""
  if [ "$c_json" = 1 ]; then
    printf '{"schema_version":1,"scope":"information_exposure","offline":%s,"workspace_running":%s,"workspace_probe_ok":%s,"rows":[' \
      "$([ "$c_offline" = 1 ] && echo true || echo false)" "$([ "$running" = true ] && echo true || echo false)" "$([ "$c_ready" = 1 ] && echo true || echo false)"
  fi
  host="当前终端的上网出口（具体 IP 已隐藏）"
  if [ "$c_offline" = 1 ]; then workspace="未验证：已选择跳过联网查询"; result=unknown
  elif [ "$c_ready" != 1 ]; then workspace="未验证：$c_reason"; result=unknown
  elif [ -z "$hip4" ] || [ -z "$wip4" ]; then workspace="查询失败，无法判断是否与本机相同"; result=unknown
  elif [ "$hip4" = "$wip4" ]; then workspace="与本机当前出口相同；可能是本机也在用代理，不能据此认定直连泄漏"; result=warning
  else workspace="与本机当前出口不同；节点服务商仍能看到连接来源"; result=improved; fi
  compare_row ipv4 "上网 IP" "$host" "$workspace" "$result"
  if [ "$c_offline" = 1 ] || [ "$c_ready" != 1 ]; then
    compare_row ipv6 "IPv6 另一条上网通道" "未验证" "未验证" unknown
  elif [ -n "$wip6" ]; then
    if [ -n "$hip6" ]; then host="可访问（IP 已隐藏）"; else host="本次未连通"; fi
    compare_row ipv6 "IPv6 另一条上网通道" "$host" "可以联网，需要检查是否绕过节点" warning
  else
    if [ -n "$hip6" ]; then host="可访问（IP 已隐藏）"; else host="本次未连通"; fi
    compare_row ipv6 "IPv6 另一条上网通道" "$host" "本次未连通；网络故障也会产生这个结果，尚不能证明已阻断" unknown
  fi

  if [ "$c_ready" != 1 ]; then
    compare_row files "能打开哪些本机文件" "当前终端有权访问的文件；还取决于 Claude 的权限设置" "未验证：$c_reason" unknown
  elif [ "$unsafe" = 1 ] || [ "$privileged" = true ] || [ "$pid_mode" = host ]; then
    compare_row files "能打开哪些本机文件" "当前终端有权访问的文件" "发现范围过大的目录、凭据目录或管理接口，需要检查" warning
  else
    compare_row files "能打开哪些本机文件" "当前终端有权访问的文件；还取决于 Claude 的权限设置" "实际开放 $bind_count 个本机目录或文件：$rw_count 个可修改，$ro_count 个只读；项目内容和 Git 记录仍可含身份" improved
  fi
  compare_identifier hostname "电脑名称" "$C_H_HOSTNAME" "$C_W_HOSTNAME"
  if [ "$c_ready" = 1 ] && [ -n "$C_W_MACHINE_ID" ] && [ -z "$C_H_MACHINE_ID" ] && [ "$C_W_MACHINE_ID" != "$C_H_HARDWARE_ID" ]; then
    compare_row machine_id "系统机器标识" "本次未读到同类标识，无法直接比较" "可读取容器自己的标识；本机同类标识未读到，不能实测确认差异" unknown
  else compare_identifier machine_id "系统机器标识" "$C_H_MACHINE_ID" "$C_W_MACHINE_ID"; fi

  if [ "$c_ready" != 1 ]; then
    compare_row hardware_ids "硬件编号与设备目录" "系统允许时可以读取" "未验证：$c_reason" unknown
  elif [ "$sys_mask" = yes ] && [ "$C_W_SYSFS" = unavailable ] && [ -z "$C_W_HARDWARE_ID" ]; then
    compare_row hardware_ids "硬件编号与设备目录" "系统允许时可以读取" "已遮住硬件信息目录；不代表所有硬件读取方法都被阻止" improved
  elif [ -n "$C_W_HARDWARE_ID" ] || [ "$C_W_SYSFS" = visible ]; then
    compare_row hardware_ids "硬件编号与设备目录" "系统允许时可以读取" "仍能读取部分硬件目录或标识；旧容器或关闭防护时可能如此" warning
  else
    compare_row hardware_ids "硬件编号与设备目录" "系统允许时可以读取" "本次没读到；未确认防护生效" unknown
  fi
  compare_identifier boot_id "Linux 开机标识" "$C_H_BOOT_ID" "$C_W_BOOT_ID"

  host="${C_H_OS:-未知} / ${C_H_ARCH:-未知}；内核 ${C_H_KERNEL:-未知}"
  workspace="${C_W_OS:-未知} / ${C_W_ARCH:-未知}；内核 ${C_W_KERNEL:-未知}"
  if [ "$c_ready" != 1 ]; then workspace="未验证：$c_reason"; result=unknown
  else result=same; workspace="${workspace}；这些信息仍可见，Linux 上可能与本机相同"; fi
  compare_row system "系统、CPU 架构与内核" "$host" "$workspace" "$result"
  if [ "$c_ready" != 1 ]; then workspace="未验证：$c_reason"; result=unknown
  else
    workspace="CPU 核心数 ${C_W_CPU_COUNT:-未知}；内存容量和部分 CPU 信息仍可见"
    if [ -n "$C_W_CPU" ] && [ "$C_W_CPU" = "$C_H_CPU" ]; then workspace="${workspace}；CPU 型号与本机相同"; fi
    result=same
  fi
  compare_row cpu_memory "CPU 与内存" "CPU 核心数 ${C_H_CPU_COUNT:-未知}；当前终端可读到的硬件信息" "$workspace" "$result"
  if [ "$c_ready" = 1 ] && [ "$C_H_UID:$C_H_GID" = "$C_W_UID:$C_W_GID" ]; then
    compare_row user_id "用户编号" "当前终端的用户编号（具体值已隐藏）" "与本机对齐，保证修改项目后的文件归属正确；这不是唯一身份标识" same
  else compare_identifier user_id "用户编号" "$C_H_UID:$C_H_GID" "${C_W_UID:+$C_W_UID:$C_W_GID}"; fi

  if [ "$c_ready" != 1 ]; then workspace="未验证：$c_reason"; result=unknown
  elif [ "$C_W_HOST_PATH_ENV" = exposed ] || [ "$C_W_MOUNTINFO_HOME" = exposed ]; then workspace="目录提示或文件挂载信息仍含本机路径；移除提示路径也不能隐藏所有挂载信息"; result=warning
  else workspace="本次未在目录提示和挂载信息中发现用户目录路径；项目名和文件内容仍可能含个人信息"; result=unknown; fi
  compare_row host_paths "本机用户名与项目路径" "当前终端能看到自己的用户名和完整路径" "$workspace" "$result"

  if [ "$c_ready" != 1 ]; then workspace="未验证：$c_reason"; result=unknown
  elif [ "$privileged" = true ] || [ "$net_cap" = 1 ] || [ "$pid_mode" = host ] || [ "$unsafe" = 1 ]; then
    workspace="发现额外权限、主机进程共享或危险挂载，需要检查"; result=warning
  elif [ "$drop_admin$drop_raw$drop_sys" = 111 ]; then
    workspace="已移除改动网关所需的关键权限；未检查所有提权或内核漏洞"; result=improved
  else workspace="没有确认关键网络权限已移除"; result=unknown; fi
  compare_row permissions "改动网络的权限" "取决于本机权限和 Claude 的授权设置" "$workspace" "$result"

  result=unknown
  case "$gw_state" in
    *'|true|healthy')
      if [ "$network" = "container:${gw_state%%|*}" ]; then workspace="确认正在借用健康网关；本次没有断开节点测试，断线阻断请用 aibox doctor --full 验证"
      else workspace="工作环境未使用预期的网关，需要检查"; result=warning; fi ;;
    *) workspace="没有确认健康网关；本次未做断线测试" ;;
  esac
  compare_row disconnect "节点断了会不会换网络" "取决于本机的代理或 VPN 设置，本次未模拟断线" "$workspace" "$result"
  compare_row account "账号、登录与封号风险" "账号和使用行为仍可关联身份；本次不读取账号资料" "相同账号仍可被识别；浏览器登录用自己的网络；不评估封号概率，也不判断节点信誉" same

  if [ "$c_json" = 1 ]; then
    printf '],"summary":{"improved_items":%d,"warnings":%d,"unverified_items":%d,"partial":%s},"note":' \
      "$c_improved" "$c_warnings" "$c_unknown" "$([ "$c_partial" = 1 ] && echo true || echo false)"
    compare_json_string "比较信息暴露面，不代表 Claude 已读取、上传或认定身份；不评估封号概率。原始标识未显示、未落盘、未传入对方环境。"
    printf '}\n'
  else
    echo
    echo "${B}对比结果${N}：$c_improved 项确认减少暴露，$c_warnings 项需要注意，$c_unknown 项未验证。"
    echo "这份结果不代表封号概率。硬件目录遮挡不等于完整硬件虚拟化，也不保证工具识别不出容器。"
    echo "本机如已开代理，检测到的是代理后的当前出口，不能当成真实宽带 IP。"
    echo "原始电脑名、机器标识和 IP 未显示、未保存，也没有传进另一边。"
    [ "$c_partial" = 0 ] || echo "本次检测不完整：环境不可用或上网 IP 查询失败；未验证项不当作通过。"
  fi
  [ "$c_partial" = 0 ] || return 2
}
