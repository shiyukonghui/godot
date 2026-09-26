# TASK-046 — 捕获的**编码代价**：快速压缩 + 可选缩放（把背靠背 ~380 ms 压下来）

> 执行者须知：先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册），再读本文件。
> 报告写到 `docs/reports/REPORT-046-capture-encode-cost.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 背景（实测归因，TASK-045）

`--mcp-capture=every_call` 的**应答后**代价已被拆开（TASK-045 实测）：
**像素比对 ~89 ms → 现在 ~14 ms**，**两张 2978×1793 PNG 编码 ~356 ms**（各 ~177 ms）→
背靠背往返仍 **377.6/386.6 ms**（off 是 18.5 ms）。**主因是编码**，本批处理它。

## 1. 要做的事（两条杠杆，都走**旁路**、默认行为不变、零契约变更）

1. **快速压缩**：引擎的 PNG 写入器已有 `p_fast` 形参（`MCPTools::screenshot_png_writer`；
   引擎侧 `image_to_png(..., p_fast)` → `PNG_IMAGE_FLAG_FAST`）。
   → **捕获落盘走 `p_fast=true`**（诊断产物，体积换速度**可接受**；写出体积的**变化要如实报**）。
   **注意**：`editor_capture_screenshot` / `running_game_capture_screenshot` 的**默认行为不得变**
   （它们是既有工具，改压缩级别会改变用户拿到的字节）→ 只在**捕获旁路**里用 fast。
2. **可选缩放**：新增 `--mcp-capture-scale=1|2|4`（**默认 1 = 不缩放**，走旁路、不进契约）。
   `running_game_capture_frames` 的 `half_resolution` 是先例。
   **关键一致性要求**：缩放必须发生在**比对之前**（即**比对与落盘用同一张图**），
   并在日志行里记 `scale`；这样 `changed_pixel_ratio` 与**文件**永远自洽
   （**否则**日志数字与拿文件去调 `editor_analyze_screenshot_diff` 得到的数字会**对不上**——那是陷阱，不允许）。
   `scale=1` 时行为必须与 TASK-045 **逐字节相同**。
3. **实测前后**：给「只判 changed」「含差异图」「两张 PNG 编码」三段耗时（**方法+分布**，不只一个数），
   以及 `every_call` 下**新的背靠背往返**（scale=1 与 scale=2 各给）；**没降就如实报**。
4. **等价性**：`scale=1` 时 TASK-044/045 的全部证据**不变**
   （同对 PNG 仍 `106800/5339554`；两个调用方的 payload sha 不变；`every_call` 与 `off` 的**响应**仍逐字节相同）。
5. 若你判断「把编码/比对挪到**非主线程**」更根本：**先别做**，在报告里给**可行性评估**（引擎线程模型/资源读回限制/
   与 GDR-20 延迟通道的关系）与代价估计，**报我裁决**。

## 2. 门

- 第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD（**从 cmd 启动**）。
- 五道门 + 门⑥ 三段式（**新收窄点逐条列**，§22.3b 规则 4）。
- 回归：`mcp045`/`mcp044` 证据脚本 + `mcp043/042/041` 门批次 + `mcp038` 两脚本，逐条归因。

## 3. 报告

按手册 §4（含「引擎依据」列），写到 `docs/reports/REPORT-046-capture-encode-cost.md`；另加：
「fast 压缩的体积/耗时前后对照」「scale 的一致性证据（日志数字 == 拿文件调 diff 的数字）」
「新的背靠背数字（scale=1/2）」「非主线程可行性评估」「结论锚点（D86）」。
**返回值：≤15 行总结 + 报告路径。**