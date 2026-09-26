# TASK-054 — D 档 + 一条引擎级诚实性：O-11/O-12 取证修复 + **C# 校验不得说谎**（D-053-3）

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件；规范：`DESIGN-DETAIL` **§24/GDR-26**、**§26/GDR-28 第 13 条**。
> 证据来源：`docs/reports/REPORT-AUDIT-RACING-BACKLOG.md`（O-11/O-12 已确认）、`REPORT-053-added-tools-2.md`（D-053-3）。
> 报告 `docs/reports/REPORT-054-forensics-and-csharp-validity.md`。返回决策者的内容**只允许**是「≤10 行总结 + 报告路径」。

## 1. **C# 校验诚实化（D-053-3，最高优先）**

实测：`CSharpScript::reload()` **恒返回 OK**（`modules/mono/csharp_script.cpp:2593-2620`）→
**mono 构建里语法错误的 `.cs` 也报 `valid:true`**（`project_validate_script`、`project_validate_scripts` 都受影响）。

**要求（二选一，**先读引擎源码再定**，给 `文件:行` 依据）**：
1. **找到真能区分的信号**（例如构建产物/诊断状态/`ScriptServer` 侧的错误记录/`get_script_method_list` 等，
   **以引擎为准**）→ 用它得出 `valid` 真值，并给「语法错误的 `.cs` → `valid:false`」的线上证据；
2. **找不到就下调声明**：**不得**把「引擎没报错」当成「有效」→ 分类为 **`unverifiable`**（或等价），
   带 `reason` + 引擎依据（`文件:行` + 引擎行为描述），**单数与批量两个工具口径必须一致**；
   契约描述同步澄清（`DESCRIPTION_OVERRIDES` append + 重生成 + 指纹 + 门① 逐字）。

**无论选哪条**，都要给：①mono 构建下「语法错误 `.cs`」与「合法 `.cs`」两条线上证据（**响应逐字**）；
②非 mono 构建下**语言不可用**仍走 `-32000`（TASK-050 口径不变）；③两个工具结论**一致**。

## 2. **O-12**：追踪要有**代次标记**（一行级）

实测：`trace` 被 3 个不同编辑器进程**纯追加**，出现 **3 个 `seq==1`** 且**无任何代次标记** → 事后无法切分。
→ 在每个进程**打开追踪文件时**写**一行** `trace_opened`（含 `pid`、启动时刻、`--mcp-port`、构建 `--version`、
   `role=editor|game`），**不占请求 `seq`**；并**更新** `analyze_mcp_trace.py` 以**按该行切段**（跨运行不再拼接）。
**不得**改变既有请求行的字段与含义。

## 3. **O-11**：分析器三处取证修复（**具体以 `REPORT-AUDIT-RACING-BACKLOG` §2.4 的原文为准**，逐条给前后对照）

① **摩擦窗口**：把「连续失败后成功」的判定改成**同一工具 + 同一连接 + 时间/序号窗口**内，
   **排除**「两次调用之间发生了别的工具调用」的伪摩擦；② **可合并 n-gram** 不得跨**连接**与**代次**混统计；
  ③ **单工具占比 / 超大响应**的判据要**排除捕获事件行**（`event:"capture"`）与 `tools/list`，
   否则诊断旁路会污染自己的统计。三条都要给**修复前后的同一份追踪上的对照输出**。

## 4. 门与纪律

第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；五道门 + 门⑥ 三段式
+ `--check-completeness`/`--added`（**契约条数不变**：本批不新增条目；若描述需改则走 override）；
回归 `mcp041/042/043` + `mcp010/019/027` + `mcp044/045/046` + `mcp050/051/052/053` 证据脚本，逐条归因；
**绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push；构建串行（mono 若需要也串行）、不抑制输出；
`.ps1` 纯 ASCII；**不可构造项显式声明**；结论按 D86 标锚点。