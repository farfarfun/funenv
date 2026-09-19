# funenv

farfarfun 内部开发/测试环境的一键初始化与 code-server 服务管理脚本集合。

## 包含内容

- `init.sh`：在 `/farfarfun` 下安装 Miniconda。
- `scripts/init.sh`：初始化 Git 全局配置并拉取 submodule。
- `scripts/env/init.sh`：配置 SSH 免密登录相关的 sshd 参数。
- `scripts/setup.sh`：code-server 服务的统一启停入口。
- `configs/code-server.yaml`：code-server 配置模板，密码通过环境变量注入，不写进文件。

## 快速开始

```bash
git clone https://github.com/farfarfun/funenv.git
cd funenv

# 可选：安装 Miniconda
./init.sh

# 启动 code-server（必须先设置密码环境变量）
CODE_SERVER_PASSWORD=<your-password> ./scripts/setup.sh start dev
```

## scripts/setup.sh 用法

统一管理 code-server 生命周期，`action` 与 `env`（`dev`/`prod`）均为必填：

```bash
CODE_SERVER_PASSWORD=<password> ./scripts/setup.sh <start|run|stop|restart|status> <dev|prod>
```

| action | 说明 |
| --- | --- |
| `start` | 后台启动，PID 写入 `.run/code-server-<env>.pid` |
| `run` | 前台启动（`exec`），便于调试，`Ctrl+C` 可直接结束 |
| `stop` | 停止已记录的进程，清理 PID 文件 |
| `restart` | 先 `stop` 再 `start` |
| `status` | 非交互查看运行状态，不修改任何状态 |

- 密码只能通过 `CODE_SERVER_PASSWORD` 环境变量传入，脚本会在 `.run/code-server-<env>.yaml` 渲染出真实配置（该文件不进版本管理），`configs/code-server.yaml` 中只保留 `${CODE_SERVER_PASSWORD}` 占位符。
- 日志、PID、渲染后的配置统一位于 `.run/`，不同 `env` 相互隔离，拒绝重复启动。
- 端口通过 `CODE_SERVER_PORT` 环境变量覆盖，默认 `8443`。

---

## 关于 farfarfun

[farfarfun](https://github.com/farfarfun) 是一个专注于实用工具库的开源组织，
涵盖云存储、数据处理、AI、多媒体与开发工具链等方向。

- 🏠 组织主页：<https://github.com/farfarfun>
- 📧 联系：farfarfun@qq.com

本项目基于 [MIT](LICENSE) 协议开源。
