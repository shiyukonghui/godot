# DESIGN-OVERVIEW — Godot 内置 MCP 模块

上游：`REQUIREMENTS.md`、hof-rs `DECISIONS.md` D30。

## 1. 架构分层

```
                    ┌──────────────────────────── hof-rs Runtime（harness 侧）────────────────────────────┐
                    │  editor endpoint (9877)                game endpoint (9878)                        │
                    │  ── 工程/场景/脚本/编辑器错误             ── 运行中游戏的输入注入与状态观测         │
                    └───────────┬────────────────────────────────────┬───────────────────────────────┘
                                │ HTTP JSON-RPC (POST /mcp)          │ HTTP JSON-RPC (POST /mcp)
   ┌────────────────────────────▼────────────────┐   ┌───────────────▼───────────────────────────────┐
   │ Godot 编辑器进程（-e）                        │   │ Godot 游戏进程（--path <proj> [scene]）        │
   │  ┌──────────────────────────────────────┐   │   │  ┌─────────────────────────────────────────┐  │
   │  │ modules/mcp_server（同一份 C++ 实现）  │   │   │  │ modules/mcp_server（同一份 C++ 实现）     │  │
   │  │  MCPServer(Node) ── _process() 逐帧泵 │   │   │  │  MCPServer(Node) ── _process() 逐帧泵    │  │
   │  │  ├ mcp_http_server（TCPServer）        │   │   │  │  ├ mcp_http_server（TCPServer）          │  │
   │  │  ├ mcp_jsonrpc（按 id 关联）           │   │   │  │  ├ mcp_jsonrpc（按 id 关联）             │  │
   │  │  └ tool_registry（scope 过滤）        │   │   │  │  └ tool_registry（scope 过滤）           │  │
   │  └───────────────┬──────────────────────┘   │   │  └───────────────┬─────────────────────────┘  │
   │                  │ 编辑器 API               │   │                  │ 游戏 API                  │
   │   EditorNode / EditorInterface / UndoRedo    │   │  Input / InputMap / SceneTree / Viewport     │
   └──────────────────────────────────────────────┘   └──────────────────────────────────────────────┘
```

关键：**同一份模块代码编译进同一个二进制**，靠 `Engine::is_editor_hint()` 与工具 `scope` 决定暴露面；两个进程各自独立监听，**没有 IPC、没有 autoload、没有文件转发**。

## 2. 被考虑的备选方案与否决理由

| 备选 | 否决理由 |
|---|---|
| A. 保留 GDExtension，只修 `execute_game_script` 的执行方式 | `Expression` 机制决定其**不可达引擎单例**（D29 裁决 6 实测）；即便改成 `GDScript.new()+reload()`，编辑器侧输入仍打不到游戏进程——进程边界未解决，属治标 |
| B. 给编辑器 run bar 打补丁，追加 `--mcp-port` | 游戏进程的生命周期、stdout、退出码仍由编辑器掌控，harness 无法可靠清理与取证；且需改引擎编辑器源码（违反 C5） |
| C. 引入 SSE / WebSocket 传输 | hof-rs 只需 `POST /mcp`；SSE 会重新引入「响应异步推送到会话」的复杂性与错位风险（现有 addon 的 SSE 分支正是脆弱点） |
| D. 编辑器↔游戏双端点仍靠 addon 的 `user://` 文件 IPC | 被「两个进程各自独立端点」取代；IPC 是 E3 失败的根因载体 |
| E. 把模块做成新的 GDExtension 并同时挂到游戏进程 | 游戏进程加载哪个 GDExtension 由项目 `addons/` 决定，仍要往**被评估对象** `A_t` 里塞 harness 自己的东西（违反证据独立性） |
| F. harness 在 `A₀` 注入输入桥 autoload | 同上：`A_t` 会多出 harness 的 autoload，污染被评估对象与哈希身份 |

## 3. 选定方案与理由

**内置 module `modules/mcp_server/`，编辑器与游戏共用一份实现；`TCPServer` + 主线程逐帧泵 + 按 JSON-RPC `id` 关联。**

理由：

1. **唯一能真正解决 E3 的形态**——游戏进程内可以直接 `Input::get_singleton()->parse_input_event()`，且 `InputMap` 就是该进程的 InputMap。
2. **不污染被评估对象**——模块编译在引擎里，`A_t` 只需是普通 Godot 工程，无需任何 harness 专用 autoload/插件。
3. **从构造上消灭错位缺陷类**——请求与响应在同一个调用栈内配对，响应写回**发起它的那条连接**；不存在共享 FIFO。
4. **保持 hof-rs 零契约改动**——工具名/描述/schema 与现有 174 工具逐字一致，`POST /mcp` 与响应信封一致。
5. **单二进制双角色**——编辑器二进制本身能 `--path` 跑游戏（A2），无需额外构建模板。

## 4. 风险与应对

| 风险 | 应对 | 回滚点 |
|---|---|---|
| 首次引擎构建失败 | **已在 M0 排掉**（非 mono 13.2 分钟 exit 0；两个坑：注册表代理导致 pip 报错需 `NO_PROXY=*`；D3D12/AccessKit 依赖需先跑官方脚本） | 不涉及 fork 源码 |
| mono 构建额外失败面（glue 生成、GodotTools、net8.0 目标包） | M0 已隔离非 mono 变量；mono 失败可退回非 mono（模块不受影响，只是不能 C#） | 非 mono 二进制 |
| 4.8-dev 漂移 | 记录基线 `57277407`；只依赖稳定 API（`Object`/`Node`/`SceneTree`/`Input`/`InputMap`/`TCPServer`/`StreamPeerTCP`/`JSON`） | 切 tag（需用户批准） |
| 主线程泵在模态/长阻塞期间不响应 | 客户端超时（既有能力）；文档化；若成为瓶颈，后续仅把 **socket I/O** 下放工作线程，响应仍按 id 关联 | 泵的实现 |
| 单帧内请求过多导致帧时长抖动 | 每帧处理有上限（`mcp_server.max_requests_per_frame`，默认 8），其余排队到下一帧；上限可配 | 同上 |
| 双实现漂移（Rust addon 与 C++ 模块并存） | 以 `tools_list.json` + golden 请求序列为**唯一契约源**，每批跑对等门 | 不需要 |
| 端口占用 | 绑定失败不崩溃，记录警告并按 `godot_mcp/port` 后备或禁用；验收要求覆盖该反例 | 端口解析 |

## 5. 与非目标相关的明确取舍

- **不追求全量对等**：分类分批（B1–B5），每批有对等门；未移植工具在 `tools/list` 中**不出现**（而不是出现但返回 not_implemented），以免误导客户端。
- **不做权限模型**：工具权限（哪个角色能调什么）仍由 hof-rs 侧的 `tools::policy` 负责，模块不做角色概念。
- **不做鉴权**：仅监听 `127.0.0.1`，与现有 addon 一致；如需远程访问由 hof-rs 侧的隧道解决。
