#!/usr/bin/env bash
# scripts/setup.sh 的行为测试。用一个桩 code-server 替代真实二进制，
# 覆盖参数解析、凭据处理、监听地址优先级、PID 生命周期四类行为。
#
# 运行：./tests/test_setup.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"

PASS=0
FAIL=0
WORK=""
STUB_DIR=""

cleanup() {
	# 清掉可能残留的桩进程
	if [ -n "$STUB_DIR" ]; then
		pkill -f "$STUB_DIR/sleeper" 2>/dev/null || true
	fi
	[ -z "$WORK" ] || rm -rf "$WORK"
}
trap cleanup EXIT

ok() {
	PASS=$((PASS + 1))
	echo "  ok   - $1"
}

ng() {
	FAIL=$((FAIL + 1))
	echo "  FAIL - $1"
	[ "$#" -lt 2 ] || echo "         $2"
}

assert_eq() {
	if [ "$2" = "$3" ]; then
		ok "$1"
	else
		ng "$1" "期望 [$2]，实际 [$3]"
	fi
}

assert_contains() {
	case "$2" in
	*"$3"*) ok "$1" ;;
	*) ng "$1" "输出中找不到 [$3]；实际输出：$2" ;;
	esac
}

assert_not_contains() {
	case "$2" in
	*"$3"*) ng "$1" "输出中不应出现 [$3]；实际输出：$2" ;;
	*) ok "$1" ;;
	esac
}

# 每个用例一套干净的仓库副本，避免 .run/ 互相污染
new_sandbox() {
	[ -z "$WORK" ] || rm -rf "$WORK"
	WORK="$(mktemp -d)"
	mkdir -p "$WORK/repo"
	cp -r "$REPO_DIR/scripts" "$REPO_DIR/configs" "$WORK/repo/"
	STUB_DIR="$WORK/bin"
	mkdir -p "$STUB_DIR"
	# 长寿命桩：记录自己收到的参数，然后一直挂着
	cat >"$STUB_DIR/code-server" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$WORK/argv.txt"
exec "$STUB_DIR/sleeper"
EOF
	# 单独的 sleeper，便于 pkill 精确清理
	cat >"$STUB_DIR/sleeper" <<'EOF'
#!/usr/bin/env bash
while true; do sleep 1; done
EOF
	chmod +x "$STUB_DIR/code-server" "$STUB_DIR/sleeper"
	export PATH="$STUB_DIR:$ORIG_PATH"
}

# 把桩换成「启动即失败」的版本
make_failing_stub() {
	cat >"$STUB_DIR/code-server" <<'EOF'
#!/usr/bin/env bash
echo "fatal: address already in use" >&2
exit 1
EOF
	chmod +x "$STUB_DIR/code-server"
}

setup_sh() {
	"$WORK/repo/scripts/setup.sh" "$@"
}

ORIG_PATH="$PATH"

echo "== 1. 参数解析 =="
new_sandbox
out="$(setup_sh 2>&1)"
assert_eq "无参数时退出码为 1" 1 "$?"
assert_contains "无参数时打印用法" "$out" "用法:"

out="$(setup_sh bogus 2>&1)"
assert_eq "未知 action 退出码为 1" 1 "$?"

out="$(setup_sh status dev 2>&1)"
assert_eq "多余参数被拒绝" 1 "$?"

out="$(setup_sh status 2>&1)"
rc=$?
assert_eq "status 退出码为 0" 0 "$rc"
assert_contains "status 报告 code-server" "$out" "code-server 未运行"

echo "== 2. 凭据处理 =="
new_sandbox
out="$(CODE_SERVER_PASSWORD='' setup_sh start 2>&1)"
assert_eq "缺少 CODE_SERVER_PASSWORD 时退出码为 1" 1 "$?"
assert_contains "缺少密码时给出明确提示" "$out" "CODE_SERVER_PASSWORD"

# 提交进仓库的模板里绝不能有密码字段
tpl="$(cat "$WORK/repo/configs/code-server.yaml")"
assert_not_contains "配置模板不含 password 字段" "$tpl" "password:"

new_sandbox
CODE_SERVER_PASSWORD='s3cr3t' setup_sh start >/dev/null 2>&1
rendered="$WORK/repo/.run/code-server.yaml"
if [ -f "$rendered" ]; then
	perm="$(stat -c '%a' "$rendered")"
	assert_eq "渲染后的配置权限为 600（不可被其他用户读取）" 600 "$perm"
	assert_contains "渲染后的配置含注入的密码" "$(cat "$rendered")" "s3cr3t"
else
	ng "渲染后的配置权限为 600（不可被其他用户读取）" "$rendered 不存在"
	ng "渲染后的配置含注入的密码" "$rendered 不存在"
fi
# 密码绝不能作为命令行参数传给 code-server（/proc/<pid>/cmdline 世界可读）
assert_not_contains "密码未出现在 code-server 的命令行参数里" "$(cat "$WORK/argv.txt")" "s3cr3t"
setup_sh stop >/dev/null 2>&1

# 含 sed 元字符的密码必须原样落盘
for pw in 'pa#ss' 'a&b' 'back\slash' "quo'te"; do
	new_sandbox
	if CODE_SERVER_PASSWORD="$pw" setup_sh start >/dev/null 2>&1; then
		rendered="$WORK/repo/.run/code-server.yaml"
		# 用 Python 解析 YAML，确认取回的密码与输入完全一致
		got="$(PW_FILE="$rendered" python3 - <<'PY' 2>/dev/null
import os, sys
try:
    import yaml
except ImportError:
    sys.exit(2)
with open(os.environ["PW_FILE"]) as f:
    print(yaml.safe_load(f)["password"], end="")
PY
		)"
		rc=$?
		if [ "$rc" -eq 2 ]; then
			echo "  skip - 密码 [$pw] 往返一致（缺 PyYAML）"
		else
			assert_eq "密码 [$pw] 经 YAML 解析后与输入一致" "$pw" "$got"
		fi
	else
		ng "密码 [$pw] 经 YAML 解析后与输入一致" "start 直接失败了"
	fi
	setup_sh stop >/dev/null 2>&1
done

echo "== 3. 监听地址优先级（SPEC §9.3） =="
new_sandbox
assert_contains "模板默认监听回环地址" "$(cat "$WORK/repo/configs/code-server.yaml")" "bind-addr: 127.0.0.1"
assert_not_contains "模板默认不监听 0.0.0.0" "$(cat "$WORK/repo/configs/code-server.yaml")" "bind-addr: 0.0.0.0"

new_sandbox
# 用户把配置文件改成非默认端口；没有环境变量覆盖时脚本不得下发 --bind-addr，
# 否则命令行参数会盖掉配置文件（优先级倒挂）
sed -i 's|^bind-addr:.*|bind-addr: 127.0.0.1:9999|' "$WORK/repo/configs/code-server.yaml"
CODE_SERVER_PASSWORD='pw' setup_sh start >/dev/null 2>&1
assert_not_contains "无环境变量覆盖时不下发 --bind-addr，配置文件生效" "$(cat "$WORK/argv.txt")" "--bind-addr"
out="$(setup_sh status 2>&1)"
assert_contains "status 报告配置文件里的监听地址" "$out" "127.0.0.1:9999"
setup_sh stop >/dev/null 2>&1

new_sandbox
CODE_SERVER_PASSWORD='pw' CODE_SERVER_PORT=18443 setup_sh start >/dev/null 2>&1
assert_contains "CODE_SERVER_PORT 覆盖端口且保持回环默认主机" "$(cat "$WORK/argv.txt")" "--bind-addr 127.0.0.1:18443"
setup_sh stop >/dev/null 2>&1

new_sandbox
CODE_SERVER_PASSWORD='pw' CODE_SERVER_BIND_ADDR='0.0.0.0:7777' setup_sh start >/dev/null 2>&1
assert_contains "CODE_SERVER_BIND_ADDR 可显式对外暴露" "$(cat "$WORK/argv.txt")" "--bind-addr 0.0.0.0:7777"
setup_sh stop >/dev/null 2>&1

echo "== 4. PID 与生命周期 =="
new_sandbox
make_failing_stub
out="$(CODE_SERVER_PASSWORD='pw' setup_sh start 2>&1)"
rc=$?
assert_eq "code-server 启动即失败时 start 返回非 0" 1 "$rc"
assert_contains "启动失败时输出日志尾部" "$out" "address already in use"
if [ -f "$WORK/repo/.run/code-server.pid" ]; then
	ng "启动失败后不留下死 PID 文件" "PID 文件仍存在"
else
	ok "启动失败后不留下死 PID 文件"
fi
out="$(setup_sh status 2>&1)"
assert_contains "启动失败后 status 报告未运行" "$out" "未运行"

new_sandbox
out="$(CODE_SERVER_PASSWORD='pw' setup_sh start 2>&1)"
assert_contains "start 成功时报告已启动" "$out" "已后台启动"
out="$(setup_sh status 2>&1)"
assert_contains "start 后 status 报告运行中" "$out" "运行中"
out="$(CODE_SERVER_PASSWORD='pw' setup_sh start 2>&1)"
assert_eq "重复 start 退出码为 1" 1 "$?"
assert_contains "重复 start 被拒绝" "$out" "拒绝重复启动"
pid="$(cat "$WORK/repo/.run/code-server.pid")"
out="$(setup_sh stop 2>&1)"
assert_contains "stop 报告已停止" "$out" "已停止"
if ps -p "$pid" >/dev/null 2>&1; then
	ng "stop 之后进程真的退出了" "PID $pid 仍存活"
else
	ok "stop 之后进程真的退出了"
fi
if [ -f "$WORK/repo/.run/code-server.pid" ]; then
	ng "stop 之后 PID 文件被清理" "PID 文件仍存在"
else
	ok "stop 之后 PID 文件被清理"
fi

echo "== 5. 陈旧 PID 文件不得误判、误杀 =="
new_sandbox
mkdir -p "$WORK/repo/.run"
"$STUB_DIR/sleeper" &
victim=$!
# 模拟 PID 被系统回收给一个无关进程：PID 文件指向它，但启动时刻记录对不上
echo "$victim" >"$WORK/repo/.run/code-server.pid"
echo "999999999999" >"$WORK/repo/.run/code-server.start"
out="$(setup_sh status 2>&1)"
assert_contains "启动时刻不匹配时 status 报告未运行" "$out" "未运行"
assert_contains "status 指明这是陈旧 PID 文件" "$out" "陈旧 PID 文件"
setup_sh stop >/dev/null 2>&1
sleep 0.3
if ps -p "$victim" >/dev/null 2>&1; then
	ok "stop 没有误杀 PID 相同的无关进程"
else
	ng "stop 没有误杀 PID 相同的无关进程" "无关进程 $victim 被杀掉了"
fi

# 只有 PID 文件、没有启动时刻记录时，同样不能认成「运行中」
echo "$victim" >"$WORK/repo/.run/code-server.pid"
rm -f "$WORK/repo/.run/code-server.start"
out="$(setup_sh status 2>&1)"
assert_contains "缺少启动时刻记录时 status 报告未运行" "$out" "未运行"
setup_sh stop >/dev/null 2>&1
sleep 0.3
if ps -p "$victim" >/dev/null 2>&1; then
	ok "缺少启动时刻记录时 stop 也不误杀"
else
	ng "缺少启动时刻记录时 stop 也不误杀" "无关进程 $victim 被杀掉了"
fi
kill "$victim" 2>/dev/null || true
wait "$victim" 2>/dev/null || true

echo "== 6. restart =="
new_sandbox
CODE_SERVER_PASSWORD='pw' setup_sh start >/dev/null 2>&1
old_pid="$(cat "$WORK/repo/.run/code-server.pid")"
out="$(CODE_SERVER_PASSWORD='pw' setup_sh restart 2>&1)"
rc=$?
assert_eq "restart 退出码为 0" 0 "$rc"
new_pid="$(cat "$WORK/repo/.run/code-server.pid" 2>/dev/null || echo '')"
if [ -n "$new_pid" ] && [ "$new_pid" != "$old_pid" ]; then
	ok "restart 换成了新进程"
else
	ng "restart 换成了新进程" "old=$old_pid new=$new_pid"
fi
if ps -p "$old_pid" >/dev/null 2>&1; then
	ng "restart 已终止旧进程" "旧进程 $old_pid 仍存活"
else
	ok "restart 已终止旧进程"
fi
setup_sh stop >/dev/null 2>&1

echo
echo "通过 $PASS，失败 $FAIL"
[ "$FAIL" -eq 0 ]
