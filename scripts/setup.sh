#!/usr/bin/env bash
# code-server 服务统一入口：start / run / stop / restart / status
# 用法：CODE_SERVER_PASSWORD=<password> ./scripts/setup.sh <action> <dev|prod>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- 配置块：端口、路径统一在此定义，全脚本复用 ----
CODE_SERVER_PORT="${CODE_SERVER_PORT:-8443}"
CODE_SERVER_BIN="${CODE_SERVER_BIN:-code-server}"
RUN_DIR="$ROOT_DIR/.run"
CONFIG_TEMPLATE="$ROOT_DIR/configs/code-server.yaml"

usage() {
	echo "用法: $0 <start|run|stop|restart|status> [dev|prod]" >&2
	echo "  start/run/stop/restart 必须指定 dev 或 prod 环境" >&2
	exit 1
}

log() {
	echo "[setup.sh] $*"
}

# 按环境隔离运行时文件，避免 dev/prod 相互覆盖
pid_file() { echo "$RUN_DIR/code-server-$1.pid"; }
log_file() { echo "$RUN_DIR/code-server-$1.log"; }
rendered_config() { echo "$RUN_DIR/code-server-$1.yaml"; }

is_running() {
	local env="$1" pid_f pid
	pid_f="$(pid_file "$env")"
	[ -f "$pid_f" ] || return 1
	pid="$(cat "$pid_f" 2>/dev/null || true)"
	[ -n "$pid" ] || return 1
	kill -0 "$pid" 2>/dev/null
}

require_bin() {
	command -v "$CODE_SERVER_BIN" >/dev/null 2>&1 || {
		echo "未找到可执行文件 $CODE_SERVER_BIN，请先安装 code-server。" >&2
		exit 1
	}
}

render_config() {
	local env="$1" out
	out="$(rendered_config "$env")"
	if [ -z "${CODE_SERVER_PASSWORD:-}" ]; then
		echo "请先设置 CODE_SERVER_PASSWORD 环境变量（不要把密码写进 configs/code-server.yaml）。" >&2
		exit 1
	fi
	mkdir -p "$RUN_DIR"
	sed "s#\${CODE_SERVER_PASSWORD}#${CODE_SERVER_PASSWORD}#g" "$CONFIG_TEMPLATE" >"$out"
	echo "$out"
}

do_start() {
	local env="$1" pid_f log_f cfg
	require_bin
	if is_running "$env"; then
		echo "code-server($env) 已在运行 (PID $(cat "$(pid_file "$env")"))，拒绝重复启动。" >&2
		exit 1
	fi
	pid_f="$(pid_file "$env")"
	log_f="$(log_file "$env")"
	rm -f "$pid_f" # 清理可能存在的陈旧 PID 文件
	cfg="$(render_config "$env")"
	nohup "$CODE_SERVER_BIN" --config "$cfg" --bind-addr "0.0.0.0:$CODE_SERVER_PORT" >>"$log_f" 2>&1 &
	echo $! >"$pid_f"
	log "code-server($env) 已后台启动，PID $(cat "$pid_f")，端口 $CODE_SERVER_PORT，日志：$log_f"
}

do_run() {
	local env="$1" cfg
	require_bin
	if is_running "$env"; then
		echo "code-server($env) 已在后台运行 (PID $(cat "$(pid_file "$env")"))，请先 stop。" >&2
		exit 1
	fi
	cfg="$(render_config "$env")"
	exec "$CODE_SERVER_BIN" --config "$cfg" --bind-addr "0.0.0.0:$CODE_SERVER_PORT"
}

do_stop() {
	local env="$1" pid_f pid
	pid_f="$(pid_file "$env")"
	if ! is_running "$env"; then
		log "code-server($env) 未运行（或 PID 文件已过期），清理陈旧 PID 文件。"
		rm -f "$pid_f"
		return 0
	fi
	pid="$(cat "$pid_f")"
	kill "$pid"
	rm -f "$pid_f"
	log "code-server($env) 已停止 (PID $pid)"
}

do_status() {
	local env="$1"
	if is_running "$env"; then
		log "code-server($env) 运行中，PID $(cat "$(pid_file "$env")")，端口 $CODE_SERVER_PORT"
	else
		log "code-server($env) 未运行"
	fi
}

ACTION="${1:-}"
ENV="${2:-}"
[ -n "$ACTION" ] || usage

case "$ACTION" in
start | run | stop | restart)
	case "$ENV" in
	dev | prod) ;;
	*) usage ;;
	esac
	;;
status)
	case "$ENV" in
	dev | prod) ;;
	*) usage ;;
	esac
	;;
*) usage ;;
esac

case "$ACTION" in
start) do_start "$ENV" ;;
run) do_run "$ENV" ;;
stop) do_stop "$ENV" ;;
restart)
	do_stop "$ENV" || true
	do_start "$ENV"
	;;
status) do_status "$ENV" ;;
esac
