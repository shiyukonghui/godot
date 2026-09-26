# TASK-029 — 契约收口：`editor_get_test_report.clear` 的 `default` 与描述（走 override，重生成指纹）

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-029-clear-default-override.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 问题（TASK-028 上报，决策者裁决）

TASK-028 把 `editor_get_test_report` 的 `clear` 改成**显式 opt-in**（缺省/`false` = **纯读、不删**；
只有显式 `clear:true` 才清），因为桥接文件 `user://mcp_test_report.json` 是**共享**的，
**一次读取会删掉别的客户端未读的报告**（M4c 的 G-3）。
但**已注册的契约 `inputSchema` 仍写着** `"clear": {"default": true, ...}` → **契约与实现不一致**（契约在说谎）。

**决策者裁决：采用方案 A** ——
`default` 改为 **`false`**，并把**共享文件的破坏性**写进描述（让智能体知道「清」会影响别的客户端）。

## 1. 要做的事

1. 在 `scripts/gen_renamed_contract.py` 里加 **`SCHEMA_OVERRIDES["get_test_report"]`**（`mode: "replace"`）：
   - 理由（`reason`）必须**逐字引用被替换的成员**：`"default": true`（这是既有机制的要求）；
   - 新 schema：`clear` 的 `default` 为 `false`，其余成员（`type` 等）**逐字保留**，`required` 不变。
2. 若描述需要改（例如写明「缺省不清；显式 `true` 会删除**共享**桥接文件，影响其它客户端」），
   加 **`DESCRIPTION_OVERRIDES["get_test_report"]`**（**append** 或按既有机制；原文逐字保留在首）。
3. **重生成契约**并**更新全部指纹**（`_meta`、文档头部等），
   **不得**手改 `tools_list.renamed.json`；
4. 若 C++ 注册块由生成器产出，同步重生成；
5. `TOOL-NAMING.md` 若由映射渲染（本身未变）→ 用 `--check-only` **证明**无需重渲染（不要空口声称）。

## 2. 门

- 第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD。
- **门①** 两端点**逐字通过**（本工具所在组）；
- 五道门 + **门⑥**；**重跑 TASK-028 的证据脚本**（27/27）确认未回退。
- 契约 diff 自证：**只**动该工具的 `inputSchema.clear.default` + 描述 + `_meta` + override 记录，
  **其它 170 条一字未动**（给出结构化 diff 的证据）。

## 3. 行为回归（必须实测，不能只看契约）

1. **缺省调用**（不给 `clear`）→ **纯读**：报告完整返回、**桥接文件仍在**；
2. 两个客户端先后读取 → **两次响应体 sha256 相同**、文件仍在（非破坏性）；
3. **显式 `clear:true`** → 才清（`cleared` 列出真实范围），随后读取为**诚实空**（`no_results:true`，不伪造 `total`）；
4. **与契约一致**：`tools/list` 里该工具的 `inputSchema.clear.default` 就是 `false`（线上实测，不是读文件）。

## 4. 报告

按手册 §4，写到 `docs/reports/REPORT-029-clear-default-override.md`；另加：
「契约结构化 diff（只动目标字段 + `_meta`）」「override 的 `reason` 原文」「线上 `tools/list` 的实测字段」
「非破坏性双客户端证据」「门① 结果」。**返回值：≤15 行总结 + 报告路径。**