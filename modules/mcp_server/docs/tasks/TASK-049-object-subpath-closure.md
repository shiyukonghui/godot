# TASK-049 — 真缺陷 `mcp027` **D8**：OBJECT/数组**子路径**写侧不接受读侧产出的形状

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件；规范见 `DESIGN-DETAIL` **§23.4/§23.5（读回↔写回闭合、OBJECT 形状）**。
> 报告 `docs/reports/REPORT-049-object-subpath-closure.md`。返回决策者的内容**只允许**是「≤8 行总结 + 报告路径」。

## 0. 缺陷（预先存在，TASK-047 复现）

`mcp027_object_shape_and_paths_evidence.ps1` 的 **`D8_whole_resource_bag_round_trips`** 失败：
写 `glow_levels/1`（**子路径**）→ `-32602 "Property name 'glow_levels/1' is not a settable property name"`。
这与 **GDR-25「读到的值必须能原样写回」**直接冲突：**读侧产出子路径，写侧却不接受它**。

## 1. 要求

1. **先复现并定根因**：给出**最小复现**（可直接粘贴的请求）+ 源码行（写侧判定该名字「不是可设置属性」的位置），
   并**说清读侧到底产出什么形状**（`glow_levels/1`？`{"glow_levels":[..]}`？两者都有？）——**以引擎为准**：
   `Object::set_indexed` / `get_indexed`（`core/object/object.cpp`）、以及资源本身的属性语义（例如 `Environment.glow_levels`
   是**属性名带 `/N`** 还是**数组属性**）→ 给 `文件:行` 依据。
2. **红先行**：先写会失败的最小测试（断言「读侧产出的形状能被写侧接受，且写后**再读**等价」），确认它因缺行为而失败；
   再实现让它通过。
3. **修法二选一，说明理由**（不得静默容忍）：
   (a) 写侧**接受** `name/index` 形式（按引擎 `set_indexed` 语义）；或
   (b) 读侧**改为产出**写侧已接受的形状（数组/对象），**并**在写侧接受整数组替换。
   **不得**只放宽错误检查而不保证「写后再读等价」——那会重新制造「报成功但没写进去」。
4. **同类排查**：**扫遍**所有读写工具，找出**其它**「读侧能产出、写侧不接受」的名字形状
   （`/`、`.`、`[i]`、数组下标、`:` 等）→ 逐条列表 + 各自处置（本批至少覆盖**与 D8 同族**的）；
   并给出**机器可跑的回归**（读→原样写→再读三层等价，§23.4）。
5. **契约不得变**（`tools_list.renamed.json` sha 不变）；若你判断必须改描述才诚实，**停下来报我**。

## 2. 门与纪律

第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；五道门 + 门⑥ 三段式
（新收窄点逐条列，§22.3b 规则 4）；回归 `mcp027` 全相 + `mcp019`/`mcp010` + `mcp041/042/043`；
**绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push；构建串行、不抑制输出；证据 `curl.exe -s -o` + sha256；
`.ps1` 纯 ASCII；结论按 D86 标提交锚点。