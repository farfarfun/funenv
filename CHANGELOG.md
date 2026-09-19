# CHANGELOG

## [未发布]

### 新增

- 新增 `scripts/setup.sh` 作为 code-server 服务的统一生命周期入口，支持 `start`/`run`/`stop`/`restart`/`status`，区分 `dev`/`prod` 环境，PID/日志/渲染配置统一放在 `.run/`。
- README 补充项目简介、安装步骤、最小运行示例与 `scripts/setup.sh` 用法说明；末尾追加组织统一介绍区块。

### 修复

- 移除 `configs/code-server.yaml` 中硬编码的明文密码，改为运行时通过 `CODE_SERVER_PASSWORD` 环境变量渲染。
- 移除 `scripts/run_code_server.sh` 注释中硬编码的 natapp authtoken（已随文件一并删除，功能由 `scripts/setup.sh` 取代）。
- `init.sh` 中的变量展开统一加引号，避免路径含空格/通配符时出错。
- `init.sh`、`scripts/init.sh`、`scripts/env/init.sh` 增加 `set -euo pipefail`，任一步骤失败即以非 0 退出码终止，不再静默继续。

### 变更

- 移除 `scripts/auto_start.sh`、`scripts/run_code_server.sh`，相关逻辑合并进 `scripts/setup.sh`，路径解析改为基于脚本自身位置，不再依赖当前工作目录或写死的绝对路径。
- `.gitignore` 补充 `*.db`、`.run/`、`logs/`，并将已跟踪的 `logs/funenv/log` 移出版本管理。

### 废弃

- 无。
