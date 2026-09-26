# `modules/mcp_server` — Godot 内置 MCP 服务模块

把 MCP（Model Context Protocol）工具逻辑**内置到引擎本体**，使同一份 C++ 实现同时存在于
**编辑器进程**与**游戏进程**，从而可以直接访问 `Input` / `InputMap` / `SceneTree` / `Viewport`。

## 为什么内置而不是继续用 GDExtension

原实现是挂在 `EditorPlugin` 上的 GDExtension，**只存在于编辑器进程**：

1. `simulate_action` / `get_input_actions` 操作的是**编辑器**的 `Input`/`InputMap` 单例，
   而游戏是**独立子进程**（`editor/run/editor_run.cpp` 用 `--path` 拉起），游戏侧靠 `user://` 文件 IPC 转发
   → **编辑器侧输入注入永远打不到游戏进程**。
2. 游戏侧唯一的脚本执行工具走 `Expression.execute([], base, false)`，**只能解析 base 的成员**，
   引擎单例与全局类一律不可达（D29 裁决 6 实测）→ 无法在游戏进程内读 `Input`/`InputMap`。

结论：在该架构下「游戏可玩性」无法被自动判定。内置模块让两个进程各自拥有**同一份**实现与**各自的**端点。

## 架构要点

```
编辑器进程 (--mcp-port=9877)          游戏进程 (--mcp-port=9878)
  MCPServer : Node                      MCPServer : Node
   └ _process() 逐帧泵                   └ _process() 逐帧泵
      ├ mcp_http_server (TCPServer)         ├ mcp_http_server
      ├ mcp_jsonrpc (按 id 关联)             ├ mcp_jsonrpc
      └ tool_registry (scope 过滤)           └ tool_registry
```

- **无跨线程队列、无共享 FIFO**：请求与响应在同一调用栈内配对，响应写回**发起它的那条连接**。
  这从构造上排除了原 GDExtension 实现（单一 FIFO `try_recv` 取响应）导致的**响应错位**缺陷类。
- **主线程逐帧泵**：所有 Godot API 调用都在主线程；每帧处理上限 `mcp_server.max_requests_per_frame`（默认 8）。
- **端口解析**：`--mcp-port=N` > `ProjectSettings: godot_mcp/port` > 默认（编辑器 9877 / 游戏 0 = 不监听）。
  仅绑定 `127.0.0.1`；绑定失败不崩溃，只记 WARNING 并禁用。
- **传输契约**：HTTP `POST /mcp` 上的 JSON-RPC 2.0；客户端只发带 `Content-Length` 的请求
  （`Transfer-Encoding: chunked` 未解码，实测返回 411）。支持 `Expect: 100-continue`。

## 构建

```bat
D:\Anaconda\Scripts\scons.exe platform=windows target=editor module_mono_enabled=no -j8
:: 单测（引擎自带 doctest）：
D:\Anaconda\Scripts\scons.exe platform=windows target=editor tests=yes module_mono_enabled=no -j8
bin\godot.windows.editor.x86_64.console.exe --test --test-case=[MCPServer]*
:: 全引擎回归：
bin\godot.windows.editor.x86_64.console.exe --test
:: M1 验收脚本（默认用 9888/9889，不占用 9877）：
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1
```

## 文档

| 文件 | 内容 |
|---|---|
| [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) | 目标、成功标准、约束、假设、非目标、里程碑 |
| [`docs/DESIGN-OVERVIEW.md`](docs/DESIGN-OVERVIEW.md) | 架构分层、被否决的备选方案与否决理由、风险 |
| [`docs/DESIGN-DETAIL.md`](docs/DESIGN-DETAIL.md) | **GDR-1..GDR-15 规范性条款**、M1 交付范围、13+ 验收用例、工具批次 B1–B5、hof-rs 集成契约 |
| [`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md) | M0 / M1 的独立验收记录（含未验证边界与已知偏差） |

**决策日志不在这里**：跨项目决策（为什么这样做、被否决了什么、每轮修复的来源）记在 harness 仓库
`F:\moonbit-hof-rs\DECISIONS.md`（D30 起为本文档所述方向；D35–D39 为 M1 的实现与验收裁决）。
本目录只放**与代码同居的规范工件**，便于在 fork 内自洽阅读。

## 状态

- 分支：`feature/mcp-server-module`（本地，未推送）。
- 已通过：**M0**（工具链 + 非 mono 基线构建）、**M1**（骨架 + HTTP 子集 + JSON-RPC + `get_project_info`/`get_project_settings`；
  独立验收 pass：模块 doctest 33/33、全引擎 1459/1459、验收脚本 20/20 连跑两次）。
- **当前优先级（用户指令）**：**优先完成本模块的工具集成与测试；harness（hof-rs）暂停**。
  因此执行顺序为 `docs/DESIGN-DETAIL.md` §16：
  **命名 lint（GDR-16）→ 生成重命名后的期望契约 → 按批次移植 B1(42) → B2(25) → B3 → B4 → B5**，
  每批四道门（`tools/list` 逐字相等 / 每工具三类证据 / doctest 全绿 / 全引擎零回归）。
- 工具命名以 `docs/tool-rename-map.json` 为**唯一事实源**（**v1.1**：174 条，含 **1 对 merge**（GDR-17 唯一无损合并）、
  2 个下架、7 个「先修实现」；另外两对曾有损的合并已按 GDR-17 取消并各自保留。`disposition` 为枚举，
  合并目标由独立字段 `merge_target` 指向；两个截图工具按 GDR-18 记条件写 `mutating=true`）。
  由此渲染的规范文档是 `docs/TOOL-NAMING.md`（生成器 `docs/scripts/gen_table.py`），
  每批对等门的参照契约是 `docs/tools_list.renamed.json`（**171 条** = 174 − 2 下架 − 1 无损合并）。
- 推迟到解除暂停之后：harness 侧授权判定改由表驱动、产品级 E1–E6 真实冒烟。
