# Codex Reconnect Doctor

一个运行在 macOS 菜单栏的 Codex 网络链路诊断工具。它用于区分本地代理未启动、代理端口异常、节点超时、OpenAI API 可达但 ChatGPT/Auth 受到挑战，以及 Codex 未确认走代理等情况。

## 为什么做这个工具

Codex 出现 `reconnecting` 时，问题可能发生在本地代理、代理节点、ChatGPT/Auth 会话链路或 Codex 启动环境。过去需要分别检查代理客户端、端口、浏览器和进程连接；本工具把这些检查收敛为一次本地诊断。

```mermaid
flowchart LR
    A[自动发现代理] --> B[检查本地端口]
    B --> C[检查 Codex 是否走代理]
    C --> D[并行检测 API ChatGPT Auth]
    D --> E[输出分层结论和建议]
```

## 当前能力

- 自动读取 macOS 系统代理和 `launchctl` 代理环境变量
- 自动发现常见本地 HTTP 代理端口
- 检查 Libcyber Desktop、Shadowrocket、Clash、Mihomo 等代理进程
- 检查 Codex 是否连接到本地代理
- 检查登录级强制代理的 LaunchAgent 是否匹配当前端口，以及当前用户会话中的6个代理变量是否全部生效
- 登录级代理保障缺失或失效时，可在“高级工具”中选择创建/修复；只要 Codex 当前已走代理，就不会因此判定连接异常
- 并行检测 OpenAI API、ChatGPT 和 Auth 链路
- 将 Cloudflare 403 标记为“网页端要求浏览器验证”；它能证明链路可达，但不会被单独判断为 Codex 重连原因
- 通过绿色、黄色、红色菜单栏状态展示结论
- 默认每 15 分钟自动检查，支持手动重测
- 保存最近 30 次本地检测结果
- 仅在发现问题时显示对应的建议操作，例如打开代理客户端或让 Codex 通过代理重新启动
- 将终端启动命令收在“高级工具”中，作为自动重启无效时的备用方案
- 提供“高级工具 → 测试诊断场景”，可安全预览10种状态、建议和建议按钮；测试不会操作代理、重启 Codex、写入登录配置或写入真实历史
- 所有检测均在本机完成，不上传诊断记录

## 状态含义

- 绿色：服务可达、响应速度正常，并确认 Codex 使用代理
- 黄色：服务可达但较慢，或未确认 Codex 使用代理
- 红色：代理节点不可用，或部分 OpenAI 服务无法建立连接
- 灰色：未发现有效代理配置，或正在检查

## 安装要求

- Apple 芯片 Mac（M1 或更新机型）
- macOS 13 或更高版本
- 已安装 Codex 桌面版
- 使用本地 HTTP 代理；自动发现失败时可以手动填写地址和端口

直接使用安装包不需要安装 Xcode、Swift 或其他开发工具。

## 从源码构建

开发环境要求：macOS 13 或更高版本、Swift 6 Command Line Tools。

```bash
chmod +x scripts/build.sh scripts/package.sh
./scripts/build.sh
```

应用生成在：

```text
build/Codex Reconnect Doctor.app
```

命令行诊断：

```bash
./build/Codex\ Reconnect\ Doctor.app/Contents/MacOS/CodexReconnectDoctor --diagnose
```

生成可发布的 ZIP：

```bash
./scripts/package.sh
```

## 安装

将 `Codex Reconnect Doctor.app` 拖入“应用程序”后启动。未签名版本第一次启动时，可能需要在访达中右键选择“打开”。

首次启动会自动读取系统代理和登录环境变量。自动发现失败时，可从菜单栏进入“设置”，手动填写本地 HTTP 代理地址与端口。

## 数据与隐私

检测历史仅保存在：

```text
~/Library/Application Support/CodexReconnectDoctor/history.json
```

工具不会读取代理订阅、节点名称、账号信息或浏览器内容。

## 安全设计

- 只接受 `127.0.0.1`、`localhost` 和 `::1` 本机代理地址，端口必须在 `1–65535` 之间
- 登录级代理保障使用独立签名 Helper 和结构化参数，不通过 `/bin/sh -c` 拼接用户输入
- 创建、修复、关闭登录级代理保障和重启 Codex 前均需要用户确认
- “高级工具”提供关闭并删除登录级代理保障的撤销入口
- 测试模式不会修改代理、登录配置或真实历史记录

## 测试

运行完整本地自检：

```bash
./scripts/test.sh
```

测试覆盖10种诊断场景、代理输入安全校验、诊断记录编解码、应用签名和压缩包完整性。

## 边界

- 工具不会自动切换代理节点。
- 工具不会绕过登录、认证或平台安全机制。
- 工具不会未经确认修改系统代理或退出 Codex。
- HTTP 状态和网络环境可能变化，诊断结论用于缩小排查范围，不替代服务商支持。

## 许可证

本项目采用 [MIT License](LICENSE)。
