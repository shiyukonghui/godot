# TASK-AUDIT-ENGINE — 独立验收：**三个引擎补丁 + 5 个新增工具 + 门完整性五条纪律**

> 你是**独立验收方**，未参与任何实现；**不得采信任何 `REPORT-*` 与决策者结论**——只看需求/详细设计/代码/你自己跑出的证据。
> 报告（**绝对路径**）`...\modules\mcp_server\docs\reports\REPORT-AUDIT-ENGINE.md`。返回决策者：**≤12 行 + 报告路径 + verdict**。
> 契约应为 **176**（171 移植 + 5 新增）；线上 9888=153 / 9889=72。**绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push。

## 0. 开工

`scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ 校验 `--version == HEAD`；mono 若需要则**串行**重建。
证据用 `curl.exe -s -o` + sha256；`.ps1` 纯 ASCII；临时件放 `%TEMP%\audit-engine\`；**不得修改仓库文件**（实验后逐字节还原并留证）。

## 1. **三个引擎补丁的「非侵入性」**（重点：**有没有改变既有行为**）

补丁清单（自己从 `git log`/`git diff` 找依据，别信我给的摘要）：
① `CSharpScript::is_source_newer_than_assembly()`（新增只读访问器）；② `ProjectSettings::save_custom_section()` / `update_settings_section_text()`；
③ `ProjectSettings::save_preserving_text()`（编辑器自身的保存）。
**要求**：
1. **逐条核实「只增不改」**：`git diff` 里**只有新增符号**吗？`reload()` / `save()` / `save_custom()` / `save_custom_section()` 的**签名与返回值**是否有改动？
   列出**每一处**被修改的既有行（若无，给出证明方法）。
2. **行为逐字节对照**（自己造）：对 `save()`（整文件重写）在**同一工程**上跑前后对照（例如用未走新 API 的路径触发），
   证明「旧路径行为不变」；对 `save_preserving_text()` 证明「只动目标节、注释/键序/BOM/CRLF 逐字保留」。
3. **调用点核查**：编辑器里**其余 27 个** `save()` 调用点是否未动；新 API 只在 `editor_node.cpp:1071`（或实际位置）被用。
4. **反向探测**：构造一个**必须整文件重写**的场景，确认它**仍然**整文件重写（新 API 不是偷偷全局替换）。

## 2. **5 个新增工具是否真的没绕过收窄闸门**（GDR-28 第 5 条）

工具：`project_build_csharp` / `project_write_text_file` / `project_validate_scripts` / `editor_set_node_script_batch` /
`editor_set_node_property_updates`。
**要求**：①对**每一个**做「**拒绝面**」测试：把**已知会被既有工具拒绝**的输入喂给新工具
（例如 `glow_levels/1` 这类**非标识符属性名**、未知属性、越界路径、`project.godot` 写入、`.tscn/.gd/.cs` 覆盖），
**必须得到与既有工具同族的拒绝**（`-32602`/`-32001` + `data.suggestion`），**不得**悄悄成功；
②`editor_set_node_property_updates` 的 `stop_on_error` 两种语义**真的成立**（含回滚后**读回**证明）；
③**代码腿**核对：新工具的写入是否都经过同一道 `ValueSlot` 闸门（给 `文件:行`）；
④**契约对等**：从**实时 `tools/list`**解析（**禁止文本包含判断**）核实并集 == 176、逐条 `name/description/inputSchema` 逐字、
`scope` 双向零泄漏、跨端点 `-32601`。

## 3. **门完整性五条纪律是否真的生效**（**要尝试绕过**）

五条：恒真断言（`check_tautologies.py`）/ 假等待（`mcp_watch_run.ps1`）/ 静默覆写证据（证据守卫）/
删证据（电池路径白名单）/ **内红必须非零**（`check_exit_propagation.py`）。
**要求**：①**各自跑一遍**（含 `accept_m1.ps1` 的 `case0_repo_exit_code_propagation`）证实它们**在门里真的被调用**；
②**尝试绕过**（每条至少一个反例）：植入一条恒真断言 → 必须被点名；植入「打印 FAIL 但不设退出码」→ 必须被点名；
让电池**删**一个未声明文件 → 必须被拦；让 watcher 在**开发未结束**时收工 → `stop_reason` 必须**不等于** `marker`；
③**给出绕过失败的证据**（这是本次验收最重要的产物）；④若某条**能绕过** → **明确报告**（这是阻塞缺陷）。

## 4. 收尾

`verdict`（分类：补丁非侵入性 / 新工具拒绝面 / 契约对等 / 门完整性五条 / 工程门 / 端口），逐项**你自己的证据**、
`defects`、`unconfirmed`、`risks`。**不得**修改仓库任何文件（实验逐字节还原）；
收尾核实 `git status --short` 干净、9877 未占用、9888/9889 已释放、无孤儿进程。