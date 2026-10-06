# funenv

farfarfun 内部开发/测试环境的一键初始化与 code-server 服务管理脚本集合。

## 包含内容

- `init.sh`：在 `/farfarfun` 下安装 Miniconda。
- `scripts/init.sh`：初始化 Git 全局配置并拉取 submodule。
- `scripts/env/init.sh`：配置 SSH 免密登录相关的 sshd 参数。
- `scripts/setup.sh`：code-server 服务的统一启停入口。
- `configs/code-server.yaml`：code-server 配置模板，密码通过环境变量注入，不写进文件。
- `tests/test_setup.sh`：`scripts/setup.sh` 的行为测试（参数解析、凭据处理、监听地址优先级、PID 生命周期）。

## 快速开始

```bash
git clone https://github.com/farfarfun/funenv.git
cd funenv

# 可选：安装 Miniconda
./init.sh

# 启动 code-server（请改为安全的实际密码）
CODE_SERVER_PASSWORD='change-me' ./scripts/setup.sh start dev
```

## scripts/setup.sh 用法

统一管理 code-server 生命周期。`start`/`run`/`stop`/`restart` 必须指定 `dev` 或 `prod`；
`status` 的环境参数可省略，省略时报告全部环境：

```bash
CODE_SERVER_PASSWORD='change-me' ./scripts/setup.sh start dev
CODE_SERVER_PASSWORD='change-me' ./scripts/setup.sh start prod
./scripts/setup.sh status
```

| action | 说明 |
| --- | --- |
| `start` | 后台启动；确认进程真的起来了才报成功，起不来则输出日志尾部并以非 0 退出 |
| `run` | 前台启动（`exec`），便于调试，`Ctrl+C` 可直接结束，退出码原样透传 |
| `stop` | 停止本脚本托管的进程，等它真正退出（必要时 `SIGKILL`），再清理运行时文件 |
| `restart` | 先 `stop`（等端口释放）再 `start` |
| `status` | 非交互查看运行状态，不修改任何状态；能区分「运行中」与「陈旧 PID 文件」 |

### 凭据

密码只能通过 `CODE_SERVER_PASSWORD` 环境变量传入，`configs/code-server.yaml` 里不含任何
`password` / `hashed-password` 字段。启动时脚本把密码渲染进 `.run/code-server-<env>.yaml`：

- 该文件权限为 `0600`，不会被同机其他用户读到；
- 密码全程只经 Bash 内建命令写入，不会作为命令行参数出现在 `/proc/<pid>/cmdline`（即 `ps aux` 读不到）；
- 含 `#`、`&`、`\`、`'` 等字符的密码按 YAML 单引号标量转义，原样生效。

### 监听地址

默认只监听回环地址 `127.0.0.1:8443`（见 `configs/code-server.yaml` 的 `bind-addr`）。
优先级为 **环境变量 > 配置文件 > 脚本内默认值**；不设置任何环境变量时脚本不下发
`--bind-addr`，配置文件里的值生效：

| 环境变量 | 作用 |
| --- | --- |
| `CODE_SERVER_BIND_ADDR` | 整体覆盖，如 `0.0.0.0:8443` |
| `CODE_SERVER_HOST` | 只覆盖主机部分 |
| `CODE_SERVER_PORT` | 只覆盖端口部分 |
| `CODE_SERVER_BIN` | 仅 `dev` 使用的 code-server 可执行文件，默认 `code-server` |

要把服务暴露到公网需显式设置 `CODE_SERVER_BIND_ADDR=0.0.0.0:<port>`，并自行确保前置
反向代理与 TLS 到位。

### 运行时文件与多环境

日志、PID、启动时刻记录、渲染后的配置统一位于 `.run/`（已在 `.gitignore` 中），
不同 `env` 相互隔离，拒绝重复启动。若存在 `configs/code-server.<env>.yaml`，
该环境会优先使用它，否则回落到 `configs/code-server.yaml`。

`prod` 只能运行系统正式安装包提供的 `/usr/bin/code-server`，不会使用
`CODE_SERVER_BIN`、`PATH` 中的同名文件或仓库内构建产物。请先通过系统的受支持包管理方式
安装正式包；该入口不存在或不可执行时，生产启动会失败。

## 测试

```bash
./tests/test_setup.sh
```

---

## 关于 farfarfun

[farfarfun](https://github.com/farfarfun) 是一个专注于实用工具库的开源组织，
涵盖云存储、数据处理、AI、多媒体与开发工具链等方向。

- 🏠 组织主页：<https://github.com/farfarfun>
- 📧 联系：farfarfun@qq.com

本项目基于 [MIT](LICENSE) 协议开源。
