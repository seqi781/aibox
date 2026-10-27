#!/usr/bin/env python3
"""compare 的隔离集成测试：固定的两端探针、Docker 元数据和网络结果，不接触真实网络或账号。"""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HOST = """OS=Linux
OS_NAME=Test Linux 1.0
KERNEL=6.12-test
ARCH=x86_64
HOSTNAME=private-hostname-never-print
UID=1000
GID=1000
MACHINE_ID=11111111111111111111111111111111
BOOT_ID=private-boot-never-print
CPU=Example CPU
CPU_COUNT=8
MEMORY_KIB=8000000
HARDWARE_ID=private-hardware-never-print
SYSFS=visible
HOST_PATH_ENV=absent
MOUNTINFO_HOME=absent
PROBE_VERSION=1
"""
WORKSPACE = HOST.replace("private-hostname-never-print", "devbox").replace(
    "11111111111111111111111111111111", "22222222222222222222222222222222"
).replace("BOOT_ID=private-boot-never-print", "BOOT_ID=").replace(
    "HARDWARE_ID=private-hardware-never-print", "HARDWARE_ID="
).replace("SYSFS=visible", "SYSFS=unavailable")
META = """RUNNING=true
NETWORK=container:gateway-test-id
PRIVILEGED=false
PID_MODE=
DROP=NET_ADMIN
DROP=NET_RAW
DROP=SYS_ADMIN
SYS_MASK=yes
MOUNT=bind|true|/projects/demo|/workspace/demo
MOUNT=bind|false|/projects/specs|/workspace/specs
MOUNT=volume|true|/var/lib/docker/volumes/home|/home/dev
"""
SECRETS = ["private-hostname-never-print", "private-boot-never-print",
           "private-hardware-never-print", "11111111111111111111111111111111",
           "22222222222222222222222222222222", "203.0.113.10", "198.51.100.20",
           "2001:db8::10", "/projects/demo", "/projects/specs"]

with tempfile.TemporaryDirectory(prefix="aibox-compare-test-") as temporary:
    base = Path(temporary)
    mocks = base / "bin"
    mocks.mkdir()
    real_sh = subprocess.check_output(["sh", "-c", "command -v sh"], text=True).strip()

    def script(name, body):
        path = mocks / name
        path.write_text("#!/bin/bash\nset -eu\n" + body)
        path.chmod(0o755)

    script("sh", f"""case "${{1:-}}" in
      */lib/environment-probe.sh) cat "$COMPARE_FIXTURE/host" ;;
      *) exec {real_sh} "$@" ;;
    esac
    """)
    script("docker", """printf '%s\\n' "$*" >> "$COMPARE_FIXTURE/docker.calls"
    case "$1" in
      inspect)
        if [ "${COMPARE_DOCKER_DOWN:-0}" = 1 ]; then exit 1; fi
        case "${@: -1}" in
          aibox-workspace) cat "$COMPARE_FIXTURE/meta" ;;
          aibox-gateway) printf '%s\\n' "${COMPARE_GATEWAY:-gateway-test-id|true|healthy}" ;;
          *) exit 93 ;;
        esac ;;
      exec)
        if [ "$2" = -i ]; then
          cat > "$COMPARE_FIXTURE/received-probe"
          cat "$COMPARE_FIXTURE/workspace"
          exit "${COMPARE_EXEC_STATUS:-0}"
        fi
        case "$*" in
          *api6.ipify.org*) [ -n "${COMPARE_WS_V6:-}" ] || exit 7; printf '%s' "$COMPARE_WS_V6" ;;
          *api.ipify.org*) [ "${COMPARE_IP_FAIL:-0}" = 0 ] || exit 7; printf '%s' "${COMPARE_WS_V4:-198.51.100.20}" ;;
          *) exit 94 ;;
        esac ;;
      *) exit 95 ;;
    esac
    """)
    script("curl", """printf '%s\\n' "$*" >> "$COMPARE_FIXTURE/curl.calls"
    case "$*" in
      *api6.ipify.org*) printf '2001:db8::10' ;;
      *api.ipify.org*) [ "${COMPARE_IP_FAIL:-0}" = 0 ] || exit 7; printf '203.0.113.10' ;;
      *) exit 96 ;;
    esac
    """)

    count = 0

    def run(*args, host=HOST, workspace=WORKSPACE, meta=META, expected=0, **settings):
        global count
        count += 1
        case = base / str(count)
        case.mkdir()
        for filename, content in (("host", host), ("workspace", workspace), ("meta", meta)):
            (case / filename).write_text(content)
        env = dict(os.environ, PATH=str(mocks) + ":" + os.environ["PATH"], COMPARE_FIXTURE=str(case))
        env.update(settings)
        completed = subprocess.run([str(ROOT / "aibox"), "compare", *args], env=env,
                                   text=True, capture_output=True)
        assert completed.returncode == expected, (args, completed.returncode, completed.stdout, completed.stderr)
        if "--json" in args or "--redact" in args or "--help" in args or "--invalid" in args:
            for secret in SECRETS:
                assert secret not in completed.stdout, ("redacted value disclosed", secret, completed.stdout)
        else:
            # The local table intentionally shows real IPs; full unique IDs remain shortened.
            for secret in ("11111111111111111111111111111111", "22222222222222222222222222222222"):
                assert secret not in completed.stdout
        received = case / "received-probe"
        if received.exists():
            assert received.read_text() == (ROOT / "lib/environment-probe.sh").read_text(), "host data sent to workspace"
        return completed, case

    def rows(result):
        data = json.loads(result.stdout)
        return data, {row["id"]: row for row in data["rows"]}

    result, case = run("--json")
    data, row = rows(result)
    assert row["ipv4"]["result"] == "improved"
    assert row["hardware_ids"]["result"] == "improved"
    assert row["machine_id"]["result"] == "improved"
    assert row["user_id"]["result"] == "same"
    assert "2 个" in row["files"]["aibox"] and "1 个只读" in row["files"]["aibox"]
    assert row["disconnect"]["result"] == "unknown"
    assert "未连通" in row["ipv6"]["aibox"] and "不能证明" in row["ipv6"]["aibox"]
    assert not data["summary"]["partial"]
    result, _ = run()
    assert "203.0.113.10" in result.stdout and "198.51.100.20" in result.stdout
    assert "11111111…" in result.stdout
    assert "Test Linux 1.0" in result.stdout and "7.6 GiB" in result.stdout
    assert "⚠ =" in result.stdout and "✓ ≠" in result.stdout
    assert len(result.stdout.splitlines()) <= 25
    assert "直接使用：" not in result.stdout and "账号、登录与封号风险" not in result.stdout

    result, _ = run("--redact")
    assert "***" in result.stdout

    for width in (60, 120):
        result, _ = run("--redact", COLUMNS=str(width))
        import unicodedata
        display_width = lambda text: sum(0 if unicodedata.combining(char) else 2 if unicodedata.east_asian_width(char) in ("W", "F") else 1 for char in text)
        lines=result.stdout.splitlines()
        assert any(line == "─" * width for line in lines)
        assert all(display_width(line) <= width for line in lines[1:21]), result.stdout

    result, _ = run("--offline", "--json", meta=META.replace("DROP=", "DROP=CAP_"))
    assert rows(result)[1]["permissions"]["result"] == "improved"

    result, _ = run("--offline", "--json", meta=META + "ADD=CAP_NET_ADMIN\n")
    assert rows(result)[1]["permissions"]["result"] == "warning"

    result, case = run("--offline", "--json")
    assert not (case / "curl.calls").exists()
    assert "curl" not in (case / "docker.calls").read_text()
    assert rows(result)[1]["ipv4"]["result"] == "unknown"

    result, _ = run("--json", COMPARE_WS_V4="203.0.113.10")
    assert "不能据此认定" in rows(result)[1]["ipv4"]["aibox"]

    result, _ = run("--json", COMPARE_WS_V6="2001:db8::20")
    assert rows(result)[1]["ipv6"]["result"] == "warning"
    assert "2001:db8::20" not in result.stdout

    result, _ = run("--json", COMPARE_IP_FAIL="1", expected=2)
    assert rows(result)[0]["summary"]["partial"]
    assert rows(result)[1]["ipv4"]["result"] == "unknown"

    for settings in ({"COMPARE_DOCKER_DOWN": "1"}, {"COMPARE_EXEC_STATUS": "1"}):
        result, _ = run("--offline", "--json", expected=2, **settings)
        data, row = rows(result)
        assert not data["workspace_probe_ok"] and data["summary"]["improved_items"] == 0

    result, _ = run("--offline", "--json", workspace=WORKSPACE.replace("PROBE_VERSION=1", ""), expected=2)
    assert rows(result)[0]["summary"]["partial"]

    result, _ = run("--offline", "--json", workspace=HOST.replace("HOST_PATH_ENV=absent", "HOST_PATH_ENV=exposed"))
    _, row = rows(result)
    assert row["hardware_ids"]["result"] == "warning"
    assert row["host_paths"]["result"] == "warning"
    assert row["machine_id"]["result"] == "warning"

    result, _ = run("--offline", "--json", workspace=WORKSPACE.replace("MOUNTINFO_HOME=absent", "MOUNTINFO_HOME=exposed"))
    assert rows(result)[1]["host_paths"]["result"] == "warning"

    for unsafe_mount in ("MOUNT=bind|true|/|/host", "MOUNT=bind|true|/var/run/docker.sock|/socket",
                         "MOUNT=bind|true|/home/example/.ssh/key|/key"):
        result, _ = run("--offline", "--json", meta=META + unsafe_mount + "\n")
        assert rows(result)[1]["files"]["result"] == "warning"
        assert rows(result)[1]["permissions"]["result"] == "warning"

    result, _ = run("--offline", "--json", meta=META.replace("PRIVILEGED=false", "PRIVILEGED=true"))
    assert rows(result)[1]["permissions"]["result"] == "warning"

    result, _ = run("--offline", "--json", meta=META.replace("NETWORK=container:gateway-test-id", "NETWORK=host"))
    assert rows(result)[1]["disconnect"]["result"] == "warning"

    result, _ = run("--offline", "--json", workspace=WORKSPACE.replace("MACHINE_ID=22222222222222222222222222222222", "MACHINE_ID="))
    assert rows(result)[1]["machine_id"]["result"] == "unknown"

    run("--help")
    run("--invalid", expected=2)
    print(f"  compare：{count} 个情景通过（脱敏、只读、旧环境、失败分支、风险差异）")
