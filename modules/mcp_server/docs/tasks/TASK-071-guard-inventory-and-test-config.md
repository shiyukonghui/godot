# TASK-071 — A：采纳守卫的**文件级清单**；B：修 **F-1** 测试配置独立性 + 声明门③口径

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件。
> 来源：`REPORT-070-audit-unconfirmed-closure.md` §⑤（守卫盲区 + 原型 + 成本）与 §④（F-1）。
> 报告（**绝对路径**）`...\modules\mcp_server\docs\reports\REPORT-071-guard-inventory-and-test-config.md`。契约 **176**（条数不变）。

## A. 证据守卫改为**文件级清单**（消除 TASK-070 §⑤ 构造出的盲区）

现状：`Get-McpEvidenceState` 只产出 `Modified`（tracked）与 `Untracked`（**目录级**），
`Restore-McpEvidence` 只遍历「**新出现的** modified/untracked」→ **「快照前已存在、之后被别处删除」完全看不见**，
且**电池裁决也会瞎**（真实静默删除后仍打印 `tracked_evidence_restored`）。

**要求**：
1. 用 `git status --porcelain -uall` 的**文件级清单**（`path -> length:LastWriteTimeUtc.Ticks`）替换目录级 Untracked；
   新增 manifest 行类型：**MISSING-UNTRACKED / APPEARED-UNTRACKED / CHANGED-UNTRACKED**（命名可微调，但语义必须这三种）。
2. **可选** `-HashUntracked`（含 sha256；默认关，理由与成本写进报告）。
3. **判定要跟上**：declared-leftover **必须**计入这三类（即**看不见的删除不再可能被报成 restored**）。
4. **证据**：①**重跑 TASK-070 §⑤ 的两个盲区场景** → 现在**必须被点名**（A 删除、B 目录内改写+新建）；
   ②成本实测（本仓未跟踪文件数，不哈希/哈希两种）；③**不得**把「能发现」说成「能还原」——**明确声明**只能发现；
   ④`git status --porcelain -uall` 前后**逐字节不变**（探针不留痕）。

## B. **F-1**：测试的**配置独立性**（`real_t` 宽度）

现状：`precision=double` 二进制上同一套用例 **338 过 / 7 红**（TASK-022 D-4 ×2、TASK-022 one-gate、TASK-025 E-3、
TASK-028 G-1 ×2、TASK-033），7 条**全是**「标量 `real_t` 成员 / `Vector2/Rect2/Vector4/Quaternion` 分量拒绝 `1e300`」
这类**单精度期望**；失败输出里 **0 条断言涉及 FLOAT32**、20 条涉及 REAL_T。
**正确写法已存在**：`tests/test_mcp_server.h:15043` 的 `if (sizeof(real_t) == 4)`。

**要求**：
1. 按该写法给这 7 条**加上配置条件**（**不是删测试、不是放宽断言**）：单精度下**原断言逐字保留**；
   双精度下改为**等价且更有意义**的断言（例如「`real_t` 能表示 `1e300` 时**应当接受**」或改用 **FLOAT32 槽**
   （`Color` 分量 / `PackedFloat32Array` 元素）来测「32 位收窄」——**你判断哪种更贴命题**并说明）。
2. **证据**：①单精度：**用例数与断言数与 TASK-070 基线一致**（345/23971，**不得减少**）；
   ②双精度：**345 全过**（或明确说明为何仍小于 345 并给依据）；③红相位（改前双精度 7 红）**当场保存**。
3. **声明口径**：在报告里明确写下「**门③（`[MCPServer]*`）是单精度门**」这一已声明事实，
   以及**双精度当前是否被任何门覆盖**（若无 → 明确说「未纳入门」，不要含糊）。

## 门与纪律

第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；五道门 + 门⑥ 三段式 +
`--check-completeness/--added/--generator-version` + `accept_m1` ×2（清单一致）；回归相关脚本**逐条归因**；
**双精度要用时串行构建**（`scripts/mcp070_build_double.cmd` 可复用，14m51s，**START-END 不得重叠**）；
**绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push；`.ps1` 纯 ASCII；**红相位输出当场保存**；
结论按 D86 标锚点；**产物一律绝对路径**。