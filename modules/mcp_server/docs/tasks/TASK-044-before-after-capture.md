# TASK-044 — 捕获：**操作前后截图 + 与操作日志同行记录**（追踪的可选扩展，零契约变更）

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册），再读本文件；
> **规范**：`DESIGN-DETAIL` **§24/GDR-26（追踪）** 与**新增的 §25/GDR-27（捕获）**；
> 报告写到 `docs/reports/REPORT-044-before-after-capture.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 目标（用户要求）

用户要求：**进行一次操作时做操作前后的截图，并与操作日志一起记录，便于排查问题**。
动机非常明确 —— 本项目的核心命题是「**报成功但什么都没发生**」（D-1/D-2 家族）。
有了它，`changed:false` 就能把「报成功但画面没变」从**推断**变成**机器可判事实**。

**形态（决策者已定）**：做成 **`§24/GDR-26` 追踪的可选扩展**，**零契约变更** ——
**不新增工具、不改任何 `inputSchema`/`description`**（171 条逐字对等门不动）；截图与结论走**旁路**（日志 + 文件）。

## 1. 用户四项选择（**必须照办**）

1. **三档开关**：`--mcp-capture=off|on_error|every_call`（**默认 `off`**）；
   配套 `ProjectSettings: godot_mcp/capture`；另有 `--mcp-capture-dir=<OS 路径>`
   （默认 = 追踪文件同目录下的 `shots/`）与 `--mcp-capture-viewport=editor|2d|3d`（**默认 `editor`**）。
2. **取景**：编辑器侧支持 **`editor`（整个编辑器窗口，即现有 `get_base_control()->get_viewport()`）**、
   **`2d`（`EditorInterface::get_editor_viewport_2d()`）**、**`3d`（`EditorInterface::get_editor_viewport_3d(0)`）**；
   游戏侧 = 游戏窗口。**先读引擎源码确认**这三个访问器在当前提交上的签名与可用性（已初查：`editor_interface.h:130-131`），
   并在报告里给**文件:行**依据。
3. **落盘**：**存原图、不设上限**（用户明确选择）。**但"不设上限"必须可见**：
   每行日志带 **`total_bytes`（累计）**；启动日志打印捕获目录与模式；
   累计超 **1 GB** 时**只 WARN 一次**（**绝不删除任何文件**）。
4. **自动 diff**：前后两图**自动比对**，把 **`changed`** 与 **`changed_pixel_ratio`** 写进日志；
   差异图**按需**落盘（例如 `--mcp-capture-diff-image=on`，默认不落）。

## 2. 关键设计（**必须按此实现，除非引擎事实不允许 —— 那就在报告里给证据并报我**）

1. **零延迟代价**：收到请求时**只做一次 framebuffer 图像拷贝**（廉价），**随后照常应答**（**不等帧**）；
   编码 / 落盘 / diff 一律在**应答之后**做。→ 捕获**不改变**任何工具的响应时序与内容。
2. **日志形态**：
   - 调用行（`§24` 的既有行）增加 `capture`：`{mode, viewport, status:"pending"|"unavailable"}`；
   - **应答之后追加一行**：`{"event":"capture","seq":<同一 seq>,"tool":…,"status":"done|unavailable|failed",`
     `"before":{path,sha256,bytes,width,height},"after":{…},"frames_waited":N,`
     `"changed":true/false,"changed_pixel_ratio":0.031,"diff":{path?},"total_bytes":…,"reason"?}`
3. **「后」的帧**：该次调用**生效并再渲染至少 1 帧**之后取图（用本模块既有的**帧计数 + 延迟通道**，
   与 `editor_bake_navigation_mesh` 的 `is_baking()` 轮询同法），日志带 `frames_waited` + 帧标识以自证。
4. **headless 不得静默**：无帧缓冲（`game_framebuffer_available()` 为假）时写
   `status:"unavailable", reason:"headless display server 没有纹理存储"`，**不写空白图、不静默跳过**。
5. **复用而非重写**（GDR-25）：`normalize_screenshot_path` / `screenshot_png_writer` /
   `game_framebuffer_available` 已在 `tool_helpers`；**把 `editor_analyze_screenshot_diff` 的像素比对算法
   从 `tools/editor_testing_read.cpp` 提升到 `tool_helpers`**，让**两者共用同一实现**
   （与 TASK-011 提升 PNG 写入器同法），并证明 `editor_analyze_screenshot_diff` 的**行为与证据不变**。
6. **零行为变化**：`off` 时与改动前的响应**逐字节相同**（沿用 `§24` 的三条对照模板，含**与任务前二进制比对**）；
   `on` 时 171 个工具的**响应**逐字节相同（截图只进日志与文件，**绝不进响应**）。
7. **健壮性**：写图失败只 WARN 并如实写 `status:"failed" + reason`，**绝不影响**工具调用；
   目录不存在则创建；文件名 `NNNN_<before|after|diff>.png`（`seq` 零填充，稳定可排序）。

## 3. 验收（硬性，每条都要证据）

1. **存在理由实验**：构造一次「**报成功但什么都没发生**」的调用（例如对一个**不存在**的属性做一次
   `node->set` 类操作，或任何已修复前的等价场景），在 `on_error`/`every_call` 下必须得到 **`changed:false`**；
   并给出一张**真实改变画面**的调用得到 **`changed:true` + `changed_pixel_ratio>0`**。
2. **零延迟证据**：同一批调用在 `off` 与 `every_call` 下的**响应耗时**对比（给出实测分布，说明未见系统性增加）。
3. **零行为对照**：`off` 与任务前二进制逐字节相同；`on` 时 171 工具响应逐字节相同（≥10 个工具 + 全量 `tools/list`）。
4. **三档开关**：`off` 不产生文件、`on_error` 只对失败调用产图、`every_call` 全产图（各给证据）。
5. **三个视口**：`editor`/`2d`/`3d` 各产出一张图，尺寸与内容合理（1x1 或全黑视为失败）。
6. **headless**：`--headless` 下写 `unavailable` 行（不写文件），且**工具调用本身照常工作**。
7. **两端点**：9888（编辑器）与 9889（游戏）各跑一条链。
8. **可见性**：`total_bytes` 随每次捕获单调增加；构造超过阈值的情形，证明**只 WARN、不删文件**。

## 4. 门

- 第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD（**从 cmd 启动**）。
- 五道门 + 门⑥ 三段式（**新增收窄点必须逐条列「新增点 × 经过的闸门 × 证据」**，§22.3b 规则 4）。
- 回归：`scripts/mcp042_*`/`mcp043_gates.ps1`、`mcp041/040/038` 相关证据脚本 + 6 个历史回归脚本，逐条归因。

## 5. 报告

按手册 §4（含「引擎依据」列），写到 `docs/reports/REPORT-044-before-after-capture.md`；另加：
「三个视口的引擎依据（文件:行）」「日志 schema 与一条**真实样例**（含 `changed:false` 与 `changed:true` 各一条）」
「零延迟与零行为对照」「diff 算法提升后 `editor_analyze_screenshot_diff` 未变的行为证据」
「不设上限的可见性证据」「对决策者的规范落笔请求（若 §25 需修正）」。**返回值：≤15 行总结 + 报告路径。**