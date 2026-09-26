# TASK-048 — 收尾三件：`mcp010` 不变式改派生 + `mcp014` 一行缺陷 + 补跑未跑的门批次

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件。报告 `docs/reports/REPORT-048-derived-invariants-and-battery.md`。
> 返回决策者的内容**只允许**是「≤8 行总结 + 报告路径」。

## 1. `mcp010` 的 4 条 TASK-010 期**硬编码不变式** → **改为派生**（不许只改数字）

`mcp010_b2_observation_evidence.ps1` 的 `scope`/`count` 相位仍硬编码：
union 48、split 17/23/8、编辑器端点 40、editor-only 17 / game-only 8 —— 现在实测 102/23、union 66 等，**必然红**。
→ 按 **`accept_m1.ps1` 的办法**（从 manifest/契约**推导**期望集合），使断言**随时间自动正确**；
若某条在历史上**有意**是快照，**在脚本头部显式标注为历史视角**并**移出 exit 判据**（不得让它持续红掩盖真回归）。
复跑并给退出码。

## 2. `mcp014_m3_evidence.ps1:183` 的一行缺陷

`Write-Utf8NoBom` 未定义（应为 `Write-McpUtf8NoBom`）→ 导致 `-Phase m3` 在 m06 后必然中止。
→ 修这一行，然后**完整复跑 `-Phase m3`**。mono 二进制若仍在且 `--version == HEAD`（自 M3 重建后**未改任何被编译文件**）
可直接复用；否则**串行重建 mono**（唯一允许的构建）并在报告里说明。

## 3. 补跑未跑的门批次与证据脚本（让闭合清单不留空）

串行跑 `scripts/mcp041_gates.ps1`、`mcp042_gates.ps1`、`mcp043_gates.ps1`、`mcp044_capture_evidence.ps1`、
`mcp045_pixel_compare_cost.ps1`、`mcp046_capture_encode_cost.ps1`（各给退出码 + 关键计数）；
把结果**追加**进 `docs/reports/MILESTONES-CLOSURE.md` §4（把「未跑」替换为真实结果；**跑不起来的仍写未跑并归因**）。

## 4. 门与纪律

第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；五道门 + 门⑥ 三段式；
本批**不改模块实现、不改契约**（只改 `scripts/**` 与 `docs/**`）；**绝不占用/杀/重启 9877**；端口 9888/9889；
禁止 push；构建串行、不抑制输出；`git diff --stat -- modules/mcp_server/tools tests` 必须为空（给证据）。