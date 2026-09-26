# TASK-AUDIT-M4 — 里程碑级独立验收：B3+B4（47 个工具）

> 你是**独立验收方**，未参与任何实现，**不得采信** `docs/reports/REPORT-0*.md` 与决策者的结论。
> 只依据规范、代码与你**自己可复现**的证据。
> 报告写到 `docs/reports/REPORT-AUDIT-M4.md`；返回值**只允许**是「≤15 行总结 + 报告路径 + verdict」。

## 1. 范围与基准

- 已实现 **113/171**（B1 41 + B2 25 + B3 40 + B4 7）。本验收覆盖 **B3+B4 = 47 个工具**（M4）。
- 权威依据：`docs/tool-rename-map.json`、`docs/tools_list.renamed.json`（171 条）、
  `docs/tool-groups-b3.json`、`-b4.json`、`docs/DESIGN-DETAIL.md`（§17/§18/§19 + GDR-16..21）、
  `docs/tasks/PLAYBOOK-group-port.md`、`F:\moonbit-hof-rs\DECISIONS.md`（D45 的 7 个 fix-first、D66/D67 的裁决）。
- **开工第一步**：校验 `--version` 的 hash 前缀 == `git rev-parse --short HEAD`；不一致就**先重建**
  （`bin/` 不受版本控制，曾在陈旧二进制上产生假红）。

## 2. 必须核实（逐项给结论 + 你自己跑出的证据）

> **本轮为 M4 的第二次验收（首轮判 `fail`，见 `REPORT-AUDIT-M4.md`）**：
> 首轮的 D-1（分量级静默错值）、D-2（`STRING→FLOAT/INT` 放行垃圾）、D-3（断言缺 `reason`）已在
> **TASK-020** 修复；同类残留面（`STRING→BOOL`、容器元素位宽、`Vector4` 元素、**分量槽位宽**、`STRING→COLOR`）
> 已在 **TASK-021** 修复。**你的首要任务**：用与首轮**同样的对抗性反例**（尤其那五种分量值与字符串值）
> 复核它们**真的闭合**，并**自己再找**同族的新面（`声明确定性转换` 与 `槽位宽` 的边界见 `PLAYBOOK` §7.7）。

### A. 全量对等与 scope（核心）
1. **自己解析** `tools/list` 的 `name` 字段（**不得**用 `-match`/文本包含：契约 `description` 会互相按名引用，
   已实测两次假 PASS），与 B1..B4 的 `implemented=true` 组并集比对：集合差集必须为空；
   并逐条与契约 `name`/`description`/`inputSchema` **逐字相等**（自己抓、自己比）。
2. **双向 scope 分离**：按映射 `scope` 推导两端点期望集合（编辑器/游戏），实况必须相等；
   任一工具出现在其 `scope` 不允许的端点即失败；跨端点调用必须 `-32601` 且**不执行**。

### B. 诚实性（本项目核心诉求）
3. **7 个 `fix_implementation_first` 的现状**：已修 4 个（`editor_remove_output_log`、`editor_disconnect_signal`、
   `editor_set_auto_dismiss_dialogs`、`editor_get_test_report`）；剩余 **3 个**（tilemap×2、`bake_navigation_mesh`，属 B5）
   **必须仍未注册**。逐条核实「已修的 4 个**真的做到了**」（自己构造证据，尤其
   `editor_get_test_report` 是否**真的累积**了断言结果、`editor_remove_output_log` 是否**真的清空**面板）。
4. **2 个 `unregister`** 仍未被注册。
5. **静默错值修复的有效性**（D67 裁决的落地）：自己构造「布局不兼容的值」（如给 `position` 传 `1e20`、
   给 `Vector2` 属性传字符串），在 **7 个受影响工具**上验证：必须 `-32602`，且**读回证明未被改动**；
   并确认**合法值仍正常写入**（回归）。
6. **批量事务语义**：`editor_add_nodes_batch` / `editor_set_node_property_batch` 用**故意坏的中间元素**验证
   **全成功或全回滚**（读族证明零半成品）；不得出现「报成功但只做一半」。

### C. 行为与宣称一致（对抗性抽样）
7. 抽样 **≥15 个 B3/B4 工具**，把实测响应与**迁移源的可观察契约**（读 Rust/GDScript）对照，列出每处差异并判可接受性。
8. **断言与场景运行器**（B4 重点）：自己跑一个**应当通过**的场景与一个**应当失败**的场景
   （`running_game_run_test_scenario` 从 9889），确认：通过的确实 `all_passed=true`；
   失败的确实 `all_passed=false` **且带 `expected`/`actual`/`reason`**；空步骤/未知步骤类型的**前置拒绝**为 `-32602`。
9. **对抗性反例**：路径逃逸（写侧与读侧）、参数滥用（缺参/类型错/越界/`NaN`）、
   多场景写（`project_set_node_property_across_scenes`）的**故意坏文件**、`project_set_setting` 的类型保真、
   `editor_set_node_property_batch` 的「无匹配节点」前置拒绝、UID 双向（方向搞反必须**响亮失败**而非静默错映射）。

### D. 延迟通道与工程门
10. deferred 工具（B4 里的等待/多帧/信号监视）自己验证：超时、pending 期间断连（`pending` 归零不崩）、
    多 pending 交错不串线、pending 期间常规请求仍毫秒级。
11. 门自己跑：`--headless --test --test-case="[MCPServer]*"`、全引擎 `--headless --test`、
    `accept_m1.ps1` ×2（PASS 清单必须一致）、`check_tool_groups.py`（B3/B4/完整性）。
12. **门脚本是否真的不再需要手工改**：核实 `accept_m1.ps1` 的 `$ToolNames` **确实由 manifest 派生**
    （而非仍有硬编码残留）；若发现残留，报缺陷。

### E. 端口与收尾
13. **9877 全程属于用户（PID 36392）**：不得占用/杀/重启；测试只用 9888/9889；
    收尾后无 9888/9889 监听、无孤儿进程（含 `editor_play_scene` 拉起的游戏子进程）。

### F. **顺手性（ergonomics）—— 本轮新增，依据 GDR-23**

> **决策者指令（D74）**：**迁移源不是完美预言机**，它只提供「工具类别 + 大致用途」；
> **「怎么用顺手」以引擎源码为第一参考源**（本 fork 的 `core/**`、`scene/**`、`editor/**`）。
> **顺手性是验收条款**：工具必须让调用方**一趟做完引擎一趟能做的事**、参数取引擎自然形态、
> 返回字段**可链式喂回**。要求调用方做「多步舞蹈」换取引擎一次调用即可给出的结果 **算缺陷**。

**判据**：对每个工具问三句话 ——
①「引擎里对应的 API 是什么？它**一次**能做到什么？」（**给出行号级证据**）
②「这个工具的参数形态、返回字段，是不是**引擎自然形态**？调用方要写多少？」
③「它的返回值能不能**直接**喂给另一个工具（路径/对象/名字可直接复用）？」

**至少覆盖以下已列出的候选（逐条给结论 + 引擎证据 + 严重度；若认为某条不是缺陷，给出理由）**：

| # | 项 | 需要你核实的点 |
|---|---|---|
| E-1 | `project_get_scene_dependencies` 的 `type` 恒为空串 | 引擎里判定依赖类型/资源类型的正确 API 是什么（`ResourceLoader::get_resource_type`? `Resource::get_class`?）；空串是否真的无信息可给 |
| E-2 | `editor_get_scene_tree` 路径含 `@EditorNode@<id>`（每次运行都变） | 引擎是否提供**相对编辑场景根**的稳定路径；非确定输出对可复现性的损害（给出两次运行的实测差异） |
| E-3 | `Vector4`/packed 读回是 `String` 而 `Vector2` 是对象 | 同一类值的形状分裂；消费者是否需要分支处理（给出线上两种形状的实测响应） |
| E-4 | `assign_shader_material` 忽略 `material_slot` | 引擎的槽位 API（`MeshInstance3D::set_surface_override_material` 等）；忽略槽位是否导致**写错位置**或**只是不精确** |
| E-5 | `set_shader_param` 用复合属性路径直写 | 引擎的 `ShaderMaterial::set_shader_parameter`；**直写是否静默失效**（这是关键，必须实测，不只是读码） |
| E-6 | `editor_get_errors`/`editor_get_output_log` 只读日志文件 | 编辑器进程内是否有更即时的来源（`EditorLog`/`EditorNode`）；文件读取是否**漏掉尚未 flush 的行** |
| E-7 | `attach_script` 用 `node.set("script", …)` | 引擎的脚本属性语义（`usage`、`@tool`、`_set` 交互）；泛写是否有副作用 |
| E-8 | 错误消息带不稳定节点 id | 是否可用稳定标识（相对路径/名字）替代 |
| E-9 | `project_read_resource` 只回 `{path,type,loaded}` | 引擎能列出的属性；「读资源却不给内容」是否强迫多走一趟 |
| E-10 | `editor_play_scene` 不传 `--mcp-port` 给游戏子进程 | **预期为引擎事实**（`editor_run.cpp`）；请核实并确认「模块内不可修」的结论是否成立 |

**另外自己主动找**：**你认为还有哪些工具「按引擎源码本可以更顺手」**（不限于上表），
给出「引擎能做什么」与「当前工具要几趟」的对照。**这一项没有数量下限**，但**每条必须有引擎源码证据**。

## 3. 硬性约束

不得修改任何文件（临时改测试须还原并留证）；临时文件放 `%TEMP%\audit-m4\`；不得 git 写操作；不得安装依赖；
证据用 `curl.exe -s -o <file>` + sha256、请求体用 `ConvertTo-Json`（**禁止** `Out-File`/管道承载响应体、
**禁止**字符串拼接 JSON）；**不要抑制 scons 输出**；**不要并发跑两个 scons**。

## 4. 报告

`verdict`（分类：全量对等 / 诚实性 / 行为一致 / 安全与事务 / 延迟通道 / 工程门 / 端口纪律）、逐项结论与**你自己跑出的证据**、
`defects`（severity/claim/evidence/location/recommendation）、`unconfirmed`、`risks`、`next_step_recommendation`。
**返回值：≤15 行 + 报告路径 + verdict。**