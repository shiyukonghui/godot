# TASK-AUDIT-M4e — 第五次独立验收：M4 收口（D1–D6 闭合）+ 顺手性 + **两条报告之间的矛盾必须解决**

> 你是**独立验收方**，未参与任何实现；**不得采信**任何 `REPORT-*`（含实现报告）与决策者结论。
> 只依据规范、代码与你**自己可复现**的证据。
> 报告写到 `docs/reports/REPORT-AUDIT-M4e.md`；返回值**只允许**是「≤15 行总结 + 报告路径 + verdict」。

## 0. 基准与开工

1. 权威依据：`docs/tools_list.renamed.json`（171 条）、`docs/tool-rename-map.json`、`docs/tool-groups*.json`、
   `docs/DESIGN-DETAIL.md`（**§17–§23 / GDR-16..GDR-25**，含 **§22.3/§22.3b**、**§23.1–§23.5**）、
   `docs/tasks/PLAYBOOK-group-port.md`（**门①–门⑥ 三段式**、§6、§7）、`F:\moonbit-hof-rs\DECISIONS.md`（D45–D85）。
2. 开工第一步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD。
3. 历史验收原文（**仅供了解历史，不得采信**）：`REPORT-AUDIT-M4{,b,c,d}.md`。

## 1. 必须核实

### A. 前四轮缺陷的**闭合**（逐条自己重造反例）
- **D1**：`project_set_node_property_across_scenes` 对**活动编辑场景**必须**真的写进去**：
  自己跑端到端链 —— 写活动场景 → **另一个工具**读回**新值** → `editor_save_scene` → **文件里含新值**；
  并核实 `mode`/`written`/`persisted` **语义表与实况一致**、**不存在「成功+未写入」组合**；
  多场景混合（活动 + 关闭）时关闭者**真落盘**；零命中时消息**不得**出现 `Applied`。
- **D2**：门⑥ **三段式**（`check_narrowing_points.py` + `--coverage` + `mcp031_gate6_coverage_probes.ps1`）
  自己跑；**自己再造** M4d 的五个探针（隐式 `const real_t x = 1.0e300;`、`static_cast<float>`、`::Color(`、
  `Vector3{...}`、跨行构造）→ 每个都必须让门**失败**；**再证明**只加空行/位移**不假红**；
  **实验后必须逐字节还原并证明 `git status` 干净**。**并自己找**新的可绕过拼写（若找到，报缺陷）。
- **D3**：`editor_get_node_properties` 不带 `properties` 时**不得**出现分组/类别标签；
  **用大小写不敏感解析器**（PowerShell `ConvertFrom-Json`）解析**整包**必须成功；
  自己核对键集合与引擎真值（`PROPERTY_USAGE_GROUP/SUBGROUP/CATEGORY`）；`running_game_*` 同族一并查。
- **D4**：**未知参数名**必须 `-32602` + 点名 + `data.suggestion`；**immediate 与 deferred 两条入口都要测**；
  并核实「已声明但工具不兑现的参数」**不**被误拒（例如需要 mono 的那类）。
- **D5**：零命中措辞（见 D1）。
- **D6**：游戏侧路径描述与**实际返回形态**一致（自己抓 `tools/list` 描述与响应比对），
  且 `path` 原样喂回 `node_path` **成功**。

### B. **两条报告之间的矛盾（必查，必须给出裁决级结论）**
`REPORT-032` 声称「**TASK-024b 记录的 `Vector4i`/`Rect2i` 写侧分量表缺口（`vector_component_hint` 返回空串）仍未修**」；
而 `REPORT-025` 声称「**已补齐 `Vector4i`/`Rect2`/`Rect2i` 且 19 项 × 两端点全部往返通过**」，
M4d 也声称验过 12+4 项往返。**请自己判定**：
1. `vector_component_hint`（或同类分发表）对 `Vector4i`/`Rect2i`/`Rect2` **到底返回什么**（源码 + 实测）；
2. **线上**把 `Vector4i`/`Rect2i`/`Rect2` 的值**读回→原样写回→再读**是否**真的成功**（两端点）；
3. 若**两条都真**，说明存在**两套并行的分发表**（一套在用、一套陈旧）→ 这是**缺陷**（说明为何能让两套并存）；
4. 给出结论：**哪个说法成立**、**缺陷归属**、**是否需要修**。

### C. 契约与 override 纪律
**13→14 条 override**（自己数并核对 `_meta.overrides`）；**自己**用生成器把契约重生成到临时文件与跟踪文件**逐字节比对**
（证明**无手改**）；**自己**做结构化 diff 证明除 override 与指纹字段外**没有别的改动**。

### D. 顺手性与行为（抽样复核，不必全量重做）
`E-10` 端口注入（自己抓子进程 cmdline + 从响应端口跑一个游戏侧工具）、`§23.4` 双向闭合（抽 ≥8 项）、
`§23.5` `OBJECT`（`null`/`{}`/同形对象三类）、`E-9` 截断、`E-6` 日志来源、`E-2` 两进程路径一致、
`G-1` 子属性路径、`G-3` `clear` 非破坏性；**自己重跑 ≥1 条零字符串手术链**并逐步确认调用方字符串处理为 0。

### E. 五形态静默错值（对抗抽样 ≥10 例）+ 延迟/事务/安全（抽样）

### F. 门与端口
六道门自己跑（门①按 ≥3 组、门⑤ ×2 且 PASS 清单一致、门⑥ 三段式）；**9877 全程 PID 36392**、
测试只用 9888/9889（另开端口收尾释放）、无孤儿、**不得** git 写操作、**不得**修改被跟踪文件。

## 2. 硬性约束

不得修改任何文件（临时实验须**逐字节还原并留证**）；临时文件 `%TEMP%\audit-m4e\`；不得安装依赖；
证据 `curl.exe -s -o` + sha256、请求体 `ConvertTo-Json`（禁止 `Out-File`/管道承载响应体）；
不抑制 scons 输出；不并发跑 scons；**`.ps1` 一律纯 ASCII**。

## 3. 报告

`verdict`（分类：D1–D6 闭合 / **报告矛盾裁决** / 契约与 override / 顺手性 / 静态错值 / 门与端口）、
逐项结论与**你自己跑出的证据**、`defects`、`unconfirmed`、`risks`、`next_step_recommendation`。
**返回值：≤15 行 + 报告路径 + verdict。**