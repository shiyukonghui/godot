# TASK-053 — C 档 2：`project_write_text_file` 错误码改判 + 三个新增工具（`project_validate_scripts` / `editor_set_node_script_batch` / M-5）

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件；**规范**：`DESIGN-DETAIL` **§26/GDR-28**（含第 10 条裁决）。
> 报告 `docs/reports/REPORT-053-added-tools-2.md`。返回决策者的内容**只允许**是「≤10 行总结 + 报告路径」。

## 1. 错误码改判（**决策者裁决，TASK-052 §10**）

`project_write_text_file` 在「**目标已存在且 `overwrite:false`**」时**不再用 `-32001`**（GDR-14 的 `-32001` 是
「**你要找的东西不存在**」，此处**存在**），也**不用 `-32602`**（该参数**已声明且取值合法**）
→ 改为 **`-32000` + `data.suggestion`**（点名 `overwrite:true`）。**必须**同时给「拒绝后文件字节未变」的证据，
并**更新**受影响的 doctest / 证据脚本期望（**不得**只改实现尺寸）。

## 2. 三个新增工具（条目原文由决策者给定；实现须与契约字面一致）

### 2.1 `project_validate_scripts`（C-4③）

- `project` + `validate` + `scripts`；作用域 `project`，`mutating=false`。
- **描述**：`Validate every script of the project in one call and answer a per-file verdict, so a batch of edited scripts can be checked without one call per file.`
- **`inputSchema`**：`paths`（array of string，**可选**；省略 = 扫描工程内全部脚本）、`include_errors_only`（boolean，默认 `false`）。
- **行为**：逐文件给出 `path`/`language`/`valid`/**分类**（`ok` / `invalid` / **`language_unavailable`**）/
  `error_text`（截断标明）；**语言不可用必须与「校验失败」区分开**（沿用 TASK-050 的 `-32000` 语义口径：
  单文件不可用 → 该项分类 `language_unavailable` + 说明，**不得**记成 `valid:false`）；
  返回 `count`/`valid_count`/`invalid_count`/`unavailable_count`；路径越界 → `-32602`。

### 2.2 `editor_set_node_script_batch`（C-4④）

- `editor` + `set` + `node_script_batch`；作用域 `editor`，`mutating=true`。
- **描述**：`Attach one script to many nodes in the edited scene in a single call, and answer per node whether the attachment landed and the script was readable.`
- **`inputSchema`**：`script_path`（string，必填）、`node_paths`（array of string，必填，≥1）、
  `keep_existing`（boolean，默认 `false`）。
- **行为**：**全成功或全回滚**（与既有批量工具同语义）；`keep_existing:true` 时已挂脚本的节点**跳过并如实计入**
  （`skipped[]` + 原因），**不得**静默覆盖；逐节点**读回核实**（`attached` 真值）；
  任一失败 → 回滚并给 `rolled_back:true` + 失败项；越界/不存在 → `-32001` + 建议。

### 2.3 M-5：`running_game_*` 采样步

- **不改工具数量**：给既有的采样读取工具（`REPORT-AUDIT-RACING-BACKLOG` 指出的那一个；**你从源码定位并在报告里点名**）
  增加**采样步/间隔**参数（`sample_stride` 或等价，**你定名并说明为何更顺手**），**默认保持现语义**；
  **必须**给「默认下响应与改动前逐字节相同」与「显式步长下返回点数/字节数」的前后对照。

## 3. 门与纪律

- 第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；
  五道门 + 门⑥ 三段式 + `--check-completeness` / `--added` exit 0（**契约 173 → 176**）。
- 契约机制沿用 `ADDED_TOOLS`（**不改**已有条目与既有清单；新工具进 `docs/tool-groups-added.json`）。
- 回归 `mcp041/042/043` + `mcp010/019/027` + `mcp044/045/046` + `mcp050/051/052` 证据脚本，**逐条归因**。
- **绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push；构建串行、不抑制输出；`.ps1` 纯 ASCII；结论按 D86 标锚点。
- **不可构造项显式声明**（例如需要 C# 语言的校验路径）。