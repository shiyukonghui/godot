# REPORT-AUDIT-ENGINE — 独立验收：三个引擎补丁 + 5 个新增工具 + 门完整性五条纪律

- 验收者：**独立验收子代理**（全新会话，未参与任何实现；未采信任何 `REPORT-*` 或决策者摘要）
- 验收对象提交锚点（D86）：**`e45ad638e6bdffb434a8e673d82d54625c63b98f`**（分支 `feature/mcp-server-module`，`HEAD`）
  - 二进制自报：`4.8.dev.custom_build.e45ad638e`（`bin\godot.windows.editor.x86_64.console.exe --version`）
  - 净引擎补丁基线：`57277407e7`（`git merge-base HEAD origin/master`）
- 端口纪律：**9877 全程未被占用/杀/重启**；本轮只用 9888 / 9889；未 push。
- 结论口径：本文每条结论都标注它**测自哪个提交**（D86）。凡是只能靠阅读/推断而不是我自己跑出的证据，都写进 §5 `unconfirmed`。

---

## 0. 开工与门绑定

| 项 | 结果 | 证据 |
|---|---|---|
| 构建 | `modules\mcp_server\scripts\build_local.cmd -Force`（tests=yes，cmd 启动）exit **0** | `log` 尾部 `build_local: exit code = 0` |
| 版本锚点 | `--version` == `e45ad638e` == `git rev-parse --short HEAD` | 见上 |
| mono | **未重建**（见 §5 unconfirmed）：磁盘上的 mono 二进制自报 `4.8.dev.mono.custom_build.48a3c2e33`，即 `HEAD~1`；`git diff --stat 48a3c2e33..HEAD` 只含 `scripts/**` 与 `docs/**`（0 个工具源码文件），所以工具行为与 HEAD 相同，但**这一判断是结构性的，不是实测** | `git diff --stat 48a3c2e33..HEAD` |
| 模块门③ | `--headless --test --test-case="[MCPServer]*"`：**345 cases / 23971 assertions / 0 failed** | `doctest_mcp.log` |
| 全引擎回归④ | `--headless --test`：**1771 cases / 448218 assertions / 0 failed / 3 skipped** | `full_regression.log` |
| 接受电池⑤ | `scripts\accept_m1.ps1` 连跑两次：**23/23 PASS ×2，PASS 清单逐字节一致**（`Compare-Object` = `identical=True`） | `accept_m1_run1.log` / `accept_m1_run2.log` / `accept_run{1,2}_passlist.txt`（同一个 sha256 前缀 `8cee697d2bfa30db`） |
| 线上契约 | accept_m1 自报并被我独立复核：**9888 = 153 / 9889 = 72 / contract = 176** | §2 |

---

## 1. 三个引擎补丁的「非侵入性」

### 1.1 净改动清单（基线 `57277407e7` → `HEAD e45ad638e6`）

`git diff 57277407e7..HEAD -- <engine files>`（排除 `modules/mcp_server/**` 与 `docs/**`）只有 **5 个文件**：

| 文件 | + | − |
|---|---|---|
| `core/config/project_settings.cpp` | 615 | **3** |
| `core/config/project_settings.h` | 78 | **0** |
| `editor/editor_node.cpp` | 19 | **1** |
| `modules/mono/csharp_script.cpp` | 20 | **3** |
| `modules/mono/csharp_script.h` | 20 | **0** |

**合计 752 增 / 7 删。** 全仓库此范围内**没有第七个被改的引擎文件**（`engine-net-diffstat.txt`）。

### 1.2 每一处被修改的既有行（完整 7 行，逐行列出）

用 `git diff … | grep '^-'` 得到**全部** 7 行（`engine-net-diff.txt`，共 7 个 `-` 行 + 4 个 `---` 文件头）：

| # | 文件:旧行 | 被删除的既有行 | 处置 | 判定 |
|---|---|---|---|---|
| 1 | `core/config/project_settings.cpp:1234` | `Error ProjectSettings::save_custom(const String &p_path, const CustomMap &p_custom, const Vector<String> &p_custom_features, bool p_merge_with_current) {` | **原样搬到 :1342**（逐字相同，见 diff 对照） | 签名/返回类型**未变** |
| 2 | `project_settings.cpp:1235` | `	ERR_FAIL_COND_V_MSG(p_path.is_empty(), ERR_INVALID_PARAMETER, "Project settings save path cannot be empty.");` | **原样搬到 :1343** | 行为**未变** |
| 3 | `project_settings.cpp:1236` | （空行） | 原样搬到 :1344 | 无 |
| 4 | `editor/editor_node.cpp:1071` | `				ProjectSettings::get_singleton()->save();` | 改为 `if (project_settings_path.is_empty() \|\| !FileAccess::exists(project_settings_path)) save(); else save_preserving_text();`（:1085–1088） | **调用点行为改变**（见 1.5） |
| 5 | `modules/mono/csharp_script.cpp:2174` | `			uint64_t script_modified_time = FileAccess::get_modified_time(get_path());` | 该三行被 `if (is_source_newer_than_assembly()) {`（:2174）替代 | **等价重构**（见 1.4） |
| 6 | `csharp_script.cpp:2175` | `			uint64_t last_valid_build_time = GDMono::get_singleton()->get_project_assembly_modified_time();` | 同上 | 同上 |
| 7 | `csharp_script.cpp:2176` | `			if (script_modified_time > last_valid_build_time) {` | 同上 | 同上 |

**证明方法（无遗漏）**：这不是「看几处像改了」——判据是 `git diff <base>..HEAD` 的 `-` 行**总数**（`--numstat` 给出 3+0+1+3+0 = 7）与上表**逐行相等**；`numstat` 的数字与 `git diff` 的 `-` 行不可能不一致，因此「没有第 8 处」由构造保证。

### 1.3 「只增不改」这个说法的准确结论

- **补丁②（`96f631addb`，「TASK-057 patch 2」）是纯粹的只增不改**：`project_settings.cpp 448+/0-`、`project_settings.h 35+/0-`。`update_settings_section_text()` / `save_custom_section()` 在本分支**首次出现**，是**新增符号**。
- **补丁①（`5f3e7fb441`）与补丁③（`2f85141a74`）不是字面意义的「只增」**：它们各改了既有行（上表 #5–#7 与 #4），另把 `save_custom()` 的头两行+空行**搬了个位置**（#1–#3）。
- **关键区分**：`git diff 96f631addb..HEAD -- core/config/project_settings* editor/editor_node.cpp` 里的 `-` 行**全部落在补丁②自己新增的代码上**（`save_custom_section()` 被拆成 `_read_settings_text_file()` + `_publish_settings_text_file()`，函数体内 `updated` → `p_text` 两处改名）。**上游既有引擎代码里，只有上表 7 行被动过。**

### 1.4 `reload() / save() / save_custom() / save_custom_section()` 的签名与返回值

| 函数 | 现值 | 是否改动 |
|---|---|---|
| `Error CSharpScript::reload(bool p_keep_state)` | `modules/mono/csharp_script.cpp:2586` | **完全未动**（net diff 里 `csharp_script.cpp` 的 3 个 `-` 行都在 `_update_exports()`，不在 `reload()`） |
| `Error ProjectSettings::save()` | `core/config/project_settings.cpp:1085` | **完全未动**（未出现在 net diff 中） |
| `Error ProjectSettings::save_custom(const String&, const CustomMap&, const Vector<String>&, bool)` | `project_settings.cpp:1342` | 签名逐字不变；返回类型 `Error` 不变；函数体只在开头多了 `_collect_settings_for_save(...)` 的调用（收集逻辑整体搬进去，**逐字节相同**——diff 以 context 形式匹配了那 400+ 行） |
| `Error ProjectSettings::save_custom_section(const String&, const String&, const CustomMap&)` | `project_settings.cpp:1824` | 补丁②引入时的签名与补丁③重写后的签名**逐字相同**；返回 `Error` 不变 |
| `Error CSharpScript::is_source_newer_than_assembly() const`（新） | `csharp_script.cpp:2621` | 新增只读访问器，不改任何既有函数 |
| `Error ProjectSettings::save_preserving_text()`（新） | `project_settings.cpp:1874` | 新增 |
| `Error ProjectSettings::_collect_settings_for_save(...)` / `_read_settings_text_file(...) const` / `_publish_settings_text_file(...) const` / `publish_settings_sections_text(...) static`（新） | `:1239 / :1708 / :1741 / :1796` | 新增，`protected`/`public static` |

> **等价性（补丁①的 `_update_exports` 重构）**：旧逻辑 `mtime(path) > assembly_mtime`；新访问器在 `path.is_empty()` 或 `mtime == 0` 时返回 `false`，其余完全相同，而这两种情形在旧式下也是 `0 > x` = `false`。因此**对任意 mtime 取值都等价**。

### 1.5 调用点核查

- **`save()` 调用点**：`git grep -c "ProjectSettings::get_singleton()->save()" -- editor` = **27 处**（其中 `editor/run/editor_run_bar.cpp:272` 是**注释**里的 TODO，因此真实调用 26 处）。
  - **只有 `editor/editor_node.cpp:1086` 一处被改**（它仍在 `if` 分支里调用 `save()`）。
  - 证明其余 26 处未动：net diff 在 `editor/**` 里**只触及 `editor/editor_node.cpp` 一个文件**（`engine-net-diffstat.txt` 的 5 行里只有它属于 `editor/`）。
- **新 API 只落在指定调用点**（`git grep`，全仓库）：
  - `save_preserving_text()`：**仅** `editor/editor_node.cpp:1088`。
  - `publish_settings_sections_text()`：**仅** `core/config/project_settings.cpp:1922`（`save_preserving_text()` 内部）。
  - `save_custom_section()`：`project_settings.cpp:1824/1948`（定义 + `ClassDB` 绑定）与 `modules/mcp_server/tools/tool_helpers.cpp:651`（**模块内唯一的工程写入者**）。
  - `update_settings_section_text()`：`project_settings.cpp:1815/1840` + 模块 doctest。
  - `CSharpScript::is_source_newer_than_assembly()`：引擎内**仅** `csharp_script.cpp:2174`，模块内**仅** `tools/project_read_files.cpp:516`。

### 1.6 行为逐字节对照（我自己造工程跑，非引用）

工程：`%TEMP%\audit-engine\proj`（`project.godot` 含 **3 行手写 `;` 注释**，sha256 起点 `32209af470d206b6…`，387 B）。全部请求走 `curl.exe -s -o` 打到 9888，响应落盘。证据 `patch_behaviour4.log`（sha256 前缀 `5954440cc0f1eccd`）。

| 编号 | 实验 | 结果 |
|---|---|---|
| B0 | 起点 | 3 处 `AUDIT-SCRATCH`、387 B |
| B1–B2 | `project_add_autoload`（走 `save_custom_section()` 节写入） | sha `32209af470d2 → 8b92f41976cb`，**手写注释 3 → 3 逐字保留** |
| B3 | 同一调用再来一次（幂等） | sha `8b92f41976cb → 8b92f41976cb`（**文件根本没碰**） |
| B4 | **反向探测**：`project_remove_autoload`（其契约描述声明仍用整文件 `save_custom()`） | sha `8b92f41976cb → a7d9e7ff13dc`；手写注释 **3 → 0**，换成引擎自己的 7 行抬头 —— **整文件重写仍然整文件重写** |
| B5 | 该丢失是否被声明 | 契约里 `project_remove_autoload` 的描述含 `every hand-written comment in that file is lost`（**声明过的有损**，不是静默） |
| B6 | `project_set_setting key=audit_top_level`（**无节名**，声明的整文件回退） | sha `32209af470d2 → a7d9e7ff13dc`，注释 **3 → 0** —— 回退路径确实是整文件 |
| B7–B8 | `project_set_setting key=audit_probe/value`（**有节名**） | sha `32209af470d2 → 4a71d1a5e4eb`，注释 **3 → 3**；`Compare-Object` 显示**只多了 3 行**：`[audit_probe]` / 空行 / `value=5.0` |

→ **「旧路径行为不变」的证据是 B4/B6**：凡是声明走整文件写者的路径，仍然整文件重写、仍然丢注释，没有被新 API 偷偷全局替换；**「新路径只动目标节」的证据是 B1–B3/B7–B8**：注释、键序、其余字节与幂等性逐条成立。

---

## 2. 5 个新增工具的「拒绝面」与契约对等

### 2.1 契约对等（**从实时 `tools/list` 解析**，不做文本包含判断）

证据：`live_battery3.log`（`e3ec8893a4452963`）、`game_battery.log`（`a95d51449cfdfdb6`）。原始响应 `%TEMP%\audit-engine\live\resp_editor_tools_list.json` / `resp_game_tools_list.json`（**curl.exe -s -o 落盘**）。

| 编号 | 断言 | 实测 |
|---|---|---|
| C0 | 契约 176 条 | `count=176`，`added_count=5`，`added_tools` = 5 个新增名（有序） |
| C1 | 9888 `tools/list` 可解析 | `http=200 count=153 sha256=333b4a6858aa3c54…` |
| C2 | 9888 上每条 `name`/`description`/`inputSchema` 逐字 | **153/153 逐字相等**（canonical 比较，与 `accept_m1.ps1 Get-CanonicalJson` 同构）；`mismatches=`（空） |
| C3/C4/C4b | scope 零泄漏（编辑侧） | 契约 23 条 `scope=game` **一条都不在 9888**；104 条 `scope=editor` **全部在 9888**；`153 = 176 − 23` |
| G2/G3 | 线上下限 | 9889 = **72**，9888 = **153** |
| G4 | **并集 == 176** | `union=176 contract=176 missing= foreign=` |
| G5 | 9889 上每条逐字 | 72/72 逐字相等 |
| G8 | scope 双向零泄漏 | `game-scope on 9888=`（空）；`editor-scope on 9889=`（空） |
| C5/G9/G10 | 跨端点 `-32601` | 9888 调 `running_game_get_scene_tree` → `-32601 Method not found`；9889 调 `editor_get_errors` → `-32601`；9888 调 `running_game_capture_screenshot` → `-32601` |

> **唯一一处非逐字节差异（已判定为非缺陷，但如实登记）**：`editor_set_node_property_updates` 的 `inputSchema` 在**原始 JSON 成员顺序**上与契约不同（`stop_on_error` 与 `updates` 互换）。**规范化后逐字相同**。理由链：①`tools_list.renamed.json._meta.order_normative=false`；②`DESIGN-DETAIL §17.4` / `accept_m1.ps1` 的 verbatim 门本身就是 canonical（键排序）比较；③源码 `tools/editor_node_property_updates.cpp:490-491` 显式写下「Key order inside a JSON object is not part of the contract」。**判定：pass（非缺陷），但若决策者要求「线上字节级 JSON 顺序」也一致，则这是一条 minor。**
> 我最初的对照脚本用 `ConvertTo-Json -Compress`（顺序敏感）报了 1 处 mismatch，改用与门一致的 canonical 比较后归零；**这两次结果都留在 `live_battery{,2,3}.log` 里，未被删除**。

### 2.2 「已知会被既有工具拒绝」的输入喂给新工具 → 同族拒绝

全部为真实请求/响应；`code` + `message` + `data.suggestion` 三件齐全。

| 新工具 | 反例 | 结果 | 判定 |
|---|---|---|---|
| `project_write_text_file` | `res://project.godot` | `-32602` + suggestion「Use project_set_setting」；**`project.godot` sha 前后相同** | ✅ |
| 同上 | `res://scenes/main.tscn` | `-32602` + suggestion（专用工具） | ✅ |
| 同上 | `res://scripts/attachable.gd` | `-32602` + suggestion | ✅ |
| 同上 | `res://Foo.cs` | `-32602` + suggestion | ✅ |
| 同上 | `res://../escape.txt`（越界） | `-32602` + suggestion；**工程外没有落文件** | ✅ |
| 同上 | 目标已存在 + `overwrite:false` | **`-32000`** + suggestion（点名 `overwrite:true`），**字节未变**（GDR-28 第 10 条） | ✅ |
| 同上 | 正常 `.txt` 新建 | 成功（`created:true` + sha256） | ✅ |
| `editor_set_node_property_updates` | 未知属性 `zzz_audit_no_such_property`（`stop_on_error:false`） | 逐条 `results[].error.code = -32001` + `suggestion`；整体 `updated=0 failed=1` | ✅ |
| 同上 | **非标识符属性名 `glow_levels/1`** | 逐条 `error.code = -32001` + suggestion | ✅ |
| 同上 | 同一输入 + `stop_on_error:true` | **顶层** `-32001` + suggestion，`rolled_back` | ✅ |
| `editor_set_node_script_batch` | `res://scenes/main.tscn`（不是脚本） | `-32602` + suggestion | ✅ |
| 同上 | 缺失脚本 | `-32001` + suggestion | ✅ |
| `project_build_csharp` | plain 构建（无 C# 后端） | `-32000` + suggestion（说明装什么/换哪个构建） —— GDR-28 第 6 条 capability-aware | ✅ |
| `project_validate_scripts` | plain 构建 + `.gd` | 成功，`category:"ok"`、`valid:true`（不伪造） | ✅ |
| 9889（game）上的 3 个 `scope=both` 工具 | `project.godot` / `.tscn` / `project_build_csharp` | 与 9888 同族拒绝（`-32602` / `-32000` + suggestion） | ✅ |
| 9889 上的 2 个 editor 工具 | `editor_set_node_script_batch` / `editor_set_node_property_updates` | `-32601`（结构性不可达） | ✅ |

**没有任何一个新工具「悄悄成功」**：每一条被拒的输入都同时给出错误码与 `data.suggestion`，并且对会落盘的用例做了 sha256 前后对照。

### 2.3 `stop_on_error` 两种语义（含**回滚后读回**）

节点 `Main/Child`（`Node2D`），先经 `editor_open_scene` 打开编辑场景。

- **`stop_on_error:false`**：`updates=[{position:{11.5,22.5}}, {zzz_audit_no_such_property:1}]`
  → 响应 `count:2 updated:1 failed:1 status:"partial"`；`results[0]` 有 `changed:true`/`old_value:{0,0}`/`new_value:{11.5,22.5}`，`results[1]` 有 `error.code=-32001`。
  → **读回证明**：`editor_get_node_properties path=Main/Child properties=[position]` 返回 **`{"x":11.5,"y":22.5}`**，即好的一条真的落盘。
- **`stop_on_error:true`**：`updates=[{position:{99.5,88.5}}, {zzz_audit_no_such_property:1}]`
  → **顶层 `-32001`** + `rolled_back:true`（`upd_mixed_true` 响应里含 `rolled_back`），`-32001` 是 `updates[1]` 那条。
  → **回滚后读回证明**：`editor_get_node_properties` 返回 **`{"x":11.5,"y":22.5}`** —— 不是 `99.5`，即第一条被**真的取回**，不是「报回滚但没回滚」。
  → 两条语义在同一节点上、同一字段上先写后读，因此能区分「拒绝」与「静默写默认值」。

### 2.4 代码腿：新工具的写入是否都过同一道 `ValueSlot` 闸门

`ValueSlot` 闸门的**唯一实现**在 `modules/mcp_server/tools/tool_helpers.cpp:1789`（`bool value_fits_slot(...)`），唯一入口 `coerce_to_property_type(...)` 在 `tool_helpers.cpp:2392`，调用点在 **`tool_helpers.cpp:2410`**。

| 新增工具 | 写入路径（`文件:行`） | 是否过 `ValueSlot` | 判定依据 |
|---|---|---|---|
| `editor_set_node_property_updates` | `tools/editor_node_property_updates.cpp:276` `write_node_property(node, property, value, error)` → `tools/running_game_node_write.cpp:1002` → `prepare_node_property_value(...)`（`:1009` 调用；定义 `:1140`）→ `coerce_to_property_type`（`tool_helpers.cpp:2392`）→ **`value_fits_slot`（`tool_helpers.cpp:2410`）** | **是** | 该工具**唯一**的写入调用就是 `:276`；`write_node_property` 是模块的单一写路径，闸门与写后回读都在它内部 |
| `editor_set_node_script_batch` | `tools/editor_set_node_script_batch.cpp:181` `p_node->set_script(...)` + `:186` 读回；回滚 `:199` | **不适用（按构造）** | 写的是 `Ref<Script>` 对象引用，不是 `Variant → 有类型的 C++ 数值成员` 的收窄；GDR-22 §20.1 的四个槽（`WIDE`/`REAL_T`/`INT32`/`UINT8`，§22.2 补 `FLOAT32`）都描述数值槽。`coerce_to_property_type` 自身对 `Variant::OBJECT` 在 `tool_helpers.cpp:2400` 直接返回，注释写明「an object reference is never narrowed」 |
| `project_write_text_file` | `tools/project_text_write.cpp:144` `write_project_text_file(...)` → `:161` `publish_text_atomically(path, content)`（定义 `tools/tool_helpers.cpp:488` 附近） | **不适用（按构造）** | 写的是文本字节，没有 `Variant → 类型化槽` 的转换；拒绝面由路径白名单（扩展名 / `project.godot` / `..`）承担 |
| `project_build_csharp` | 不写任何工程属性/文件内容；只在能力缺失时 `-32000` | **不适用** | 它调用外部 `dotnet build`，返回退出码与捕获输出 |
| `project_validate_scripts` | **只读**（逐个脚本给 verdict） | **不适用** | 无写入路径 |

→ **结论：5 个新工具里唯一存在「Variant→类型化槽」写入的是 `editor_set_node_property_updates`，它**确实**经过同一道 `ValueSlot` 闸门（`tool_helpers.cpp:2410`），没有被旁路。其余 4 个没有该类写入，因此「过闸门」这一命题对它们不成立，而不是「绕过了闸门」。**

---

## 3. 门完整性五条纪律（**每条都尝试绕过**）

### 3.0 五条纪律各自「被门调用」的事实

| 纪律 | 实现 | 谁调用它（`git grep`，提交 `e45ad638e6`） | 我跑过什么 |
|---|---|---|---|
| 恒真断言 | `scripts/check_tautologies.py` | `scripts/mcp059_gates.ps1:83-85`（`Invoke-Step` 三步：scan / --probes / --coverage） | 直接跑 scan（exit 0）与 `--probes`（**18/18**），并植入反例（§3.1） |
| 内红必须非零 | `scripts/check_exit_propagation.py` | **`scripts/accept_m1.ps1:728-744`（`case0_repo_exit_code_propagation`，这是接受电池的一个 case）**；另 `mcp069_stale_expectation_reverse_probe.ps1` | **accept_m1 连跑两次都 PASS 该 case**；直接跑 scan exit 0；反例与演示见 §3.2 |
| 静默覆写证据 | `scripts/mcp_evidence_guard.ps1`（`Get-McpEvidenceState` / `Restore-McpEvidence` / `Test-McpDeclaredPath`） | `scripts/mcp056_regression_battery.ps1:56/131/186-187/197`（声明 `-AllowedPaths`/`-AllowedRoots`，`exit 1` 在 `:237`）；`mcp06x_*` 系列 | 跑 `mcp069_guard_whitelist_probe.ps1`（exit 0，§3.3） |
| 删证据（电池路径白名单） | 同上（`Restore-McpEvidence` 的白名单语义） | 同上一行 | 同上；反例是「电池删一个**未声明**文件」（§3.3） |
| 假等待 | `scripts/mcp_watch_run.ps1` | **只在 breakout/观察者脚本里**：`mcp061_watch_evidence.ps1`、`mcp065b_env.ps1`/`mcp065b_run.ps1`、`mcp066b_env.ps1`/`mcp066b_run.ps1` | 我写了自己的观察者反例（§3.4） |

> **诚实的结构性观察（不是阻塞缺陷，但决策者应当知道）**：五条里**只有 `check_exit_propagation.py` 挂在 `accept_m1.ps1`**（唯一「每批必跑两次」的接受电池）。`check_tautologies.py` 挂在 `mcp059_gates.ps1`，证据守卫挂在 `mcp056_regression_battery.ps1`，观察者挂在 breakout 运行脚本里。也就是说「在门里真的被调用」对四条成立（门 = 各自所在的门驱动器/电池），但**没有全部收敛到同一个 CI 入口**；一条纪律不会因为 `accept_m1` 变绿而被自动复查。见 §5 risks。

### 3.1 恒真断言：植入 → 必须被点名

反例脚本：`%TEMP%\audit-engine\insertion_probe.ps1`，输出 `insertion_probe.log`（`f855bb5d3ae83514`）。它临时在 `modules/mcp_server/scripts/` 下新建探针文件，跑完**删除**，并比较前后 `git status --porcelain`。

```
UNPINNED scripts\zz_audit_tautology_probe.ps1 ps_or_true (1 hit(s))
    line 3: Check 'audit_probe' ($auditValue -eq 0 -or $true) ('planted tautology')
TAUTOLOGY CHECK FAILED: 1 problem(s)   -> exit 1
```

- ✅ **绕过失败**：植入的恒真断言（**落在已声明拼写集合内**：`-or $true`）被**点名**，exit 1。
- ⚠️ **声明边界（不是新缺陷）**：把同一个常数写成**集合外**拼写（裸 `($true)`）时，脚本 **exit 0 且不点名**。这正是脚本 docstring 第 33–38 行声明的边界（"The check is spelling-visible only"），与 §22.3b 对门⑥ 的口径同构：**有限集合保证 + 必须打印边界**。我把它记为**已知边界**而不是绕过缺陷；但若有人把「写了恒真断言一定会被抓」当保证用，就是错的。

### 3.2 内红必须非零：打印 FAIL 但不设退出码 → 必须被点名

反例脚本同上，输出同一份 `insertion_probe.log`：

```
UNDISCHARGED scripts\zz_audit_exitprop_probe.ps1 ps_check_printer
    the file carries this shape and no declared guard for it:
    a red step or check can be reported and the process still exits 0
EXIT-CODE PROPAGATION CHECK FAILED: 1 problem(s)   -> exit 1
```

- ✅ **绕过失败**：一个「有 PASS/FAIL 打印器、`-f $tag,`、但从不设退出码」的文件被**点名**，exit 1。
- ✅ **真机演示**（实现者自带的另一半，我亲自跑）：`mcp069_exit_propagation_demo.ps1 -OutRoot %TEMP%\audit-engine\exitprop` → exit **0**，且三条腿都成立（`exitprop-demo.log`，`cbb5ccc7d05687d2`）：
  - `unguarded`：它的 summary 里带 `EXIT 3`，**进程 exit 0**（缺陷被复现）；
  - `guarded_red`：同一输入 + **真实 guard 文本** → **exit 1**；
  - `guarded_green`：只有那一步改成绿 → **exit 0**（guard 不是常数）。
  - 并且它自证「抽取的 `Invoke-Step` 与 guard 块是真实文件的**逐字切片**」（sha256 打印）。
- ✅ **门里调用**：`accept_m1.ps1` **两次**都打出 `PASS case0_repo_exit_code_propagation`。
- ⚠️ **声明边界**：一个「打印 `FAIL` 字样、但不含任何已声明聚合形状」的文件**不会被抓**（脚本 docstring 第 32–39 行声明）。同 §3.1，记为已知边界。

### 3.3 静默覆写证据 / 删证据（电池路径白名单）：删未声明文件 → 必须被拦

`mcp069_guard_whitelist_probe.ps1 -OutRoot %TEMP%\audit-engine\guardprobe` → **exit 0**，`guardprobe.log`（`41fdf40e990ae598`）。它在一个 `%TEMP%` 里的**scratch git 仓库**上跑（不碰被测仓库）：

| 断言 | 实测 |
|---|---|
| W10/W11/W12 | **未声明**的 `docs/reports/REPORT-planted.md`（电池运行期间写下的报告）**原样存活、sha256 不变**；声明外的已跟踪文件仍保持被修改状态（**不会被 revert**） |
| W13/W14/W15 | 声明的 `evidence/new_declared.json` 被移除、声明的 `evidence/tracked.txt` 回到 HEAD —— 白名单**真的在做事**，不是「什么都不干」 |
| W20–W23 | **默认拒绝**：完全不给声明时，`restored=0 removed=0 untouched=3`，四个路径**一个都没动** |
| W24 | 一个会等于「所有路径」的声明（`./`）**抛异常被拒**，而不是被接受 |
| W25/W27 | 前缀规则而非子串规则：`not-evidence/a.json` **不**算已声明 |

- ✅ **绕过失败**：「让电池删一个未声明文件」的两种写法都失败——不声明（默认拒绝什么都不删）与声明别的目录（未声明文件被 `UNTOUCHED`）。
- ⚠️ **边界**：这条纪律保证的是「**`Restore-McpEvidence` 不会超出声明范围动文件**」。它**不**检查**电池步骤本身**是否用别的方式删了东西——那是 §3 之外的工具行为。若一个步骤在没有守卫快照的路径下删文件，本纪律看不到。登记为边界（`unconfirmed` 区）。

### 3.4 假等待：开发未结束时收工 → `stop_reason` **必须不等于** `marker`

我自己的观察者反例：`%TEMP%\audit-engine\watch_probe.ps1` → **exit 0**，`watchprobe2.log`（`1886aaf792b84f05`）。四条腿：

| 编号 | 场景 | `stop_reason` | 判定 |
|---|---|---|---|
| T1/T2 | **开发仍在进行**（marker 路径不存在，trace 有内容），`TimeoutSec=4` | **`timeout`**（`marker_seen=False`） | ✅ 不等于 `marker` |
| S1/S2 | 开发卡住（trace 停止更新），`StaleSec=2` | **`stale`**（`activity_seen=True`） | ✅ 不等于 `marker` |
| M1 | marker 叶子文件真的存在 | **`marker`** | ✅ 该原因不是常数 |
| D1 | marker 路径上放的是**目录** | **`timeout`**，`marker_seen=False` | ✅ `Test-Path -PathType Leaf` 顶住了「同名目录冒充完成」 |

- ✅ **绕过失败**：想「在开发还没结束时就收工」，只能得到 `timeout` 或 `stale`；只有**真的存在 marker 叶子文件**才得到 `marker`。
- ⚠️ **边界**：观察者只认「marker 文件是否存在」，不校验 marker 的**内容或写入者**；任何进程只要创建那个叶子文件就能让它判 `marker`。这是设计选择（确定性停止条件），登记为边界而不是绕过缺陷。

### 3.5 反例实验后的逐字节还原

- `insertion_probe.ps1` 的 **P3**：植入/删除探针前后 `git status --porcelain` **完全一致**（`before == after` 为 True）。
- 本轮**曾**因一条失败的复合命令在仓库根落下一个字面名为 `%D%` 的目录（内含两个我自己的 JSON）。我在发现后**立即删除**，并把「删除」写进本轮记录；此后 `git status --porcelain` 只剩既有未跟踪物 + 任务书本身（见 §6）。**这是我的操作残留，不是被测产物**，我把它如实登记。

---

## 4. 判定汇总

| 分类 | 判定 | 依据 |
|---|---|---|
| **补丁非侵入性** | **pass（附一条纠正）** | 净改动只有 5 个引擎文件 / 752 增 / 7 删；7 行逐行列出并逐条判定；`reload()`/`save()` 完全未动；`save_custom()`/`save_custom_section()` 签名与返回类型未变；B1–B8 的字节对照证明「旧路径仍整文件、新路径只动目标节」。**要纠正的是任务书的措辞**：补丁②是「只增不改」，补丁①/③**不是**——它们改了 7 行既有行（其中 3 行是纯搬家、3 行是等价重构、1 行是**有意的调用点行为改进**）。 |
| **新工具拒绝面** | **pass** | 14 条编辑器侧 + 6 条游戏侧反例全部同族拒绝并有 suggestion；无「悄悄成功」；`stop_on_error` 两种语义含**回滚后读回**；`ValueSlot` 代码腿给出 `文件:行`。 |
| **契约对等** | **pass** | 实时解析：9888=153 / 9889=72 / 并集=176 / missing=0 / foreign=0；153+72 条逐字（canonical）；`scope` 双向零泄漏；跨端点 `-32601`。唯一差异是 1 条 `inputSchema` 的**成员顺序**（声明为非规范）。 |
| **门完整性五条** | **pass（5/5 的绕过尝试全部失败）** | §3.1–3.4；每条都有真实反例与失败证据。另附四条边界与一条结构性观察（§3.0）。 |
| **工程门** | **pass** | 构建 exit 0；版本锚点一致；模块 doctest 345/23971/0；全引擎 1771/448218/0；accept_m1 23/23 ×2 且清单一致。 |
| **端口** | **pass** | 9877 全程无 LISTENING、无相关进程；9888/9889 已释放（只剩内核 TIME_WAIT，无进程）；无孤儿 Godot 进程。 |

**verdict = pass**（无阻塞缺陷；登记 3 条 boundary 与 2 条流程性风险，见下）

---

## 5. defects / unconfirmed / risks

### defects（阻塞项）
- **无。** 五条纪律的绕过尝试全部失败。

### unconfirmed（未被我实测确认）
1. **mono/C# 路径未独立复测**：磁盘上的 mono 二进制是 `48a3c2e33`（`HEAD~1`）。我没有重建 mono（串行重建代价大），因此 §2 里 `project_build_csharp` 的**能力缺失拒绝**只在 plain 构建上实测；C# **成功编译**那条腿（`invalid`/`ok`/`not_compiled` 三分类在 mono 下的真实表现）**不在本轮证据内**。
2. **补丁③的编辑器「开窗保存」调用点未在窗口化编辑器下实测**：`editor_node.cpp:1071` 的分支带 `!cmdline_mode` 守卫，`--headless`/`--import` 都到不了它（这也是原缺陷长期没被看见的原因）。我对 `save_preserving_text()` 的**路径复用与集合**只做了源码级核对（它调用 `_collect_settings_for_save()` 后走 `publish_settings_sections_text()` + `_publish_settings_text_file()`），**没有**在窗口化编辑器里跑一次真实 open 并比对 `project.godot`。
3. **`mcp059_gates.ps1` / `mcp056_regression_battery.ps1` 未整脚本重跑**：「恒真断言」「证据守卫」被这两个门驱动器调用，是由 `git grep` 的行号 + 我单独跑被调命令（exit 0）证明的，不是由重跑整个驱动器证明的。
4. **双精度（`precision=double`）构建未验**：`ValueSlot::FLOAT32` 的设计主张（双精度下 `Color`/`PackedFloat32Array` 仍按 32 位判）是源码级结论，与本机单精度二进制无关，本轮未做双精度构建。

### risks
1. **R-1（流程）**：五条纪律未收敛到单一 CI 入口。`accept_m1` 只跑 `check_exit_propagation.py`；`check_tautologies.py` 在 `mcp059_gates.ps1`，证据守卫在 `mcp056_regression_battery.ps1`，观察者在 breakout 脚本里。只跑 `accept_m1` 变绿**不能**推出另外四条生效。
2. **R-2（边界）**：`check_tautologies.py` 与 `check_exit_propagation.py` 都是**拼写可见**的有限集合检查（各自 docstring 已声明）。集合外的恒真断言与 FAIL 打印器**不会被抓**——本轮我用两个探针实测到了这一点，并把它登记为**已知边界**而非缺陷。
3. **R-3（观察者）**：`mcp_watch_run.ps1` 的完成判据是「marker 叶子文件存在」，不校验写入者；任何进程都能伪造 marker。
4. **R-4（证据守卫范围）**：守卫只约束 `Restore-McpEvidence` 自身（不超出声明范围）；它不能发现「某个步骤绕过守卫、在别处删了文件」。

---

## 6. 收尾干净性

```
$ git status --porcelain
?? .graphifyignore
?? build-m0.cmd
?? graphify-out/
?? install-deps-m0.cmd
?? modules/mcp_server/docs/tasks/TASK-AUDIT-ENGINE.md
```

- 与开工时（以及 PLAYBOOK §5 声明的既有未跟踪物）**完全一致**；`git diff`（已跟踪文件）**为空**。
- 本报告是本轮唯一**新增**的仓库内文件（`docs/reports/REPORT-AUDIT-ENGINE.md`），**未提交**：审计侧的纪律是「不得修改仓库任何文件」，报告是任务书要求的交付物，我把它留作未跟踪文件交由决策者提交（避免我替决策者制造提交）。
- 所有实验件都在 `%TEMP%\audit-engine\` 下；`insertion_probe.ps1` 曾临时新建的两个探针文件已删除且前后 `git status` 一致；被我误建的根目录 `%D%\` 已删除。
- 端口：9877 / 9888 / 9889 均无 LISTENING；无 Godot 进程残留；未 push。

### 证据目录（`%TEMP%\audit-engine\`，sha256 前缀）

| 文件 | sha256(前 16) | 内容 |
|---|---|---|
| `engine-net-diffstat.txt` | `0f2c9a3d2123fb23` | 净引擎改动文件表 |
| `engine-net-diff.txt` | `ec70e6c92f6ddf04` | 净引擎 diff（含全部 7 个 `-` 行） |
| `diff-patch1/2/3.txt` | `6b0ee95c2abde614` / `70decff99a232fd5` / `41867b2962fce8c7` | 三个补丁各自的提交 diff |
| `patch_behaviour4.log` | `5954440cc0f1eccd` | §1.6 字节行为（B0–B8） |
| `live_battery3.log` | `e3ec8893a4452963` | §2 编辑器侧契约 + 拒绝面 |
| `game_battery.log` | `a95d51449cfdfdb6` | §2 游戏侧契约对等 |
| `game_reject.log` | `a7136d2563402642` | §2 游戏侧拒绝面 |
| `insertion_probe.log` | `f855bb5d3ae83514` | §3.1/§3.2 植入反例 + 还原 |
| `exitprop-demo.log` | `cbb5ccc7d05687d2` | §3.2 三腿演示 |
| `guardprobe.log` | `41fdf40e990ae598` | §3.3 证据守卫白名单 |
| `watchprobe2.log` | `1886aaf792b84f05` | §3.4 假等待反例 |
| `doctest_mcp.log` | `bd0ec5279b79b183` | 门③ |
| `full_regression.log` | `62993e2b2bed21c9` | 门④ |
| `accept_m1_run1.log` / `accept_m1_run2.log` | `65cd257dcb6366dd` / `396c3466e0718330` | 门⑤ 两次 |
| `accept_run1_passlist.txt` / `accept_run2_passlist.txt` | `8cee697d2bfa30db` ×2 | 两次 PASS 清单逐字节一致 |