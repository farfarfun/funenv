# CHANGELOG

## [未发布]

### 新增

- 新增 `scripts/setup.sh` 作为 code-server 服务的统一生命周期入口，支持 `start`/`run`/`stop`/`restart`/`status`，区分 `dev`/`prod` 环境，PID/日志/渲染配置统一放在 `.run/`。
- README 补充项目简介、安装步骤、最小运行示例与 `scripts/setup.sh` 用法说明；末尾追加组织统一介绍区块。
- 新增 `tests/test_setup.sh`：覆盖参数解析、凭据处理、监听地址优先级、PID 生命周期四类行为，共 45 条断言。已反向验证——回退到本次修复前的实现时其中 21 条会失败。
- `scripts/setup.sh` 支持 `CODE_SERVER_BIND_ADDR` / `CODE_SERVER_HOST` 覆盖监听地址，以及 `configs/code-server.<env>.yaml` 形式的环境专属配置。
- `tests/test_setup.sh` 补齐前台 `run` 路径用例（缺密码、可执行文件缺失、前台常驻不自行返回、不写 PID 文件、渲染配置权限 0600、密码不进命令行参数、监听地址覆盖、退出码原样透传、已有后台实例时拒绝启动），断言总数增至 57 条。已反向验证——把 `do_run` 的 `exec` 改成后台执行并去掉重复启动检查后，其中 6 条会失败。

### 修复

- 移除 `configs/code-server.yaml` 中硬编码的明文密码，改为运行时通过 `CODE_SERVER_PASSWORD` 环境变量渲染。
- **密码不再经由命令行参数传递。** 原先用 `sed "s#...#$CODE_SERVER_PASSWORD#g"` 渲染配置，明文密码会出现在 `sed` 进程的 `/proc/<pid>/cmdline`（权限 `-r--r--r--`，同机任何用户 `ps aux` 即可读到）。改为全程只用 Bash 内建命令写入。
- **渲染出的配置不再世界可读。** `.run/code-server-<env>.yaml` 原先按默认 umask 创建为 `0644`，明文密码在服务整个生命周期内对同机所有用户可读；现在收紧为 `0600`。
- **含特殊字符的密码不再被静默改写。** `sed` 渲染会把密码里的 `#` 当成表达式分隔符（直接报错退出）、把 `&` 展开成匹配到的整段文本、把 `\` 吞掉，结果是登录密码与设置的值不一致。改为按 YAML 单引号标量转义。
- **监听地址默认值改为安全值，并修正优先级倒挂。** 原先 `configs/code-server.yaml` 默认 `bind-addr: 0.0.0.0:8443`，且 `scripts/setup.sh` 无条件下发 `--bind-addr 0.0.0.0:$CODE_SERVER_PORT`；由于 code-server 的命令行参数优先级高于配置文件，用户在配置文件里改成回环地址会被静默忽略，服务仍暴露在所有网卡上。现在默认 `127.0.0.1:8443`，且只有显式设置环境变量时才下发 `--bind-addr`，恢复「环境变量 > 配置文件 > 代码默认值」（SPEC §9.3）。
- **`start` 不再谎报成功。** 原先 `nohup ... &` 后直接写 PID 并打印「已后台启动」，端口被占用、配置写错、`user-data-dir` 不可写等失败全被包装成成功（退出码 0），`.run/` 里留下死 PID。现在启动后观察一段时间确认进程存活，失败则清理 PID、输出日志尾部并以非 0 退出。
- **`status` 不再误报、`stop` 不再误杀无关进程。** 原先 `is_running()` 只做 `kill -0`，PID 被系统回收给别的进程后会被认成服务还活着，`stop` 会直接 `kill` 掉那个无关进程；僵尸进程也能通过 `kill -0`，导致刚崩掉的服务一直显示「运行中」。现在额外记录并比对进程启动时刻（`/proc/<pid>/stat` 的 `starttime`），并排除僵尸状态。
- **`stop` 会等进程真正退出**（必要时升级 `SIGKILL`），`restart` 因此不再在旧进程尚未释放端口时就拉起新进程。
- `status` 的环境参数改为可省略，省略时报告所有已配置环境（SPEC §6.1）；多余参数会被拒绝。
- 移除 `scripts/run_code_server.sh` 注释中硬编码的 natapp authtoken（已随文件一并删除，功能由 `scripts/setup.sh` 取代）。
- `init.sh` 中的变量展开统一加引号，避免路径含空格/通配符时出错。
- `init.sh`、`scripts/init.sh`、`scripts/env/init.sh` 增加 `set -euo pipefail`，任一步骤失败即以非 0 退出码终止，不再静默继续。

### 变更

- 移除 `scripts/auto_start.sh`、`scripts/run_code_server.sh`，相关逻辑合并进 `scripts/setup.sh`，路径解析改为基于脚本自身位置，不再依赖当前工作目录或写死的绝对路径。
- `.gitignore` 补充 `*.db`、`.run/`、`logs/`，并将已跟踪的 `logs/funenv/log` 移出版本管理。

### 废弃

- 无。
