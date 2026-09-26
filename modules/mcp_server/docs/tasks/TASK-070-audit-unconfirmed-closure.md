# TASK-070 — 关闭 TASK-AUDIT-ENGINE 的 5 条**未确认**（含窗口化实测补丁 3）

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件。
> 来源：`REPORT-AUDIT-ENGINE.md` 的 `unconfirmed` 5 条。报告（**绝对路径**）
> `...\modules\mcp_server\docs\reports\REPORT-070-audit-unconfirmed-closure.md`。契约 **176**（本批**条数不变**）。

## 逐条关闭（每条给**新证据**，不得复述上游）

1. **mono/C# 成功腿**：串行重建 mono 到 HEAD（校验 `--version == HEAD`），在 **mono 构建**上实测
   `project_build_csharp` 的**成功腿**（真构建 exit 0 + 产物 sha256）与**能力缺失腿**（非 mono → `-32000` + 建议）；
   并给 C# 三态（`ok` / `invalid`+编译器原文 / `not_compiled`）在 **mono 构建**上的实测。
2. **窗口化 `save_preserving_text()`（补丁 3）实测**：**真的开一次窗口化编辑器**（`--mcp-port=9888`），
   对**带 ≥4 条手写注释**且 **`[input]` 非末节**的 `project.godot`，比对**开窗前 / 开窗后**：
   ①注释**逐字保留**（含 `[input]` 里那条仍在 `[input]` 内）；②`sha256` 与逐行 diff；③**幂等**（再开一次）；
   ④**对照**：`--import` 与 `--headless` 路径不变；⑤**反向**：非 `!cmdline_mode` 之外的既有 `save()` 调用点行为不变。
3. **`mcp059_gates.ps1` 与 `mcp056_regression_battery.ps1` 整脚本重跑**（不是 grep 行号 + 单跑被调命令）：
   给完整退出码与步骤清单；**若电池自身仍会因「工作树须干净」非零**，必须证明那是**自检**而非回归。
4. **双精度构建**：若本机能构建 `precision=double`，实测 `ValueSlot::FLOAT32` 的判定；**不能构建就如实声明**并给理由
   （构建时长/依赖/是否值得），**不得**假装验过。
5. **证据守卫的边界**（只约束自身还原函数）：构造一个**绕过守卫在别处删文件**的场景，
   **证明该纪律确实看不到它**（即**承认识别盲区**），并给出**建议**（如何把守卫扩到「全局未跟踪文件快照」）。
   **至少**：给出一条低成本改进或明确说明为何不做。

## 门与纪律

第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；五道门 + 门⑥ 三段式 +
`--check-completeness/--added/--generator-version` + `accept_m1` ×2（清单一致）；回归相关脚本**逐条归因**；
**mono 与 plain 都需时严格串行**；**绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push；`.ps1` 纯 ASCII；
**红相位输出当场保存**；结论按 D86 标锚点；**产物一律绝对路径**。