# TASK-052 — C 档 1：**契约扩张机制** + 两个新增工具（`project_build_csharp` / `project_write_text_file`）

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件；**规范**：`DESIGN-DETAIL` **§26/GDR-28（契约扩张）**。
> 证据来源：`docs/reports/REPORT-AUDIT-RACING-BACKLOG.md`（M-2/N-3 已确认）。报告 `docs/reports/REPORT-052-added-tools.md`。
> 返回决策者的内容**只允许**是「≤10 行总结 + 报告路径」。

## 0. 机制（先做，规范见 §26/GDR-28）

1. 生成器新增 **`ADDED_TOOLS`** 列表（**与两张 override 表分离**），在重命名 + override 之后**确定性追加**；
   `_meta` 增 **`added_tools`**（有序名列表）+ **`added_count`**；**幂等**（连跑两次同 sha）。
2. `check_tool_groups.py --check-completeness` 的并集断言改为 **`171 + N = 66 + 105 + N`**
   （新增**恰好一次**：missing=0 / foreign=0 / duplicated=0）；新增 **`--added`** 校验新清单。
3. 新增工具进 **`docs/tool-groups-added.json`**（**不改**既有批次清单），受**同样的组规则**约束。
4. **对等门表述**：门① = 「**171 条移植工具逐字 + N 条新增条目逐字**」。

## 1. 两个新增工具（条目原文，**由决策者给定**；实现须与契约字面一致）

### 1.1 `project_build_csharp`

- **渠道/动作/对象**：`project` + `build` + `csharp`（作用域 `project`，`mutating=true`，两端点可见——按映射口径你复核后定，并在报告说明）。
- **描述（英文，逐字）**：
  `Build the project's C# solution by running the .NET SDK on its .csproj files, and answer the exit code with the captured output. Requires a Godot build with C# support and a .NET SDK on PATH; when either is missing the call is refused with the reason and what to install.`
- **`inputSchema`**：`timeout_ms`（integer，默认 `120000`，最小 `1000`，最大 `600000`）、
  `configuration`（string，enum `["Debug","Release"]`，默认 `"Debug"`）、
  `extra_args`（array of string，默认 `[]`）、`rescan`（boolean，默认 `true`）。
- **行为要求**：跨进程调用（**先读引擎/工具链源码确认**可用的 SDK/`dotnet` 发现路径与 `.csproj` 定位规则，给 `文件:行` 依据）；
  **超时必须真的杀掉子进程**并在响应里如实说明（`timed_out:true`）；捕获 stdout/stderr（**截断要标明**）；
  返回 `exit_code` / `stdout` / `stderr` / `duration_ms` / `command`（**真实命令行**）/ `project_files`（参与的 `.csproj`）/
  `rescanned`；**失败不得伪造成 `exit_code:0`**；`rescan` 走既有编辑器 rescan 语义（说明依据）。
  **capability-aware**：无 C# 支持或无 SDK → **`-32000` + `data.suggestion`**（说缺什么、怎么装）。
- **证据**：①成功构建一次（在 `%TEMP%` 建最小 C# 工程，用 **mono 构建**的编辑器；给出真实 exit code 与输出）；
  ②故意写错的 `.cs` → 非零退出 + 输出含错误；③无 SDK/无 C# 支持的环境 → 诚实拒绝；
  ④超时路径（用一个能挂住的构造或 `timeout_ms` 极小，证明**子进程被杀**）。

### 1.2 `project_write_text_file`（N-3）

- **渠道/动作/对象**：`project` + `write` + `text_file`（作用域 `project`，`mutating=true`）。
- **描述（英文，逐字）**：
  `Write a project text file such as a .csproj, .sln, NuGet.config or .cfg, and answer the resulting size and sha256. Refuses scene, resource and script paths (use the dedicated tools for those) and refuses project.godot (use project_set_setting).`
- **`inputSchema`**：`path`（string，必填）、`content`（string，必填）、`overwrite`（boolean，默认 `false`）。
- **行为要求（**现状与必须保持的东西写清**）：
  ①**拒绝**：`project.godot`（指向 `project_set_setting`）、`.tscn`/`.tres`/`.gd`/`.cs`（指向专用工具）、
    `res://` 之外的路径与 `..`（既有 `normalize_screenshot_path` 同族规则）→ **`-32602` + `data.suggestion`**（点名该用哪个工具）；
  ②**不删除任何文件**（本工具**没有删除路径**；给代码腿证据）；
  ③`overwrite:false` 且文件已存在 → **拒绝**（`-32001` + 建议传 `overwrite:true`），**不得**静默覆盖；
  ④写后**读回核实**（大小 + sha256），返回 `path`/`bytes`/`sha256`/`created`；
  ⑤**原子发布**（复用既有 `publish_file_atomically` 同族语义）并在报告里说明。
- **证据**：①写 `.csproj` 与 `NuGet.config`（`%TEMP%` 最小 C# 工程）；②四类拒绝各一条；
  ③`overwrite:false` 命中已存在 → 拒绝且文件**字节未变**；④写后再用别的工具读回（零字符串手术链）。
- **与 `project_build_csharp` 的闭环（这是本批的价值证明）**：**从零**用工具建一个最小 C# 工程
  （`project_set_setting` 写 `application/config/name` → `project_write_text_file` 写 `.csproj`/`NuGet.config` →
  `project_create_script` 写 `.cs` → `project_build_csharp` 构建成功），**全过程只用工具**，逐步给响应与 sha256。

## 2. 门与纪律

第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；五道门 + 门⑥ 三段式
（新收窄点逐条列，§22.3b 规则 4）；`check_tool_groups.py --check-completeness` 与 `--added` 必须 exit 0；
回归 `mcp041/042/043` + `mcp010/019/027` + `mcp044/045/046` + TASK-050/051 证据脚本（**逐条归因**）；
**绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push；构建串行、不抑制输出；`.ps1` 纯 ASCII；结论按 D86 标锚点。
**能力缺失（无 SDK / 非 mono 构建）必须诚实拒绝**，不得伪造成功；不可构造项**显式声明**。