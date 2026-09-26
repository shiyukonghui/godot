# DESIGN-DETAIL — TASK-005（可实施粒度）

工件属阶段三（详细设计）。输入：`REQUIREMENTS.md` + `DESIGN-OVERVIEW.md`。
目标：另一个工程师（或子代理）照着本文件即可实现，**不需要再做设计决策**。

---

## A. 第一部分：框架清理（精确到行级指令）

### A.1 新文件 `tools/tool_helpers.h`（`namespace MCPTools`）

许可证头**逐字复制** `tools/tool_builder.h` 第 1–29 行（同一 Godot 头），然后：

```cpp
#pragma once

#include "core/io/dir_access.h"
#include "core/string/string_name.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "core/variant/variant_internal.h"   // Vector2/3/Color/Rect2 等按需包含，以能编译为准

namespace MCPTools {

// `res://a/b` -> `res://a/b/c`; the root keeps exactly one slash.
String join_path(const String &p_dir, const String &p_entry);

// Rust's `str::lines()` ...
Vector<String> split_lines(const String &p_text);

// Mirrors `serialize_variant` of the reference implementation ...
Variant serialize_variant(const Variant &p_value);

// Mirrors `collect_files_by_ext` of the reference ...
void collect_files_by_extension(const String &p_path, const Vector<String> &p_extensions,
		bool p_include_addons, Vector<String> &r_out);

} // namespace MCPTools
```

函数体**逐字**取自 `tools/project_read_analysis.cpp` 现有定义（`_join_path` 第 73–78 行、
`_split_lines` 第 85–102 行、`_serialize_variant` 第 202–308 行、`_collect_files_by_extension` 第 159–196 行），
**只**把 `static` 去掉、名字去掉前导 `_`、递归自调用改名。注释里原有的那条
「a few helpers are reproduced here instead of being shared」说明必须**删掉**并换成「唯一共享定义」的说明。

### A.2 新文件 `tools/tool_helpers.cpp`

包含 `tool_helpers.h`，函数体照搬；`_collect_files_by_extension` 内部对
`join_path(...)` 的调用改名（**不要**再复制一份 `_join_path`）。

### A.3 两组成员文件的改动（最小 diff）

`tools/project_read_analysis.cpp`：
1. 删除第 61–196 行那一段「Shared helpers」里的 `_join_path`、`_split_lines`、`_serialize_variant`、
   `_collect_files_by_extension` 四个定义；
2. **保留** `_path_attribute`、`_extension_set`、`_resource_extensions`、`_reference_extensions`、
   `_scene_extensions`（组特有，不上提）；
3. 全部调用点改名：`_join_path`→`join_path`、`_split_lines`→`split_lines`、
   `_serialize_variant`→`serialize_variant`、`_collect_files_by_extension`→`collect_files_by_extension`；
4. 新增 `#include "tool_helpers.h"`。

`tools/project_read_template.cpp`：
1. 删除 `_join_path`（第 198–204 行）、`_split_lines`（第 206–227 行）两个定义；
2. `_serialize_variant`（第 64–173 行）**逐字比较**与 A.1 中上提版本是否一致：
   - 一致 → 删除本地定义，调用点改用 `serialize_variant`；
   - **不一致** → 不要删！保留本地版本、不改为共享调用，并在报告 `deviations` 登记「template 与 analysis 的
     serialize_variant 语义不逐字一致」。**注意**：删本地版本前必须逐字节 diff 两份函数体（可
     `git show HEAD:<path>` 或直接 `sed -n` 抽取比较），不得凭印象。
3. 全部调用点改名；
4. 新增 `#include "tool_helpers.h"`。

> `template` 组的 `_trim_stars`、`_get_project_string`、`_get_screen_size`、`_search_*`、`_scan_*`、
> `_has_reference_extension` **一律不动**（它们不是本任务点名的 4 个助手，且 `_get_screen_size` 依赖
> 编辑器守卫）。

### A.4 断言「同一函数只有一个定义」

```powershell
# 期望：每个名字恰好 1 处「定义」（tools/tool_helpers.cpp），加上头里的 1 处声明
rg -n "^(String|Vector<String>|Variant|void) (join_path|split_lines|serialize_variant|collect_files_by_extension)\b" modules\mcp_server\tools\
# 反例检查：期望 0 行
rg -n "static (String _join_path|Vector<String> _split_lines|Variant _serialize_variant|void _collect_files_by_extension)" modules\mcp_server\tools\
```

### A.5 重构等价性证据（AC-2，先做重构、后做新组，顺序不可颠倒）

1. **重构前**：在**当前 HEAD 的构建产物**上，起 9888（编辑器 scratch 工程），用
   `curl.exe -s -X POST -H "Content-Type: application/json" --data-binary @body.json http://127.0.0.1:9888/mcp`
   采集一组**固定请求**的**完整响应体**，写进 `%TEMP%\mcp-t005-equiv\before\`：
   - `tools/list`（并集 13 条的完整清单，含每一字节）
   - 已实现两组各 3 个工具：`project_read_template` 取 `project_get_info`、`project_get_settings`、
     `project_search_file_contents`；`project_read_analysis` 取 `project_get_statistics`、
     `project_detect_circular_dependencies`、`project_find_script_references`——参数固定，
     且**必须落在同一 scratch 工程**上（否则路径/计数不同）。
   - 另加 9889（游戏进程）的 `tools/list` 一份。
2. **重构后**：重新构建，以**同一 scratch 工程、同一端口、同一请求体**再采一次到 `after\`。
3. 比较：文件长度相等 + 逐字节相等 + sha256 相等；把 `before/after` 两个 sha256 与逐字节结果贴进报告
   「重构等价性证据」一节。**不得**只比较解析后的 JSON（键序/空白/转义差异必须被抓到）。

---

## B. 第二部分：6 个工具的可观察契约（**权威**）

统一：`channel=project`、`mutating=false`、`scope=MCPToolScope::BOTH`；`description` 与 `inputSchema`
**逐字**抄自 `docs/tools_list.renamed.json`（下表只给字段名，抄写时以该文件为准）。
`verb` 取自 `docs/tool-rename-map.json`。注册顺序 = `docs/tool-groups.json` 的 `tools` 数组顺序。

### B.1 `project_list_scripts`（旧 `list_scripts`，`scripts/script.rs:68`）

| 项 | 值 |
|---|---|
| 参数 | 无（`{"type":"object","properties":{},"required":[]}`） |
| verb | `list` |
| 成功返回 | `{"scripts":[<路径>...],"count":<N>}`（`scripts` 是**路径字符串数组**，不是对象数组——迁移源如此） |
| 遍历规则 | 从 `res://` 递归；**仅**跳过名为 `"."`/`".."` 的项（**不跳过** `.godot`、`.import` 等其它隐藏项，**不下钻限制**：`addons` 也进）；文件取 `ends_with(".gd") \|\| ends_with(".gdshader")`，**大小写敏感** |
| 路径拼接 | 根为 `res://` 时 `res://<name>`，否则 `<dir>/<name>`（与 `join_path` 的语义一致，注意根特例不得产出 `res:///x`） |
| 上限 | 无（迁移源无上限） |
| 确定性 | 用**目录扫描顺序**，同一次构建/同一棵树可复现；不得把 `HashMap` 迭代序写进响应 |
| 错误 | 契约无必填参数 ⇒ **不存在缺参类**；`res://` 不可读时按迁移源**返回空列表**（`count:0`），不编造错误 |

> 注意与 `project_get_statistics` 的 `gd` 计数**不是同一个东西**（后者跳过一切 `.` 开头项且默认不读 addons）。
> 这是刻意保留的组间差异，**不得**统一。

### B.2 `project_read_script`（旧 `read_script`，`script.rs:73`）

| 项 | 值 |
|---|---|
| 参数 | `path`（string，**必填**） |
| verb | `read` |
| 成功返回 | `{"path":<归一后路径>,"content":<文件全文>,"size":<content.length()>}` |
| 编码 | 经 `MCPTools::read_project_text_file`（UTF-8，与迁移源 `FileAccess::get_as_text` 一致） |
| 大小写 | 路径**大小写敏感**（`FileAccess` 语义，Windows 上由引擎处理，不得自行 `to_lower()`） |
| 上限 | 无截断（与迁移源一致） |
| 错误 | 缺 `path` → `-32602`；`read_project_text_file` 打不开 → `-32001` + `data.suggestion`（PLAYBOOK §6.1） |
| 行号 | **不返回行号**（迁移源无行号；TASK-005 §2.2 要求对照写明） |

### B.3 `project_validate_script`（旧 `validate_script`，`script.rs:158`）

| 项 | 值 |
|---|---|
| 参数 | `path`（string，**必填**） |
| verb | `validate` |
| 成功返回（可编译） | `{"path":<归一>,"valid":true,"message":"Script compiles successfully"}` |
| 「校验失败」返回 | **仍是成功响应**（不是 JSON-RPC 错误）：`{"path":<归一>,"valid":false,"error_text":<错误码名>,"message":"Compilation failed. Check the script for errors."}` |
| 错误 | 缺 `path` → `-32602`；文件不存在 → `-32001` + `suggestion`（迁移源用 `not_found(&format!("Script '{}'", path), "")`） |
| 实现要求 | **spike 先行**（见 A/§D）：在 doctest 进程实测「构造脚本语言实例 → 设源码 → 编译」是否可用且不崩。可用即用真实编译结果；不可用则退化为**诚实的启发式检查**，措辞**不得**声称语法正确，并在报告 `deviations` 登记（含实测输出） |

### B.4 `project_read_resource`（旧 `read_resource`，`resource.rs:75`）

| 项 | 值 |
|---|---|
| 参数 | `path`（string，**必填**） |
| verb | `read` |
| 成功返回 | `{"path":<归一>,"type":<resource->get_class()>,"loaded":true}` |
| 加载 | `ResourceLoader::load(归一化路径)` |
| 上限/大小写 | 无上限；路径不大写转换 |
| 错误 | 缺 `path` → `-32602`；加载返回 null 或资源不存在 → `-32001` + `suggestion`（迁移源 `not_found("Resource 'x'", "")`） |
| 明确不做 | **不**序列化资源属性、**不**返回 `properties`（见 DESIGN-OVERVIEW §5；差异须在报告逐条写明，作为 deviation） |

### B.5 `project_get_resource_preview`（旧 `get_resource_preview`，`resource.rs:278`）

| 项 | 值 |
|---|---|
| 参数 | `path`（string，**必填**）、`max_size`（integer，可选，**默认 256**） |
| verb | `get` |
| 成功返回 | `{"image_base64":<标准 base64 PNG>,"width":<输出宽>,"height":<输出高>,"format":"png","path":<归一>}` |
| 分支 1 | 扩展名（`path.get_extension().to_lower()`，**无点**）∈ {`png`,`jpg`,`jpeg`,`bmp`,`webp`,`svg`} → `Image::load(path)`；失败 → `-32603`（迁移源 `internal("Failed to load image: {:?}")`） |
| 分支 2 | 其它扩展名 → `ResourceLoader::load`；成功则先试 `Object::cast_to<Texture2D>`（取 `get_image()`），再试 `Object::cast_to<Image>`；两者都失败 → 资源类型无预览，迁移源给 `invalid_params`（`-32602`）——**保留该错误类**（这是「参数/对象不适用」而非「不存在」） |
| 缩放 | 当 `width > max_size \|\| height > max_size`：`scale = min(max_size/width, max_size/height)`（double），`new_w = (int)(width*scale)`，`new_h = (int)(height*scale)`，`Image::resize(new_w, new_h)`；否则不缩放 |
| 编码 | `CryptoCore::b64_encode_str(png.ptr(), png.size())`（**禁止** `Marshalls::get_singleton()`） |
| `max_size` 边界 | `<= 0` → `-32602`（显式错误，避免 `Image::resize` 的 `ERR_FAIL`/除零）；类型错 → `-32602` |
| 错误 | 缺 `path` → `-32602`；`path` 不存在（分支 2 的 `ResourceLoader::load` 返回 null）→ `-32001`；图片存在但解码失败 → `-32603` |

### B.6 `project_read_scene_file_content`（旧 `get_scene_file_content`，`scene.rs:228`）

| 项 | 值 |
|---|---|
| 参数 | `path`（string，**必填**） |
| verb | `read` |
| 成功返回 | `{"path":<归一>,"content":<全文>,"size":<content.length()>}` |
| 与 B.2 的关系 | 形状相同、实现可共用同一私有读 helper（如 `_read_text_payload`）；但**描述与错误消息独立**（迁移源分别用「场景文件 'x'」/「File 'x'」），模块内统一英文消息，报告登记语言差异 |
| 上限 | 无截断 |
| 错误 | 缺 `path` → `-32602`；文件不存在 → `-32001` + `suggestion` |
| 明确不做 | 不解析 `.tscn`、不返回节点树、不返回行号（那是别组工具） |

---

## C. 注册与共享文件改动

`tools/project_read_files.h`：许可证头 + `#pragma once` + `#include "../tool_registry.h"` +
顶部注释列出 6 个工具及迁移源位置（照 `project_read_analysis.h` 的写法）+
`void register_project_read_files_tools(MCPToolRegistry &r_registry);`

`tools/registration.cpp`：在 `#include "project_read_analysis.h"` 后追加
`#include "project_read_files.h"`；在 `register_all_tools()` 末尾追加
`register_project_read_files_tools(r_registry);`（**只加这些**，不动既有两行）。

`docs/tool-groups.json`：`project_read_files.implemented` → `true`（**唯一**允许的字节改动）。

`scripts/accept_m1.ps1`：
- `$ToolNames`：在末尾（`project_get_scene_exports` 后）追加本组 6 个名字；
- 三处硬编码计数 `($ToolNames.Count)` 用的是运行时表达式（保持），但脚本头注释与
  `implemented tools = 13` 之类的**字面量输出**要同步为 19。实现者必须 `rg -n "\b13\b" scripts\accept_m1.ps1`
  逐条核对，只改「工具数」语义的那几处，**不得**放松任何断言。

---

## D. 实现顺序（严格 TDD，红 → 绿 → 重构）

1. **重构等价性 baseline**（A.5 第 1 步）——在**未改任何代码**时先采集。
2. 写 `tool_helpers.{h,cpp}` + 改两个成员文件（第一部分）。
3. 构建 → 跑模块 doctest / 全引擎（重构必须零行为变化）→ 重采 A.5 第 2 步并比较。
   **提交 1**：`mcp_server: TASK-005 - hoist shared tool helpers out of the group files (no behaviour change)`
4. **spike**：探查 doctest 进程内 (a) `GDScript` 实例化+编译、(b) `Image::load`/`save_png_to_buffer` 是否可用。
   把探针真实输出记进报告（探针代码定稿前删除）。
5. **红阶段**：写 `tests/test_mcp_server.h` 新用例（见 §E），此时 `project_read_files.*` 尚不存在、
   `tool-groups.json` 尚未置 true；跑模块 doctest，**保存失败输出**。失败原因必须是「工具不存在/计数不符」，
   不是编译错或断言写法错。**提交 2**：`mcp_server: TASK-005 - failing tests for the project_read_files group (TDD red)`
6. **绿阶段**：实现 `project_read_files.{h,cpp}` + 注册 + `tool-groups.json` + `accept_m1.ps1` 清单；
   跑模块 doctest 至全绿。**提交 3**：`mcp_server: TASK-005 - project_read_files group, 6 read-only project tools (TDD green)`
7. **门② 真实证据**：建 `%TEMP%` 证据工程（脚本 / `.gdshader` / `.tres` / `.tscn` / PNG /
   `addons/` / 隐藏目录 / 一个语法错误脚本），对每个工具采成功 / 缺参 / 底层失败三类（用 `--data-binary`);
   编辑器 9888 + 游戏 9889 各一轮。
8. **五道门**：①`check_contract_subset.ps1 -Group project_read_files`（并集语义，期望 19）
   ②三类证据（上一步）③模块 doctest ④全引擎 ⑤`accept_m1.ps1` 连跑两次。
9. **报告** `docs/reports/REPORT-005-project-read-files.md`（PLAYBOOK §4 全节 + 「重构等价性证据」一节）。
   **提交 4**（docs）。

---

## E. 测试策略（必须逐条覆盖；写在 `tests/test_mcp_server.h`）

现有 fixture：`TestMCPServer::ScratchProject`（`res://mcp_server_test_fixture`，构造建树/析构清树）。
本组需要它**新增**素材（可以就地扩展 fixture，注意不得破坏既有 analysis 用例的**精确计数**断言——
若既有断言依赖文件总数/扩展名直方图，新增素材会导致它们变红，**必须**优先用**新增的独立 fixture 目录**
或选在既有无扩展名统计之外的扩展名；`docs/DESIGN-*` 的既有基线断言见 `REPORT-004 §2`）。

| 用例 | 必须断言的内容 |
|---|---|
| `the project_read_files group is registered for both processes` | `get_tool_count()==19`；6 个新名字 `has_tool` 为真；编辑器/游戏两视角都可见（`BOTH`） |
| `project_list_scripts lists scripts and shaders deterministically` | 精确集合（含 `.gdshader`）、`count`、连续两次调用 byte-identical、名字大小写敏感（`X.GD` 不被收） |
| `project_read_script returns the file text verbatim` | `path`/`content`/`size` 三键；`size == content.length()`；中文/CRLF 保真；缺参 `-32602`；不存在 `-32001` 带 `suggestion` |
| `project_validate_script distinguishes valid and broken code` | **仅在 spike 证明 doctest 可用时**断言 `valid==true`/`false` 两例；否则断言「缺参 `-32602` + 文件不存在 `-32001` + 响应形状含 `valid`」，并在报告写明正例由门② 承载 |
| `project_read_resource reports the loaded resource type` | `.tres` 成功形状（`type` 为类名、`loaded==true`）；缺参 `-32602`；不存在 `-32001`；**不得**出现 `properties` 键 |
| `project_get_resource_preview returns a scaled png` | fixture 内放一张已知尺寸 PNG：`width/height` 与 `max_size` 关系正确（如 64×32 的图 + `max_size=16` → 16×8）；`format=="png"`；`image_base64` 非空且可被 base64 解出 `\x89PNG` 魔数（用 `CryptoCore::b64_decode` 或长度/前缀断言）；`max_size=0` → `-32602`；缺参 `-32602`；不存在 `-32001` / 非图片资源 `-32602` |
| `project_read_scene_file_content returns the raw tscn text` | 形状与 `.tscn` 全文（含 `[gd_scene` 首行）；缺参 `-32602`；不存在 `-32001` |
| `the file readers never write to the project` | 依次调用 6 个工具后 `list_files_recursive(fixture)` 逐字节不变（AC-10） |

> **禁止**写「若 X 不可用则跳过断言」的假通过用例。若某项无法在 doctest 构造，就**不写该断言**，
> 改由门② 真实证据承载，并在报告里显式声明「不可构造及其原因」。

既有用例中需要同步的期望值（红阶段就会暴露）：`[MCPServer] the shared registration entry point
registers the group`（13→19）、`[MCPServer] tools of later batches are not registered`（13→19）。
`tools/list exposes exactly the six template group tools` 用的是**独立**注册表（6 条），**不变**。

---

## F. 报告要素（`docs/reports/REPORT-005-project-read-files.md`）

按 PLAYBOOK §4，另加：
1. 「重构等价性证据」一节：`before/after` 请求清单、每例的长度 + 逐字节结果 + sha256；
2. 「助手唯一性」一节：§A.4 两条 `rg` 的真实输出；
3. 「spike 实测」一节：doctest 内 `GDScript` 编译与 `Image` PNG 能力的真实输出，以及由此得出的取舍；
4. 逐工具表里**明确写出**「迁移源可观察契约 vs C++ 实现」对照（TASK-005 §2.2 要求），
   尤其 `project_read_script`/`project_read_scene_file_content` 是否有行号、字段名是否一致；
5. 不可构造类逐工具声明（PLAYBOOK §3 门② 要求）。