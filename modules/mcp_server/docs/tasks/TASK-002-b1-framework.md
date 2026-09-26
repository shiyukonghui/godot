# TASK-002 — B1 框架先行：注册分组 + 工具编写助手 + 模板组（工程只读族）

> **执行者须知**：你没有参与此前工作，本文件是**唯一任务来源**，必须自包含地读完再动手。
> 完成后**必须**把完整报告写到 `modules/mcp_server/docs/reports/REPORT-002-b1-framework.md`，
> 返回给决策者的内容**只允许**是「简洁总结（≤15 行）+ 报告路径」。

## 0. 背景

用户裁决：**优先完成 Godot 内置 MCP 模块的工具集成与测试；harness（hof-rs）暂停**（`DECISIONS.md` D43）。
命名事实源已冻结并通过独立验收（**映射 v1.1**，`pass`，见 `DECISIONS.md` D45/D46）：
`docs/tool-rename-map.json`（70917 B，sha256 `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd`）、
期望契约 `docs/tools_list.renamed.json`（171 条）。

**B1 批次 = 42 个旧工具 → 41 个注册**（`get_editor_performance` 已被无损合并，不单独注册），
清单见 `docs/DESIGN-DETAIL.md` §10。41 个 C++ 实现超出单个子代理容量，因此**框架先行**（本任务），
之后按组并行。**本任务只交付框架 + 一个模板组**，不要试图把 B1 全做完。

## 1. 必读（规范性，只读）

| 文件 | 作用 |
|---|---|
| `docs/DESIGN-DETAIL.md` | §10（B1 精确清单）、**§16**（执行顺序）、**GDR-16**（命名 lint）、**GDR-17**（合并不损）、**GDR-18**（条件写）、§7（注册表与 scope）、§5–§6（HTTP/JSON-RPC 契约） |
| `docs/tool-rename-map.json` | 命名与处置的**唯一事实源**（v1.1） |
| `docs/tools_list.renamed.json` | **每批对等门的参照物**（171 条，含 description/inputSchema） |
| `docs/reports/REPORT-AUDIT-001-rename-map-v1.1.md` | 上一轮独立验收（含 R-1..R-6 风险与 N-1/N-2） |
| `F:\moonbit-hof-rs\DECISIONS.md` | D38/D41/D43/D44（协作协议）/D45/D46（B1 架构决定） |
| 迁移源（**语义参照**，只读） | `F:\RustProjects\godot-mcp-pro\godot_mcp_gdext\src\commands\*.rs` 与 `addons\godot_mcp_rs\**` |

## 2. 任务（4 部分）

### 2.1 预备：映射 v1.2（消歧描述）+ 修两个 nit

1. **description 消歧（R-1/R-2/R-3）**：以下 7 个工具**光看名字仍不足以可靠二选一**，
   必须在 `tools_list.renamed.json` 的对应 `description` 里**内联一句判别点**（返回值形状 / 上限 / 大小写 / 过滤规则）：
   - `editor_analyze_signal_flow` / `editor_list_signal_connections`
   - `project_search_file_names` / `project_search_file_contents` / `project_find_files_referencing_symbol`
   - `project_convert_uid_to_path` / `project_convert_path_to_uid`
   做法：在 `scripts/gen_renamed_contract.py` 已有的 **`DESCRIPTION_OVERRIDES`** 表里逐条登记
   （表在 B0 已预留、并要求把理由写进 `_meta.overrides`）。**不要手改契约文件**（会被重生成覆盖）。
   判别点必须来自**读实现得到的真实差异**（例如：`search_in_files` 逐行返回且大小写不敏感、上限 50；
   `find_node_references` 按文件聚合且大小写敏感、上限 100），**不得编造**。
2. **nit N-1**：`docs/scripts/gen_table.py` 目前把 `disposition` 渲染成「`merge_into`→目标」，
   与枚举值不严格相等 → 改为**纯枚举**输出（目标信息已有独立列，避免重复）。
3. **nit R-4**：`scripts/accept_m1.ps1` 的 SUMMARY 必须打印
   「已实现工具数 / 契约 171」并显式标注 `known_deviation`（当前逐字对等门只覆盖已实现工具），
   避免批次门被误读为全量门。**不要**为了补齐 171 而注册未实现的工具。
4. 重跑生成器与文档渲染器（`docs/scripts/gen_table.py`），更新 `TOOL-NAMING.md` 与头部指纹。

### 2.2 框架：注册分组 + 工具编写助手

1. **注册分组**：`tools/` 下按组拆分文件，每组提供 `void register_<group>_tools(ToolRegistry &r)`；
   共享注册表只保留 `register_all_tools(registry)`，其中**每组一行**调用。
   目的：后续并行移植时，每个子代理**只拥有自己的组文件 + 一行注册**，不改共享文件（消除冲突）。
   现有 2 个工具（`project_get_info`/`project_get_settings`）迁入 project 组，**行为与 `tools/list` 输出逐字不变**。
2. **工具编写助手**（统一三类证据与错误语义，见 GDR-6/GDR-7/GDR-14）：
   - `ToolDef` 构建器：**必须**显式声明 `channel`/`verb`/`scope`/`mutating`（与 GDR-16 lint 对接）；
   - 参数校验助手（`require_string`/`require_int`/`optional_*`，失败 → `-32602` 且信息可读）；
   - 结果封装：成功 → `{"content":[{"type":"text","text":"<json>"}]}`；
     工具内部资源缺失 → `-32001`；未实现 → `-32000`（附 `data.suggestion`）；
   - 磁盘/资源访问助手（项目根路径解析；`DirAccess`/`FileAccess`/`ResourceLoader` 的安全封装）。
3. **编辑器/游戏双目标编译**：模块同时为 editor 与 game target 编译，**编辑器专有 API 必须用
   `#ifdef TOOL_ENABLED`（或等价守卫）包住**，并保证 `Engine::is_editor_hint()==false` 时不注册/不暴露编辑器专有工具。
   `get_project_info` 含编辑器派生值（`EditorInterface.get_base_control().get_size()`）——按此规则处理。

### 2.3 模板组（**由决策者指定的 6 个工具**，不得扩缩）

只移植这 6 个（其余 B1 工具留给后续并行任务）：

| # | 新名（契约为准） | 旧名 | 备注 |
|---|---|---|---|
| 1 | `project_get_info` | `get_project_info` | **已实现**，迁入组文件；含编辑器派生值 → 注意 `#ifdef TOOL_ENABLED` |
| 2 | `project_get_settings` | `get_project_settings` | **已实现**，迁入组文件 |
| 3 | `project_get_filesystem_tree` | `get_filesystem_tree` | 新实现 |
| 4 | `project_search_file_names` | `search_files` | 新实现：**只按文件名**匹配 |
| 5 | `project_search_file_contents` | `search_in_files` | 新实现：逐行 `{file,line,text}`、大小写**不敏感**、上限 **50** |
| 6 | `project_find_files_referencing_symbol` | `find_node_references` | 新实现（**取消合并**后独立）：按文件聚合 `{file,lines[]}`、大小写**敏感**、上限 **100** |

- 第 5、6 项是**取消合并后的两个独立工具**，语义不同，**绝不能实现成同一个**（这是 GDR-17 的直接检验点）。
- `project_get_info` / `project_get_settings` 迁移后 `tools/list` 输出必须**逐字不变**（回归护栏）。

### 2.3.1 全 B1 的组清单（**必须一并产出，但不实现**）

把 B1 的 **41 个**待移植工具（42 旧工具 − `get_editor_performance`（已合并））**全部分组**，
落成 **`docs/tool-groups.json`**，供决策者派后续并行任务：

```json
{ "groups": [
  { "name": "project_read_template", "batch": "B1", "implemented": true, "tools": ["project_get_info", "..."] },
  { "name": "<后续组名>", "batch": "B1", "implemented": false, "tools": ["<new_name>", "..."] }
] }
```

- **每组一个 `channel` + 读写属性**，组内工具应能放进同一个 `tools/<group>.{h,cpp}`，且**组间无共享文件**。
- 分组依据：旧实现所在的命令模块（`commands/*.rs`）+ `channel` + `mutating`（读写）。
- 建议 4–6 组、每组 ≤ 10 个工具（单个子代理可完成）。
- **必须满足**：41 个工具**恰好出现一次**、无遗漏无重复（在报告里给出计数断言的真实输出）。
  这个文件是后续并行派发的**唯一依据**，必须精确。

### 2.4 门与脚本

1. **契约子集对等脚本**（新增 `scripts/check_contract_subset.ps1`）：输入组名（或工具名集合），
   断言引擎 `tools/list` 与该组在 `tools_list.renamed.json` 中的子集**逐字相等**
   （name / description / inputSchema 三者；多余或缺失即失败），并支持对 **9888（编辑器）与 9889（游戏）**两个端点各跑一次。
2. **每工具三类证据**：成功 / 缺参（`-32602`）/ 底层失败（如资源不存在 → `-32001`，或明确的工具错误）。
   证据必须落盘到报告（真实请求与响应片段）。
3. `--test --test-case=[MCPServer]*` 全绿；全引擎 `--test` **0 failed**（基线 1465，只允许因新增测试而增加）。
4. `scripts/accept_m1.ps1` **连跑两次**全过。

## 3. 硬性约束

- 只允许修改 `code\godot\modules\mcp_server\**`。其它一切（引擎其它目录、`godot_mcp_gdext`、**整个 hof-rs 仓库**）**只读**。
- 用户正在使用的 Godot 4.7.1-mono 占用 **9877**（PID 36392）：**绝不占用、绝不杀/重启**；测试端口 **9888/9889**；scratch 放 `%TEMP%`。
- 提交到 `feature/mcp-server-module`（英文提交信息），**禁止 push**；结束后工作树只应剩既有未跟踪物
  （`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）。
- **不得**注册未实现的工具；**不得**注册 2 个 `unregister_until_implemented` 项；
  7 个 `fix_implementation_first` 必须**先写红测试再修实现**（B1 内的 `clear_output` 属此列，若它落在你的组里才处理）。
- 不得伪造输出；本任务之后会有**全新子代理**做独立验收，证据必须可复现（命令 + 输出 + 文件路径）。
- 不得安装依赖、不得访问 100.105.152.101:18080。

## 4. 报告要求（写到 `docs/reports/REPORT-002-b1-framework.md`）

- `status`、`commits`（sha + 一行说明）
- **模板组清单**：6 条 old→new 逐条（与上表一致）
- **`docs/tool-groups.json`**：全 B1 分组（每组的 channel/读写属性/工具清单/是否已实现）
  + 「41 个工具恰好各出现一次」的计数断言真实输出
- 框架设计：注册分组结构（文件清单 + 每组的注册入口）、助手 API 清单、编辑器/游戏守卫方式
- 三类证据：6 个工具各 1 组成功/缺参/底层失败的**真实请求与响应**
- 门：契约子集对等（编辑器 9888 + 游戏 9889）覆盖这 6 个工具；doctest；全引擎；accept ×2（贴输出与退出码）
- 新指纹：`tools_list.renamed.json`、`TOOL-NAMING.md`、`docs/tool-groups.json`（若动过映射也给）的字节数与 sha256
- **剩余 B1 的并行拆分建议**：基于 `tool-groups.json`，指出各组建议的派发顺序与风险
- `deviations`（与任务书的任何偏离，必须显式列出）、`blockers`、`next_step_recommendation`

**返回给决策者**：≤15 行总结 + 报告路径。