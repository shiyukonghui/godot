# TASK-056 — 收口新增工具验收的 D1/D2/D3 + 补跑 TASK-055 声明未跑的回归

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件。
> 证据：`docs/reports/REPORT-AUDIT-ADDED.md`（**verdict=fail**，D1 阻断 / D2 文档漂移 / D3 外观）、
> `docs/reports/REPORT-055-csharp-compile-verdict-patch.md`（**D-1：一批回归电池未跑**）。
> 报告 `docs/reports/REPORT-056-audit-added-d1-fix.md`。返回决策者的内容**只允许**是「≤8 行总结 + 报告路径」。

## 1. **D1（阻断，必修）**：`language_unavailable` **不得**发布 `"valid": false`

实测：`project_validate_scripts` 的 `category=language_unavailable` 条目**逐字发布了 `"valid": false`**
（`project_read_files.cpp:364` + `project_validate_scripts.cpp:168`；只有 `unverifiable` 走了 `null`）——
**违反 TASK-053 §2.1 与 GDR-25 的诚实性口径**，且与 TASK-054 的处理**不对称**。
→ 改为与 `unverifiable` 一致的**不声称**（`valid: null` + `category` + `reason`），
**单数与批量两个工具口径必须一致**；契约描述若需同步澄清 → `DESCRIPTION_OVERRIDES` append + 重生成 + 指纹 + 门① 逐字。
**证据**：①同一请求的响应逐字前后对照；②两个工具对该文件结论一致；③`count/valid_count/invalid_count/unavailable_count` 语义自洽。

## 2. **D2（文档漂移）**：`docs/tool-groups-added.json` 的 `source.entries` 生成器版本

仍写 `v1.15.0`，实际已 `1.16.0`（TASK-054 未同步）→ 更新（**只改该字段**），并证明其余字段未变。

## 3. **D3（外观）**：`project_build_csharp` 的 `command` 字段分隔符混用

实测 `"C:\Program Files\dotnet\/dotnet.exe"`（反斜杠 + 斜杠混用，执行本身成功）→
**规范化为一致分隔符**（并说明用哪种、为什么），**不得**改变真实执行路径与 `exit_code`。

## 4. **补跑 TASK-055 声明未跑的回归**（不得再留空）

`accept_m1.ps1` ×2（PASS 清单一致）+ `mcp041/042/043_gates.ps1` + `mcp010/019/027` + `mcp044/045/046` +
`mcp050/051/052` 证据脚本，**逐条归因**；跑不起来的**仍写未跑并归因**。

## 5. 门与纪律

第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；五道门 + 门⑥ 三段式 +
`--check-completeness`/`--added`（契约**条数不变**）；**mono 若需要则串行**；
**绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push；不抑制输出；`.ps1` 纯 ASCII；结论按 D86 标锚点。