# REPORT-005 — 框架清理（助手去重）+ 移植组 `project_read_files`（6 个只读工具）

- **status**：`pass` — 五道门全绿（退出码 0），无 blocker；工作树除开工前既有的未跟踪物外干净。
- **任务书**：`docs/tasks/TASK-005-project-read-files.md`；通用规范 `docs/tasks/PLAYBOOK-group-port.md`；详细设计 `docs/spec/TASK-005/DESIGN-DETAIL.md`（三者都已完整阅读）。
- **分支**：`feature/mcp-server-module`；**未 push**。
- **范围**：只改 `modules/mcp_server/**`。`F:\moonbit-hof-rs`、`godot_mcp_gdext`、契约/映射/生成器全程**只读**（§6 指纹证明）。
- **端口纪律**：用户编辑器（PID **36392**）占 **9877**，开工前与收尾均为 `LISTENING 36392`；门① 与门⑤ 各自打印
  `pid_before=36392 pid_after=36392`（两次）。测试只用 **9888（编辑器）/9889（游戏）**；scratch 一律在 `%TEMP%`；
  收尾时 9888/9889 上只剩 `TIME_WAIT`，无 `LISTENING`（自己起的 PID 全部已结束）。
- **证据采集**：一律 `curl.exe --data-binary @file`，并用 **`curl.exe --output <file>`** 保存原始字节
  （不能用 PowerShell 管道：`Out-File -Encoding ascii` 会把非 ASCII 字符变成 `?`，第一轮证据就是这样被污染的，
  已重采；见 §5.4）。
  - **勘误补充（TASK-005 修复轮，2026-09-22）**：上面这句声明在写下时**并不完全成立** —— 门② 确实已改用
    `curl.exe --output`，但 **§4 的采集脚本 `%TEMP%\mcp-t005-equiv\capture.ps1:47` 对全部用例仍走了
    `| Out-File -Encoding ascii -NoNewline`**，因此 §4 的 2 条 `tools/list` 行仍带有同一缺陷。
    详见 §4.1 勘误。

---

## 0. commits

| sha | 一行说明 |
|---|---|
| `8386726429` | `mcp_server: TASK-005 - hoist shared tool helpers out of the group files (no behaviour change)`（2 new + 2 M） |
| `4b144e6c1d` | `mcp_server: TASK-005 - failing tests for the project_read_files group (TDD red)`（1 file changed；**含临时探针**，见 §8 deviation 16） |
| `69ccfef13e` | `mcp_server: TASK-005 - project_read_files group, 6 read-only project tools (TDD green)`（2 new + 4 M；**删除临时探针**） |
| 本报告 | 随第四个提交入库（docs only）。 |

`git log --oneline -1` 即本报告的 sha；该提交不包含任何实现改动。

---

## 1. 逐工具表（迁移源可观察契约 vs C++ 实现）

组信息（`docs/tool-groups.json`）：`channel=project`、`mutating=false`、`scope=both`、6 个工具，**无写操作**。
`description` / `inputSchema` 逐字取自 `docs/tools_list.renamed.json`（门① 与门⑤ 双双逐字收口）。
`verb` 取自 `docs/tool-rename-map.json`（`list` / `read` / `validate` / `read` / `get` / `read`）。C++ 落点统一为
`tools/project_read_files.cpp`（注册在文件末 `register_project_read_files_tools`）。

| new_name | 迁移源 | 迁移源可观察契约 | C++ 实现（可观察契约） | 差异 |
|---|---|---|---|---|
| `project_list_scripts` | `script.rs:68` (`cmd_list_scripts`) | 无参数。`{scripts:[路径字符串...], count}`。从 `res://` 递归；**仅**跳过 `"."`/`".."`；`addons`、`.godot`、`.hidden` 等**都下钻**；文件取 `ends_with(".gd") \|\| ends_with(".gdshader")`（**大小写敏感**）。无上限。`res://` 不可读 → 空列表。 | `_collect_scripts_recursive` / `_tool_list_scripts`：`{scripts:[String], count}`，扫描序，无上限。 | **一致**。唯一可见差别是**路径归一**：`join_path` 对根特例与迁移源的 `format!("res://{}")` 逐字节等价（实测无 `res:///x`）。 |
| `project_read_script` | `script.rs:73` (`cmd_read_script`) | `path`（必填）。`{path, content, size}`，`content = FileAccess::get_as_text()`，**无行号、无截断**，路径大小写敏感。缺参 `invalid_params`；打不开 `not_found("File 'x'")`。 | `_read_text_payload` / `_tool_read_script`：`{path, content, size}`，`size = content.length()`。 | ①`path` **归一后回显**（迁移源原样回显）；②不存在 → `-32001` + `data.suggestion`（迁移源 suggestion 为空）；③`size` 是**字符数**不是 UTF-8 字节数（实测见 §5.4）；④错误消息统一英文。**字段名与行号语义完全一致：无 `lines`/`line_numbers` 键，恰好 3 个键**（doctest 用 `payload.size()==3` 钉死）。 |
| `project_validate_script` | `script.rs:158` (`cmd_validate_script`) | `path`（必填）。`exists` 检查 → 读文本 → `GDScript::new_gd()` + `set_source_code` + `reload()`；`OK` → `{path, valid:true, message:"Script compiles successfully"}`；否则 → `{path, valid:false, error_text:"{:?}"（如 ERR_PARSE_ERROR）, message:"Compilation failed. Check the script for errors."}`。**「编译失败」仍是成功响应**（不是 JSON-RPC 错误）。文件不存在 → `not_found("Script 'x'")`。 | `_tool_validate_script`：形状与两条 message 逐字相同；真编译走 `ScriptServer::get_language_for_extension(后缀)` → `ClassDB::instantiate(type)` → `set_source_code` + `reload`（不 include `modules/gdscript`，因此 `module_gdscript_enabled=no` 也能编译本模块）；`error_text` 用 `_error_identifier()` 映射为 `ERR_*` 标识符。 | ①真编译只在 `ScriptServer::are_languages_initialized()` 为真时进行（编辑器/游戏进程：§5.2 证据 05/06 实测 positive/negative 都对）；否则退回**结构检查**并在 message 里明说「没有编译」，`error_text="ERR_PARSE_ERROR"`（引擎无标识符表，见 §3）；②语言按**文件后缀**解析（迁移源恒用 GDScript）；③不存在 → `-32001` + suggestion。 |
| `project_read_resource` | `resource.rs:75` (`cmd_read_resource`) | `path`（必填）。`ResourceLoader::load`；成功 `{path, type: r.get_class(), loaded:true}`；null → `not_found("Resource 'x'")`。 | `_tool_read_resource`：`{path, type, loaded}`，`FileAccess::exists` 先判空再 load。 | ①路径归一后回显；②**不返回 `properties`**（DESIGN-OVERVIEW §5 的窄语义，逐字保留迁移源的 3 键形状，doctest 用 `payload.size()==3` + `has("properties")==false` 钉死）；③不存在 → `-32001` + suggestion。 |
| `project_get_resource_preview` | `resource.rs:278` (`cmd_get_resource_preview`) | `path`（必填）、`max_size`（可选，默认 256）。图片后缀（`png jpg jpeg bmp webp svg`，无点、小写）→ `Image::load`，失败 `internal("Failed to load image: {:?}")`；否则 `ResourceLoader::load` → 先 `Texture2D.get_image()` 再 `Image`，都不行 → `invalid_params("Resource type 'x' does not have an image preview")`。缩放 `scale=min(max/w,max/h)`、`new=(int)(w*scale)`。PNG → base64。返回 `{image_base64,width,height,format:"png",path}`。 | `_tool_get_resource_preview`：同一分支顺序与同一两条错误类；base64 走 `CryptoCore::b64_encode_str`；返回 5 键。 | ①`max_size<=0` → **`-32602`**（迁移源会把 0 交给 `Image::resize`，是 `ERR_FAIL` + 除零）；②`max_size` 类型错 → `-32602`；③`path` 不存在 → **`-32001`**（在分支前判定；迁移源的图片分支会变成 `-32603` decode 失败）；④`ResourceLoader::load` 返回 null → `-32001`（DESIGN §B.5 明定；迁移源是 `-32603`）；⑤base64 **不经** `Marshalls::get_singleton()`；⑥路径归一后回显。 |
| `project_read_scene_file_content` | `scene.rs:228` (`cmd_get_scene_file_content`) | `path`（必填）。`file_exists` → `FileAccess` 只读 → `{path, content, size}`，`size = content.len()`（Rust 字节）。缺参是中文消息；不存在 → `not_found("场景文件 'x'")`。**不解析 `.tscn`、不返回节点树、不返回行号**。 | `_read_text_payload` / `_tool_read_scene_file_content`：与 `project_read_script` 共用读 helper，但**错误措辞独立**（`Scene file 'x'`）；3 键、无行号。 | ①路径归一；②`size` 是字符数不是字节数（与 `project_read_script` 同一个 deviation）；③错误消息英文（`Scene file 'x'`，迁移源中文）；④不存在 → `-32001` + suggestion。**字段名与行号语义一致：恰好 3 键、无 `lines`**。 |

---

## 2. 红/绿证据（TDD）

**红阶段**（`4b144e6c1d` 的树；`project_read_files.{h,cpp}` 尚不存在、`tool-groups.json` 的 `implemented` 仍为 false）：

```
[doctest] test cases:  75 |  64 passed | 11 failed | 1429 skipped
[doctest] assertions: 676 | 612 passed | 64 failed |
[doctest] Status: FAILURE!
EXIT=1
```

11 个失败用例（失败原因全部是「工具不存在 / 计数不符」，不是编译错或断言写法错）：

```
TEST CASE:  [MCPServer] the shared registration entry point registers the group
TEST CASE:  [MCPServer] tools of later batches are not registered
TEST CASE:  [MCPServer] tools/list is byte-identical across consecutive calls
TEST CASE:  [MCPServer] the project_read_analysis group is registered for both processes
TEST CASE:  [MCPServer] the project_read_files group is registered for both processes
TEST CASE:  [MCPServer] project_list_scripts lists scripts and shaders deterministically
TEST CASE:  [MCPServer] project_read_script returns the file text verbatim
TEST CASE:  [MCPServer] project_validate_script distinguishes valid and broken code
TEST CASE:  [MCPServer] project_read_resource reports the loaded resource type
TEST CASE:  [MCPServer] project_get_resource_preview returns a scaled png
TEST CASE:  [MCPServer] project_read_scene_file_content returns the raw tscn text
```

代表性失败断言（原样）：

```
.\modules/mcp_server/tests/test_mcp_server.h(2352): ERROR: CHECK( registry.get_tool_count() == 19 ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(2365): ERROR: CHECK( registry.has_tool(names[i]) ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(2380): ERROR: CHECK_FALSE( tool_error.is_error() ) is NOT correct!
```

构成：**8 个新增用例里的 7 个**红（`the file readers never write to the project` 在红阶段**空真**，如实登记）
＋**4 个既有用例**因期望数 13→19 而红。基线（TASK-004 交付态）**65 例 / 607 断言**。

**绿阶段**（`69ccfef13e`，临时探针已删除）：

```
[doctest] test cases:  73 |  73 passed | 0 failed | 1429 skipped
[doctest] assertions: 726 | 726 passed | 0 failed |
[doctest] Status: SUCCESS!
EXIT=0
```

新增 8 个用例（65→73）、+119 断言（607→726）：

| 用例 | 固定的行为 |
|---|---|
| `the project_read_files group is registered for both processes` | 19 个工具；6 个新名字 `has_tool` 为真、编辑器/游戏两个视角都可见 |
| `project_list_scripts lists scripts and shaders deterministically` | fixture 子树**精确集合**（含 `.hiddendir/secret.gd`、`addons/plug/in_addon.gd`、`.gdshader`）；`count==scripts.size()`；`upper.GD` **不被收**（大小写敏感）；连续两次调用 byte-identical |
| `project_read_script returns the file text verbatim` | 恰好 3 键；`path`/`content`/`size`；`size==content.length()`；CRLF 与中文保真；无 `lines`/`line_numbers`；缺参 `-32602`；不存在 `-32001`+`suggestion`；路径归一后回显 |
| `project_validate_script distinguishes valid and broken code` | `valid` 为 bool；平衡脚本 `true`、不平衡脚本 `false` 且带 `error_text`；两者**在两种模式下答案相同**；缺参 `-32602`；不存在 `-32001`+`suggestion` |
| `project_read_resource reports the loaded resource type` | `.tres` → `type=="Resource"`、`loaded==true`；恰好 3 键、**无 `properties`**；缺参 `-32602`；不存在 `-32001`+`suggestion` |
| `project_get_resource_preview returns a scaled png` | 64×32 + `max_size=16` → 16×8；默认 256 不缩放（64×32）；`format=="png"`；`image_base64` 前缀 + **真 base64 解码出 `89 50 4E 47`**；`max_size=0`→`-32602`；类型错→`-32602`；缺参→`-32602`；不存在→`-32001`；非图片资源→`-32602` |
| `project_read_scene_file_content returns the raw tscn text` | 恰好 3 键；`size==content.length()`；首行 `[gd_scene`；含 `[node name="Main" type="Node2D"]`；缺参 `-32602`；不存在 `-32001`（消息含 `Scene file`） |
| `the file readers never write to the project` | 依次调用 6 个工具后 fixture **11 个文件**的列表逐字节不变（AC-10） |

---

## 3. 助手唯一性（DESIGN-DETAIL §A.4）

`rg.exe` **不在 PATH 上**（实测 `rg NOT found`）。两条检查改用 ripgrep 内核的 harness `grep` 工具执行，
并用 PowerShell `Select-String` 交叉核对；语义与 §A.4 完全一致。**真实输出**：

正向（期望：4 处定义在 `tool_helpers.cpp` + 4 处声明在 `tool_helpers.h`）：

```
F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\tools\tool_helpers.h
Line 61: String join_path(const String &p_dir, const String &p_entry);
Line 68: Vector<String> split_lines(const String &p_text);
Line 73: Variant serialize_variant(const Variant &p_value);
Line 79: void collect_files_by_extension(const String &p_path, const Vector<String> &p_extensions,

F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\tools\tool_helpers.cpp
Line 40: String join_path(const String &p_dir, const String &p_entry) {
Line 47: Vector<String> split_lines(const String &p_text) {
Line 66: Variant serialize_variant(const Variant &p_value) {
Line 174: void collect_files_by_extension(const String &p_path, const Vector<String> &p_extensions, bool p_include_addons, Vector<String> &r_out) {
```

反例（期望 0 行）：

```
No matches found
```

**上提前的逐字节比较**（用脚本对两文件按花括号配对抽出函数体后取 sha256）：

```
==== _serialize_variant
analysis lines 202-308 sha256=09c2d7f9f1cb0adece4b9a009020d86584f229fc570387c3da36b2af1632bda5
template lines 67-173 sha256=09c2d7f9f1cb0adece4b9a009020d86584f229fc570387c3da36b2af1632bda5
byte-identical: True
==== _join_path
analysis lines 73-78 sha256=74987c95f887e4f25ce6d8349e96e9a16602afd64478e147a1eb37e850f886b4
template lines 199-204 sha256=74987c95f887e4f25ce6d8349e96e9a16602afd64478e147a1eb37e850f886b4
byte-identical: True
==== _split_lines
analysis lines 85-102 sha256=3858a839b67d2ec9132bb1c63d5e64d971a0d77263f3ed60a6f2d773e1b9ea94
template lines 210-227 sha256=3858a839b67d2ec9132bb1c63d5e64d971a0d77263f3ed60a6f2d773e1b9ea94
byte-identical: True
==== _collect_files_by_extension
analysis lines 159-196 sha256=38aad12287183817bceebf0fd6f010d9243d0ef23819f4e641536a054be0c5b2
template : ABSENT
```

即：三份重复定义**逐字节相同**（template 的 `_serialize_variant` 与 analysis 的完全一致，**可以删除**），
第四份只有 analysis 有。`project_read_template.cpp` 的本地副本**全部删除**，没有「语义不一致不得不保留」的情况。

---

## 4. 重构等价性证据（AC-2）

**方法**：在**未改任何代码**时用当时的已构建二进制（`bin\...console.exe`，2026/9/22 的 TASK-004 交付产物）采 `before\`；
重构并重建后，用**同一 scratch 工程、同一端口、同一请求体文件**再采 `after\`；比对**长度 + 逐字节 + sha256**
（不是解析后的 JSON，键序/空白/转义差异都会被抓到）。

- scratch 工程：`%TEMP%\mcp-t005-equiv\proj`（`project.godot` + `scripts/equiv.gd`(EQUIV_MARKER) + `scripts/helper.gd`
  + `scenes/equiv.tscn`(EQUIV_MARKER) + `scenes/cycle_a.tscn` ⇄ `cycle_b.tscn` + `resources/{equiv,other}.tres`
  + `addons/plug/plugin.cfg`）。先跑一次 `--import` 与一次**丢弃的 warm-up 采集**，让 `.uid`/`.godot` 落定，
  避免「首次运行生成 sidecar」污染 before/after 比较（warm-up 与 before 的 8 个 sha256 完全相同，证明状态已稳）。
- 请求体：`%TEMP%\mcp-t005-equiv\bodies\01..07.json`，两轮**复用同一批文件**（其 sha256 见下表末），
  全程 `curl.exe --data-binary @file --output <raw bytes>`。
  **勘误（2026-09-22）**：最后这句与实际脚本不符 —— `capture.ps1` 实际用的是 `| Out-File -Encoding ascii`
  （见 §4.1）；下表 6 条 ASCII 工具调用不受影响，但 2 条 `tools/list` 行已作废。

| 用例（9888 编辑器） | before 长度 | after 长度 | sha256（before = after） | 逐字节相同 |
|---|---|---|---|---|
| `01 tools/list` ⚠️**已作废，见 §4.1 勘误**（真实 13 工具 = **4229** 字节） | ~~3411~~ | ~~3411~~ | ~~`cf74a90b9708093e99c9a622e761d56411a056dcf9e186c20b14587e9ed6df72`~~ | ~~**True**~~ |
| `02 project_get_info` | 187 | 187 | `dfd2db52b7717f4f8cc5b5c533bcaf0110fb054ac9c446f1c56129b74511f9a7` | **True** |
| `03 project_get_settings`（prefix `application/`） | 1867 | 1867 | `595cdca41005cb39006ae221e7d42ed9b57629c538122d8367430757aaca3942` | **True** |
| `04 project_search_file_contents` | 304 | 304 | `9eca624fea9851fe5d40017b088cfcd5388bd729536c098d3da524a0f976a141` | **True** |
| `05 project_get_statistics` | 310 | 310 | `03858601f26b590e8eeaa1af1dcebbae6a892b24976d3afdb89e462ce587ce4d` | **True** |
| `06 project_detect_circular_dependencies` | 415 | 415 | `3dcf902b842d28dc2dee0bc48cc823fe38f3401e8792827b9797df83e1745941` | **True** |
| `07 project_find_script_references` | 344 | 344 | `3f67207a1f133b00c7448d6e0d48f6b258a63b6851822ca755aad78d2a94fee2` | **True** |
| `game 9889 tools/list` ⚠️**已作废，见 §4.1 勘误**（真实 13 工具 = **4229** 字节） | ~~3411~~ | ~~3411~~ | ~~`cf74a90b9708093e99c9a622e761d56411a056dcf9e186c20b14587e9ed6df72`~~ | ~~**True**~~ |

请求体（两轮字节相同，sha256）：

```
01_tools_list                              17b0e4fe8898d0f7b668dd1437d3078266e8d170bc490ebbb012e2bbbcd7b913
02_project_get_info                        e7e1d25cad97c9ad18133498f2b824e824e68f0a436d354ab585abe6cf9fc236
03_project_get_settings                    7bd78299a34916b86aa1296debbf9a1322e40d831ee14d7b3bd95945a12132e2
04_project_search_file_contents            899389bec486ddb9e5bc4133eb502d7250036a622fba1559d3ba8d903f7e6efa
05_project_get_statistics                  3aef0a549ca9415e694244f7ae6a4abe7c19a3f8d000e74215d4fd2b63f8331c
06_project_detect_circular_dependencies    29cf0bb2b9c4d8530f823ab61957a0c58b8cb337ec10008800a985e5dfd5fbe5
07_project_find_script_references          bafeee7bdcaf0f460f93eb3d7bf5ce976668d4877d05031cfbf317862c3fab51
```

**结论（勘误后，2026-09-22）**：8 个用例中 **6 个 ASCII 工具调用（02–07）+ 2 个重采的 `tools/list`
全部长度相等、逐字节相等、sha256 相等 —— 重构零可观察行为变化。**
（原句写「8/8」时其中 2 例 `tools/list` 的字节来自有损采集，已作废；修正见 §4.1。02–07 六例为纯 ASCII，
有损管道对其无损，原值有效且未被改动。）
（`tools/list` 的 **4229** 字节 / 13 条即重构后的旧并集〔原写 3411，为采集损坏值，已更正〕；
本组落地后 HEAD 为 19 条，见 §4.1 的 P2 与门⑤ case20。）

### 4.1 勘误（2026-09-22，TASK-005 修复轮）：2 条 `tools/list` 证据作废与字节保真重采

> 本节是 **append-only 勘误**；§4 正文原样保留，只把作废的两行划掉并标注。

**（1）原两行为何失效 —— 确定性证明，不是推断**

§4 的采集脚本 `%TEMP%\mcp-t005-equiv\capture.ps1` 第 47 行是：

```powershell
& curl.exe -s -X POST -H "Content-Type: application/json" --data-binary "@$bodyFile" "$url" `
   | Out-File -FilePath $respFile -Encoding ascii -NoNewline
```

PowerShell 5.1 会把管道中的字节流**按文本行解码、再以 ASCII 重编码**：每个非 ASCII 字符（3 个 UTF-8 字节）
塌成 1 个 `?`（0x3F）。原始字节实测：

```
stored before\01_tools_list.resp : len=3411 0x3F=409 nonzero-high=0
stored after \01_tools_list.resp : len=3411 0x3F=409 nonzero-high=0   (两者 sha256 相同)
干净重采（本次）                  : len=4229 0x3F=0   nonzero-high=1227
算术 : (4229-3411)/2 = 409    ;    1227/3 = 409    ;    409 = stored 的 0x3F 计数
```

`4229 − 3411 = 818 = 2 × 409`，而干净响应里恰有 `409` 个非 ASCII 字符（`1227 / 3 = 409`）。
即**每个非 ASCII 字符从 3 字节塌成 1 字节**——这是恒等式，证明 3411 只可能来自采集损坏，
不可能是引擎的真实输出（契约与 C++ 源码里的 description 都是中文；门① 逐字 True 已证活体描述为中文）。

后果：

1. `01 tools/list`（3411/3411）与 `game 9889 tools/list`（3411/3411）是在比较**两份被同样损坏的文件**，
   `?` 把不同中文串抹成同一串，**不构成 `tools/list` 未变的证据**；
2. 报告原写的「`tools/list` 的 3411 字节 / 13 条」是**事实错误**，真实为 **4229 字节 / 13 条**。

**不受影响**：§4 中 6 个工具调用（02–07）的响应全为纯 ASCII，`-Encoding ascii` 对其**无损**，
长度与 sha256 均为真值，本次**未改动**。

**（2）修正后的采集方式（字节保真）**

本次重采**不再用任何 PowerShell 管道承载响应体**，改为让 `curl.exe` 直接写文件：

```powershell
curl.exe -s -o <respfile> -X POST -H "Content-Type: application/json" `
  --data-binary "@<bodyfile>" http://127.0.0.1:<port>/mcp
```

- scratch 工程与请求体与 §4 **完全相同**：`%TEMP%\mcp-t005-equiv\proj`；
  body `%TEMP%\mcp-t005-equiv\bodies\01_tools_list.json`（58 字节，
  sha256 `17b0e4fe8898d0f7b668dd1437d3078266e8d170bc490ebbb012e2bbbcd7b913`，与 §4 表末一致）。
- 端口：编辑器 **9890**、游戏 **9889**（**绝未使用 9877**，全程 9877 的监听者始终是 PID 36392）。
- 启动命令：`--headless -e --path <proj> --mcp-port=9890`（编辑器）/
  `--headless --path <proj> --mcp-port=9889`（游戏）。

**（3）三个测量点**

`8386726429^` 与 `8386726429` 都由我在临时 worktree `F:\mcp-t005-errata-before` 里用
`D:\Anaconda\Scripts\scons.exe platform=windows target=editor tests=yes module_mono_enabled=no -j8`
重新构建（`SCONS_EXIT=0`；全量 00:14:08.92，重构提交增量 00:00:31.98）；P2 用仓库既有二进制。

| 点 | 源码 | 二进制 sha256 | 工具数 |
|---|---|---|---|
| **P0 before** | `8386726429^` = `59f6681316` | `279a05de613172f3be25db7065a002e81343141967a6396db39a329178fb1981` | 13 |
| **P1 after（§4 的真正对照点）** | `8386726429`（重构提交本身） | `9f7147b180cf1427833622cbf10e28e18bdb48010274cf70486be9292084fde2` | 13 |
| P2 HEAD（本组落地后，**不是** §4 的对照点） | `c6fe7d7f00` | `06034dd46626c2edc2ddb3fcb0814c49e773f0c87a3e6ca444c96a4d417d2912` | 19 |

**（4）修正后的真实字节**

```
tag                      tools  len   0x3F  high  sha256
P0 before_editor_9890      13   4229    0   1227  d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80
P0 before_game_9889        13   4229    0   1227  d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80
P1 refactor_editor_9890    13   4229    0   1227  d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80
P1 refactor_game_9889      13   4229    0   1227  d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80
P2 after_editor_9890       19   5392    0   1413  1a055b3214e45f32a357cd1fb55de173da2d493c0b687342a7916ca89111fc9f
P2 after_game_9889         19   5392    0   1413  1a055b3214e45f32a357cd1fb55de173da2d493c0b687342a7916ca89111fc9f
```

**逐字节结论**（对原始字节数组用 `[System.Linq.Enumerable]::SequenceEqual` 逐一比对）：

```
P0_before_editor   vs P1_refactor_editor : lengthEqual=True  bytesEqual=True  shaEqual=True
P0_before_game     vs P1_refactor_game   : lengthEqual=True  bytesEqual=True  shaEqual=True
P0_before_editor   vs P0_before_game     : lengthEqual=True  bytesEqual=True  shaEqual=True
P1_refactor_editor vs P1_refactor_game   : lengthEqual=True  bytesEqual=True  shaEqual=True
P0_before_editor   vs P2_after_editor    : lengthEqual=False bytesEqual=False （13 条 vs 19 条，本就不应相等）
```

即 **§4 的重构等价性主张（P0 vs P1，13 条 `tools/list`）现在由干净字节独立复现：长度相等 + 逐字节相等 +
sha256 相等**；before 与 after 的 sha256 同为
`d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80`。

**独立交叉验证**：我采到的 P0（4229 / `d94a75f3…`）与**独立验收子代理**用其自建重构前二进制采到的
`%TEMP%\mcp-t005-acc\mybefore\01_tools_list.resp` **逐字节相同** —— 两条互相独立的证据链互证。

**（5）为什么 HEAD 不能当 §4 的对照点**

§4 证的是「**上提共享助手**这一次重构零行为变化」，该重构发生在 `8386726429`。
`c6fe7d7f00`（HEAD）在其后又落地了 `project_read_files` 组，**新增 6 个工具**，
所以 HEAD 的 `tools/list` 是 **5392 字节 / 19 条**（P2），与 13 条的 before **本就不应相等**
（这也正是 §4 表末原句「本组落地后为 5393 字节 / 19 条」的意思）。
把 HEAD 当作 §4 的「after」会把「特性新增」误读成「重构改变了行为」；正确对照点是 **P1 = `8386726429`**。

- §6.5 门⑤ `case20` 的 `5393` 是 19 条 `tools/list`、由 `accept_m1.ps1` 的 `Invoke-Mcp`
  （.NET 字符串 → `UTF8.GetBytes`）采集的**干净**字节，因请求体不同比本节的 5392 多 1 字节，
  **未被污染、保持有效**。
- §6.5 `case20` 与本节 P2 的 sha256 不同（`768401f8…` vs `1a055b32…`），差异同样只来自请求体的 `id` 写法，
  两者都是各自请求的真实响应字节。

**（6）本次证据文件与清理**

重采的原始响应留在 `%TEMP%\mcp-t005-errata\captures\*.resp`、导入复核日志在
`%TEMP%\mcp-t005-errata\`（scratch，**刻意不入库**）；重建用的 worktree `F:\mcp-t005-errata-before`
已 `git worktree remove --force` 删除并 `git worktree prune`，`git worktree list` 只剩主工作树，
`.git\worktrees` 不存在。

---

## 5. spike 实测（doctest 进程内的 GDScript 编译与 Image PNG 能力）

探针是**临时 TEST_CASE**（`print_line` 直接写 stdout），在提交 2 中入库、在提交 3 中**已删除**（当前树
`Select-String -Pattern 'SPIKE|print_line'` 命中 **0** 行）。

### 5.1 SPIKE 1（带守卫的探针）

```
SPIKE languages_initialized=0 language_count=1
SPIKE language[0]=GDScript ext=gd
SPIKE classdb_GDScript=1 classdb_Node=1 classdb_Node2D=1
SPIKE compile_attempt=SKIPPED (no initialised script language)
SPIKE image_valid=1 8x4
SPIKE image_load=0 64x32
SPIKE png_bytes=94 magic=89504e47
SPIKE b64_len=128 prefix=iVBORw0KGgoA
[doctest] test cases: 1 | 1 passed | 0 failed | 1502 skipped
[doctest] assertions: 0 | 0 passed | 0 failed |
[doctest] Status: SUCCESS!
```

### 5.2 SPIKE 2（**故意绕过守卫**，直接量「构造 + 设源码 + 编译」在无语言进程里的行为）

```
SPIKE2 language=GDScript type=GDScript
SPIKE2 instantiate=1
SPIKE2 script_valid=1
SPIKE2 before_reload_good
SPIKE2 reload_good=36 name=Compilation failed
SPIKE2 reload_broken=43 name=Parse error
[doctest] test cases: 1 | 1 passed | 0 failed | 1503 skipped
[doctest] Status: SUCCESS!
```

### 5.3 由实测得出的取舍

1. **不 SIGSEGV**，但**无守卫的编译是错的**：`GDScript` 在 `ClassDB` 里存在、实例化成功，可
   `ScriptServer::register_language()` 在模块初始化阶段就跑（所以 `get_language_count()==1`），
   而 `Main::test_setup()` **从不调用 `init_languages()`**，于是 `are_languages_initialized()==false`。
   在没有 init 的语言上编译，**合法的 `extends Node` 脚本返回 36（ERR_COMPILATION_FAILED）**——
   照抄迁移源的写法会把「好脚本」报成 `valid:false`（**假阴性**）。
   → 定稿的守卫是 **`ScriptServer::are_languages_initialized()`**（不是 `get_language_count()>0`）。
2. 编辑器/游戏进程里语言是初始化的，**真编译可用且正确**：门② 证据 05 得到
   `{"message":"Script compiles successfully","valid":true}`，证据 06 得到
   `{"error_text":"ERR_PARSE_ERROR","valid":false}` —— 正例与负例都在真实进程里成立。
3. **doctest 走的是诚实降级分支**（message 里明说没有编译），因此 §E 要求的正/负例在 doctest 里由
   「结构性检查」承载、真编译正负例由**门② 真实工程证据**承载；**没有**写「不可用就跳过」的假通过用例。
4. `error_names[]` 是**散文描述**（`36 -> "Compilation failed"`、`43 -> "Parse error"`），不是 Rust `{:?}` 的
   `ERR_*` 标识符；引擎也没有标识符表。定稿用 `_error_identifier()` 把编译器/解码器**实际会返回**的值映射成
   `ERR_*`，其余回落散文，避免造假标识符。
5. **`Image` 能力全可用**：`create_empty` 正常、`Image::load` 对 64×32 PNG 返回 0、`resize` 后
   `save_png_to_buffer` 得到 94 字节且首 4 字节 `89 50 4e 47`、`CryptoCore::b64_encode_str` 产出 128 字符且前缀
   `iVBORw0KGgo`。因此 `project_get_resource_preview` 的 doctest 正例**用真图、真编解码**，不需要交给门②。

### 5.4 门② 的一处采集缺陷（已修）

第一轮证据用 `curl ... | Out-File -Encoding ascii`，把 `scripts/cjk.gd` 的两个中文字符写成了 `?`
（响应 210 字节）。改用 `curl.exe --output <file>` 保存原始字节后重采（218 字节），并逐字节核对：

```
decoded chars      = 55
utf8 bytes         = 63
reported size      = 55
disk bytes         = 63
has CRLF           = True
has CJK            = True
disk == content    = True
```

即：内容与磁盘**逐字节相同**（UTF-8 + CRLF 保真），`size` 是**字符数 55**，而迁移源 Rust 的 `content.len()`
会报 **63**（字节数）——这就是逐工具表里的 deviation。

---

## 6. 五道门（真实输出 + 退出码）

构建（统一，**pwsh**；`-j8`）：

```
D:\Anaconda\Scripts\scons.exe platform=windows target=editor tests=yes module_mono_enabled=no -j8
```

三次构建均 `SCONS_EXIT=0`，耗时 31s / 37s / 35s（增量）。

### 6.1 门① 契约子集逐字（`check_contract_subset.ps1 -Group project_read_files`）→ **GATE1_EXIT=0**

```
group       : project_read_files
tools       : project_list_scripts, project_read_script, project_validate_script, project_read_resource, project_get_resource_preview, project_read_scene_file_content
implemented : 19 tool(s) across the groups marked implemented: project_get_info, ..., project_read_scene_file_content
contract    : 171 entries

user editor on 9877 before run: pid=36392
importing scratch projects ...
[PASS] editor_9888_contract_subset
       editor port=9888 tools=19 order=project_get_info > ... > project_read_scene_file_content | project_list_scripts: name=True description=True inputSchema=True | project_read_script: name=True description=True inputSchema=True | project_validate_script: name=True description=True inputSchema=True | project_read_resource: name=True description=True inputSchema=True | project_get_resource_preview: name=True description=True inputSchema=True | project_read_scene_file_content: name=True description=True inputSchema=True
[PASS] game_9889_contract_subset
       game port=9889 tools=19 order=project_get_info > ... > project_read_scene_file_content | （6 条同样 name=True description=True inputSchema=True）
[PASS] guard_user_port_9877
       pid_before=36392 pid_after=36392

group=project_read_files tools=6 contract=171
implemented_union=19 tools
3/3 checks passed
```

`check_contract_subset.ps1` **未改动**（并集语义由 TASK-004 修正后已够用）。

### 6.2 门② 三类证据 → 见 §7（编辑器 21 例 + 游戏 21 例，逐字节相同）

### 6.3 门③ 模块 doctest（`--headless --test --test-case="[MCPServer]*"`）→ **EXIT=0**

```
[doctest] test cases:  73 |  73 passed | 0 failed | 1429 skipped
[doctest] assertions: 726 | 726 passed | 0 failed |
[doctest] Status: SUCCESS!
```

基线 65 例 / 607 断言 → **只增不减**（+8 例 / +119 断言）。

### 6.4 门④ 全引擎回归（`--headless --test`）→ **EXIT=0**

```
[doctest] test cases:   1499 |   1499 passed | 0 failed | 3 skipped
[doctest] assertions: 425007 | 425007 passed | 0 failed |
[doctest] Status: SUCCESS!
```

基线 1491 例 / 424888 断言 → +8 例 / +119 断言，**0 failed**。

### 6.5 门⑤ `accept_m1.ps1` 连跑两次 → **A_EXIT=0 / B_EXIT=0**

两次均 **22/22 cases passed**，PASS 清单 `Compare-Object` 差异 **0 行**：

```
PASS  case1_GET_mcp_200 / case2_initialize / case3_tools_list_fixture / case4_tools_call_project_info
PASS  case5_tools_call_invalid_params / case6_unknown_method / case7_parse_error / case8_concurrent_100
PASS  case9_keep_alive_two_requests / case10_half_packet / case11_body_too_large / case15_connection_reaping
PASS  case16_expect_100_continue / case17_header_too_large_431 / case18_bare_lf_terminator_400
PASS  case19_invalid_utf8_body_warns / case20_tools_list_cross_process_restart / case12_game_process_endpoint
PASS  case13_game_without_port / case14_port_occupied / guard_user_port_9877 / gate_scope_declared
22/22 cases passed
implemented tools = 19; contract = 171; known_deviation = per-batch verbatim gate only
```

`case20`（跨进程重启逐字节一致性）两次的真实证据：

```
run A: pid_first=53200 pid_second=47564 tools=19 bytes=5393/5393 byte_identical=True
       sha256_first=768401f893bfa55a7d066cc71dc0edf39b96230138dad5deee1f11d3bffb07b9
       sha256_second=768401f893bfa55a7d066cc71dc0edf39b96230138dad5deee1f11d3bffb07b9
run B: pid_first=35236 pid_second=51684 tools=19 bytes=5393/5393 byte_identical=True
       sha256_first=768401f893bfa55a7d066cc71dc0edf39b96230138dad5deee1f11d3bffb07b9
       sha256_second=768401f893bfa55a7d066cc71dc0edf39b96230138dad5deee1f11d3bffb07b9
```

`guard_user_port_9877` 两次均 `listening=True pid_before=36392 pid_after=36392`；19 条工具
`name_verbatim=True inputSchema_verbatim=True description_verbatim=True`。

### 6.6 AC-11 `check_tool_groups.py` → **EXIT=0**

```
ASSERT  every B1 tool appears exactly once: PASS (duplicates=0, missing=0, foreign=0)
ASSERT  every name exists in the 171 entry contract: PASS
ASSERT  every group is one channel + one mutating value: PASS
ASSERT  41 == 42 - 1: PASS
BYTES 5441
SHA256 5445d39a117626f8ad001dd588b91c1e15784d53bce4d1ef8595dd72d00e1da9
TOOL-GROUPS CHECK PASS
```

---

## 7. 门② 三类证据（真实请求与响应）

### 7.1 证据工程（`%TEMP%`，不入库）

`%TEMP%\mcp-t005-evidence\proj`：

```
project.godot                 name/version + run/main_scene="res://scenes/main.tscn"
scripts/valid.gd              可编译：@export var speed + func ping()
scripts/broken.gd             语法错：func broken( -> void:
scripts/cjk.gd                UTF-8 + CRLF（`var 名称 : String = "中文"`）
shaders/effect.gdshader       shader_type canvas_item;
scenes/main.tscn              [gd_scene ...] + ext_resource + Node2D
resources/simple.tres         可加载但无预览的 Resource
resources/plain.txt           存在但不是可加载资源
images/small.png              64×32 PNG（脚本生成的合法 PNG）
.hidden/secret.gd             隐藏目录：list_scripts 会收
addons/plug/{plugin.cfg,addon_script.gd}   addons：list_scripts 会下钻
```

驱动：每个请求体先写文件，再
`curl.exe -s -X POST -H "Content-Type: application/json" --data-binary @<file> --output <file> http://127.0.0.1:<port>/mcp`；
引擎 `bin\...console.exe --headless [-e] --path <proj> --mcp-port=<port>`（编辑器 9888 / 游戏 9889）。
**全程未占用 9877。**

### 7.2 编辑器 9888（原样粘贴；`id` 即用例号）

```
### 01 project_list_scripts — 成功（无参数）
BODY {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_list_scripts","arguments":{}}}
RESP {"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"count\":6,\"scripts\":[\"res://.hidden/secret.gd\",\"res://addons/plug/addon_script.gd\",\"res://scripts/broken.gd\",\"res://scripts/cjk.gd\",\"res://scripts/valid.gd\",\"res://shaders/effect.gdshader\"]}","type":"text"}]}}

### 02 project_read_script — 成功（UTF-8 + CRLF 保真）
BODY {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"project_read_script","arguments":{"path":"res://scripts/cjk.gd"}}}
RESP {"id":2,"jsonrpc":"2.0","result":{"content":[{"text":"{\"content\":\"extends Node\\n\\nvar 名称 : String = \\\"中文\\\"\\r\\nvar second := 2\\r\\n\",\"path\":\"res://scripts/cjk.gd\",\"size\":55}","type":"text"}]}}

### 03 project_read_script — 缺参
BODY {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"project_read_script","arguments":{}}}
RESP {"error":{"code":-32602,"message":"Missing required parameter: path"},"id":3,"jsonrpc":"2.0"}

### 04 project_read_script — 底层失败
BODY {"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"project_read_script","arguments":{"path":"res://scripts/missing.gd"}}}
RESP {"error":{"code":-32001,"data":{"suggestion":"Use project_get_filesystem_tree to list the files of the project"},"message":"File 'res://scripts/missing.gd' not found"},"id":4,"jsonrpc":"2.0"}

### 05 project_validate_script — 成功且真编译通过（编辑器进程语言已初始化）
BODY {"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"project_validate_script","arguments":{"path":"res://scripts/valid.gd"}}}
RESP {"id":5,"jsonrpc":"2.0","result":{"content":[{"text":"{\"message\":\"Script compiles successfully\",\"path\":\"res://scripts/valid.gd\",\"valid\":true}","type":"text"}]}}

### 06 project_validate_script — 成功但编译失败（仍是 JSON-RPC 成功响应）
BODY {"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"project_validate_script","arguments":{"path":"res://scripts/broken.gd"}}}
RESP {"id":6,"jsonrpc":"2.0","result":{"content":[{"text":"{\"error_text\":\"ERR_PARSE_ERROR\",\"message\":\"Compilation failed. Check the script for errors.\",\"path\":\"res://scripts/broken.gd\",\"valid\":false}","type":"text"}]}}

### 07 project_validate_script — 缺参
RESP {"error":{"code":-32602,"message":"Missing required parameter: path"},"id":7,"jsonrpc":"2.0"}

### 08 project_validate_script — 底层失败
RESP {"error":{"code":-32001,"data":{"suggestion":"Use project_get_filesystem_tree to list the .gd files of the project"},"message":"Script 'res://scripts/missing.gd' not found"},"id":8,"jsonrpc":"2.0"}

### 09 project_read_resource — 成功
BODY {"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"project_read_resource","arguments":{"path":"res://resources/simple.tres"}}}
RESP {"id":9,"jsonrpc":"2.0","result":{"content":[{"text":"{\"loaded\":true,\"path\":\"res://resources/simple.tres\",\"type\":\"Resource\"}","type":"text"}]}}

### 10 project_read_resource — 缺参
RESP {"error":{"code":-32602,"message":"Missing required parameter: path"},"id":10,"jsonrpc":"2.0"}

### 11 project_read_resource — 底层失败
RESP {"error":{"code":-32001,"data":{"suggestion":"Use project_get_filesystem_tree to list the files of the project"},"message":"Resource 'res://resources/missing.tres' not found"},"id":11,"jsonrpc":"2.0"}

### 12 project_get_resource_preview — 成功（64×32 + max_size=16 → 16×8）
BODY {"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"project_get_resource_preview","arguments":{"path":"res://images/small.png","max_size":16}}}
RESP {"id":12,"jsonrpc":"2.0","result":{"content":[{"text":"{\"format\":\"png\",\"height\":8,\"image_base64\":\"iVBORw0KGgoAAAANSUhEUgAAABAAAAAICAYAAADwdn+XAAAAAXNSR0IArs4c6QAAAB5JREFUKJFj5JWS+8/BwMBALmZhEGCgCIwaMBgMAAADbQJKGSugSAAAAABJRU5ErkJggg==\",\"path\":\"res://images/small.png\",\"width\":16}","type":"text"}]}}

### 13 project_get_resource_preview — 成功（默认 max_size=256，不缩放）
BODY {"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"project_get_resource_preview","arguments":{"path":"res://images/small.png"}}}
RESP {"id":13,"jsonrpc":"2.0","result":{"content":[{"text":"{\"format\":\"png\",\"height\":32,\"image_base64\":\"iVBORw0KGgoAAAANSUhEUgAAAEAAAAAgCAYAAACinX6EAAAAAXNSR0IArs4c6QAAAFpJREFUaIHt0LENgDAQBMEHOSImpv8uTRkbeFa6/DTX8377nplTt2bN0QEAAKC+0AYAAID6QhsAAADqC20AAACoL7QBAACgvtAGAACA+kIbAAAA6gttAE4H+AHl/AKz4L8fggAAAABJRU5ErkJggg==\",\"path\":\"res://images/small.png\",\"width\":64}","type":"text"}]}}

### 14 project_get_resource_preview — 缺参
RESP {"error":{"code":-32602,"message":"Missing required parameter: path"},"id":14,"jsonrpc":"2.0"}

### 15 project_get_resource_preview — 底层失败
RESP {"error":{"code":-32001,"data":{"suggestion":"Use project_get_filesystem_tree to list the files of the project"},"message":"File 'res://images/missing.png' not found"},"id":15,"jsonrpc":"2.0"}

### 16 project_get_resource_preview — 资源存在但无预览（-32602）
BODY {"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"project_get_resource_preview","arguments":{"path":"res://resources/simple.tres"}}}
RESP {"error":{"code":-32602,"message":"Resource type 'Resource' does not have an image preview"},"id":16,"jsonrpc":"2.0"}

### 17 project_get_resource_preview — max_size=0（-32602）
BODY {"jsonrpc":"2.0","id":17,"method":"tools/call","params":{"name":"project_get_resource_preview","arguments":{"path":"res://images/small.png","max_size":0}}}
RESP {"error":{"code":-32602,"message":"Parameter 'max_size' must be a positive integer, got 0"},"id":17,"jsonrpc":"2.0"}

### 18 project_get_resource_preview — 存在但不可加载（-32001）
BODY {"jsonrpc":"2.0","id":18,"method":"tools/call","params":{"name":"project_get_resource_preview","arguments":{"path":"res://resources/plain.txt"}}}
RESP {"error":{"code":-32001,"data":{"suggestion":"Use project_get_filesystem_tree to list the files of the project"},"message":"Resource 'res://resources/plain.txt' not found"},"id":18,"jsonrpc":"2.0"}

### 19 project_read_scene_file_content — 成功（原文，含 [gd_scene 首行）
BODY {"jsonrpc":"2.0","id":19,"method":"tools/call","params":{"name":"project_read_scene_file_content","arguments":{"path":"res://scenes/main.tscn"}}}
RESP {"id":19,"jsonrpc":"2.0","result":{"content":[{"text":"{\"content\":\"[gd_scene load_steps=2 format=3]\\n\\n[ext_resource type=\\\"Resource\\\" path=\\\"res://resources/simple.tres\\\" id=\\\"1_r\\\"]\\n\\n[node name=\\\"Main\\\" type=\\\"Node2D\\\"]\\n\",\"path\":\"res://scenes/main.tscn\",\"size\":143}","type":"text"}]}}

### 20 project_read_scene_file_content — 缺参
RESP {"error":{"code":-32602,"message":"Missing required parameter: path"},"id":20,"jsonrpc":"2.0"}

### 21 project_read_scene_file_content — 底层失败（本工具自己的措辞）
RESP {"error":{"code":-32001,"data":{"suggestion":"Use project_get_filesystem_tree to list the .tscn files of the project"},"message":"Scene file 'res://scenes/missing.tscn' not found"},"id":21,"jsonrpc":"2.0"}
```

（02 的中文在终端里按 UTF-8 原样输出；此处粘贴时若终端不接受中文会显示为乱码，字节事实见 §5.4 的
`disk == content = True`。）

### 7.3 游戏进程 9889（同工程、同请求体）

21 例与编辑器**逐字节相同**（`editor-*.resp` vs `game-*.resp`，长度与每字节比较全 True）：

```
case                                           editorB   gameB editor==game
01_list_scripts_success                            280     280 True
02_read_script_success                             218     218 True
03_read_script_missing_param                        93      93 True
04_read_script_bottom_failure                      191     191 True
05_validate_script_success_valid                   170     170 True
06_validate_script_success_invalid                 227     227 True
07_validate_script_missing_param                    93      93 True
08_validate_script_bottom_failure                  197     197 True
09_read_resource_success                           153     153 True
10_read_resource_missing_param                      94      94 True
11_read_resource_bottom_failure                    200     200 True
12_get_resource_preview_success_scaled             314     314 True
13_get_resource_preview_success_default            395     395 True
14_get_resource_preview_missing_param               94      94 True
15_get_resource_preview_bottom_failure             192     192 True
16_get_resource_preview_not_an_image               117     117 True
17_get_resource_preview_max_size_zero              116     116 True
18_get_resource_preview_not_a_resource             197     197 True
19_read_scene_file_content_success                 324     324 True
20_read_scene_file_content_missing_param            94      94 True
21_read_scene_file_content_bottom_failure          205     205 True
ALL_EDITOR_GAME_IDENTICAL = True
```

### 7.4 **不可构造类**的逐工具声明

| 工具 | 成功 | 缺参 | 底层失败 | 声明 |
|---|---|---|---|---|
| `project_list_scripts` | ✅ 01 | ❌ **不存在** | ❌ **不存在** | 契约 `{"properties":{},"required":[]}`，**既没有必填参数也没有可选参数**，缺参类在语义上不存在；该工具**也没有任何错误路径**——`res://` 不可读时按迁移源返回空列表（`count:0`），不编造错误。这是全部 6 个工具里唯一「三类都不可能全构造」的一个，如实声明。 |
| `project_read_script` | ✅ 02 | ✅ 03 | ✅ 04 | 三类全可达 |
| `project_validate_script` | ✅ 05（真编译 positive）/ 06（真编译 negative） | ✅ 07 | ✅ 08 | 三类全可达；**真编译正负两例都有**（§5.3 第 2 条） |
| `project_read_resource` | ✅ 09 | ✅ 10 | ✅ 11 | 三类全可达 |
| `project_get_resource_preview` | ✅ 12 / 13 | ✅ 14（另 16/17 两个 `-32602` 变体） | ✅ 15（另 18 一个 `-32001` 变体） | 三类全可达且各多一个变体 |
| `project_read_scene_file_content` | ✅ 19 | ✅ 20 | ✅ 21 | 三类全可达 |

---

## 8. 文件指纹（sha256 + 字节数）

| 文件 | bytes | sha256 |
|---|---|---|
| `tools/tool_helpers.h`（新） | 4869 | `9c01df9112689b102c14d7d36e517a06fa9c9cbe2f3848eada1c5556a6685d3c` |
| `tools/tool_helpers.cpp`（新） | 6805 | `b38369b0256576755445f5fe6e3a6a0ee7c8f8a17689160d767d1ce2e36d923c` |
| `tools/project_read_files.h`（新） | 3403 | `1f83cfa7f898c2cd4dd3bd6fcabaccef44c3f6888f1ae25affb542de80f14db4` |
| `tools/project_read_files.cpp`（新） | 23354 | `250f24b3848b5a7eef04331d7ea7ca264aa80ce1e1519458c6472a43bcb3e868` |
| `tools/project_read_analysis.cpp`（M） | 38575 | `7302b78e68476fb4fc71d403db0f27da9ed5b43a19a851fe3ed54641ede10cb4` |
| `tools/project_read_template.cpp`（M） | 22401 | `048184815b6159e8196bf659008698e7a05d56e74e6f862f8a046281615e95e6` |
| `tools/registration.cpp`（M） | 2746 | `a0064e8b2556f99452b8caae747fa131e76dfaca4e6469391d4cbcc31c343df5` |
| `tests/test_mcp_server.h`（M） | 123154 | `8ac05dcfc40b460142ffb062ff2e052d9412d5ecb697c203aabef7c7125cb681` |
| `docs/tool-groups.json`（M，1 字节级变更） | 5441 | `5445d39a117626f8ad001dd588b91c1e15784d53bce4d1ef8595dd72d00e1da9` |
| `scripts/accept_m1.ps1`（M） | 56134 | `618996187628029cf493c9fc907697f278279b700557ebfe3db2f931f2913abf` |
| `docs/tools_list.renamed.json`（**未改**） | 98953 | `64723fb9fbe8247512171ee4ae8b6950486bad3722cb957091414b73ecf573f5`（= REPORT-003/004 记录值） |
| `docs/tool-rename-map.json`（**未改**） | 70917 | `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd`（= REPORT-002/004 记录值） |

`docs/tool-groups.json` 相对 REPORT-004 的 `5442 / 3ea451c2…` 只差 `project_read_files.implemented`
`false → true`（5442 → 5441）。

**改动集边界**（`git status --short`）：只剩开工前就存在的未跟踪物
`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`、`modules/mcp_server/docs/spec/`
（最后一项是**决策者开工前**创建的 spec 工件，非本次改动，未纳入任何提交）。
仓库根无残留 fixture 目录（`mcp_server_test_fixture*` 均不存在）。

---

## 9. deviations（与手册/任务书的偏离，逐条显式）

1. **`scripts/accept_m1.ps1` 的 `$ToolNames` 6 → 19 名**（任务书 §3 显式授权）。逐条核对：
   `Select-String -Pattern '\b13\b'` 的 4 处命中**没有一处是工具数**——
   `54: GDR-13`、`156: GDR-13`、`275: -eq 13`（CR 字节值）、`1046: case 13`；
   脚本里工具数全部走运行时表达式 `$ToolNames.Count`（`implementedCount = $ToolNames.Count`、
   `$firstJson.tools -eq $ToolNames.Count`），所以**只加名单、无字面量可改**，也未放松任何断言
   （`$ActualTools.Count -eq $ToolNames.Count` 与 19 条逐字比较都保留）。
2. **`docs/tool-groups.json` 的 `implemented` false→true**（任务书 §3 显式授权），且是门① 并集语义的事实源。
3. **DESIGN-DETAIL §E 的「既有期望值需同步」清单不完整**：它点名 2 个用例（`the shared registration entry
   point registers the group`、`tools of later batches are not registered`），实际有 **4 个**——
   另有 `tools/list is byte-identical across consecutive calls`（`build_tools_list(true).size()`）
   与 `the project_read_analysis group is registered for both processes`（`get_tool_count()`）。
   四处都同步为 19，红阶段全部如实暴露。
4. **`project_validate_script` 的真编译受 `ScriptServer::are_languages_initialized()` 守卫**（§5.3）：
   编辑器/游戏进程真编译（门② 05/06），doctest 进程走结构检查并在 message 里明说没有编译。
   `error_text` 在降级分支固定为 `"ERR_PARSE_ERROR"`（引擎只有散文表，没有标识符表）。
5. **降级分支的启发式是「括号配对」检查**，会跳过 `#` 注释与单/双引号字符串；它**不是 parser**，
   代码注释与响应 message 都不允许把它读成「语法正确」。
6. **`_error_identifier()` 是手写映射**：把编译器/解码器实际会返回的 13 个 Error 值映射为 Rust `{:?}` 的
   `ERR_*` 拼写，其余回落 `error_names[]` 散文。引擎没有可复用的标识符表。
7. **`size` 是字符数不是字节数**：`project_read_script` / `project_read_scene_file_content` 的
   `size = content.length()`（DESIGN §B.2 明定），实测 `cjk.gd` 报 **55** 而文件是 **63** 字节；
   迁移源 Rust 的 `content.len()` 会报 63。**按设计实现，但与迁移源有可见差异。**
8. **`project_get_resource_preview` 的三条语义收紧**：`max_size<=0` → `-32602`；
   路径不存在 → 分支前判定为 `-32001`；`ResourceLoader::load` 返回 null → `-32001`
   （DESIGN §B.5，与迁移源的 `-32603` 不同）。
9. **「存在但不可加载」的路径**（如 `resources/plain.txt`）返回 `-32001 Resource 'x' not found`——
   文件其实存在，消息用了「not found」。这是 DESIGN §B.5「load 返回 null → -32001」的直接结果，
   如实登记为措辞怪癖（语义上它是「无法作为资源加载」，不是「磁盘上没有」）。
10. **`project_read_resource` 不返回 `properties`**（DESIGN-OVERVIEW §5 的窄语义）：`{path,type,loaded}` 恰好 3 键，
    doctest 用 `payload.size()==3` 与 `has("properties")==false` 钉死，防止后续「顺手补全」。
11. **`project_list_scripts` 的三类证据不完整**（§7.4）：它既无必填参数也无任何错误路径，
    「缺参」与「底层失败」在语义上不存在，不是构造失败。
12. **`project_list_scripts` 的 doctest「精确集合」限定在 fixture 子树内**：该工具没有 `path` 参数，
    而 doctest 进程的 `res://` 是整个引擎检出目录，全局精确集合既不稳定也无意义；
    子树内的集合是精确的，且额外钉了「`.hiddendir` 与 `addons` 会下钻」「`upper.GD` 不被收」两条判别点。
13. **重构等价性的 before/after 都做了 warm-up**：先 `--import` 再跑一次丢弃的采集，让 `.uid`/`.godot`
    落定；warm-up 与 before 的 8 个 sha256 完全一致，证明进入比较时状态已稳定。
14. **`rg.exe` 不在 PATH**：DESIGN §A.4 的两条 `rg` 检查用 ripgrep 内核的 harness grep + `Select-String`
    执行并交叉核对（§3 为真实输出）。
15. **证据工程 `--import` 会让引擎崩溃** ⚠️**已撤回 / 不可复现 —— 见 §9.1 勘误**：`bin\...console.exe --headless --path <evidence proj> --import`
    以 `EXIT=-1073741819`（0xC0000005，访问违例）结束，栈顶是
    `ERROR: Parameter "singleton" is null. at: EditorNode::is_cmdline_mode (editor\editor_node.cpp:6732)`。
    与 mcp_server 模块无关（模块未被调用），门② 因此**不依赖 import 缓存**直接起编辑器/游戏进程采集
    （6 个工具本身也不需要 import 缓存：`Image::load` 直读文件、`.tres` 直接 `ResourceLoader::load`）。
    如实登记为环境观察。
16. **临时探针进了提交 2**：`4b144e6c1d`（红）包含 2 个临时 TEST_CASE（SPIKE / SPIKE2），
    `69ccfef13e`（绿）删除它们——这样红阶段真实输出与已提交的红树**逐字对应**。当前树无探针残留（§5 已核对 0 行）。
17. **`modules/mcp_server/docs/spec/` 保持未跟踪**：它是决策者在我开工前创建的 spec 工件，非本次改动，
    未纳入任何提交。
18. **门② 第一轮采集被自己的脚本污染**（`Out-File -Encoding ascii` 把中文写成 `?`），
    已改用 `curl.exe --output` 采原始字节并重采全部 21 例（§5.4）。

### 9.1 勘误（2026-09-22，TASK-005 修复轮）：deviation 15 的 `--import` 崩溃主张 **已撤回**

> append-only 勘误；上面 deviation 15 原文保留，仅标注为**已撤回**。

**复核结论：无法复现该崩溃，该条撤回**（原文的 `EXIT=-1073741819` / 0xC0000005 不成立）。
门② 的操作结论（**不依赖** import 缓存）不受影响，且仍被全部工具调用成功所支持。

我用**当前 HEAD 的既有二进制**（`bin\godot.windows.editor.x86_64.console.exe`，
sha256 `06034dd46626c2edc2ddb3fcb0814c49e773f0c87a3e6ca444c96a4d417d2912`）共复核 **23 次**，
覆盖报告原命令与其变体。**每一次日志里 `C0000005` / `access violation` 的命中数都是 0**；
其中 **11 次能读到真实退出码，全部 `EXIT=0`**；另 12 次由 `Start-Process` 启动，受 PowerShell 5.1
`-PassThru` 不回填 `ExitCode` 的怪癖影响未能读到数值，但进程均**正常终止**且无任何崩溃标记。

真实命令与结果（工程用报告自己的证据工程 `%TEMP%\mcp-t005-evidence\proj` 的**副本**；
`--mcp-port` 只用 9890 / 9891）：

```
(a) 全新工程(无 .godot) --headless    --path <proj_a> --import --mcp-port=9890   -> EXIT=0
(b) 全新工程(无 .godot) --headless -e --path <proj_b> --import --mcp-port=9890   -> EXIT=0
(c) 保留 .godot 缓存    --headless    --path <proj_c> --import --mcp-port=9891   -> EXIT=0  (cwd=%TEMP%)
(d) 报告原命令形式(无 --mcp-port) --headless    --path <proj_d> --import         -> EXIT=0
(e) 报告原命令形式(无 --mcp-port) --headless -e --path <proj_e> --import         -> EXIT=0
(f) 条件 (a) 用同一启动方式重复 6 次                                              -> 6/6 EXIT=0，无标记
(g) 条件 (a) 用 Start-Process 启动方式重复 8 次                                   -> 8/8 正常终止，无标记
(h) 首轮用 Start-Process 各跑 (a)–(d) 一次                                        -> 4/4 正常终止，无 0xC0000005
```

stderr 真实内容：

```
(a)(b)(c)(f)(g)(h 除 a) : stderr 为空，无 ERROR / WARNING
(d)(e)                  : WARNING: [MCP] bind failed on 127.0.0.1:9877; MCP server disabled
                          at: MCPServer::_start_service (modules\mcp_server\mcp_server.cpp:391)
```

即不带 `--mcp-port` 时引擎会**优雅地**尝试绑定用户端口 9877 并失败——这是唯一出现在 stderr 的
MCP 相关消息，**不是崩溃**（事后核对 9877 监听者仍是 PID 36392）。

**唯一的例外，也很可能正是原报告的来源**：在首轮 (h) 的条件 (a) 那次用 `Start-Process ... -NoNewWindow`
启动、且**后台正同时跑着一次全量 SCons 构建**（抢 CPU）时，stderr 里**出现过一次**：

```
ERROR: Parameter "singleton" is null.
   at: EditorNode::is_cmdline_mode (editor\editor_node.cpp:6732)
WARNING: A Thread object is being destroyed without its completion having been realized.
```

但**同一次运行的进程仍然正常退出**；在其余 22 次复核中（含同启动方式 8 次）该行**再未出现**。
这一行正是报告写作「栈顶」的那一行；它在源码里是 `ERR_FAIL_NULL_V(singleton, false)`
（`editor/editor_node.cpp`）——**打印 ERROR 后返回 false，不会崩溃**。
报告把它读成崩溃栈顶，是把**非致命的错误日志**误判成了**访问违例**。

**独立反例（验收方）**：独立验收子代理在 8 种条件下（有无 `.godot`、有无 `-e`、换 cwd、
并发开编辑器、自建 scratch 工程）**全部 `EXIT=0`**，同样搜不到
`C0000005` / `access violation` / `is_cmdline_mode`。

**判定**：`--import` 崩溃在 23 次（我）+ 8 次（验收方）复核中均不可复现，真机证据只有「退出码 0」
与「偶发一条非致命 `ERR_FAIL_NULL_V` 日志」。故 deviation 15 **撤回**，不作为环境观察保留。

**附注（与本次撤回相关的端口纪律）**：不带 `--mcp-port` 的 `--headless [-e]`
调用会尝试绑定 9877；行为是**优雅失败**、不影响 PID 36392，但后续流程应始终显式带 `--mcp-port`。

---

## 10. blockers

**无。** 全程无环境阻塞：三次构建 `SCONS_EXIT=0`；五道门 `EXIT=0`；
端口纪律无一次违反（9877 始终是用户的 PID 36392，9888/9889 用后即释放，收尾只剩 `TIME_WAIT`）。

---

## 11. next_step_recommendation

1. **B1 剩余组的框架前提已就绪**：`tools/tool_helpers.{h,cpp}` 有 4 个共享助手（唯一性有机械证据），
   后续组（`project_write_resource_scene` 4、`editor_read_scene_inspector` 7、`editor_write_scene_editor` 10、
   `running_game_read_scene` 1）可直接 include，不必再复制。
2. **`tool_helpers` 还缺两个后续组大概率要用的助手**（本任务只授权上提 4 个，故未动）：
   `_trim_stars`、`_has_reference_extension` 之类仍是 template 组私有；`editor_*` 组若要复用请另开小任务，
   不要在组文件里再造第 2 份。
3. **建议把 §9 deviation 4/5/6 写进 `docs/DESIGN-DETAIL.md §17`**：`ScriptServer::are_languages_initialized()`
   是「能否真编译」的唯一正确判据（`get_language_count()>0` 会给出假阴性），凡后续组要碰脚本编译
   （`editor_*`/B3 的 `create_script`/`edit_script`、B4 的 `run_test_scenario`）都会踩同一个坑。
4. **`check_contract_subset.ps1` 无需再改**（并集语义已够用）；`accept_m1.ps1` 的 `$ToolNames`
   需要**每个组落地时**继续追加（下一个组记得同步，否则门⑤ 必然 FAIL）。
5. ~~**`--import` 访问违例（§9 deviation 15）值得单独排查**：它会周期性影响任何「先 import 再跑」的证据流程，
   但不在本任务的改动面内，本任务未触碰引擎其它目录。~~
   **（2026-09-22 勘误：该访问违例不可复现，deviation 15 已撤回，**无需**单独排查；
   见 §9.1。`--import` 在 HEAD 二进制上 23 次复核全部 `EXIT=0`。）**
6. 下一个建议派发的组：按 REPORT-002 §8 顺序为 `project_write_resource_scene`（B1 里唯一的写组，
   `mutating=true`，注意 GDR-18 的条件写与「不得写 `.uid`」的只读纪律正好相反——它是**允许写**的组，
   需要单独裁定允许落盘的文件范围）。

---

## 12. 复现方法（验收方可独立重跑）

```powershell
# 0) 构建（pwsh/cmd，勿用 Git Bash；MSYSTEM 会让 SCons 去 bin/build_deps 找依赖并失败）
D:\Anaconda\Scripts\scons.exe platform=windows target=editor tests=yes module_mono_enabled=no -j8

# 1) 门③ 模块 doctest / 门④ 全引擎
bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"
bin\godot.windows.editor.x86_64.console.exe --headless --test

# 2) 门① 契约子集（自起 9888/9889、自建 scratch 工程、自带 9877 pid 守卫）
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\check_contract_subset.ps1 -Group project_read_files

# 3) AC-11 组清单机器校验
python modules\mcp_server\docs\scripts\check_tool_groups.py

# 4) 门⑤ 收口脚本 ×2（很慢：每轮都要多次启停引擎进程）
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1

# 5) 门② 证据工程（%TEMP%，刻意不入库；工程清单与全部请求/响应见 §7）
#    mkdir -p %TEMP%\mcp-t005-evidence\proj\{scripts,shaders,scenes,resources,images,.hidden,addons\plug}
#    ... 按 §7.1 写文件（PNG 用任意 64x32 合法 PNG）...
bin\...console.exe --headless -e --path %TEMP%\mcp-t005-evidence\proj --mcp-port=9888
#    游戏侧去掉 -e、用 --mcp-port=9889
#    每个用例：把 §7.2 的 BODY 写进 body.json，然后
curl.exe -s -X POST -H "Content-Type: application/json" --data-binary @body.json --output resp.json http://127.0.0.1:9888/mcp

# 6) §4 重构等价性重采（**必须**字节保真；完整方法、三个测量点与结论见 §4.1）
#    git worktree add --detach F:\mcp-t005-before-wt 8386726429^   # 重构前  = §4 的 before
#    git worktree add --detach F:\mcp-t005-before-wt 8386726429    # 重构提交 = §4 的 after（仍是 13 条工具）
#    D:\Anaconda\Scripts\scons.exe platform=windows target=editor tests=yes module_mono_enabled=no -j8
#    起引擎：编辑器 --headless -e --path <proj> --mcp-port=9890；游戏 --headless --path <proj> --mcp-port=9889
#    采集【必须】让 curl 直接写文件，禁止 `| Out-File` / `| Set-Content`：
curl.exe -s -o resp.raw -X POST -H "Content-Type: application/json" --data-binary "@%TEMP%\mcp-t005-equiv\bodies\01_tools_list.json" http://127.0.0.1:9890/mcp
#    期望：13 条 tools/list = 4229 字节，sha256 d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80
#          before 与 after 长度 + 逐字节 + sha256 全等
```

**勘误（2026-09-22）**：报告初版 §4 的 2 条 `tools/list` 证据系有损采集（已作废并重采，见 §4.1）、
§9 deviation 15 的 `--import` 崩溃不可复现（已撤回，见 §9.1）。**交付代码与其余结论未改动**——
重构等价性已用干净字节独立复现（13 条 `tools/list` = **4229** 字节，before/after 逐字节相同）。

结论：**框架清理做完（助手唯一、等价性逐字节可证），`project_read_files` 组 6 个只读工具按契约逐字实现并经五道门验证；
`status = pass`。**
