# TASK-068 — 收口登记项：陈旧期望派生 + 两处描述澄清（契约 sha 只移动一次）+ 报告勘误

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件。
> 来源：`REPORT-067-script-listing-and-editor-save.md`（§⑦ 登记项）、`DECISIONS.md` D125 裁决 (a)–(d)。
> 报告（**绝对路径**）`...\modules\mcp_server\docs\reports\REPORT-068-registered-items.md`。契约 **176**（本批**条数不变**）。

## 1. `check_rename_map.py` 仍硬编码 **171**（既有陈旧期望）

契约已是 176（171 移植 + 5 新增）。**要求**：与 TASK-064 同法——**改为派生**（`171 + _meta.added_count`，
或读第六份清单），**`171` 本身保留为被检查的字面量**；**不得放松断言**；给**修复前后的退出码对照**与
**反向探针**（同一输入上旧表达式为假、新表达式为真）。并**顺手普查** `scripts/**` 是否还有同类硬编码条数（`171/173/175/176/152/72/153`），逐条列出处理。

## 2. 两处**描述澄清**（**本批一次性移动契约 sha**，故合并做）

1. **`.godot` 生成脚本会被列出**（TASK-067 的副作用）：**裁决 = 不收窄 walk**（收窄会撞钉住的
   `.hiddendir/secret.gd` 断言，且列出生成文件是**诚实**的）。→ 在 `project_list_scripts` 的**描述**里
   **如实声明**：会包含 `.godot` 下的生成脚本（例如 Mono 的 `res://.godot/mono/temp/obj/**`），调用方应自行过滤。
2. **`waited_seconds` 入/出参命名**（R4 §8.2 登记）：先**核实事实**（是同一个名字既做入参又做出参，还是两个字段语义不同？给 `文件:行` 与两种读法的线上证据），
   再**最小澄清**：①若确实同名异义 → 出参改名（或入参改名），**保留旧名作为可接受别名**（避免破坏既有调用方）；
   ②若只是文档含混 → **只改描述**。**必须给「旧调用仍可用」的证据**。

两处都走 `DESCRIPTION_OVERRIDES`（`reason` 逐字引用被替换成员）+ 生成器递增 + **重生成** + **全部指纹**
（含 `tool-groups-added.json` 的 `source.generator_version`）+ 门① 逐字；**契约条数保持 176**。

## 3. 报告勘误（**append-only，不改历史**）

`BREAKOUT-FINDINGS-R4.md` §8.3 的 `.dll` 字节数陈旧（19968 → 实测 20992）→ 以**追加勘误**方式修正，
标注日期、依据（谁在哪个提交上实测）、以及**为什么不改原文**。

## 4. 门与纪律

第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；五道门 + 门⑥ 三段式 +
`--check-completeness/--added/--generator-version`；`accept_m1` ×2（清单一致）；回归 `mcp041…067` 相关脚本**逐条归因**；
**mono 与 plain 都需时严格串行**；**绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push；`.ps1` 纯 ASCII；
**红相位输出当场保存**；结论按 D86 标锚点；**产物一律绝对路径**。