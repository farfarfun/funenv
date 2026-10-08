#!/usr/bin/env bash
# code-server 服务统一入口：start / run / stop / restart / status
# 用法：CODE_SERVER_PASSWORD='change-me' ./scripts/setup.sh <action>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- 配置块：端口、监听地址、路径统一在此定义，全脚本复用 ----
# 默认值必须是安全的（SPEC §9.3）：默认只监听回环地址，需要对外暴露时
# 由操作者显式设置 CODE_SERVER_BIND_ADDR / CODE_SERVER_HOST。
CODE_SERVER_DEFAULT_HOST="127.0.0.1"
CODE_SERVER_DEFAULT_PORT="8443"
CODE_SERVER_BIN="${CODE_SERVER_BIN:-code-server}"
CODE_SERVER_CONFIG="${CODE_SERVER_CONFIG:-$ROOT_DIR/configs/code-server.yaml}"
RUN_DIR="$ROOT_DIR/.run"

usage() {
	cat >&2 <<'EOF'
用法:
  ./scripts/setup.sh start             后台启动
  ./scripts/setup.sh run               前台启动（便于调试）
  ./scripts/setup.sh stop              停止
  ./scripts/setup.sh restart           重启
  ./scripts/setup.sh status            查看状态

环境变量:
  CODE_SERVER_PASSWORD   必填，登录密码；只允许通过环境变量传入
  CODE_SERVER_BIND_ADDR  可选，形如 0.0.0.0:8443，显式覆盖监听地址
  CODE_SERVER_HOST       可选，只覆盖监听地址的主机部分
  CODE_SERVER_PORT       可选，只覆盖监听地址的端口部分
  CODE_SERVER_BIN        可选，code-server 可执行文件，默认 code-server
  CODE_SERVER_CONFIG     可选，配置模板路径
EOF
	exit 1
}

log() {
	echo "[setup.sh] $*"
}

die() {
	echo "[setup.sh] 错误：$*" >&2
	exit 1
}

pid_file() { printf '%s/code-server.pid' "$RUN_DIR"; }
log_file() { printf '%s/code-server.log' "$RUN_DIR"; }
rendered_config() { printf '%s/code-server.yaml' "$RUN_DIR"; }
# 记录启动时刻，用来证明 PID 还是当初那个进程
token_file() { printf '%s/code-server.start' "$RUN_DIR"; }

# 进程是否真的活着。僵尸进程也能通过 `kill -0`，必须按进程状态排除，
# 否则刚起就崩掉的服务会被一直报成「运行中」。
pid_alive() {
	local stat_out
	stat_out="$(ps -ww -o stat= -p "$1" 2>/dev/null)" || return 1
	[ -n "$stat_out" ] || return 1
	case "$stat_out" in
	*Z*) return 1 ;;
	esac
	return 0
}

read_pid() {
	local pid_f="$1"
	[ -f "$pid_f" ] || return 1
	tr -cd '0-9' <"$pid_f"
}

# 进程的启动时刻。PID 会被系统回收复用，但「PID + 启动时刻」事实上唯一，
# 所以它才是「这个 PID 还是当初那个进程」的证明。
# Linux 下读 /proc/<pid>/stat 第 22 个字段（jiffies 精度）；
# 用 `.*) ` 贪婪截断可以躲开 comm 字段里可能出现的空格和括号。
proc_start_token() {
	local pid="$1" token=""
	if [ -r "/proc/$pid/stat" ]; then
		token="$(sed 's/.*) //' "/proc/$pid/stat" 2>/dev/null | awk '{ print $20 }')"
	else
		token="$(ps -ww -o lstart= -p "$pid" 2>/dev/null | tr -s ' ')"
	fi
	[ -n "$token" ] || return 1
	printf '%s' "$token"
}

# 只认本脚本托管的那个进程。单纯 `kill -0` 会在 PID 被回收后让
# status 误报运行中、让 stop 误杀别人的进程（SPEC §6.1 / §6.3）。
is_running() {
	local pid recorded current token_f
	pid="$(read_pid "$(pid_file)")" || return 1
	[ -n "$pid" ] || return 1
	pid_alive "$pid" || return 1
	token_f="$(token_file)"
	[ -f "$token_f" ] || return 1
	recorded="$(cat "$token_f" 2>/dev/null)"
	[ -n "$recorded" ] || return 1
	current="$(proc_start_token "$pid")" || return 1
	[ "$recorded" = "$current" ] || return 1
	return 0
}

clear_runtime_marks() {
	rm -f "$(pid_file)" "$(token_file)"
}

require_bin() {
	command -v "$CODE_SERVER_BIN" >/dev/null 2>&1 ||
		die "未找到可执行文件 $CODE_SERVER_BIN，请先安装 code-server。"
}

# 把值渲染成 YAML 单引号标量，内部单引号按 YAML 规则双写。
# 密码可能含 # & \ : 等字符，直接拼进 sed 表达式会被当成元字符。
yaml_single_quote() {
	local value="$1"
	printf "'%s'" "${value//\'/\'\'}"
}

# 渲染运行时配置。密码只在这里落盘，且：
#   1. 文件权限收紧到 0600，不再是默认 umask 下世界可读的 0644；
#   2. 全程只用 Bash 内建命令写入，密码不会出现在任何进程的
#      /proc/<pid>/cmdline 里（`ps aux` 读不到）。
render_config() {
	local out tpl
	out="$(rendered_config)"
	tpl="$CODE_SERVER_CONFIG"
	[ -f "$tpl" ] || die "找不到配置模板 $tpl"
	[ -n "${CODE_SERVER_PASSWORD:-}" ] ||
		die "请通过 CODE_SERVER_PASSWORD 环境变量提供密码，不要写进 configs/code-server.yaml。"
	mkdir -p "$RUN_DIR"
	rm -f "$out"
	(
		umask 077
		: >"$out"
	)
	# 过滤模板里可能残留的 password/hashed-password，避免与注入值产生重复键
	grep -v -E '^[[:space:]]*(password|hashed-password)[[:space:]]*:' "$tpl" >>"$out" || true
	printf 'password: %s\n' "$(yaml_single_quote "$CODE_SERVER_PASSWORD")" >>"$out"
}

# 只有操作者显式给出环境变量时才下发 --bind-addr。code-server 的命令行参数
# 优先级高于配置文件，无条件下发会让脚本里的代码默认值吞掉用户在
# configs/code-server.yaml 里写的 bind-addr（SPEC §9.3 优先级倒挂）。
bind_addr_override() {
	if [ -n "${CODE_SERVER_BIND_ADDR:-}" ]; then
		printf '%s' "$CODE_SERVER_BIND_ADDR"
	elif [ -n "${CODE_SERVER_HOST:-}" ] || [ -n "${CODE_SERVER_PORT:-}" ]; then
		printf '%s:%s' \
			"${CODE_SERVER_HOST:-$CODE_SERVER_DEFAULT_HOST}" \
			"${CODE_SERVER_PORT:-$CODE_SERVER_DEFAULT_PORT}"
	fi
}

# 仅用于展示：没有环境变量覆盖时读配置文件里的 bind-addr
effective_bind_addr() {
	local override from_cfg tpl
	override="$(bind_addr_override)"
	if [ -n "$override" ]; then
		printf '%s' "$override"
		return
	fi
	tpl="$CODE_SERVER_CONFIG"
	from_cfg=""
	if [ -f "$tpl" ]; then
		from_cfg="$(sed -n 's/^[[:space:]]*bind-addr[[:space:]]*:[[:space:]]*//p' "$tpl" | head -1)"
	fi
	printf '%s' "${from_cfg:-$CODE_SERVER_DEFAULT_HOST:$CODE_SERVER_DEFAULT_PORT}"
}

# 用 Bash 数组传命令，不拼字符串、不用 eval（SPEC §6.3）
build_cmd() {
	local override
	CODE_SERVER_CMD=("$CODE_SERVER_BIN" --config "$(rendered_config)")
	override="$(bind_addr_override)"
	[ -z "$override" ] || CODE_SERVER_CMD+=(--bind-addr "$override")
}

refuse_if_running() {
	local pid
	if is_running; then
		pid="$(read_pid "$(pid_file)")"
		die "code-server 已在运行 (PID $pid)，拒绝重复启动。"
	fi
}

# 启动后必须确认进程真的活着。只写 PID 就报成功的话，端口被占用、
# 配置写错、user-data-dir 不可写这些失败都会被包装成「启动成功」，
# 并在 .run/ 里留下一个死 PID。
verify_started() {
	local i
	# 观察一段时间，确认它不是「起来就立刻崩」
	for ((i = 0; i < 15; i++)); do
		sleep 0.1
		is_running || return 1
	done
	return 0
}

do_start() {
	local log_f pid token
	require_bin
	refuse_if_running
	log_f="$(log_file)"
	clear_runtime_marks # 清理陈旧的 PID / 启动时刻记录
	render_config
	build_cmd
	nohup "${CODE_SERVER_CMD[@]}" >>"$log_f" 2>&1 &
	pid=$!
	if ! token="$(proc_start_token "$pid")"; then
		echo "[setup.sh] 错误：code-server 启动后立即退出，日志尾部：" >&2
		tail -n 20 "$log_f" >&2 2>/dev/null || true
		exit 1
	fi
	echo "$pid" >"$(pid_file)"
	printf '%s' "$token" >"$(token_file)"
	if ! verify_started; then
		clear_runtime_marks
		echo "[setup.sh] 错误：code-server 启动失败，日志尾部：" >&2
		tail -n 20 "$log_f" >&2 2>/dev/null || true
		exit 1
	fi
	log "code-server 已后台启动，PID $pid，监听 $(effective_bind_addr)，日志：$log_f"
}

do_run() {
	require_bin
	refuse_if_running
	render_config
	build_cmd
	log "code-server 前台启动，监听 $(effective_bind_addr)"
	exec "${CODE_SERVER_CMD[@]}"
}

do_stop() {
	local pid_f pid i
	pid_f="$(pid_file)"
	if ! is_running; then
		if [ -f "$pid_f" ]; then
			log "code-server 未运行，清理陈旧 PID 文件 $pid_f"
			clear_runtime_marks
		else
			log "code-server 未运行"
		fi
		return 0
	fi
	pid="$(read_pid "$pid_f")"
	kill "$pid" 2>/dev/null || true
	# 必须等它真的退出，否则紧随其后的 start 会撞上还没释放的端口
	for ((i = 0; i < 100; i++)); do
		pid_alive "$pid" || break
		sleep 0.1
	done
	if pid_alive "$pid"; then
		log "code-server 未响应 SIGTERM，发送 SIGKILL"
		kill -9 "$pid" 2>/dev/null || true
		for ((i = 0; i < 20; i++)); do
			pid_alive "$pid" || break
			sleep 0.1
		done
	fi
	wait "$pid" 2>/dev/null || true # 若是本次调用启动的子进程，顺手回收
	! pid_alive "$pid" || die "无法停止 code-server (PID $pid)"
	clear_runtime_marks
	log "code-server 已停止 (PID $pid)"
}

do_status() {
	local pid_f pid
	pid_f="$(pid_file)"
	if is_running; then
		pid="$(read_pid "$pid_f")"
		log "code-server 运行中，PID $pid，监听 $(effective_bind_addr)"
	elif [ -f "$pid_f" ]; then
		log "code-server 未运行（$pid_f 是陈旧 PID 文件）"
	else
		log "code-server 未运行"
	fi
}

ACTION="${1:-}"
[ "$#" -eq 1 ] || usage

case "$ACTION" in
start | run | stop | restart | status) ;;
*) usage ;;
esac

case "$ACTION" in
start) do_start ;;
run) do_run ;;
stop) do_stop ;;
restart)
	do_stop
	do_start
	;;
status) do_status ;;
esac
