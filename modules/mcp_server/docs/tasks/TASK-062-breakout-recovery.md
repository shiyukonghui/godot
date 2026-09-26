# TASK-062 — **回收第 2 轮试测产物**（落错目录）+ 生成缺失的汇总发现

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件。
> 报告 `docs/reports/REPORT-062-breakout-recovery.md`。返回决策者：**≤8 行总结 + 报告路径**。

## 0. 事实（决策者已核对）

第 2 轮（TASK-060，打砖块 C#）的 workflow **被取消**，我没拿到结构化返回；但**产物实际存在**，
只是**落错目录**：`F:\RustProjects\godot-mcp-pro\code\godot\docs\`（引擎仓根，**未跟踪**，445 个文件），
而非 `modules/mcp_server/docs/`。里面已有：
- `docs/reports/BREAKOUT-TEST-PLAN.md`、`BREAKOUT-DEV-LOG.md`、`BREAKOUT-OBSERVATIONS.md`；
- `docs/reports/evidence/task060/{c-obs,c1,c2,c3,c4,probe-cs2,probe-cs3,probe-gdscript,probe-paths,...}`。

**根因（我的错）**：TASK-060 写「产物一律写到 `docs/reports/`」——**相对路径**，而子代理 cwd 是引擎仓根。
→ 今后所有任务书**必须用绝对路径**（或明确写 `modules/mcp_server/docs/...`）。

## 1. 要做的事

1. **回收**：把根 `docs/reports/**` **整体搬进** `modules/mcp_server/docs/reports/**`（同名同结构；
   `docs/reports/evidence/task060` → `modules/mcp_server/docs/reports/evidence/task060`）；
   **修正被搬文件里的路径引用**（它们现在指向根 `docs/...`，改指新位置）；搬完**删除**空的根 `docs/`；
   给「搬前/搬后的文件计数与内容 sha256 对照」（证明**没有丢内容**）。
2. **诚实标注**：在这三份产物**头部**加一行状态说明（**append/前插**均可，别改原内容）：
   ①本轮 workflow **被取消**，产物为**中断时的快照**；②观察者使用**旧协议**（TASK-061 之前）——
   **观察在开发结束前停止**（`BREAKOUT-OBSERVATIONS.md` 的覆盖**不完整**）；③**不要**把快照当完整记录。
3. **补做 §D 汇总**（TASK-060 §D 从未产出）：**基于真实证据**写
   `modules/mcp_server/docs/reports/BREAKOUT-FINDINGS.md`：
   - **专答六条新能力判据**（§A）：**注释保全 / C# 真结论（invalid+编译器原文、ok、not_compiled）/ 批量父子 /
     批量挂脚本（含 keep_existing 跳过）/ `scope` 收窄 / 捕获 `changed:false`** ——
     逐条给「**通过 / 不通过 / 不可构造**」+ **证据路径 + sha256**（**以 `evidence/task060/**` 的原文为准，不要凭报告叙述**）；
   - **四张表**（异常 / 缺失工具 / 可合并 / 可优化）每条带证据；标出**不建议做**的；
   - **疑似缺陷**单列（最小复现 + 期望/实际 + 证据 sha256 + 严重度）；
   - **明确写清哪些结论受「观察不完整」影响**（不得含糊）。
4. **不得修改模块实现/契约**；本批只动 `docs/**` 与（必要时）`scripts/**` 的取证脚本。

## 2. 门与纪律

`git diff --stat -- modules/mcp_server/tools tests` **必须为空**（给证据）；契约不动；
**绝不占用/杀/重启 9877**；禁止 push；`.ps1` 纯 ASCII；结论按 D86 标锚点；
**证据文件若被 `.gitignore` 挡住（`*.log`）要 `git add -f`**（TASK-061 已登记该陷阱）。