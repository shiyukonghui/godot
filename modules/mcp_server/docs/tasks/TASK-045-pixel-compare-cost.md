# TASK-045 — 捕获的**后续代价**优化：像素比对改用原始字节遍历

> 执行者须知：先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册），再读本文件。
> 报告写到 `docs/reports/REPORT-045-pixel-compare-cost.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 背景（实测代价，TASK-044 D4）

`--mcp-capture=every_call` 下：**响应路径**只多一次 framebuffer 拷贝（同调用服务端中位 0–1 ms → 7–8 ms），
但**应答之后**的 PNG 编码 + **全图像素比对**占住主线程 ~400 ms →
**背靠背**往返 18.5 ms → 453.6 ms（请求间有空隙时 30.7 ms，说明代价集中在读回来那一刻）。

引擎侧根因：`MCPTools::compare_screenshot_pixels`（`tools/tool_helpers.cpp`，由 TASK-044 从
`editor_testing_read.cpp` 提升而来）用 **`Image::get_pixel()` 逐像素**读，533 万像素就是 533 万次函数调用 +
多次格式转换；`Image` 已有 `get_data()` 可直接拿到原始缓冲。

## 1. 要做的事

1. **改用 `Image::get_data()` 的原始字节遍历**（**先读引擎源码确认**：`core/io/image.cpp` 的 `get_data()`、
   `get_format()`、以及各格式的行距/通道数语义，给出**文件:行**依据）。
2. **必须覆盖相机直接可比的情形**：两个 `Image` **格式与尺寸都相同**时走快路径；
   **格式不同**时先用 `Image::convert()` 归一化（或退回逐像素路径）——**说清你选了哪条并给理由**。
3. **行为必须逐位等价**：`threshold` 语义、每通道 `get_r8()` 比较、`MAX(dr,MAX(dg,db))`、两种差异色、
   `Math::snapped(…, 0.01)` 全部**不得**变；尺寸不一致时的**报错顺序**（先尺寸检查、后上限检查）也不得变。
4. **两个调用方都要复测**：`editor_analyze_screenshot_diff` 的 doctest 与线上证据**不变**；
   捕获的 `changed_pixels`/`total_pixels` 与旧实现**完全相同**（同一对 PNG 给同一数字：106800 / 5339554）。
5. **给前后实测数字**：同一像素比对在**优化前/后**的耗时（给出测量方法与分布，不要只给一个数）；
   并给 `every_call` 下**背靠背往返**的**新**数字（期望大幅下降；若没降，如实报）。
6. **门⑥**：本批若引入收窄点，逐条列「新增点 × 经过的闸门 × 证据」（§22.3b 规则 4）。

## 2. 门

- 第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD（**从 cmd 启动**）。
- 五道门 + 门⑥ 三段式；**门③/④ 必须刷新基线**（只增不减）。
- 回归：`mcp044` 的 62 条活证据 + `mcp043/042/041` 门批次 + `mcp038` 两脚本，逐条归因。

## 3. 报告

按手册 §4（含「引擎依据」列），写到 `docs/reports/REPORT-045-pixel-compare-cost.md`；另加：
「优化前后耗时实测与测量方法」「等价性证据（同一对图的数字一致 + 两个调用方证据不变）」
「新的背靠背往返数字」「结论锚点（D86）」。**返回值：≤15 行总结 + 报告路径。**