# REPORT-002 — B1 框架先行：注册分组 + 工具编写助手 + 模板组（工程只读族）

- **任务书**：`docs/tasks/TASK-002-b1-framework.md`（自包含，唯一来源）
- **status**：`complete`（4 部分全部交付；所有门全绿；三类证据可复现；`deviations` 见 §9）
- **分支**：`feature/mcp-server-module`；HEAD `5e75c1aa3ed2451908e6ec3b07638d18df1816f8`（**未 push**）
- **改动物围栏**：`git diff --name-only 1090d04803..HEAD | grep -v '^modules/mcp_server/'` = **0 命中**；
  hof-rs / `godot_mcp_gdext` / 引擎其它目录全部只读。
- **9877 纪律**：全部运行（构建、`--test`、accept×2、证据采集、契约子集门）前后
  `9877 pid=36392 → 36392` 不变；本任务只使用 9888/9889；scratch 全在 `%TEMP%`。

## commits

| sha | 说明 |
|---|---|
| `3de118ac2d` | 契约 v1.2：7 条 description 判别点（R-1/R-2/R-3）+ nit N-1（纯枚举）/ R-4（SUMMARY 批次门声明） |
| `e14a1b0aad` | `docs/tool-groups.json`：B1 41 个工具 → 7 组 + 机器校验脚本 |
| `5e75c1aa3e` | B1 框架（分组建注册 + 工具编写助手 + 编辑器守卫 + 结构化工具错误）+ 模板组 6 工具 + 测试 + 契约子集门 |

---

## 1. 预备：映射 v1.2（消歧描述）+ 两个 nit

### 1.1 七条 description 判别点（R-1/R-2/R-3）

做法：全部登记在 `scripts/gen_renamed_contract.py` 的 `DESCRIPTION_OVERRIDES`（表头 B0 已预留），
**没有手改契约文件**（重生成得到），理由全部进 `_meta.overrides`。判别点来自**读迁移源实现**得到的真实差异：

| old_name | 判别点（内联句的要点） | 源码依据（只读复核） |
|---|---|---|
| `analyze_signal_flow` | 按节点嵌套 `nodes[]`、只留持久连接（`flags & 1`）、`node_path` 精确、无 `signal_name` 过滤 | `analysis.rs:387-410`、`analysis.rs:96-160` |
| `find_signal_connections` | 扁平 `connections[]`（`{source,signal,target,method}`）+`count`、收全部连接、`node_path`/`signal_name` 均子串 | `batch.rs:207-263` |
| `search_files` | 只匹配**文件名**子串（大小写不敏感、上限 200）、不读内容不返回行号 | `project.rs:159-191` |
| `search_in_files` | 逐行 `{file,line,text}`（大小写不敏感、上限 50、跳过 `addons`/`.godot`） | `project.rs:194-246` |
| `find_node_references` | 按文件聚合 `{file,lines[]}`（每文件 ≤5 行、大小写敏感、上限 100、只扫 `.tscn/.gd/.tres/.gdshader`） | `batch.rs:419-512` |
| `uid_to_project_path` | 入参文本 UID、出参 `{uid,path}`，UID 文本非法即参数错误 | `project.rs:295-305` |
| `project_path_to_uid` | 入参项目路径、出参 `{path,uid}`，未注册路径 `uid=""` 且**不报错** | `project.rs:308-322` |

**生成器两处必须修的既有缺陷**（否则 override 表根本不可用）：

1. 「未登记就不得改动」的断言在**已登记**时也触发（`if canonical(description) != canonical(tool[...])` 无条件执行），
   即 override 一填就 FATAL。改为只在**未 override** 时断言，并对已 override 的条目断言**只能追加**
   （`value.startswith(old + " ")`）——原文不会被静默丢弃。
2. 新增「登记的 override 必须恰好触发一次」自检：`old_name` 写错时从静默无效变成硬失败。

生成器版本 `1.1.0 → 1.2.0`。

### 1.2 nit N-1 + nit R-4

- **N-1**：`docs/scripts/gen_table.py` 的 `disposition` 单元格改回**纯枚举**（合并目标的独立列已有信息）。
  并新增回归护栏：把 174 行渲染结果**反向解析**回枚举值并断言。
- **R-4**：`scripts/accept_m1.ps1` 的 SUMMARY 现在打印
  `implemented tools : 6 / contract 171`，并显式标注 `known_deviation: per-batch gate, NOT a full-contract gate`；
  同时新增一条 `gate_scope_declared` 结果行，且断言 `契约 == 171` 与 `已实现 ≤ 契约`。
  **没有**为凑齐 171 注册任何未实现工具。

### 1.3 重跑

```
$ python modules/mcp_server/scripts/gen_renamed_contract.py
gen_renamed_contract: input tools = 174
gen_renamed_contract: output tools = 171
gen_renamed_contract: merged = 1 (get_editor_performance -> get_performance_monitors)
gen_renamed_contract: unregister = 2 (navigate_to, export_project)
gen_renamed_contract: description overrides = 7 (append-only, search_files, search_in_files, uid_to_project_path, project_path_to_uid, find_signal_connections, find_node_references, analyze_signal_flow)
gen_renamed_contract: old contract sha256 = 8f8051c4c0f8941089f0b21a193cef7c51fa7c41d7e312b1463ea8593f313c54
gen_renamed_contract: rename map sha256 = 2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd
gen_renamed_contract: output sha256 = 898d868278147cb6f11e83fe11e4e065fb9aa66d13b0a801d81a89354618d57b
gen_renamed_contract: self-checks = OK (lint 171/171, unique 171/171, disposition enum OK)
```

（映射 sha256 与冻结值 `2f552719…` **逐字相同**；生成器**幂等**，复跑同 sha。
`_meta`: `generator_version=1.2.0`、`count=171`、`excluded=[navigate_to, export_project]`、
`merged=[get_editor_performance→get_performance_monitors]`、`overrides=7`。）

```
$ python modules/mcp_server/docs/scripts/gen_table.py
TABLE   rendered rows=174 (assert rows == 174: PASS)
N-1     disposition cells parsed = 174, all pure enum values (no '->target' decoration); merge_into cells = 1
DETERMINISM  render run#1 == render run#2 byte-identical (95673 bytes): PASS
WROTE   .../docs/TOOL-NAMING.md  bytes=98462  sha256=f68f1551dc01a72331ae9b1590a8ed9167102c10a947a8f1607bfae0b2561d59  (write-then-read-back byte-identical)
```
渲染结果第 223 行现在是：`| \`get_editor_performance\` | … | \`merge_into\` | … |`（纯枚举）。

---

## 2. 模板组清单（6 条，与任务书 §2.3 一致，未扩缩）

| # | 新名 | 旧名 | 处置 |
|---|---|---|---|
| 1 | `project_get_info` | `get_project_info` | 已实现 → 迁入组文件（`tools/list` 条目**逐字不变**） |
| 2 | `project_get_settings` | `get_project_settings` | 已实现 → 迁入组文件（`tools/list` 条目**逐字不变**） |
| 3 | `project_get_filesystem_tree` | `get_filesystem_tree` | 新实现 |
| 4 | `project_search_file_names` | `search_files` | 新实现：只按文件名匹配 |
| 5 | `project_search_file_contents` | `search_in_files` | 新实现：逐行、大小写不敏感、上限 50 |
| 6 | `project_find_files_referencing_symbol` | `find_node_references` | 新实现（取消合并后独立）：按文件聚合、大小写敏感、上限 100 |

迁移回归护栏：`tests/test_mcp_server.h` 的 6 工具 `tools/list` **逐字节**期望里，前两条与 M1 版本
（`REPORT`/`ACCEPTANCE` M1 节记录的 2 工具载荷）逐字相同；契约子集门（§6.4）对 6 条各比 name/description/inputSchema
三维。

---

## 3. `docs/tool-groups.json`（全 B1 41 个，**只产清单不实现**）

```json
{ "batch": "B1",
  "counts": { "b1_old_tools": 42, "excluded_merged": 1, "b1_tools_to_port": 41, "groups": 7 },
  "groups": [ … ] }
```

| 组名（= 文件 `tools/<group>.{h,cpp}`） | channel | 读写 | 工具数 | implemented | 工具 |
|---|---|---|---|---|---|
| `project_read_template` | project | read（mutating=false） | 6 | **true** | project_get_info, project_get_settings, project_get_filesystem_tree, project_search_file_names, project_search_file_contents, project_find_files_referencing_symbol |
| `project_read_analysis` | project | read | 7 | false | project_get_statistics, project_analyze_scene_complexity, project_detect_circular_dependencies, project_find_unused_resources, project_find_script_references, project_get_scene_dependencies, project_get_scene_exports |
| `project_read_files` | project | read | 6 | false | project_list_scripts, project_read_script, project_validate_script, project_read_resource, project_get_resource_preview, project_read_scene_file_content |
| `project_write_resource_scene` | project | **write** | 4 | false | project_create_resource, project_create_scene_file, project_delete_scene_file, project_edit_resource |
| `editor_read_scene_inspector` | editor | read | 7 | false | editor_get_errors, editor_get_output_log, editor_get_open_scripts, editor_get_scene_tree, editor_get_selection, editor_get_viewport_3d_camera, editor_analyze_signal_flow |
| `editor_write_scene_editor` | editor | **write** | 10 | false | editor_open_scene, editor_save_scene, editor_reload_plugin, editor_rescan_project_filesystem, editor_set_node_selection, editor_remove_node_selection, editor_add_resource_to_node_property, editor_set_viewport_3d_camera, editor_capture_screenshot, editor_remove_output_log |
| `running_game_read_scene` | running_game | read | 1 | false | running_game_find_nearby_nodes |

另外文件里带 `source`（B1 的派生来源与「被排除的合并项」）、`alerts`
（`fix_implementation_first=[editor_remove_output_log]`、`conditional_write_mutating_true=[editor_capture_screenshot]`、
`game_process_side=[running_game_find_nearby_nodes]`）与每组 `notes`。

### 3.1 计数断言的真实输出（`docs/scripts/check_tool_groups.py`）

```
$ python modules/mcp_server/docs/scripts/check_tool_groups.py
SOURCE  DESIGN-DETAIL.md section 10: B1 declares 42 old tools, parsed 42/42
DERIVE  excluded (merge_into) = get_editor_performance
DERIVE  B1 tools to port = 42 - 1 = 41
GROUP   project_read_template        channel=project      mutating=False implemented=True  tools=6
GROUP   project_read_analysis        channel=project      mutating=False implemented=False tools=7
GROUP   project_read_files           channel=project      mutating=False implemented=False tools=6
GROUP   project_write_resource_scene channel=project      mutating=True  implemented=False tools=4
GROUP   editor_read_scene_inspector  channel=editor       mutating=False implemented=False tools=7
GROUP   editor_write_scene_editor    channel=editor       mutating=True  implemented=False tools=10
GROUP   running_game_read_scene      channel=running_game mutating=False implemented=False tools=1
ASSERT  distinct tools in manifest = 41
ASSERT  B1 tools to port        = 41
ASSERT  every B1 tool appears exactly once: PASS (duplicates=0, missing=0, foreign=0)
ASSERT  every name exists in the 171 entry contract: PASS
ASSERT  every group is one channel + one mutating value: PASS
ASSERT  41 == 42 - 1: PASS
BYTES 5443
SHA256 9644911a01e983e69074b7988462789388e2dc59e17c74308fabb368d2ab0e59
TOOL-GROUPS CHECK PASS
```

校验器不采信我手写的分组：它**重新从 `DESIGN-DETAIL.md` §10 解析** 42 个旧名 → 用映射表
`disposition == merge_into` 排除 1 个 → 得到 41 个 new_name，再与清单逐条对账（含每组 channel/mutating
与映射表一致、组 ≤10、名称存在于 171 条契约）。**7 组而非任务书建议的 4–6 组**的原因见 §9 deviations。

---

## 4. 框架设计

### 4.1 文件清单与注册入口

| 文件 | 作用 |
|---|---|
| `tools/registration.h/.cpp` | `void register_all_tools(MCPToolRegistry &r)`；**每组一行调用**（+ 每组一个 include）。`mcp_server.cpp` 只调用它，不再维护组清单 |
| `tools/tool_builder.h/.cpp` | 工具编写助手：`ToolBuilder`、参数校验、结果封装、磁盘助手、editor 守卫 |
| `tools/project_read_template.h/.cpp` | B1 模板组 6 个工具；`void register_project_read_template_tools(MCPToolRegistry &r)` |
| `tools/<group>.{h,cpp}`（后续） | 其余 6 个组按 `docs/tool-groups.json` 并行加入 |
| `tool_registry.h/.cpp` | `MCPToolDef`（新增 `mutating`）+ `MCPToolError` + `scope_from_string` + `get_tool_count` |
| `mcp_jsonrpc.cpp/.h` | 只负责把 `MCPToolError` 序列化成线上错误对象；错误码枚举改为**别名** `tool_registry.h` 的 `MCPErrorCode`（两处定义不可能漂移） |
| 删除 `tools/project.h/.cpp` | 2 个工具迁入模板组文件（`git rm`），行为与 `tools/list` 条目不变 |

`mcp_server.cpp` 的注册幂等守卫从「`has_tool("project_get_info")`」（耦合具体工具名）改为
`registry.get_tool_count() > 0`。

### 4.2 助手 API 清单

```cpp
// tools/tool_builder.h（namespace MCPTools）
bool is_editor_process();
class ToolBuilder {                    // channel/verb/scope/mutating/handler 必须显式声明
  ToolBuilder(const String &name, const String &description);
  ToolBuilder &channel(..); &verb(..); &scope(..); &mutating(..); &schema(..); &handler(..);
  bool build(MCPToolDef &r_def, String &r_reason) const;   // 缺声明 / lint 失败 → false + 可读原因
  bool register_into(MCPToolRegistry &r) const;            // + 游戏进程不注册 editor-scope 工具
};
Dictionary empty_object_schema();      // {"type":"object","properties":{},"required":[]}

bool require_string (args, key, out, err);      // 缺参/类型错 → -32602
bool require_int    (args, key, out, err);      // 接受 2.0，拒绝 2.5
bool optional_string(args, key, def, out, err); // 缺省用默认；出现即必须类型正确
bool optional_int   (args, key, def, out, err);
bool optional_bool  (args, key, def, out, err);

Dictionary content_result(const Variant &payload);   // 成功信封唯一实现点

bool normalize_project_path(const String &in, String &out, MCPToolError &err); // 只允许 res://、禁 .. 与空段
Ref<DirAccess> open_project_dir(const String &path, MCPToolError &err);        // 不存在 → -32001 + suggestion
bool read_project_text_file(const String &path, String &out, MCPToolError &err);// 不存在 → -32001 + suggestion
String file_extension(const String &file_name);                                 // 去点扩展名（保留大小写，与参照一致）

// tool_registry.h
struct MCPToolError { int code; String message; Variant data; bool is_error() const;
  static invalid_params(msg)          // -32602，裸原因（GDR-6：不加前缀）
  static internal(msg)                // -32603 "Internal error: <m>"
  static no_scene()                   // -32000 "No scene is currently open" + data.suggestion
  static not_implemented(what, sug)   // -32000 "Not implemented: <what>" + data.suggestion
  static not_found(what, sug)         // -32001 "<what> not found" + data.suggestion
};
MCPToolDef: + String channel; + String verb; + bool mutating; + handler(const Dictionary&, MCPToolError&)
MCPToolRegistry::scope_from_string("editor"|"game"|"both") / get_tool_count()
```

### 4.3 编辑器 / 游戏守卫

- **编译期**：`tools/tool_builder.h` 里
  `#ifdef TOOLS_ENABLED` → `#define MCP_EDITOR_TOOLS_ENABLED 1`。**本 fork 不存在 `TOOL_ENABLED`**
  （`grep -rn TOOL_ENABLED` 无该宏定义，Godot 4.x 用 `TOOLS_ENABLED`），任务书的「`#ifdef TOOL_ENABLED`（或等价守卫）」
  按等价守卫实现；`project_read_template.cpp` 的 `EditorInterface/Control` 头与 `get_base_control()`
  分支都在 `#ifdef MCP_EDITOR_TOOLS_ENABLED` 内。
- **运行期**：`MCPTools::is_editor_process()` = `Engine::is_editor_hint()`；
  `ToolBuilder::register_into()` 在**游戏进程**里**根本不注册** `scope=EDITOR` 的工具（不是「注册但隐藏」），
  同时 `tools/list` 与 `tools/call` 仍按 scope 过滤（GDR-7 双层）。
- `project_get_info` 的 `editor_screen_size`：编辑器进程走 `EditorInterface::get_base_control()->get_size()`，
  否则回退 `SceneTree` 根视口 —— 两条约束叠加后，游戏构建里该分支连编译产物都不存在。

---

## 5. 三类证据（6 个工具，真实请求与响应）

采集方式（可复现）：`%TEMP%\godot-mcp-evidence\proj` 构造 scratch 工程（`project.godot`、`scripts/player.gd`
含第 3/5 行 `PlayerHealth`、`scenes/main.tscn` 引用该脚本、`PLAYER_README.md` 第 2 行 `playerhealth`、`notes.txt`），
以 `--headless -e --path <proj> --mcp-port=9888` 启动引擎（**不碰 9877**），逐个用
`curl.exe -s -X POST -H "Content-Type: application/json" --data-binary @body.json http://127.0.0.1:9888/mcp`
（body 走文件：JSON 作为命令行参数会被 Windows 引号规则吃掉内部双引号，退化成 `-32700`——这是采集脚本第一版的真实翻车，
已修正）。所有响应均为**原样粘贴**。

### 5.1 `project_get_info`（`arguments:{}`）— 成功

```json
BODY {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_get_info","arguments":{}}}
RESP {"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"editor_screen_size\":{\"height\":2.0,\"width\":2.0},\"project_name\":\"MCP evidence project\",\"version\":\"\"}","type":"text"}]}}
```

缺参 / 底层失败**在该工具契约下不可构造**（无参数、全函数，参照实现同样 total）；替代证据 = 传无关参数仍成功（宽松）：

```json
BODY {…"arguments":{"bogus":1}}}
RESP {"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"editor_screen_size\":{\"height\":2.0,\"width\":2.0},\"project_name\":\"MCP evidence project\",\"version\":\"\"}","type":"text"}]}}
```

### 5.2 `project_get_settings`

成功（`prefix` 过滤）：

```json
BODY {…"arguments":{"prefix":"application/config/name"}}}
RESP {"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"count\":2,\"settings\":{\"application/config/name\":\"MCP evidence project\",\"application/config/name_localized\":{}}}","type":"text"}]}}
```

缺参类（类型错 → `-32602`）：

```json
BODY {…"arguments":{"prefix":7}}}
RESP {"error":{"code":-32602,"message":"Parameter 'prefix' must be a string, got float"},"id":1,"jsonrpc":"2.0"}
```

底层失败：`ProjectSettings` 单例在运行的引擎里恒存在，`prefix` 无匹配时按设计返回 `count:0`（非错误）→ 该类不可构造。
代码里另有一条防御分支（单例为 null → `-32000 Not implemented: ProjectSettings` + `data.suggestion`），
在运行的引擎中不可达、也无直接测试，如实记为未覆盖分支（§9 deviation 2）。

### 5.3 `project_get_filesystem_tree`

成功（`max_depth:1`，节选）：

```json
BODY {…"arguments":{"max_depth":1}}}
RESP {"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"tree\":{\"children\":[{\"children\":[…] ,\"name\":\".godot\",\"path\":\"res://.godot\",\"type\":\"directory\"},{\"name\":\"notes.txt\",\"path\":\"res://notes.txt\",\"type\":\"file\"},{\"name\":\"PLAYER_README.md\",\"path\":\"res://PLAYER_README.md\",\"type\":\"file\"},{\"name\":\"project.godot\",\"path\":\"res://project.godot\",\"type\":\"file\"},{\"children\":[{\"name\":\"main.tscn\",\"path\":\"res://scenes/main.tscn\",\"type\":\"file\"}],\"name\":\"scenes\",…},{\"children\":[{\"name\":\"player.gd\",…}],\"name\":\"scripts\",…}],\"name\":\"res://\",\"path\":\"res://\",\"type\":\"directory\"}}","type":"text"}]}}
```

缺参类（`max_depth` 类型错 → `-32602`）：

```json
BODY {…"arguments":{"max_depth":"deep"}}}
RESP {"error":{"code":-32602,"message":"Parameter 'max_depth' must be an integer, got String"},"id":1,"jsonrpc":"2.0"}
```

底层失败（目录不存在 → `-32001` + `data.suggestion`）：

```json
BODY {…"arguments":{"path":"res://__no_such_dir__"}}}
RESP {"error":{"code":-32001,"data":{"suggestion":"Call the tool without 'path' (or with 'res://') to address the project root"},"message":"Directory 'res://__no_such_dir__' not found"},"id":1,"jsonrpc":"2.0"}
```

### 5.4 `project_search_file_names`

成功（`pattern:"player"`；大小写不敏感，命中 `PLAYER_README.md`）：

```json
BODY {…"arguments":{"pattern":"player"}}}
RESP {"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"count\":3,\"matches\":[\"res://PLAYER_README.md\",\"res://scripts/player.gd\",\"res://scripts/player.gd.uid\"]}","type":"text"}]}}
```

缺参（`-32602`）：

```json
BODY {…"arguments":{}}
RESP {"error":{"code":-32602,"message":"Missing required parameter: pattern"},"id":1,"jsonrpc":"2.0"}
```

底层失败（`path` 不存在 → `-32001`）：

```json
BODY {…"arguments":{"pattern":"player","path":"res://__no_such_dir__"}}}
RESP {"error":{"code":-32001,"data":{"suggestion":"Call the tool without 'path' (or with 'res://') to address the project root"},"message":"Directory 'res://__no_such_dir__' not found"},"id":1,"jsonrpc":"2.0"}
```

### 5.5 `project_search_file_contents`

成功（逐行 `{file,line,text}` + `query`；大小写**不敏感**）：

```json
BODY {…"arguments":{"pattern":"PlayerHealth"}}}
RESP {"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"count\":3,\"matches\":[{\"file\":\"res://PLAYER_README.md\",\"line\":2,\"text\":\"the player reads playerhealth\"},{\"file\":\"res://scripts/player.gd\",\"line\":3,\"text\":\"# PlayerHealth keeps the player alive\"},{\"file\":\"res://scripts/player.gd\",\"line\":5,\"text\":\"var label := \\\"PlayerHealth\\\"\"}],\"query\":\"PlayerHealth\"}","type":"text"}]}}
BODY {…"arguments":{"pattern":"playerhealth"}}}      ← 同一工程、同一语义输入的小写形态
RESP {"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"count\":3,\"matches\":[…同上 3 条…],\"query\":\"playerhealth\"}","type":"text"}]}}
```

缺参 / 底层失败：`{"code":-32602,"message":"Missing required parameter: pattern"}`、
`{"code":-32001,…"Directory 'res://__no_such_dir__' not found"}`（原文同 §5.4 形状，此处不重复）。

### 5.6 `project_find_files_referencing_symbol`

成功（按文件聚合 `{file,lines[]}` + `pattern`；**大小写敏感**）：

```json
BODY {…"arguments":{"pattern":"PlayerHealth"}}}
RESP {"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"count\":1,\"matches\":[{\"file\":\"res://scripts/player.gd\",\"lines\":[3,5]}],\"pattern\":\"PlayerHealth\"}","type":"text"}]}}
```

**GDR-17 直接检验点（同一工程、同一输入形态，两者结论不同）**：

```json
BODY {…"arguments":{"pattern":"playerhealth"}}}
RESP {"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"count\":0,\"matches\":[],\"pattern\":\"playerhealth\"}","type":"text"}]}}
```
→ 与 §5.5 的 `count:3` 对照：**逐行 vs 聚合、不敏感 vs 敏感**确有差异，**未被实现成同一个**。

缺参（`-32602`）：`{"error":{"code":-32602,"message":"Missing required parameter: pattern"},"id":1,"jsonrpc":"2.0"}`
底层失败：该工具契约**没有 `path` 参数**，扫描恒从 `res://` 起（`open_project_dir("res://")` 失败 → `-32001`
是代码里唯一的底层分支），在活工程里**不可达** → 已按 §9 deviation 3 显式登记。可核验的替代证据：
①该分支复用的是与 §5.3/§5.4/§5.5 相同的 `MCPTools::open_project_dir`（那三条真实响应已证明其 `-32001` 形状）；
②该工具的成功路径（`{pattern,matches[],count}` 空结果形状）由 doctest 覆盖：
`[MCPServer] the two de-merged search tools stay distinct (GDR-17)` 用必然不存在的 pattern 调用它并断言
`count==0`、`pattern` 原样回显、`matches` 为空、且**没有** `query` 键（与 §5.5 的形状区分）。
**没有**直接触发它的 `-32001` 的测试——如实记录为未覆盖分支。

---

## 6. 门（全部真实输出 + 退出码）

构建命令统一为（**必须用 pwsh/cmd，不能用 Git Bash**：`MSYSTEM` 会让 SCons 去
`bin/build_deps` 找 AccessKit/D3D12 依赖而 exit 255——本任务第一版构建的真实翻车）：

```
D:\Anaconda\Scripts\scons.exe platform=windows target=editor tests=yes module_mono_enabled=no -j8
```

### 6.1 模块 doctest（`--test-case=[MCPServer]*`）

```
.\bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"
[doctest] test cases:  53 |  53 passed | 0 failed | 1429 skipped
[doctest] assertions: 410 | 410 passed | 0 failed |
[doctest] Status: SUCCESS!
EXIT=0
```
（M1 基线 39 例 / 267 断言；本任务 +14 例 / +143 断言。）

**TDD 红阶段证据**（先写测试、构建后运行，暴露 2 个真实缺陷，修完转绿）：

```
[doctest] test cases:  53 |  51 passed | 2 failed | 1429 skipped
[doctest] assertions: 404 | 401 passed | 0 failed | ← 3 assertions failed
.\modules/mcp_server/tests/test_mcp_server.h(726): ERROR: CHECK( reason.is_empty() ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(1076): ERROR: CHECK( contents_description.contains("逐行") ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(1078): ERROR: CHECK( references_description.contains("按文件聚合") ) is NOT correct!
```
- 前者是**产品缺陷**：`ToolBuilder::build()` 成功后不清空 `r_reason`，把上一次失败原因留给调用方 → 已修（build 开头清空）。
- 后者是**测试缺陷**：`String(const char*)` 按 Latin-1 解码（模块文件开头注释早有规定），中文断言必须走
  `String::utf8` → 已修，避免把「真通过」写成「假失败」的反面（更危险的是反向的假通过）。

### 6.2 全引擎 `--test`

```
.\bin\godot.windows.editor.x86_64.console.exe --headless --test
[doctest] test cases:   1479 |   1479 passed | 0 failed | 3 skipped
[doctest] assertions: 424691 | 424691 passed | 0 failed |
[doctest] Status: SUCCESS!
EXIT=0
```
基线 1465 + 新增 14 例 = **1479**，0 failed（只增不减）。

### 6.3 `accept_m1.ps1` ×2

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\modules\mcp_server\scripts\accept_m1.ps1
```
两次（run A / run B）均 **21/21 cases passed，EXIT=0**，PASS 清单一致：

```
PASS case1_GET_mcp_200 | case2_initialize | case3_tools_list_fixture | case4_tools_call_project_info
PASS case5_tools_call_invalid_params | case6_unknown_method | case7_parse_error | case8_concurrent_100
PASS case9_keep_alive_two_requests | case10_half_packet | case11_body_too_large | case15_connection_reaping
PASS case16_expect_100_continue | case17_header_too_large_431 | case18_bare_lf_terminator_400
PASS case19_invalid_utf8_body_warns | case12_game_process_endpoint | case13_game_without_port
PASS case14_port_occupied | guard_user_port_9877 | gate_scope_declared
21/21 cases passed
implemented tools = 6; contract = 171; known_deviation = per-batch verbatim gate only
```
（`case1` 的 `status.tools` 已按 6 校验；`case3`/`case12` 的逐字门覆盖这 6 个工具；
`guard_user_port_9877` 两次都记录 `pid_before=36392 pid_after=36392`。）

### 6.4 契约子集对等门（**新增** `scripts/check_contract_subset.ps1`）

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\modules\mcp_server\scripts\check_contract_subset.ps1
group       : project_read_template
tools       : project_get_info, project_get_settings, project_get_filesystem_tree, project_search_file_names, project_search_file_contents, project_find_files_referencing_symbol
contract    : 171 entries
[PASS] editor_9888_contract_subset
       editor port=9888 tools=6 order=project_get_info > project_get_settings > project_get_filesystem_tree > project_search_file_names > project_search_file_contents > project_find_files_referencing_symbol | project_get_info: name=True description=True inputSchema=True | project_get_settings: name=True description=True inputSchema=True | project_get_filesystem_tree: name=True description=True inputSchema=True | project_search_file_names: name=True description=True inputSchema=True | project_search_file_contents: name=True description=True inputSchema=True | project_find_files_referencing_symbol: name=True description=True inputSchema=True
[PASS] game_9889_contract_subset
       （同上，game port=9889 tools=6 …）
[PASS] guard_user_port_9877
       pid_before=36392 pid_after=36392
3/3 checks passed
EXIT=0
```
脚本自起引擎（`-e` 编辑器 9888 / `--headless` 游戏 9889）、自建 scratch 工程、只杀自己起的 PID；
缺参/多余即失败；支持 `-Group`（读 `tool-groups.json`）或 `-Tools a,b,c`；`-SkipEditor/-SkipGame` 可单侧跑。

---

## 7. 新指纹（字节数 + sha256）

| 文件 | bytes | sha256 |
|---|---|---|
| `docs/tools_list.renamed.json` | 98923 | `898d868278147cb6f11e83fe11e4e065fb9aa66d13b0a801d81a89354618d57b` |
| `docs/TOOL-NAMING.md` | 98462 | `f68f1551dc01a72331ae9b1590a8ed9167102c10a947a8f1607bfae0b2561d59` |
| `docs/tool-groups.json` | 5443 | `9644911a01e983e69074b7988462789388e2dc59e17c74308fabb368d2ab0e59` |
| `docs/tool-rename-map.json`（未改） | 70917 | `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd` |
| `scripts/gen_renamed_contract.py` | 21390 | `179959e408eb16c8f85324670e945567028ff87fbe0d10ea731072a87eba7496` |
| `scripts/accept_m1.ps1` | 52075 | `a759d9977c52032e47ccae57bf0aad98df533a65f8e41244cda1fc88c6949fc2` |
| `scripts/check_contract_subset.ps1` | 17788 | `c167e747627d4c1338149db899985b4b1f03ea353a1b05d62214e5d9bb7528c2` |
| `docs/scripts/gen_table.py` | 25710 | `54bb66645e698b922d338cc7f58a618e16171955c154de8dd35362411613410b` |
| `docs/scripts/check_tool_groups.py` | 6431 | `b1ccbd07c22b0ac6a5f10c38796ed1aed61fa845287b5efa006450e8d4c9f7ca` |

`docs/tool-rename-map.json` **一个字节都没动**（映射 v1.1 不变，v1.2 只动契约描述）。

---

## 8. 剩余 B1 的并行拆分建议（基于 `tool-groups.json`）

**派发顺序建议**（依赖与风险从低到高）：

1. `project_read_analysis`（7，project/read，无写风险）——最像模板组，可与
   `project_read_files`（6）**同时派**（组间零共享文件，两组都只 projections 磁盘读取）。
2. `editor_read_scene_inspector`（7，editor/read）——第一次碰编辑器 API，是
   `MCP_EDITOR_TOOLS_ENABLED` 守卫与 `scope=EDITOR` 的实战检验点；建议单独一批。
3. `project_write_resource_scene`（4，project/write）——第一批写盘工具，三类证据的「底层失败」
   必须覆盖 `res://` 不可写/路径不存在；`project_edit_resource` 的读改写语义要与参照逐字对齐。
4. `editor_write_scene_editor`（10，editor/write）——**风险最高**，必须单独一批、且**先处理
   `editor_remove_output_log`**（映射表 `fix_implementation_first`：先写红测试再修实现，
   参照实现的 `clear_output` 有已知行为缺口），其余 9 个含条件写
   `editor_capture_screenshot`（GDR-18: `mutating=true`，`save_path` 非空即落盘）。
5. `running_game_read_scene`（1）——单工具但**必须走游戏进程 9889 门**（`scope=GAME`，编辑器的
   `tools/list` 里绝不能出现），建议与 (2) 或 (4) 同批但**独立验证 9889**。

**每组都必须自带**：`docs/tool-groups.json` 组名 + `scripts/check_contract_subset.ps1 -Group <name>`
（9888 与 9889 各一次）+ doctest + 全引擎 0 failed + 三类证据。写盘组额外需要「写后读回」的正向证据与
「路径不存在」的负向证据；editor 组额外需要「游戏进程 tools/list 不含该组」的反向证据。

**系统性风险**：①`editor_*` 组越多，`is_editor_hint()` 的注册守卫越关键（现在的守卫是「不注册」，
若某组用裸 `registry.register_tool` 绕过 `ToolBuilder` 就会漏守卫——建议在 review 时
`grep -n "\.register_tool(" tools/` 只应出现在 registration 相关处）；②`-32001` 语义按 GDR-14
只用于「工具内部找不到资源」，写盘组不要拿它当「参数错」；③契约 `description` 若后续再改，
必须再走 `DESCRIPTION_OVERRIDES`（append-only 自检会拦住直接改契约文件）。

---

## 9. deviations / blockers / next_step_recommendation

### deviations（与任务书的偏离，逐条显式）

1. **组数是 7 而非任务书「建议 4–6 组」**。约束的算术下界就是 7：B1 的 41 个工具按 channel 分是
   project 23 / editor 17 / running_game 1；「每组一个 channel + 一个读写属性」+「每组 ≤10 个工具」
   ⇒ project 至少 3 组（read 19 → 2 组，write 4 → 1 组）、editor 至少 2 组、running_game 1 组，
   合计 7。已按此交付并在 `check_tool_groups.py` 里断言每组的 channel/mutating 与映射表一致。
2. **`get_project_info` / `project_get_settings` 的「三类证据」只有部分可达**：前者无参数且参照实现
   为全函数（缺参/底层失败不可构造，替代证据=传无关参数仍成功）；后者无 `path`/无外部资源依赖
   （缺参类以「可选参数类型错 → -32602」替代，底层失败不可构造）。
3. **`project_find_files_referencing_symbol` 的底层失败类不可达**：契约只给 `pattern`，扫描恒从 `res://`
   起；代码里 `open_project_dir("res://")` 失败 → `-32001` 的守卫真实存在但活工程不可触发。
4. **`-32001` 的语义强于参照实现**：参照实现在 `path` 不存在时**静默返回空结果**；本实现按
   GDR-14 与任务书 §2.4.2 的「底层失败类」要求改为 `-32001 + data.suggestion`。这是**有意的行为差异**，
   已在 §5 用真实响应固定，供决策者裁决（若要求逐字对齐参照，应改成空结果并另找底层失败类）。
5. **`optional_*` 对「出现但类型错」的参数报 `-32602`**（参照实现是静默忽略）。依据任务书 §2.2.2
   「参数校验助手（…失败 → -32602 且信息可读）」。影响面：`project_get_settings.prefix/include_default`、
   `project_get_filesystem_tree.max_depth` 等。
6. **`#ifdef TOOL_ENABLED` 用了等价守卫 `MCP_EDITOR_TOOLS_ENABLED`（仅在 `TOOLS_ENABLED` 下定义）**：
   本 fork 内 `TOOL_ENABLED` 不存在，照抄该拼写会让编辑器分支在编辑器构建里被静默编译掉。
   实测依据：`grep -rno "\bTOOL_ENABLED\b" --include=*.h --include=*.cpp --include=*.py .` 全树仅 **1 命中**，
   且就是我在 `tools/tool_builder.h` 里解释该事实的注释；`SConstruct:564` 只定义 `TOOLS_ENABLED`。
7. **编辑了 `docs/DESIGN-DETAIL.md`**（新增 GDR-19 / §17，并同步 §1 文件布局与 §7 的 `MCPToolDef` 片段）：
   任务书只要求重跑 `gen_table.py` 更新 `TOOL-NAMING.md`。理由：后续并行组会照 DESIGN-DETAIL 实施，
   让规范与已交付代码脱节会把错误设计扩散到 6 个后续组；改动纯为事实对齐 + 新增条款，未改任何既有 GDR 的语义。
8. **工作树残留 `M modules/mcp_server/docs/tasks/TASK-002-b1-framework.md`**：该改动**在我开始前就已存在**
   （我未触碰，未纳入任何提交）。它是交到我手上的任务书版本相对 `1090d04803` 的差异（§2.3 模板组改为
   指定 6 个工具 + 新增 §2.3.1 全 B1 分组）。已刻意不提交他人未定稿的文档；若决策者希望入库，
   可单独 `git add` 该文件。
9. 除上述「未跟踪物 + 该 M」外工作树干净；`git diff --name-only 1090d04803..HEAD` 过滤
   `modules/mcp_server/` 后 **0 命中**。

### blockers

无。

### next_step_recommendation

1. 请决策者对 **deviation 4/5/7** 裁决（`-32001` 强语义、`optional_*` 严格化、DESIGN-DETAIL 改动是否保留）。
2. 裁决后可立即按 §8 的顺序派后续并行任务：先 `project_read_analysis` + `project_read_files`
   （可同时派），再到 editor 两组与 game 组；每组用 `scripts/check_contract_subset.ps1 -Group <name>` 收口。
3. 建议把「所有组必须经 `ToolBuilder` 注册」写成下一批任务书的硬性约束（防止绕过 editor 守卫与
   `mutating` 显式声明）。
4. `editor_remove_output_log`（`clear_output`）进 `editor_write_scene_editor` 时，任务书必须逐字要求
   「先写红测试再修实现」，且不得为过门而先注册。

---

## 10. 勘误（TASK-003 §1.5 / 裁决 D-2；**追加段，以上原文一字未改**）

**结论：§5.5/§5.6（本文件 `:319-344`）里用作「两个工具不是同一套实现」直接检验点的那个实例
——同一输入 `playerhealth` → `project_search_file_contents` `count:3` 而对
`project_find_files_referencing_symbol` `count:0` ——**不成立**；可复现的差异是 **3 vs 1**。**

- **审计方 TASK-AUDIT-002 的复现**（`docs/reports/REPORT-AUDIT-002-b1-framework.md` D-2，`:469-500`；
  自造工程 `%A2%\proj`，`src/case_target.gd` 三行分别是 `FooBar` / `foobar` / `FOOBAR`）：
  pattern **`FOOBAR`** → `project_search_file_contents` = **3 命中**（大小写不敏感，三行全中）/
  `project_find_files_referencing_symbol` = **1 命中**（大小写敏感，只命中真正含 `FOOBAR` 的那一行，
  `lines:[4]`）。
- **因此原文的「`project_find_files_referencing_symbol` = `count:0`」有误。** 原 `count:0` 来自 pattern 取
  **全小写** `playerhealth`；审计方还指出该自述**内部不自洽**（`:475-479`）——那条 `count:3` 的命中列表里
  出现了「文件里就存在小写 `playerhealth`」的文本。补充事实（读源码可得，非推断）：
  `project_find_files_referencing_symbol` 只扫 `.tscn/.gd/.tres/.gdshader`，而 `PLAYER_README.md`
  是 `.md`；`project_search_file_contents` 的白名单包含 `md`，所以那一行只有搜索方能命中。
  无论哪种读法，**「0」都不是「同一输入」上的可复现结论**，可复现的一对数字是 **3 vs 1**。
- **机制与结论不受影响**：两个工具仍是**两套独立实现**（输出形状 逐行 `{file,line,text}` vs 按文件聚合
  `{file,lines[]}`；大小写 不敏感 vs 敏感；上限 50 vs 100），`3 vs 1` 同样证明二者不等价；
  **错的只有「0」这个数字**，实现本身没有任何缺陷（审计方明确写明「不改代码」，`:496`）。
- 保留原文（不删改原句）以便「改动 → 提交 → 决策日志」可追溯；**本段是唯一权威更正**，后续引用以本段为准。

（追加时间：TASK-003 执行期间；依据 `F:\moonbit-hof-rs\DECISIONS.md` D49 对 D-2 的裁决。）

**勘误 2（TASK-004 §3.2）：本文件 `:194` 的注释「只允许 res://、禁 `..` 与空段」已过期。**

- 该行是 §4.2「助手 API 清单」里 `normalize_project_path` 的一句话摘要。**现行权威是
  `docs/DESIGN-DETAIL.md` §17.2**：`..` 在**折叠之前**对原始剩余部分判定并拒绝；而 `.` 段与**空 / 仅空白段**
  是**被折叠掉**的（`res://.` → `res://`、`res://src/.` → `res://src`、`res:// ` → `res://`、`res://a//b` → `res://a/b`），
  这正是 TASK-003 §1.3 的裁决 D-4。也就是说「禁空段」的旧说法与现行行为不同，应以 DESIGN-DETAIL §17.2 为准。
- 原文（含 `:194`）按 **append-only** 约定一字未改，仅追加本行。

（追加时间：TASK-004 执行期间；依据 `docs/tasks/TASK-004-project-read-analysis.md` §3.2。）
