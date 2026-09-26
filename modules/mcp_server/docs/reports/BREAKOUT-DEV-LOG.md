## 4. 六条新能力判据 —— 逐条实测响应（含 sha256）

> 方案 §2 要求「逐条给出实测响应」；§5.1 要求每条至少三列：**判据编号 / 结论 / 证据（文件 + sha256）**。
> 下面每条都按该格式给，并在必要时补**反例检查结果**。

### 4.1 ① 注释保全 — `project_set_setting` / `editor_add_input_action`

**构造（实测）**：手写 `project.godot`（4 行 `; mcp060 comment N of 4`，节序 `[application] → [input] → [rendering]`，`[input]` **不是**末节，UTF-8 **无 BOM**、纯 LF）。
`S0 = 841e2803e5b8b4b77f37b5cdfad4174cfdeec25771371fe1c9fc0696a78bed3a`（383 B）。

| 判据 | 结论 | 证据 |
|---|---|---|
| **P1a** 证据真的写进去了（`S1 != S0`） | **通过** | `S1 = 94050a8079a71d6881b249725e7debc1f6e11411cb417bc3ef6af5f0317f2888`（1046 B）；`c1/project.godot.before` vs `c1/project.godot.after` |
| **P1b** 注释仍在（4/4 逐字） | **通过** | `p1_report.txt`：`comments=4`，`; mcp060 comment {1..4} of 4` 各 ≥1 次；`c1/project.godot.after` |
| **P1c** 目标节外逐字节不变 | **通过（附一条 cosmetic 观测）** | `p1c_section_split.txt`；见下方说明 |
| **P1d** 落点正确（都在 `[input]` 内） | **通过** | `p1_report.txt`：`[input]` offset 197、`[rendering]` offset 821、`probe_action` 205、`probe_action2` 293、`probe_key` 735 → 三者全在区间内 |
| **P1e** 幂等（同参再调 → `S2 == S1`） | **通过** | `S2 = 94050a8079a71d6881b249725e7debc1f6e11411cb417bc3ef6af5f0317f2888` = `S1` |
| **P1f** 引擎真的认了（不看文件看引擎） | **通过** | `editor_get_input_actions` 里 `mcp060_probe_action=True`、`mcp060_probe_action2=True`（`c1/c1_a6_get_input_actions.response.json`，sha256 `1a5da0e4…d1388`）；**另**：手写里有 `paddle_left` 吗 → `False`（说明不是我猜的），引擎内置 `ui_left` → `True` |
| **P1g** 对照组：未切换整文件写的工具**必须丢注释** | **通过** | `project_remove_autoload`（先 `project_add_autoload` 造出可删的 key）→ 文件以 `; Engine configuration file.` 开头、**探针注释 0 行**（`;` 开头行共 7 行，全是引擎自己的头）；`c1/p1g_after_remove_autoload.txt` |

**P1c 的细节（重要，因为它解释了「为什么不是逐字节」）**：
- `[application]` 节：**逐字节相同**（82 B → 82 B）。
- `[rendering]` 节：**去掉尾部换行后逐字节相同**（177 B → 178 B，差的正好是**追加节前 Godot 自己插的那个空行**）。
- 新增 `[physics]` 节被**追加到文件末尾**（46 B）。
- ⇒ **所有既有内容都在**；唯一差异是「追加一个全新节时前面的空行」。这不是注释丢失，也不是值被改写。

**调用与 sha256（逐个工具）**：

| 调用 | 工具 | 结果 | 响应 sha256 |
|---|---|---|---|
| `c1_a1_set_setting_input` | `project_set_setting{key:"input/mcp060_probe_action"}` | ok，`saved:true` | `a170b1cf055b0b424c27dfc0b3d25aea1f9a9f85925e17cd629a260169c0678f` |
| `c1_a2_add_input_action` | `editor_add_input_action{action,key:"K"}` | ok，`persisted:true` | `cf8a279559895fdec038e576cf246b5b6ff2ca32ee0a2311be2f2865ffdd02a8` |
| `c1_a2b_...` | 只给 `action` | ok，`event_count:0` | `7566f3a3823ac2f5da46c3432de695cc49520d7d49f69026cec82766fa86ff5a` |
| `c1_a2c_set_setting_probe_key` | `project_set_setting{key:"input/mcp060_probe_key"}` | ok | `ac4fceb6f2d1020e1404e318bbb388696d71a2db1c20583377a94c7501bde4e4` |
| `c1_a3_set_setting_physics` | `project_set_setting{key:"physics/common/physics_ticks_per_second",value:60}` | ok，`saved:true` | `191f06ae0d524dce80249d56d65958242d11327fc26955b33eb690666416c15b` |
| `c1_a5_..._repeat` | 同 a1 再调一次 | ok，**落盘字节不变** | `5604ab8fadaddc40b3e8f4fe2412ab5321c7484bffb257ff1aa56a6d64e2866e` |
| `c1_g0` / `c1_g1` / `c1_g2` | `project_remove_autoload`（不存在 / `project_add_autoload` / 真删） | `-32001`（文件未动） / ok / ok | `2142884b…9ab1` / `8b4217f7…283c` / `c0b481ce…7ced` |

**反例检查**：`C1 != 4`？否（=4）。注释行消失？否。`S1 == S0`？否。出现引擎 7 行头？**只在 P1g 的对照组里出现**（这是预期的）。幂等失败？否。`has_action` 为 false？否。

**新增观察（不在方案判据里，但重要）**：`project_set_setting` 写 `Dictionary` 值时，**引擎回显把 `74` 变成 `74.0` 并在 JSON 里加了 `keycode`/`type` 的键序**，落盘文本是 `"keycode": 74.0`（`project.godot.after`）——即**浮点化**；这是引擎序列化，不是本模块的收窄（登记为观察）。

### 4.2 ② C# 真结论 — `project_validate_scripts` / `project_validate_script` / `project_build_csharp`

**先说一个必须记的最重要发现（否则后面的数字没有意义）**：
> **`ok` 只在「本编辑器进程加载过项目程序集」时才可能出现。** `project_build_csharp` 是**另起 `dotnet build` 子进程**，它**不会**让已经在跑的编辑器加载新程序集；此时 `GDMono::get_project_assembly_modified_time()` 仍为 0，`is_source_newer_than_assembly()` 对每个可读 `.cs` 都为真 ⇒ **一律 `not_compiled`**。构建之后**必须重启编辑器**（REPORT-055 的证据脚本在它的 build 与 `ok` 检查之间正是这么做的，D86 锚点 `6fdb76af`）。
> **另有一个真实的工程配置根因**（本轮首次定位）：`Path::get_csharp_project_name()`（`modules/mono/utils/path_utils.cpp:232`）= `dotnet/project/assembly_name`，**空则取 `application/config/name`**。本工程的 `config/name` 是 `mcp-breakout`，而 `.csproj` 生成的是 `Mcp060Breakout.dll` ⇒ 引擎去找 `.godot/mono/temp/bin/Debug/**mcp-breakout.dll**`，**找不到** ⇒ 编辑器 stderr（`--verbose`）打出 `.NET: Failed to load project assembly` ⇒ 程序集时间 0 ⇒ 全 `not_compiled`。
> **修法（用 MCP 工具，不改实现）**：`project_set_setting{key:"dotnet/project/assembly_name", value:"Mcp060Breakout"}`，回读 `{"dotnet/project/assembly_name":"Mcp060Breakout", ...}`（sha256 `254d170df59fcc1797f65fe2ff81f39e8acd50a26757edeccfde69e6078c5c61`）。**改配置不是绕过工具**，而且这是引擎给这个用途的正规设置。

| 判据 | 结论 | 证据 |
|---|---|---|
| **P2a** 四类别都出现过（`ok`／`invalid`／`not_compiled` 各 ≥1） | **通过** | `ok`：`c2/c2_v5_validate_ok.response.json`（`valid_count=2`）与 `c2/c2_a2_validate_all_final.response.json`（`valid_count=6`）；`invalid`：`c2/c2_v2_validate_broken_built.response.json` 与 `c2/c2_v4_validate_both_in_one_response.response.json`；`not_compiled`：`c2/c2_v1_validate_broken_notbuilt.response.json`、`c2/c2_v3_validate_fixed_notbuilt.response.json` |
| **P2b** `not_compiled ≠ invalid`（T1 与 T3 都必须是 `not_compiled`） | **通过** | T1（写坏未构建）→ `count=1 invalid=0 not_compiled=1`，`valid=null`；T3（改好未构建）→ `count=1 invalid=0 not_compiled=1`，`valid=null`（两者响应 sha256 都是 `a631ecb2…5d39`，**逐字节相同**） |
| **P2c** 编译器原文是真的（`error CS####` + 文件位置） | **通过** | `c2/c2_v2_…` 的 `error_text` = `…\scripts\Broken.cs(5,5): error CS1519: 成员声明中的标记“this”无效 […] \| …\Broken.cs(5,23): error CS1002: 应输入 ; […]`；`p2_report.txt` 三条自检 `error CS####=True`、`Broken.cs=True`、`(行,列)=True` |
| **P2d** `valid` 的口径：`ok→true`、`invalid→false`、`not_compiled→null` | **通过** | `ok`：`c2b_validate_one` → `category=ok valid=True`；`invalid`：`v2` → `valid=False`；`not_compiled`：`v1`/`v3` → `valid=null`（**不是 `false`**） |
| **P2e** `count` 自洽（= 五类之和 = 被问的文件数） | **通过** | `a0`：`count=6 sum=6 self_consistent=True`；`a2`：`count=7 ok=6 not_compiled=1 sum=7 returned=7 errors_only=False` |
| **P2f** 单数工具对「改过未构建」拒绝且**不**说 `Compilation failed` | **通过** | `c2/c2_sv1_singular_broken_notbuilt.response.json` → `-32000`，message 含 `no build of this source is loaded, so the file was not compiled`，`data.suggestion` 明说「This is 'not compiled', which is not 'does not compile'」；**对照**：构建失败后的单数工具给 `code=0` + `valid=false` + `Compilation failed` |
| **P2g** 诚实边界写清 | **通过（声明）** | `p2_report.txt` 里 `P2g NOTE`：`invalid` 只可能在**本会话真的跑过一次 `project_build_csharp` 之后**出现；没有那次构建，工具**只能**答 `not_compiled`；**不得**把「工具能自己编译 C#」写成结论 |
| **强证据：同一响应里 `invalid` 与 `not_compiled` 并存** | **复现成功** | `c2/c2_v4_validate_both_in_one_response.response.json`：`count=2 invalid=1 not_compiled=1 sum=2`，两条 item 分别是 `SignalRegistry.cs: invalid`（`error_text` 带 CS0103）+ `Broken.cs: not_compiled`（`valid=null`）；sha256 `f83988170bbfbf5372e10797d9aa312b25d142eaebfc6c43f43c7cecb862f09e`（`REPORT-055` 的强证据形式，D86 锚点 `6fdb76af`，本轮**独立复现**） |
| **不可构造项：`unverifiable`** | **不可构造（显式声明）** | 试过的手段：`editor_execute_gdscript` 里 `ResourceLoader.load("res://scripts/Ball.cs","Script")` → 返回 `CSharpScript`（**引擎能把它当 `Script` 载入**），所以「载入失败」这条分支对一个**可读的 `.cs`** 不可达；`c2/c2_probe_engine_cs_state` 与 `probe-cs2/q1_*` 为证；未构造成功，**不记为通过** |

**构建（`project_build_csharp`）的真实输出**：

| 次数 | 场景 | exit_code | 响应 sha256 |
|---|---|---|---|
| 1 | 首次（`SignalRegistry.cs` 真有 CS0103×3） | **1** | `fb8d88641c70fb63863c201665b208e36f79750ec804ce1aff75fec5e73d3eaf` |
| 2 | 修好后 | 0 | `27ddf120a68c7b294cbc99677127a900b24052e3876943b0faeb1b27a29eb844` |
| 3 | 故意写坏 `Broken.cs` | 1 | `ce4e5f844eae1ff8728c91547cd9b54412048535b3d35efdfaf321f7798015fd` |
| 4 | 写坏 `SignalRegistry.cs`（为并存证据） | 1 | — |
| 5 | 全部修好后 | 0 | — |

> **第一次构建失败是真的**：`scripts/SignalRegistry.cs(10,31): error CS0103: 当前上下文中不存在名称"SignalName"`、两处 `ConnectFlags`。**我改的是我自己的 C# 源码**（`GodotObject.ConnectFlags.Deferred`），**不是模块实现**；修复后的源码与 sha256 在 `b0-bootstrap/authored-files.sha256`。

### 4.3 ③ 批量父子 — `editor_add_nodes_batch{resolve_within_batch:true}`

| 判据 | 结论 | 证据 |
|---|---|---|
| **P3a** 一次调用建完（单次、`status:ok`、`count` 对、`errors:[]`） | **通过** | `c3/c3_a1_batch_27.response.json`：`count=26 created=26 errors=0 status=ok`，响应 sha256 `c841696ca4bf68e82d0f3730d3cae1db951fd99b0f18992b77d41052c4ce029d`；追踪里**只有 1 行**该调用（`trace-*`） |
| **P3b** `parent_source` 两个值都出现 | **通过** | 逐元素列表：`scene`=**5**（`Main`/`Walls`/`Paddle`/`Ball`/`Bricks`），`batch`=**21**（3 墙 + 18 砖），`missing`=**0** |
| **P3c** **另一个工具**读回树（不能只看响应） | **通过** | `c3/c3_a2_read_tree.response.json`（`editor_get_scene_tree`）：`Main`、`Walls/WallLeft|Right|Top`、`Paddle`、`Ball`、`Bricks` 全 True，18 砖 **18/18**；**再** `editor_save_scene` 后 `project_read_scene_file_content` 读盘：砖 **18/18**、`Paddle`、`WallTop` 都在（`c3/main.tscn.final` + `c3/c3_a9_read_scene_final.response.json`） |
| **P3d** 顺序约束真被拒绝 + **整批回滚** | **通过** | `c3/c3_d1_batch_reversed.response.json` → **`-32001`**，`message="nodes[0]: parent 'RevHost' is created later in this batch (nodes[1]) not found"`，`data.batch{status:"rolled_back", on_error:"all_or_nothing", count:0, errors:[{index:0,…}]}`；读回证明 `RevHost`/`RevChild` **都不在树里** |
| **P3e** 同批重名被拒绝 + 回滚 | **通过** | `c3/c3_e1_batch_duplicate.response.json` → **`-32602`**，`"nodes[2]: 'DupHost/DupChild' is already created by nodes[1] of this batch, so a reference to it would be ambiguous"`，`rolled_back` 里逐项带 `index`/`node_path`/`reason`；读回 `DupHost` **不存在** |
| **P3f** 默认（不带 `resolve_within_batch`）逐字未变 | **通过** | 同一 body（`DupHost`+`DupChild`×2）不带该参数 → **`-32001`** `"nodes[1]: parent 'DupHost' not found"` + `rolled_back`（父路径**只按调用到达时的场景树解析**）；读回 `DupHost=False`、`DupChild count=0` |
| **P3g** 拒绝形状可链式判 | **通过** | `data.batch.errors[].index` 能定位**第 i 项**（d1 指 `index:0`，e1 指 `index:2`），并带 `parent_path`/`type`/`reason`；`suggestion` 给出下一步 |

**第一次尝试的教训（已撤回的错误构造）**：最初把 `Brick_r0_c0`（父 `Bricks`）+ `Bricks`（父 `.`）倒序放进批，**结果是成功**——因为 `Bricks` **已经在场景里**（本批更早的调用建的），`parent_path` 按场景树解析就够了，**不需要** `resolve_within_batch`。这不是工具的问题，是**构造不严**：要有判别力，父名必须是场景里不存在的（改 `RevHost`/`RevChild` 后才拒绝）。这条**本身就是「同一工具调两次才摸清用法」**，记入 §5。

### 4.4 ④ 批量挂脚本 — `editor_set_node_script_batch`

（本节在 §4.7 汇总时填入实测数字；脚本 `mcp060_c4_script_batch.ps1`，证据 `evidence/task060/c4/`。）

### 4.5 ⑤ `scope` 收窄 — `editor_list_signal_connections{scope:"user"}`

（本节在 §4.7 汇总时填入；脚本 `mcp060_c5_signals.ps1`，证据 `evidence/task060/c5/`。）

### 4.6 ⑥ 捕获的诚实性 — `--mcp-capture=every_call` 的 `changed:false`

（本节在 §4.7 汇总时填入；脚本 `mcp060_c6_capture.ps1`，证据 `evidence/task060/c6/`。）

### 4.7 六条判据汇总表（最终）

（在 §4.4–§4.6 实测完成后回填；格式：判据编号 / 结论 / 证据文件 + 行号 + sha256。）

---

## 5. 摩擦记录（同一工具调几次才成功 / 错误消息够不够自纠 / 是否必须先 A 探路再 B）

| # | 工具/工具族 | 调了几次才成功 | 错误消息自纠性 | 是否必须先 A 探路 |
|---|---|---|---|---|
| 1 | `editor_execute_gdscript` | **3 次**（前两次 `-32602 Parse error`） | **不足**：只说 `Parameter 'code' does not compile: Parse error`，**不指哪一行哪一列**。实测结论：**body 必须显式 `return`**，尾表达式会被丢掉并回 `{"result":null,"result_type":"Nil"}`（`probe-gdscript/p1_*` vs `p2_var_return`）。这条不是文档里有的，是**试出来的** | 是：先用 8 个最小 body 探清语法（`mcp060_probe_gds.ps1`） |
| 2 | `editor_add_nodes_batch`（顺序约束） | **2 次**（第一次构造不严，见 4.3） | 好：`reason` 直接写「Parent 'RevHost' is created later in this batch (nodes[1])」，`suggestion` 告诉你怎么改 | 是 |
| 3 | `editor_set_node_property*` 的 `node_path` 拼写 | **2 轮**（先 20/20 失败，再 20/20 成功） | **不足**：`-32001 Node '/root/Main/Ball' not found` 不告诉你它期望 `/root/...` 还是 `Main/...`；同一端点上的 `editor_set_node_script_batch` 又**认** `/root/...` | 是（A 探路：先从 `editor_get_scene_tree` 看它怎么叫节点） |
| 4 | `editor_set_node_property_batch` | **2 次**（先猜 `updates`） | **好**：`data.suggestion` 直接列出 `node_type, property, value` | 否（一次自纠） |
| 5 | `project_write_text_file`（.cs） | **1 次** | **好**：直接给替代工具 | 否 |
| 6 | `project_validate_scripts`（C# 判据） | **很多次**（因为要找到「为什么全 `not_compiled`」） | **好**：`reason` 里带引擎信号名（`is_source_newer_than_assembly`、`is_script_valid`）+ 文件行号（`csharp_script.h`、`script_language.h:180`）**这直接指明了 `not_compiled` 的两个来源**；`message` 还明说「不是编译失败」。**这是全轮自纠性最好的错误消息** | 是（但探路成本低） |
| 7 | `Restart-Editor`（不是工具，是流程） | **3 次** | — | — |

**其它摩擦（不构成「必须 A 探路」但值得记）**：
- `project_set_setting` 的 `Dictionary` 值经引擎回显会**浮点化**（`74 → 74.0`）。
- `editor_get_input_actions` 在**没有**该 action 时**不报错**，只是不列它——要判「有没有」必须**解析名字集合**，不能看文本包含（与 PLAYBOOK §7.4 同类陷阱）。
- **PowerShell 5.1 侧**（不是 MCP 的问题，但确实吃掉了三轮）：`ConvertTo-Json` 对**同一个** `OrderedDictionary` 实例第二次序列化会**永不返回**（先给它加了 `Count` 属性）；`Out-String | Select-String` 会把输出缓冲到进程结束；`Get-Process | ForEach { taskkill }` 在 `$ErrorActionPreference='Stop'` 下会被 taskkill 的 stderr 中断。这些都在 `%TEMP%\mcp-breakout\*.ps1` 的注释里留了原文。

---

## 6. 疑似缺陷 / 契约与描述不符（**只记录，不改实现**）

| # | 现象 | 期望 | 实际 | 严重度 | 证据 |
|---|---|---|---|---|---|
| **D-1** | **`node_path` 的基准在两个工具间不一致** | 同一个 MCP 端点上，`editor_set_node_property` / `editor_get_node_properties` 与 `editor_set_node_script_batch` 要么都收 `/root/...`，要么都不收；若要区分，description 里应写明 | `editor_set_node_script_batch` 收 `/root/Main/...`（方案 §2④ 就这么写、实测成功），`editor_set_node_property`/`editor_get_node_properties` **只收** `Main/...` | **minor–major**（实际用起来要多试一轮；20 次调用全废） | `c3/c3_a5_setpos_*.response.json`（`-32001`）vs `c4/…`（④ 用 `/root/...` 成功） |
| **D-2** | `editor_set_node_property_batch` **只能按类型**批量写同一值 | 契约描述「批量设置同类型节点的属性」**是准确的**——所以这**不是**契约错，而是**能力缺口**：没有「按路径列表批量写不同值」的工具 | 需要 N 次 `editor_set_node_property` | minor（可合并候选，见方案 §5） | `c3/c3_a5_batch_positions.response.json`（`-32602` Unknown parameter 'updates'） |