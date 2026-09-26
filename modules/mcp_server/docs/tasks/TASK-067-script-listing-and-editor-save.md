# TASK-067 — 修 `project_list_scripts` 的 `.cs` 失明 + 查清并处理「编辑器自身保存吃注释」

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件。
> 依据：`REPORT-066-csharp-breakout.md`（F-066-1…F-066-7）、`BREAKOUT-FINDINGS-R4.md`（B5/B6 边界与纠错）。
> 报告（**绝对路径**）`...\modules\mcp_server\docs\reports\REPORT-067-script-listing-and-editor-save.md`。契约 **176**。

## 1. **`project_list_scripts` 对 `.cs` 失明**（先独立复核，再修）

第 4 轮实测：C# 工程里该工具**列不出 `.cs`**（一条调用即可复现）。
**要求**：①**先独立复核**（给复现的请求/响应与 sha256，别只信上游报告）；②查引擎侧「脚本枚举」的真实来源
（`ResourceLoader`/`ScriptServer`/`EditorFileSystem`/扩展名过滤，给 `文件:行`）；
③修（或**如实声明为何不可为**）；④**判据**：GDScript 与 C# 混合工程里，两种脚本**都被列出**且字段形状一致；
⑤**契约条数不变**（若只改行为/描述则走 override；不要新增工具）。

## 2. **编辑器自身保存吃注释**（第 4 轮实测：**窗口化编辑器启动**会重写 `project.godot` 并丢掉手写注释）

**要求**：
1. **先定根因**（`文件:行`）：是 `editor/settings/project_settingseditor.cpp` 的定时器/保存、还是 `ProjectSettings::save_custom`、
   还是 `--import`/启动期某个保存路径？给出**最小复现**（窗口化启动前/后 `project.godot` 的 sha 与注释行数对照）。
2. **区分两条路径**：**工具写入**（已按节发布）vs **编辑器自身写入**（本条的嫌疑）——报告中必须分开陈述。
3. **若确认属引擎自身 → 打第三个补丁**（纪律同 D112：最小 / 朝上游形状 / 附为什么 / 可被门覆盖）：
   让编辑器自身的保存**也走按节发布**（复用补丁 2 的 `save_custom_section`/`update_settings_section_text` 能力），
   使**启动与保存都不再吃注释**；证据：带注释的 `project.godot` 经窗口化启动**前后注释逐字保留**（含 `[input]` 非末节）。
4. **若根因不在我们可控范围**（例如引擎设计如此）→ **如实声明**并给可复现证据 + 建议。

## 3. 其余发现（按证据强度择要）

从 `REPORT-066-csharp-breakout.md` 的 7 条里挑**产品侧且证据强**的修（例如 `waited_seconds` 回显名、dll 字节数陈旧之类
若属工具/文档缺陷则修；属试测产物缺陷则只登记）。**逐条说明修/不修及理由**。

## 4. 门与纪律

第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；五道门 + 门⑥ 三段式 +
`--check-completeness/--added/--generator-version`；`accept_m1` ×2（清单一致）；回归 `mcp041…066` 相关脚本**逐条归因**；
**mono 与 plain 都需时严格串行**；**绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push；`.ps1` 纯 ASCII；
**红相位输出当场保存**；结论按 D86 标锚点；**产物一律绝对路径**。