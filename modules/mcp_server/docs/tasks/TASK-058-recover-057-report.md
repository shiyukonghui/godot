# TASK-058 — **恢复 TASK-057 的报告**并补跑其缺项（实现已提交，报告缺失）

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件；**TASK-057 的任务书**是 `docs/tasks/TASK-057-mono-anchor-and-settings-publish.md`
> （**你要核实的就是它那四件事**）。报告写 `docs/reports/REPORT-057-mono-anchor-and-settings-publish.md`。
> 返回决策者的内容**只允许**是「≤10 行总结 + 报告路径」。

## 0. 已知事实（决策者独立核对过）

- TASK-057 的**实现提交已存在**：`96f631addb`（`mcp_server: TASK-057 three closures and engine patch 2 (ProjectSettings section publish)`）。
- **两个二进制的 `--version` 都自报 `96f631add` == 当前 HEAD**（plain 与 mono）→ 说明 mono 干净树重建**已做**。
- **`docs/reports/REPORT-057-*.md` 缺失** → 执行者未写完报告即中断；工作树干净（只剩 4 个既有未跟踪物）。

## 1. 你要做的

1. **先只读核实** `96f631addb` **到底改了什么**（`git show --stat` + 关键 diff），逐条对照 TASK-057 的四件事：
   ①**D-B1** mono 干净树重建 + 复跑到 `mcp052` 53/53 与 `mcp053` 73/73；
   ②**R-B2** 生成器版本**三处一致的机器断言**（含**失败的演示**：改一处 → exit 非 0 → 还原）；
   ③**R-B3** 回归电池**不再静默覆写**被跟踪证据（默认写 `%TEMP%` 或自动还原 + 打印清单），
     并给「重跑前后 `git status`/`git diff --stat` 为空」的证据；
   ④**引擎补丁 2** `ProjectSettings` **局部发布**：选了哪条面（最优/次优/保底）、`文件:行` 依据、
     **注释与其余文本逐字保留**的**字节级证据**（含 `[input]` **非末节**反例、幂等、`--import` 与游戏运行后不变、BOM/CRLF、并发）、
     以及**既有 175 条工具行为逐字节不变**（`project_set_setting` 等默认仍整文件重写）；
     若动了 `editor_add_input_action` 的行为 → **单列「行为变更」一节**并说明为什么安全
     （**若没动**，明确写「只提供 API，未切换行为」）。
2. **补跑缺的**：五道门 + 门⑥ 三段式 + `--check-completeness`/`--added`；
   `accept_m1` ×2（清单一致）；`mcp052`/`mcp053` 与 `mcp041/042/043`、`mcp010/019/027`、`mcp044/045/046`、`mcp050/051/054/056`
   按**受影响面**抽跑并**逐条归因**；**跑不起来的写明未跑并归因**（不得只报「全绿」）。
3. **若发现 TASK-057 有未完成/做错的部分**：**如实写进报告**（列出缺陷），**并做完**（除非它需要改规范 → 报我）。
4. **写报告** `docs/reports/REPORT-057-mono-anchor-and-settings-publish.md`：含上面 1–3 的真实输出、退出码、
   证据路径与 sha256、以及**结论锚点（D86）**。**报告提交之后**再 `build_local.cmd -Force` 复验
   `--version == 新 HEAD`（若只改了文档，说明「等价二进制」的理由）。

## 2. 门与纪律

**构建严格串行**（mono 与 plain 皆然）、**从 cmd 启动**、不抑制输出；**绝不占用/杀/重启 9877**；端口 9888/9889；
禁止 push；`.ps1` 纯 ASCII；**不得**修改 `DESIGN-DETAIL`（要改就报我）。