# TASK-057 — 收口三条（D-B1 / R-B2 / R-B3）+ **引擎补丁 2**：`project.godot` 局部发布

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件；**补丁纪律见 D112**。
> 证据：`docs/reports/REPORT-AUDIT-ADDED-B.md`（**verdict=pass**；D-B1 / R-B2 / R-B3）。
> 报告 `docs/reports/REPORT-057-mono-anchor-and-project-settings-publish.md`。返回决策者：**≤8 行总结 + 报告路径**。

## 1. D-B1（medium）：mono 二进制是**脏树构建**

`bin\godot.windows.editor.x86_64.mono.console.exe` 自报 `4e3de1090` ≠ HEAD `427fc79da`（构建于提交前）→
这是 `mcp052`（52/53）与 `mcp053`（72/73）**唯一**失败项 `engines_match_head`。
→ **在 HEAD 串行重建 mono**（`module_mono_enabled=yes tests=yes`），复跑两个脚本到 **53/53 与 73/73**，
并给「mono 与 plain 两个二进制的 `--version` 都 == HEAD」的证据。
（构建后如需，再 `build_local.cmd -Force` 恢复 plain 并复验 `--version`。）

## 2. R-B2：把**生成器版本一致性**变成**机器断言**

`docs/tool-groups-added.json` 的 `source.entries` 版本号是**自由文本**，`check_tool_groups.py` **完全不校验** →
漂移会静默复发（本类已复发两次）。
→ 加**机器断言**（三处必须相等：`GENERATOR_VERSION` / `_meta.generator_version` / 清单里的版本字段），
放进 `check_tool_groups.py`（或专门的契约一致性脚本），**并造一次失败演示**（改一处 → 必须 exit 非 0 → 还原）。

## 3. R-B3：回归电池**不得静默覆写**被跟踪的证据

15 步回归里 13 步会重写 `docs/reports/evidence/task0xx/**`（还有 `mcp051` 会新建 `task051/red/e20_child_status.json`）→
重跑会**静默改写历史取证**（人工 `git checkout --` 才补得回来）。
→ **二选一**（说明理由）：①电池**默认写到 `%TEMP%`**，只把「摘要」复制进仓库；或
②电池结束时**自动还原**被它改写的被跟踪文件，并**打印还原清单**。
**必须**给「重跑前后 `git status --short` 与 `git diff --stat` 为空」的证据。

## 4. **引擎补丁 2**：`ProjectSettings` 的**局部发布**（一次解决 R1–R9）

**现状**（实测）：`ProjectSettings::save_custom` → `_save_settings_text` **写头 + 所有已存设置**（`project_settings.cpp:1162-1210/1234-1341`），
`ConfigFile::save` 同样整文件 → 「加一个输入动作」会**重写整个 `project.godot` 并丢掉手写注释**（TASK-042/043 已实测并写进 5 个工具的描述）。
而**文本拼接**方案有 **R1 可复现静默失败**（`[input]` 非末节时键落错节 → `has_action=false`）与 R2–R9 共 9 条风险。

→ **补丁面（按优先级）**：
1. **最优**：在引擎侧提供一个**能只更新某一节/某一组键**的写出口（例如
   `ProjectSettings::save_custom_section(const String &p_section, ...)` 或一个
   「读原文 → 只替换目标节文本 → 原子写回」的**引擎实现**，使**注释与其余文本逐字保留**）；
   **必须**由引擎自己序列化目标节（**不得**让上层做文本手术）。
2. **次优**：暴露 `_save_settings_text` 的**分节输出**（例如能取到某一节的序列化文本），由引擎保证格式；
   上层只做「按节替换」这一件**已被规范化**的事。
3. **保底**：若上面两条都不可行 → 明确**不做**，并把「整文件重写/注释丢失」保持为**已声明行为**
   （现状，5 个工具描述已记载），**不得**退回文本拼接。

**要求**：①`文件:行` 调研依据 + 为什么选这一条 + 代价；②**既有 175 条工具行为逐字节不变**
（`project_set_setting` 等**默认仍整文件重写**——避免改变既有语义；新能力**只在新路径上启用**）；
③**注释与其余文本逐字保留**的**字节级证据**（含 `[input]` **非末节**的反例、幂等、`--import` 与运行后不变、
并发写与 BOM/CRLF 的处置）；④**如果**要让 `editor_add_input_action` 用上新路径，
必须在报告里单列「行为变更」一节并说明**为什么这是安全的**（否则本批只提供 API、不改行为，由我另批切换）。

## 5. 门与纪律

第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；五道门 + 门⑥ 三段式 +
`--check-completeness`/`--added`（契约**条数不变**）；**构建严格串行**（mono 与 plain 皆然）；
回归 `mcp041/042/043` + `mcp010/019/027` + `mcp044/045/046` + `mcp050/051/052/053/054/056` 脚本，逐条归因；
**绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push；不抑制输出；`.ps1` 纯 ASCII；结论按 D86 标锚点。