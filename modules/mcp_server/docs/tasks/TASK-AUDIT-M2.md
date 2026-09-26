# TASK-AUDIT-M2 — 里程碑级独立验收：B1+B2（66 个工具）

> 你是**独立验收方**，未参与任何实现，**不得采信实现方与决策者的结论**。
> 只依据规范、代码与你**自己可复现**的证据。所有实现方报告（`docs/reports/REPORT-*.md`）都是**自述，不是证据**。
>
> 报告写到 `docs/reports/REPORT-AUDIT-M2.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径 + verdict」。

## 0. 验收范围（M2）

模块 `code\godot\modules\mcp_server\` 的 **B1+B2 共 66 个工具**是否达到「可按契约使用、且不谎报、不越界」。
里程碑级验收**不逐组重建**，而是覆盖：全量对等、跨组一致性、宣称行为与实测一致、安全边界、诚实性、工程门。

## 1. 权威依据（只读）

- `docs/tool-rename-map.json`（映射 v1.1，`scope`/`channel`/`mutating` 的唯一事实源）
- `docs/tools_list.renamed.json`（契约 v1.3，**171 条**，`_meta.order_normative=false`）
- `docs/tool-groups.json`（B1 = 41/41）与 `docs/tool-groups-b2.json`（B2 = 25/25）
- `docs/DESIGN-DETAIL.md`：§17/GDR-19（框架）、§18/GDR-20（延迟通道）、§19/GDR-21（输入边界）、§16、§10
- `docs/tasks/PLAYBOOK-group-port.md`（每组的门与已知偏差）
- `F:\moonbit-hof-rs\DECISIONS.md`（**D43** 优先级、**D45** 七个 `fix_implementation_first`、
  **D51** 验收粒度、**D56/D57/D59** 最近的裁决与已知偏差）
- 迁移源（语义参照，只读）：`godot_mcp_gdext/src/commands/*.rs`、`addons/godot_mcp_rs/**`

## 2. 必须核实的项（按类别，逐项给结论 + 你自己跑出的证据）

### A. 全量契约对等（核心）
1. 已实现并集是否**恰好**等于 B1∪B2 的 66 个工具（自己 `tools/list` 两端点取回并计算集合差集）。
2. 全部 66 条在**其可见端点**上 `name`/`description`/`inputSchema` **逐字相等**（自己抓、自己比；
   不要只跑 `check_contract_subset.ps1`）。
3. **双向 scope 分离**：编辑器端点 9888 = 49、游戏端点 9889 = 40；
   任一工具不得出现在其 `scope` 不允许的端点上；跨端点调用必须 `-32601` 且**不执行**。

### B. 诚实性（本项目的核心诉求）
4. **7 个 `fix_implementation_first`**（`disconnect_signal`、`clear_output`、`set_auto_dismiss`、
   `tilemap_set_cell`、`tilemap_fill_rect`、`bake_navigation_mesh`、`get_test_report`）：
   目前**只有 `editor_remove_output_log` 被真正修好**。请核实：
   ①它现在的行为**真的清空了 Output 面板**（自己复现：产生可识别日志 → 调用 → 断言消息消失，
   且**不是**靠截断日志文件冒充）；
   ②**其余 6 个工具当前未被注册**（不得以「未修好的形态」上线）。
5. **2 个 `unregister_until_implemented`**（`project_export_game`、`navigate_to`）**必须未被注册**。
6. **不得有任何工具谎报成功**：抽样你怀疑的若干（例如 `editor_rescan_project_filesystem`、
   `editor_reload_plugin`、`project_create_scene_file`、`editor_capture_screenshot` 在 headless 下的拒绝），
   对**每种失败情形**确认返回错误码而**不是**「成功但什么也没发生」。

### C. 行为与宣称一致（对抗性抽样）
7. 抽样 **≥15 个工具**（跨 4 个通道、含 editor/game/both、含至少 3 个写工具、含 2 个 deferred 工具），
   逐条把**实测响应形状**与**迁移源的可观察契约**（读 Rust/GDScript 源码）对照，列出**每一处差异**并判断是否可接受。
8. **对抗性反例**：
   - 路径逃逸：`res://a/./../b`、`res://../x`、绝对路径、`..%2f`、NUL、超长路径 →
     必须拒绝且**不得**写出项目外（自己构造，记录响应）；
   - 参数滥用：缺参、类型错、越界整数（`1e20`）、`NaN`、空字符串、超大 `count`、
     `node_path` 指向不存在节点、`property` 是只读属性；
   - **deferred 通道**：超时（用一个永不满足的等待）、**pending 期间断连**（不得崩溃/泄漏，
     需 `get_status_body()` 的 `pending` 归零）、多 pending 交错不串线、pending 期间常规请求仍毫秒级响应。

### D. 工程门（自己跑）
9. `--headless --test --test-case="[MCPServer]*"`、全引擎 `--headless --test`、`accept_m1.ps1` **连续两次**
   （两次 PASS 清单必须一致）、`check_tool_groups.py`（B1 与 B2 两个 manifest）。
10. **端口纪律**：**9877 全程属于用户（PID 36392）**，你**不得**占用、杀、重启它；
    测试只用 9888/9889；收尾后**不得**留下 9888/9889 监听与孤儿进程（自己用 `netstat` + 进程树证明）。

### E. 一致性
11. `docs/tool-groups.json`、`docs/tool-groups-b2.json`、契约、映射四者一致（66 个名字、channel/scope/mutating 不得冲突）。
12. `docs/TOOL-NAMING.md` 与映射一致（抽样即可）；生成器幂等（可选）。

## 3. 硬性约束

- **不得修改任何文件**（含被验收件、脚本、文档）；临时文件放 `%TEMP%\audit-m2\**`。
  若必须临时改测试以验证某不变量，**必须还原**并给出还原证据（文件 sha256 + `git status` 干净）。
- 不得 git 写操作；不得安装依赖；不得访问 100.105.152.101:18080。
- 证据采集一律 `curl.exe -s -o <file>` 落盘后算 sha256；请求体用 `ConvertTo-Json` 生成
  （**禁止** `Out-File`/管道承载响应体，**禁止**字符串拼接 JSON——这两者此前各污染过一版证据）。
- **不要抑制 scons 输出**（曾因抑制输出造成构建竞态残留，把旧日志误读为本批缺陷）。
- 严格区分「证据支持」与「推断」；不确定写 `unconfirmed`。

## 4. 报告要求（`docs/reports/REPORT-AUDIT-M2.md`）

- `verdict`: `pass` | `fail`（**分类判定**：全量对等 / 诚实性 / 行为一致 / 安全边界 / 工程门，逐类给结论）
- 每项结论附**你自己跑出的命令与输出**（或源码行号）
- `defects`: `{ id, severity(blocker|major|minor|nit), claim, evidence, location, recommendation }`
- `deviations_ruled`：对 `PLAYBOOK` §6 已知偏差与各报告自报偏差的抽样复核结论
- `unconfirmed`、`risks`、`next_step_recommendation`

**返回值：≤15 行总结 + 报告路径 + verdict。**