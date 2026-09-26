# REPORT-059 — D-4 行为切换与描述同批 + 门内恒真断言（D-2）+ 小缺陷（D-1/D-5/D-7/D-3）

> 本报告**取代**上一轮留在同一路径的判定包。判定包已按任务书要求**另存为附件**：
> `docs/reports/REPORT-059-JUDGEMENT-PACK.md`（逐字保留，未改一字；本报告引用它的判定）。
>
> **结论锚点（D86）**
> - **本批的代码/脚本提交**：`d569b58d28`（D-4 实现）→ `60584b317e`（D-2/D-1/D-5 脚本）→ `739e0bb555`（判定包留存）
>   → `cd7224274`（D-8：停止在检查里钉死生成器版本；`mcp059_gates.ps1`）
> - **全部门与回归实测的 HEAD**：`cd7224274`（`--short=9`），分支 `feature/mcp-server-module`
> - **两个二进制**（本批**串行**重建，从 `cmd` 启动、不抑制输出、未并发跑第二个 scons）：
>   - plain：`4.8.dev.custom_build.cd7224274`
>   - mono：`4.8.dev.mono.custom_build.cd7224274`
> - **契约**：175 条（`docs/tools_list.renamed.json`，142227 B → 148333 B，SHA256
>   `c169bb676ec61c190a772b976bc8301aefc3c4b43c3545deae2cb931b6963334`）
> - **工作树收尾**：只剩既有未跟踪物 **4 个**（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、
>   `install-deps-m0.cmd`）＋本报告（待提交）。`git diff --stat` **0 行**。

- **status**：**PASS**（D-4 / D-2 / D-1 / D-5 / D-7 / D-3 六件事全部落地；五道门 + 门⑥ 三段式 + 契约三检查 +
  15 步回归电池 + 两条点名脚本全部实跑并退出 0）
- **本批新增发现的缺陷**：**D-8**（三处检查把生成器版本钉死成字面量 `1.17.0`，被本批的版本递增打红；见 §6）

---

## 0. 做了什么（一句话版）

TASK-057 补丁 2 提供了 `ProjectSettings::save_custom_section()`，但**没有切换任何工具**，把「5 条契约描述已被证伪」
报成 D-4。本批**把行为与描述同批切换**：3 个工具改走引擎的按节写出口（注释不再丢），2 个工具**诚实保留**整文件重写
并在描述里写清**为什么**；同时修掉门内的恒真断言（D-2）、重复 `Check`（D-1）、硬编码 scons 路径（D-5），
并把门⑥ 式的「有限集合 + 插入探针 + pin 清单」搬到恒真断言这一类缺陷上。

---

## 1. D-4：行为切换

### 1.1 判定（**采用**判定包，但逐条复测；两处判定被纠正）

任务书与手册允许我阅读源码来生成决策，**不允许**把上一轮的文字当预言机。判定包 §2 的每一条我都对着树复测过，
`文件:行` 依据见下。**两处与判定包不同**，按复测结果执行：

| 判定包的说法 | 复测结果 | 处置 |
|---|---|---|
| 行 787 的工具是 `editor_reload_mcp_plugin`（"to be confirmed"） | 实际是 **`editor_reload_plugin`**（`docs/tools_list.renamed.json` 第 787 行的 `name`；§1.5 的 `_meta.overrides` 记录键是 `reload_plugin`） | 按 `editor_reload_plugin` 处理 |
| 契约条数 175（判定包 §2.4 断言） | **复测为真**：`_meta.count=175`，`result.tools` 175 条，本批未改条数 | 保持 |

其余判定（引擎 API 语义、两处发布助手、四个回退条件、`_meta.overrides` 机制、生成器版本三处一致、门① 逐字）
全部复测通过，逐条依据见 §1.2 / §1.4。

### 1.2 哪些工具**切换**、哪些**不切换**，以及**回退条件**（源码依据）

五个工具的写入路径（本批改动前的实测）：

| 契约 `name` | 写入路径 | 判定 |
|---|---|---|
| `project_set_setting` | `tools/project_setting_write.cpp:217` `set_setting()` → `:218` `publish_project_settings()` → `tools/tool_helpers.cpp:575` `publish_project_settings_to()` → `:564` `save_custom()` | **切换** |
| `editor_add_input_action` | `tools/editor_input_simulation.cpp:665` `persist_input_action()` → `tool_helpers.cpp:842/862` `persist_input_action_to()` → `:815` `publish_project_settings_to()` | **切换** |
| `project_add_autoload` | `tools/project_autoload_write.cpp` `set_setting(key, declared)` → `publish_project_settings[_to]()` | **切换** |
| `project_remove_autoload` | 同上，但是 `settings->clear(key)` —— **删键** | **不切换**（见下） |
| `editor_reload_plugin` | `tools/editor_write_scene_editor.cpp:396-397` `EditorNode::set_addon_plugin_enabled(name,false/true,false)`；保存由**编辑器自己**的 `_update_addon_config()` → `queue_save()` → `ProjectSettingsEditor` 定时器 → `ProjectSettings::save()` 整文件完成 | **不切换**（见下） |

**新引擎 API 的结构性事实（复测，非转述）**：

- `ProjectSettings::update_settings_section_text()`（`core/config/project_settings.cpp:1537-1680`）
  **只替换已存在键的值跨度**（`:1605-1619`）、**只追加**不存在的键（`:1628-1659`），**从不删除键**
  （契约注释 `core/config/project_settings.h:226-227`）。
  节名非法（含 `[`/`]`/换行、空）→ `ERR_INVALID_PARAMETER`（`:1540-1543`）；键不属于该节 → `ERR_INVALID_PARAMETER`
  （`:1553`）；值无法序列化 → `ERR_INVALID_DATA`（`:1557`）；**空 `p_custom`** → `OK` 且文本不变（`:1562-1564`）。
- `ProjectSettings::save_custom_section()`（`:1682-1777`）是 I/O 半边：**目标文件不存在时返回
  `ERR_FILE_NOT_FOUND` 且什么都不创建**（`:1685-1689`）；`updated == text` 时**连文件都不碰**（`:1728-1733`）。
- 节名 = 键**首个** `/` 之前的部分（`_get_property_list()` 的切分，`:1309-1320`：无 `/` 的键落到 **空 category**，
  即文件顶部**无头全局块**），这同时是 `save_custom_section()` 对 `p_custom` 的强制规则（`:1552-1554`）。

**四个整文件回退条件**（全部明写进三条新描述，并被 `tools/tool_helpers.h` 与 doctest 逐个钉住）：

1. **键无法唯一归节**：键没有 `/`，或 `/` 在首字符 —— `_save_settings_text()` 把它写进**无头全局块**
   （`category = ""`，`:1314-1315`），那个块**没有节名**可以交给按节写出口；
2. **目标文件不存在**：按节写出口**只写进文件、从不创建文件**（`:1685-1689`），而整文件写出口**会**创建它 ——
   回退因此**逐字节保留**了 TASK-059 之前这一情形的行为（**这是与旧行为的唯一差异被显式处置的地方**：不是"新 API 更好"，
   而是"回退保持旧行为"）；
3. **引擎拒绝按节写**：节名带 `[`/`]`/换行、值无法序列化、文件读不回来（`:1540-1558`、`:1691-1710`）——
   整文件写出口是**唯一还能产出所要求终态**的写者；
4. **该设置名已在文件的无头全局块里**：`ConfigFile` 把那个块叫 `""` 节（`core/io/config_file.cpp:282/298`），
   而 `ProjectSettings` 会把写在那里的 `section/key` 解析成**同一个设置名** —— 按节写会留下一条**过期重复行**，
   整文件写出口则会规范化整个文件。文件**压根读不成 config** 时归入本类（不在引擎自己的读取器都拒绝的文件上做手术）。

第 5 条「空 `p_custom`」在**工具路径上不可达**（三个切换的工具都恰好写一个键），故不作为回退条件，只在
`tools/tool_helpers.h` 里登记为 API 语义。

**两个不切换的工具，理由（写进各自的描述）**：

- `project_remove_autoload`：本工具**全部工作就是删键**，而按节写出口**从不删键**。要按节做就必须从内存重建整节
  `[autoload]`、重排其余条目的序列化形状、丢掉节内手写注释，并新增「枚举命名空间构造 `CustomMap`」的辅助函数 ——
  对一个工具而言是真实且**高风险**的行为变更。**保留整文件重写，并诚实说明注释仍会丢。**
- `editor_reload_plugin`：**保存不是本模块发出的**。`set_addon_plugin_enabled()` 的 `p_config_changed=false`
  **约束不了** `_update_addon_config()`（`editor/editor_node.cpp:4548`/`4627` 都走它），它无条件
  `project_settings_editor->queue_save()`，由编辑器自己的定时器 `_save()` → `ProjectSettings::save()` 整文件完成。
  本模块既决定不了「要不要写」，也拿不到「写哪一节」——**无节可命名**。新描述改为点明
  「本工具自己不写文件、保存是编辑器的副作用」。

### 1.3 实现落点

| 内容 | 位置 |
|---|---|
| `String MCPTools::project_setting_section(const String &)` | `tools/tool_helpers.h`（声明）/ `tools/tool_helpers.cpp` |
| `bool MCPTools::publish_project_setting_to(path, key, out_whole_file, err)` | 同上；四个回退条件**逐个命名**在同一个 `if` 里，与契约的描述是同一张清单 |
| `bool MCPTools::publish_project_setting(key, out_whole_file, err)` | 对 `project_settings_file_path()` 的包装 |
| `add_autoload(..., const String &p_target_path = String())` / `remove_autoload(..., const String &p_target_path = String())` | `tools/project_autoload_write.h/.cpp`：**纯可测性**接口扩展（默认空串 = 本进程真实的 `project.godot`），使二者能在 doctest 里对着一个测试自己拥有的文件跑；行为默认值不变 |
| 5 个 C++ 注册字面量 | `tools/project_setting_write.cpp` / `project_autoload_write.cpp` / `editor_input_simulation.cpp` / `editor_write_scene_editor.cpp`，由 `scripts/mcp059_sync_literals.py` **从契约同步**（门① 逐字门要求两侧字节相等） |

**取值来源**：按节写发布的是 `settings->get_setting(key)`（**内存里的当前值**），不是调用方传进来的
`converted` —— 这与整文件写出口 `_save_settings_text()` 读的 `get(key)`（`:1200`）是**同一个读**，
所以落进文件的是「整文件保存这一个键会写的同一串字节」。

**顺手修掉的一处死代码**：`add_autoload()` 在键不存在分支里读 `settings->get_setting(key)` 并 `(void)` 掉，
而该读在键缺失时会打一条 `ERROR: Request for nonexistent project setting` —— 即「第一次
`project_add_autoload` 必然打一条引擎错误」。该行删除（行为不变）。

### 1.4 描述同批改（v1.18.0，`mode: replace`）

- 生成器 `scripts/gen_renamed_contract.py`：`GENERATOR_VERSION` `1.17.0` → **`1.18.0`**；
  5 条 `DESCRIPTION_OVERRIDES` 记录全部改成 **`mode: "replace"`** —— 被移除的是一句**事实错误**的话，
  append 式的判别句会把假话留**在调用方读的那个字段里**（这正是 TASK-007 引入 `replace` 的理由）。
- 每条新 `reason` **逐字引用**：①旧契约原文（中文句首，`replace` 模式的守卫要求）；②**被移除的假句**
  （`(the engine has no partial-publish API)`，为了审计）。原文"引擎无局部发布 API"因此**只**留在
  `_meta.overrides` 的审计记录里，**不再出现在任何 `description` 或任何 C++ 字面量里**（实测 `findstr` 命中 5 处，
  全部是 `reason`）。
- 三条**切换**工具的正文由模块级常量 `_T059_SECTION_WRITE` 承载（**一份字面量、三处引用**，防止三份描述漂移），
  它同时说清任务书要求的三件事：①按节写**保留注释与其余文本**（注释、空行、键序、UTF-8 BOM、CRLF 逐字节）；
  ②**何时仍整文件重写**（四个回退条件逐个列出）；③**这是行为改善——之前每次都整文件重写、每次都丢注释**。
- 两条**不切换**工具的正文说明「为什么切不了」以及「注释**仍然**会丢」，不冒充能力。
- 指纹同步：`docs/tool-groups-added.json` 的 `source.generator_version` → `1.18.0`（并与 `source.entries` 散文同步，
  以满足 `check_tool_groups.py` 的「散文可以多说，不能少说/说错」断言）。`_meta.map_sha256` **未动**
  （映射文件本批未改，实测仍为 `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd`）。
- **契约条数不变**：175（`mcp059_contract_pre_post.py` 断言 `before=after=175`）。

### 1.5 行为变更（**逐条声明**，不只写"改善了"）

1. **注释不再丢**（三个切换的工具，且在四个回退条件**不成立**时）：这是本批的**目的**，也是行为**改善**。
2. **目标文件不存在时**：新 API **不创建**文件，**回退**到整文件写出口**创建**它 —— **旧行为被保留**（不是"新行为"）。
3. **删除/清空一个键**（`project_remove_autoload`）：**仍是整文件重写**，注释**仍然会丢**。描述明写。
4. **只写被点名的那一个设置**：整文件写出口会把**内存里所有**设置都重新落盘（含编辑器里**未保存**的改动），
   按节写只落这一个键。即「一次工具调用不再顺手把编辑器内存里其它未保存的改动提交到磁盘」。这是**改善**，
   但确实是调用方可观察的差异，故明写。
5. **`save_custom()` 会跳过「等于初始值」的设置**（`:1286`）而按节写会**显式写出**它：把一个设置写回引擎默认值时，
   文件里由「键被移除」变成「键在、值为默认」。加载后的**设置值相同**（读取结果等价），差异仅在文件内容 ——
   归入「场景①的文件内容变更」，在此显式登记。
6. **未被本批改动的**：`--import` 与游戏运行都把文件留原样（实测）；`save_custom()` 的整文件行为未动
   （`mcp057_settings_publish_evidence.ps1` 的 `p2_save_custom_still_rewrites_the_whole_file` 仍 PASS）；
   175 条工具的**名字与 `inputSchema` 逐字节未动**（§3.1）。

---

## 2. 证据（红/绿当场保存；工具路径与字节级各一条腿）

### 2.1 TDD 红/绿（**红相位输出当场保存**，不事后补造）

- **重构步**（先落地无行为变化的接口，证明不破坏既有）：`build_local.cmd` exit 0；
  `--test-case="[MCPServer]*"` → `332 | 331 passed | 1 failed`，唯一失败是
  `TASK-054 O-12`（`mcp_trace` 目标文件陈旧：`-Force` 没跑，`version_generated.gen.h` 变了而该对象没重建 —— 
  `build_local.cmd` 头部注释记载的**已知陷阱**）；随后 `-Force` 构建即恢复。
- **红相位**（只加了测试、未实现切换）：`--test-case="[MCPServer] TASK-059*"`
  ```
  test cases:  3 |  0 passed |  3 failed | 1761 skipped
  assertions: 86 | 66 passed | 20 failed
  Status: FAILURE!
  ```
  失败**原因正确**：`comment_lines(after) == 7`（拿到了整文件写出口自己的 7 行头，期望 4）、
  `after.contains("; comment 1 of 4") == false`、`whole_file == true`（期望 false）。
  日志：`%TEMP%\t059\red_phase.txt`（**当场落盘**）。
- **绿相位**（实现切换后）：`3 | 3 passed | 0 failed`，`89 | 89 passed | 0 failed`，`Status: SUCCESS!`
  日志：`%TEMP%\t059\green_phase.txt`。
- **模块套件**：`335 | 335 passed | 0 failed`（332 → 335，**只增不改**），`assertions 23714 | 23714 passed | 0 failed`。
  日志：`%TEMP%\t059\module_after_switch.txt`。

**D-3 的教训（按任务书要求写进报告，逐字）**：
> **红相位输出必须当场保存**（这是本项目的既有纪律，不得事后补造）。

TASK-057 的 4 个引擎侧 doctest 至今**没有**红相位输出（执行者写完代码即中断），本批**接受该声明、不伪造**
（任务书 §3 已裁定接受），并以**进程外**证据替代（§2.2/§2.3）。

### 2.2 工具路径的活证据（`scripts/mcp059_section_switch_evidence.ps1`，**30/30 PASS**）

在 9888 上启动 plain 编辑器，对着一个**带 4 行手写注释、`[input]` 故意不是末节**的 scratch 工程，**通过 MCP 工具**
（不是裸引擎 API）调用，全部实测：

| 检查 | 关键实测 |
|---|---|
| `p3_set_setting_keeps_every_comment` | `comments before=4/4 after=4/4`；文件**不以** `; Engine configuration file.` 开头 |
| `p3_set_setting_only_the_target_section_moved` | `prefix before [application] identical=True; suffix from [input] on identical=True` |
| `p3_set_setting_key_landed_in_its_section` | `[application] at 87, mcp059_marker=42 at 211, [input] at 255` —— 新键在 `[application]` 内，**不在**文件末尾 |
| `p3_set_setting_is_idempotent` | 第二次同参调用 sha256 不变 |
| `p3_add_input_action_keeps_every_comment` | `[input] at 236, mcp059_switch= at 284, [rendering] at 738` —— 注释 4/4，键在 `[input]` 内而非 `[rendering]` 之下（R1 反例被排除） |
| `p3_input_action_visible_to_the_engine` | **另起** `--headless --script` 进程问引擎自己的 InputMap：`has_action(mcp059_probe_action)=True`，注释仍 4/4 |
| `p3_add_autoload_keeps_every_comment` | 新建整节 `[autoload]` 之后注释仍 4/4 |
| `p3_fallback_remove_autoload_rewrites_the_whole_file` | 4 行手写注释消失、文件现在带引擎自己的 **7** 行头、`StartsWith('; Engine configuration file.')=True` —— **如实表现** |
| `p3_fallback_bare_key_rewrites_the_whole_file` | 同上（无 `/` 的键）；且 `p3_fallback_bare_key_still_saved_the_value`（`mcp059_bare=7` 在位）、`_error_free`（`error_code=0`：回退是**声明过的成功**，不是错误） |
| `p3_import_leaves_the_file_unchanged` | `--import` exit 0，sha 前后相同，注释 4/4 |
| `p3_game_run_leaves_the_file_unchanged` | `--quit-after 2` exit 0，sha 前后相同 |
| `p3_live_tools_list_is_deterministic` | 同进程两次 `tools/list` **字节相同**，live count=152 |
| `p3_rewritten_descriptions_are_on_the_wire` | 5 条描述与契约**逐字相等**；切换的那条同时含「section by section」「behaviour improvement」且**不含**「no partial-publish」；保留的那条含「never deletes a key」 |
| `p3_port_9877_guard` | `listening=False pid_before=-1 pid_after=-1 ours=False same_pid=True asked_by_us=False` |

**回退条件 2（目标文件不存在）在工具路径上不可达**：三个切换的工具都写到本进程真实的 `project.godot`，
而编辑器起于一个该文件必然存在的工程。它由 **doctest**（`TASK-059 ... the four fall-backs` 的 `(3)`）覆盖：
`CHECK(whole_file)` + `CHECK(FileAccess::exists(missing))` + 引擎读回值 —— **此处显式声明不可构造的原因**。

### 2.3 引擎侧字节级证据（`scripts/mcp057_settings_publish_evidence.ps1`，**23/23 PASS**）

TASK-057 的 24 项在此仍全绿，**且计数从 24 降到 23 正是 D-1 去重生效**的可见结果：

```
[PASS] p2_bytes_exact_lf :: actual=409B sha=5453ba95… expected=409B
[PASS] p2_idempotent_second_call :: sha after first=5453ba95… sha after second=5453ba95…
[PASS] p2_bom_preserved :: before[0..2]=EF BB BF after[0..2]=EF BB BF
[PASS] p2_crlf_preserved_and_new_line_is_crlf :: no_bare_lf=True inserted_with_crlf=True
[PASS] p2_RED_naive_splice_is_silent_and_wrong :: has_action=False (expected false) file_still_parses=True
[PASS] p2_has_action_true_after_publish_R1_reversed :: has_action=true
[PASS] p2_concurrency_four_writers_all_exit_zero :: … survivors=4/4 (…); still running after the wait: 0
[PASS] p2_save_custom_still_rewrites_the_whole_file :: header_written=True hand_comments_gone=True
[PASS] p2_no_scratch_engine_process_left :: swept at the end: 0 process id(s) ; test ports 9888/9889 still bound:
--- checks: 23, failures: 0 ---
SETTINGS-PUBLISH EVIDENCE PASS
```

### 2.4 幂等 / 非末节反例 / 导入与游戏运行 —— 一句话汇总

- **幂等**：工具路径（`p3_set_setting_is_idempotent`）与引擎路径（`p2_idempotent_second_call`、
  doctest `(1)`/`(4)`）三级都实测「第二次同参调用字节不变」。
- **`[input]` 非末节反例**：`p3_input_action_landed_inside_input_not_after_it`（工具路径）＋
  `p2_RED_naive_splice_*`（被否决的文本拼接静默落错节的**红对照**）＋ doctrine 的 `(1)`。
- **`--import` / 游戏运行后不变**：工具路径两条 + 引擎路径两条，四组 sha 前后相同。

---

## 3. D-2（门内恒真断言）+ D-1（重复 `Check`）

### 3.1 D-2 的修法

`mcp057_settings_publish_evidence.ps1` 的 `p2_no_scratch_engine_process_left` 原判据以一个与常量 `$true` 的析取结尾
（该拼写逐字写在文件里的注释中，并被下面的机器检查 pin 住）。与常量真的析取就是常量真，而 `Check` 只在判据为假时
才让 `$script:Failures` 自增 —— 所以**这一行永远不可能失败**，它自称"检查没有残留进程"，实际**什么都没检查**。

现在它是一句真断言，且**两条腿**：

```
$swept = Stop-ScratchEngineProcesses
$busyPorts = @(Get-BusyTestPorts @(9888, 9889))
Check 'p2_no_scratch_engine_process_left' (($swept.Count -eq 0) -and ($busyPorts.Count -eq 0)) (…)
```

第二条腿（**把测试端口真的 bind 一次**）不是装饰：一个没能加载探针主循环的 scratch Godot 会**一直跑下去**，
它既留下进程、也**占着监听**。`Test-TestPortFree` 用 `TcpListener` 试探而**不解析 `netstat` 文本** ——
`netstat` 的状态词随系统语言本地化，文本匹配会在换语言时**静默停止工作**（这正是 D-2 的同类）。

### 3.2 失败演示（`scripts/mcp059_d2_failure_demo.ps1`，**11/11 PASS**）

**造残留 → 必须 FAIL → 清理 → 还原**，三段式，全部实测：

```
[PASS] d2_no_leftover_before_the_demo :: processes matching the sweep selector:
[PASS] d2_baseline_evidence_exits_zero :: baseline exit code = 0
[PASS] d2_baseline_check_passes       :: [PASS] p2_no_scratch_engine_process_left :: swept at the end: 0 process id(s)
[PASS] d2_leftover_is_visible_to_the_selector :: manufactured pid=85876 name=mcp059_fake_godot; selector found 1 process(es)
[PASS] d2_manufactured_evidence_exits_nonzero :: WITH a leftover present the evidence script exits 1
[PASS] d2_manufactured_check_reports_fail :: [FAIL] p2_no_scratch_engine_process_left :: swept at the end: 1 process id(s) 85876
[PASS] d2_no_leftover_after_the_cleanup
[PASS] d2_fake_binary_removed
[PASS] d2_restored_evidence_exits_zero :: restored exit code = 0
[PASS] d2_restored_check_passes
--- exit codes: baseline=0 manufactured=1 restored=0 ---
D2 FAILURE DEMO PASS (a leftover makes the fixed check fail, a clean machine makes it pass)
```

残留物是**真的独立进程**（把 `cmd.exe` 复制成 `%TEMP%\mcp057\mcp059_fake_godot.exe` 再带休眠命令行启动），
它恰好满足 `Stop-ScratchEngineProcesses` 的选择器（进程名含 `godot` **且**命令行提到 scratch 根），
所以证据脚本的扫尾**真的**杀掉它并**真的**报 1。它**不是**用户 9877 上的编辑器（全程未碰 9877）。

### 3.3 把这一类固化为仓库内断言（判定包 §3.2 的建议）

新增 **`scripts/check_tautologies.py`**（门⑥ 的同形答案：**已声明拼写集合 + 插入探针 + pin 清单 + 有界保证**）：

- 扫描 `modules/mcp_server/scripts/**` 与 `modules/mcp_server/docs/scripts/**` 的 `.ps1`/`.py`；
- **14 种已声明拼写**（9 PowerShell：`-or $true`、`-or 'true'`/`"true"`、`-and $false`、`-and 'false'`/`"false"`、
  `if ($false)`、`if ($true)`、`$true -eq $true`、`$false -eq $false`、`$true -ne $false`；
  5 Python：`or True`、`and False`、`if True:`、`if False:`、`assert True`）；
- **`--probes`**：每种拼写插入合成样本**必须命中**（`14/14`），另加 **4 个近似但不恒真**的样本**必须不命中**
  → `PROBES: 18/18`；插入探针文件本身**不进仓库**（内存字符串，不写树）；
- **`--coverage`**：打印已声明集合与**集合之外**（运行时把 `double` 隐式写进槽位、由变量构成的恒真、`.cmd`、
  根目录以外的文件……）——**保证是有界的，不是"无恒真"的证明**；
- **pin 清单**：恰好 1 条 —— 修复后留下的注释**逐字引用**了旧判据，pin 把这句引用变成**记录在案的决定**
  （并给出理由），而不是一个新的缺陷。清单条目与源码**双向**失配都失败（引文消失 = 过期 pin）。

实测：

```
DECLARED SPELLINGS : 9 powershell + 5 python
PINNED             : 1 (file, pattern) pair(s)
PINNED OK scripts\mcp057_settings_publish_evidence.ps1 ps_or_true (1) :: TASK-059 D-2: …
          at line 396: # the constant `$true`: the predicate was `($swept.Count -eq 0 -or $true)`. A
TAUTOLOGY CHECK PASS (every hit is pinned; scanned=2 file kind(s) under 2 root(s))
PROBES: 18/18 (14 declared spelling(s) + 4 near miss(es))
```

### 3.4 恒真模式普查（**独立复跑**，确认无第二处）

在**修 :364 之前**用仓库脚本的同一批拼写普查 `scripts/**`（`.ps1` / `.cmd` / `.py`，含 `docs/scripts/**`）：

| 拼写 | 命中 | 判定 |
|---|---|---|
| `-or $true` | **1**（`mcp057_settings_publish_evidence.ps1:364`） | **已修**（并 pin 住那句引文） |
| `-or 'true'` / `-or "true"` | 0 | — |
| `-and $false` / `-and 'false'` | 0 | — |
| `if ($false)` / `if ($true)` | 0 | — |
| `$true -eq $true` / `$false -eq $false` / `$true -ne $false` | 0 | — |
| `or True` / `and False` / `if True:` / `if False:` / `assert True` | 0 | — |
| `-eq $false` / `-ne $true` 作**常量**谓词 | 0 | 既有命中全部是**对已解析 JSON 值/引擎返回值的真实比较**（例：`$gameProbe.is_editor -eq $false`），不是常量谓词 |

**结论：无第二处。**（普查的机器化版本就是 §3.3 的 `check_tautologies.py`，此后每次门都会重跑。）

### 3.5 D-1：重复 `Check` 去重（**未删掉 survivor 断言**）

`:319` 与 `:332` 曾以**同一个 id** 调用 `Check` 两次（参数不同），导致汇总里同 id 两行、`checks:` 计数含重复项。
处理：**删掉 `:319` 那次调用**（它只断言 `$jobCodesOk`），**保留 `:332`**（它断言 `$jobCodesOk` **加上** survivor 计数
——证据更强的那一条）。`:319` 的原结果折进 survivor 行的证据串，判据本身**一条都没丢**。
可见结果：本批引擎侧证据的 `checks: 24` → **`checks: 23`**。

---

## 4. 小缺陷

### 4.1 D-5：scons 路径改为**探测** + 可读报错

`mcp057_build_mono.cmd`（以及**同一处缺陷**的 `build_local.cmd`）原先在两处硬编码
`D:\Anaconda\Scripts\scons.exe`。现在两个脚本用**同一段探测**，按序尝试三个来源，并**打印命中的来源**
（一个错的解释器因此是可见的，而不是静默的）：

1. `%SCONS%`（显式覆盖，路径或名字）；2. PATH 上的 `scons`；3. 已知绝对路径（保留给写这个文件的机器）。
   一个 `pip` 装的 `scons.exe` 是 `python -m SCons` 的启动器，其目录被加进 `PATH` 以免找不到 Python。

三个来源都不成立时打印一段**可照做的报错**并 `exit /b 3`（列出三个来源+"`set SCONS=…`"或
"`python -m pip install scons`"+如何只看探测不构建）。`--probe-only` 可供检查，`SCONS_NO_KNOWN_PATH=1`
是**测试钩子**（让候选 3 可被关掉，好在那台确实装有候选 3 的机器上**确定性地**演示报错）。

演示 `scripts/mcp059_d5_scons_probe_demo.ps1`，**9/9 PASS**：

```
[PASS] d5_build_local_resolves :: exit=0; scons: D:\Anaconda\Scripts\scons.exe  (from first `scons` on PATH)
[PASS] d5_build_mono_resolves  :: exit=0; scons: D:\Anaconda\Scripts\scons.exe  (from first `scons` on PATH)
[PASS] d5_resolution_names_its_source
[PASS] d5_bad_override_falls_through_visibly :: SCONS 指向不存在的路径时仍解析成功，且来源被打印
[PASS] d5_scrap_the_path_reports_readably :: exit=3; first line: FATAL: no scons interpreter found; this build cannot run.
[PASS] d5_error_names_all_three_candidates
[PASS] d5_error_suggests_the_probe
[PASS] d5_probe_only_does_not_build
[PASS] d5_no_hardcoded_invocation_left
```

### 4.2 D-7：`save_custom_section` 的已知窗口 —— **保留现状，如实登记**

`core/config/project_settings.cpp:1763-1764` 用 `DirAccess::remove_absolute(p_path)` 紧跟
`rename_absolute(temp, p_path)`，**不是** POSIX 的原子替换，两者之间存在一个极小窗口；代码以
「备份 + 失败回滚」（`:1741-1775`）覆盖它。**本批保留现状**（任务书 §3 允许），登记为**已知窗口**：
`remove` 与 `rename` 之间若进程被杀，目标文件会短暂缺失，回滚路径只在**函数自己能观察到失败**时才触发。
本批的并发证据（四个写者）仍只断言「不撕裂 / 目标节外字节不动」，**不**保证 no-lost-update —— 脚本自己
也这么声明。**未做**低成本的原子替换：Windows 上 `MoveFileEx(..., MOVEFILE_REPLACE_EXISTING)` 需要动引擎
I/O 层且要重跑并发矩阵，风险/收益不划算。

### 4.3 D-3：接受声明 + 教训入报告

见 §2.1 末：**接受** TASK-057 的「4 个新 doctest 无红相位输出、无法重建」声明，**不伪造**红日志；
把教训（**红相位输出必须当场保存**）写进报告，并在本批的 TDD 里**当场落盘**红/绿两侧输出。

---

## 5. 契约 pre/post：既有的 175 条工具

`scripts/mcp059_contract_pre_post.py`（**allow-list，不是 diff 阅读器**；before 侧从 git 读出，
故不依赖任何第二份副本）—— **20/20 PASS**：

```
before: 213b1791258aa476e6b271e57733a689ad8f3ff9:…tools_list.renamed.json (142227 bytes)
after : …tools_list.renamed.json (148333 bytes)
[PASS] count_is_175 :: before=175 after=175
[PASS] names_and_order_identical :: the ordered name list is byte-identical (175 names)
[PASS] every_inputSchema_identical :: moved schema(s): none (175/175)
[PASS] only_the_five_descriptions_moved
[PASS] desc_project_set_setting / desc_editor_add_input_action / desc_project_add_autoload
       / desc_project_remove_autoload / desc_editor_reload_plugin
[PASS] meta_only_the_allowed_keys_moved :: moved: generator_version, overrides; unexpected: none
[PASS] meta_count_unchanged / meta_map_sha256_unchanged / meta_added_tools_unchanged / meta_added_count_unchanged
[PASS] meta_excluded_unchanged / meta_merged_unchanged / meta_generated_from_sha256_unchanged
[PASS] meta_order_normative_unchanged / meta_tool_count_in_unchanged
[PASS] five_replace_records_present
CONTRACT PRE/POST PASS
```

即：**175 条的名字与顺序逐字节不变、175 条的 `inputSchema` 逐字节不变**；**只有 5 条 `description`**
加上 `generator_version` 与它们的 `overrides` 审计记录发生变化。**契约条数 175 不变。**

**在线侧**（门①，实况 `tools/list` 对契约逐字）：5 次运行各 `3/3 checks passed`，
`implemented_union=152 tools (editor endpoint) / 72 tools (game endpoint)`，`contract=175`。
**回归侧**：15 步电池跑完后 `git diff --stat = 0 行`、`newly modified=0`、`newly untracked=0`
（`tracked_evidence_restored`）—— 即那些脚本重写的**被跟踪证据**逐字节回到 HEAD，
说明**没有任何工具响应**在这些场景里发生非声明变化。

**（诚实边界）**「175 工具的场景①文件内容变更」这一条，本批的机器证据是：
①5 条描述变更（上面）；②`p3_*` 里三个切换工具在**同一场景**下的文件字节变化（§2.2）；
③其余工具在既有证据脚本的场景下**响应与证据文件逐字节不变**（电池的 `newfile modified=0`）。
**本批没有**新建一个"对全部 175 个工具各调一次并逐字节比对响应"的通用工具——
那需要一个本批范围之外的新测试骨架；此处**不声称**做过它。

---

## 6. **本批新发现的缺陷 D-8**：三处检查把生成器版本钉死

本批把 `GENERATOR_VERSION` 从 `1.17.0` 升到 `1.18.0` 之后，**三处检查被打红**，而它们与本批的行为改动毫无关系：

| 位置 | 症状 |
|---|---|
| `scripts/mcp057_rb2_failure_demo.ps1:61-81` | **R-B2 版本断言的失败演示自己失效**：三处漂移的字面量都"找不到"，报 `FAILED checks = 3`、exit 1。即"证明断言会失败"的那件工具**在版本一致性被做对的下一刻就坏了** |
| `scripts/mcp053_added_tools_evidence.ps1:331` | `contract_generator_version_is_1_17_0` 变红 |
| `scripts/mcp054_forensics_and_csharp_evidence.ps1:294` | `contract_generator_version_is_1_17_0` 变红（green 相位） |

**这与 D-2 是同一类**：一个检查在**不报错也不声明**的情况下停止检查/开始误报。

**处置**：三处一律改为**在运行时从唯一事实源读取** `GENERATOR_VERSION`（`scripts/gen_renamed_contract.py` 的正则提取），
于是**真的漂移仍被抓住**（三处一致性的权威仍是 `check_tool_groups.py --generator-version`），
而**合法的版本递增不再是一次假警报**。两处检查改名以反映其真实含义
（`contract_generator_version_matches_the_generator`）。修复后实测：R-B2 失败演示
`drift: 1.18.0 -> 9.9.9 (read from gen_renamed_contract.py, not hardcoded)` → `PASS`；
`mcp054 -Label green` → `53/53 checks passed`；`mcp053` → `73/73 checks passed`。

**附带修掉的一处自身缺陷**：`mcp059_contract_pre_post.py` 原以 `--rev HEAD` 为默认，在**本批提交之后**
HEAD 就是 after 侧，于是它报"什么都没动" —— 一句关于没人问的那个比较的真话、关于本批的假话。
已改为默认**记录在案的批前版本 `213b17912`**，并保留 `--rev` 覆盖。（在第一次门跑里被抓住。）

---

## 7. 门⑥（GDR-24 / §22.3b 规则 4）：**新增收窄点 = 0**

三段式全部 exit 0：

```
gate6_narrowing          : scanned=75 / pinned=75；0 误报；PASS
gate6_narrowing_coverage : 打印已声明集合与集合外说明；18 处 pinned 行号漂移（pin 按 marker id + occurrence，
                           脚本自己声明这不是失败）；exit 0
gate6_coverage_probes    : 101/101 checks passed（含 B1b_restored_byte_identical、
                           B1b_worktree_clean_of_probes）
```

**`scanned`/`pinned` 与 TASK-057 同为 75/75 ⇒ 本批新增收窄点数为 0。** 逐条表因此为空，但**理由必须写出来**：
本批新增的代码是 `project_setting_section()`（`find_char`/`substr`，无窄化）、`publish_project_setting_to()`
（`CustomMap[p_key] = settings->get_setting(p_key)`，无窄化）、一个 `Ref<ConfigFile>` 探测（无窄化）、
以及调用点重接线。**没有新增任何 `(real_t)`/`(float)`/`Color(`/`Vector*`/字面量装不进 32 位这类收窄拼写**，
故无需新增 `// MCP-NARROWING:` 标记，也无需在 `PINNED` 里登记。

**行号漂移从 TASK-057 的 11 处升到 18 处**，原因是本批在 `tool_helpers.cpp`（+约 70 行的头注释与两个新函数）、
`editor_input_simulation.cpp`、`editor_write_scene_editor.cpp` 里插入了文本，使既有标记行号下移 ——
pin 是按 marker id + occurrence，所以这不是失败（脚本自己如此声明），此处明确记录以免被误读。

**边界（不得含糊）**：`check_narrowing_points.py --coverage` 自己打印
`anything outside tools/** (the module's other sources and the engine are not scanned)` ——
**引擎侧收窄不在门⑥ 范围内**。本批**没有**改动引擎侧任何收窄代码（本批未改任何 `core/**` 文件），
所以这个边界在本批不产生缺口。

---

## 8. 门与回归：真实输出与退出码

### 8.1 基线绑定（R-1）

本批**两次**从 `cmd` 启动、**严格串行**重建（绝不并发跑第二个 scons）：

| 步骤 | 命令 | 退出码 | 实测 |
|---|---|---|---|
| 1 | `modules\mcp_server\scripts\build_local.cmd -Force` | 0 | plain `--version` → `4.8.dev.custom_build.cd7224274` **== HEAD** |
| 2 | `modules\mcp_server\scripts\mcp057_build_mono.cmd` | 0 | mono `--version` → `4.8.dev.mono.custom_build.cd7224274` **== HEAD** |

两个脚本现在都先打印 `scons: <路径> (from <来源>)`（D-5），日志 `%TEMP%\t059_build_plain_h1.txt` /
`%TEMP%\mcp057\mono_build.log`，**不抑制 scons 输出**。

### 8.2 批次门电池 `scripts/mcp059_gates.ps1` —— **22 步全部 exit 0**

命令：`powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp059_gates.ps1`
日志：`%TEMP%\mcp059\gates\20260925-044357\`（每步一份 + `summary.txt`），控制台副本 `%TEMP%\t059_gates_console.txt`。

```
engine --version: 4.8.dev.custom_build.cd7224274
git HEAD short : cd7224274
version_matches_head: True
```

| 步 | 结果 | 退出码 |
|---|---|---|
| 门③ 模块 doctest | `test cases: 335 \| 335 passed \| 0 failed \| 1429 skipped`；`assertions: 23714 \| 23714 passed \| 0 failed`；`Status: SUCCESS!` | 0 |
| 门④ 全引擎回归 | `test cases: 1761 \| 1761 passed \| 0 failed \| 3 skipped`；`assertions: 447949 \| 447949 passed \| 0 failed` | 0 |
| 门⑥a/b/c | §7 | 0 ×3 |
| T-059 恒真扫描 / 探针 / 覆盖 | §3.3（`18/18`） | 0 ×3 |
| `--check-completeness` | `BYTES ADDED 6060 \| SHA256 ADDED 33880d5c… \| TOOL-GROUPS-COMPLETENESS CHECK PASS` | 0 |
| `--added` | 同 SHA256 `33880d5c…`；`TOOL-GROUPS-ADDED CHECK PASS` | 0 |
| `--generator-version` | `GENERATOR_VERSION == _meta.generator_version == source.generator_version: PASS (1.18.0)` | 0 |
| 契约 pre/post（T-059） | §5 | 0 |
| R-B2 失败演示（**D-8 修复后**） | `three drifts detected, three byte-exact restores, baseline green` | 0 |
| D-5 scons 探针演示 | `9/9` | 0 |
| 门① 契约逐字 ×5（default + 4 组） | 每次 `3/3 checks passed`；`contract=175`；`implemented_union=152 (editor) / 72 (game)` | 0 ×5 |
| 工具路径活证据（T-059） | `checks: 30, failures: 0` → `SECTION-SWITCH EVIDENCE PASS` | 0 |
| 补丁 2 引擎侧证据 | `checks: 23, failures: 0` → `SETTINGS-PUBLISH EVIDENCE PASS` | 0 |
| D-2 失败演示 | `baseline=0 manufactured=1 restored=0` → `D2 FAILURE DEMO PASS` | 0 |
| **整体** | `ALL GATE STEPS EXIT 0` | **0** |

**门⑤（`accept_m1` ×2）** 按 TASK-057 的划分留在 15 步电池里（见 §8.3），门电池不重复。

### 8.2b 本报告自身的提交与二进制锚点的关系（**明确记录，避免被误判成 D-B1**）

- **门与回归实测的 HEAD**：`cd7224274`（§8.2 顶部那个 `version_matches_head: True` 就是这一对）。
- **本报告的最终提交**：**本文件所在的 HEAD（自引用）**，即 `cd7224274` 之后**只有本报告一个文件**的提交。
- 因此：两个二进制自报 `cd7224274`，而当前 HEAD 比它**多一个纯文档提交**。这**不是** D-B1 那种缺陷：
  D-B1 要求「二进制包含**当次代码**的哈希」，而本报告提交**不改变任何被编译的字节**
  （`git show --stat HEAD` 只有 `REPORT-059-section-publish-switch.md` 一行）。
- 若下一批的门要求 `--version` **严格等于**当时的 HEAD，只需先
  `modules\mcp_server\scripts\build_local.cmd -Force`（需要 mono 时再 `mcp057_build_mono.cmd`）**串行**重建；
  本批**不**为「补齐一个纯文档提交的哈希」再烧两次全量重建 —— 与 REPORT-057 §8.1 的处置相同。

### 8.3 15 步回归电池（`mcp056_regression_battery.ps1`）—— **整体 exit 0**

命令：`powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp056_regression_battery.ps1`
（**严格串行**、每步一个 `powershell -File` 子进程、日志默认 `%TEMP%`）
日志：`%TEMP%\mcp_server_regression\20260925-045018\`，控制台副本 `%TEMP%\t059_battery.txt`。

| 步 | 脚本 | 退出码 | 关键实测 |
|---|---|---|---|
| 1 | `accept_m1_run1` | 0 | `22/22 cases passed`；`implemented tools = 152 (editor) / 72 (game); contract = 175` |
| 2 | `accept_m1_run2` | 0 | 同上 |
| — | `accept_m1_pass_lists_agree` | 0 | `checks=22 / checks=22 / differing_lines=0` |
| 3 | `mcp041_gates` | 0 | `STEP regress_mcp040_racing EXIT 0 (45s)` |
| 4 | `mcp042_gates` | 0 | 同上（46s） |
| 5 | `mcp043_gates` | 0 | 同上（46s） |
| 6 | `mcp010_b2_observation_evidence` | 0 | `phase game: 29/29 checks passed` |
| 7 | `mcp019_b4_evidence` | 0 | `PASS H1_user_editor_port_9877_guard` |
| 8 | `mcp027_object_shape_and_paths_evidence` | 0 | `phase green: 60/60 checks passed`；log sha256 `cbd0dc74…` |
| 9 | `mcp044_capture_evidence` | 0 | `PASS guard_user_port_9877`；`40/40 checks passed (phase editor)` |
| 10 | `mcp045_pixel_compare_cost` | 0 | `15/15 checks passed` |
| 11 | `mcp046_capture_encode_cost` | 0 | `23/23 checks passed` |
| 12 | `mcp050_parameter_guidance_evidence` | 0 | `port 9877 guard : pass=True classification=environment_fact_no_listener_before_or_after`；summary sha256 `c9d874b7…` |
| 13 | `mcp051_b_tier_evidence` | 0 | 同上 9877 守卫；summary sha256 `6dde7ffe…` |
| 14 | `mcp052_added_tools_evidence` | 0 | `53/53 checks passed`；log sha256 `e0048121…` |
| 15 | `mcp053_added_tools_evidence` | 0 | `73/73 checks passed`；log sha256 `9697a18f…` |
| — | `tracked_evidence_restored` | 0 | `git diff --stat after=0 line(s); newly modified=0; newly untracked=0; restore failures=0`（`SUMMARY restored=66 removed=1 kept-dirty-before=0`） |
| **整体** | | **0** | `ALL REGRESSION STEPS EXIT 0` |

### 8.4 任务书点名的脚本 —— **逐条归因**

| 点名 | 状态 | 归因 |
|---|---|---|
| `mcp041` / `mcp042` / `mcp043` | **已跑**（电池步 3/4/5，exit 0） | 三者重写被跟踪证据 → 正是 R-B3 的受影响面；已还原（§8.3 末行） |
| `mcp010` / `mcp019` / `mcp027` | **已跑**（电池步 6/7/8，exit 0） | `mcp019` 的 **9877 用户端口守卫**通过（本批**未占用 9877**） |
| `mcp044` / `mcp045` / `mcp046` | **已跑**（电池步 9/10/11，exit 0） | 属"受影响面"清单 |
| `mcp050` / `mcp051` / `mcp052` / `mcp053` | **已跑**（电池步 12/13/14/15，exit 0） | `mcp053` 的版本检查经 **D-8 修复**后为 `contract_generator_version_matches_the_generator` PASS |
| `mcp054` | **已跑**（电池外，单跑）：`mcp054_forensics_and_csharp_evidence.ps1 -Label green` → `[green] 53/53 checks passed`，exit 0 | 它的版本检查正是 D-8 打红的三处之一，**必须重跑**才算修好；它写进 `docs/reports/evidence/task054/green/**` 的 17 个被跟踪文件本任务跑完后用 `git checkout --` **逐字节还原**（`git diff --stat = 0`） |
| `mcp056` | **已跑**（就是电池本身 `mcp056_regression_battery.ps1`）＋ `mcp056_evidence.ps1 -Phase both` → `both: 22/22 checks passed`，exit 0 | 后者写进 `docs/reports/evidence/task056/**` 的 2 个被跟踪文件已还原；它**新建**的未跟踪文件 `evidence/task056/summary-both.txt` 已删除 |
| `mcp057` | **已跑全部三件**：`mcp057_settings_publish_evidence.ps1`（门电池内，`23/23`）、`mcp057_rb2_failure_demo.ps1`（门电池内，PASS）、`mcp057_gates.ps1`（**未跑**） | `mcp057_gates.ps1` 的步骤清单是 `mcp059_gates.ps1` 的**真子集**（门③/④/⑥、契约三检查、R-B2 演示、门①×5、补丁 2 证据）—— 逐条都在 §8.2 里已跑并 exit 0，重复跑只会把墙钟翻倍而不产生任何**不同**的检查。**不谎报**：它本身未被执行 |
| `mcp054_gate_battery.ps1` / `mcp054_regression_battery.ps1` / `mcp056_gates.ps1` / `mcp051_regression_battery.ps1` 等 | **未跑** | **不在任务书点名清单**；其中 054/056 的 battery 与 `mcp056_regression_battery.ps1` 覆盖同一批步骤 |
| `mcp044_zero_change.ps1` | **未跑** | 未点名；是 `mcp044_capture_evidence.ps1`（已跑）之外的补充检查 |

### 8.5 纪律核对

| 纪律 | 实测 |
|---|---|
| **绝不占用/杀/重启 9877** | ✅ 全程未在 9877 起过任何进程；本轮所有脚本开工/收尾时 9877 均**无监听**（用户 Godot 当时未运行）；`mcp019`/`mcp050`/`mcp051`/`mcp054`/`mcp056_evidence` 的 9877 守卫全部 `pass=True`，分类均为 `environment_fact_no_listener_before_or_after` |
| 测试端口 9888/9889 | ✅ 只用这两个；收尾时两者**无 LISTENING**（仅有 TIME_WAIT 客户端残留），无任何 `*godot*` 残留进程 |
| 禁止 push | ✅ **没有任何 push**；分支仍为本地 `feature/mcp-server-module` |
| 构建**严格串行**、从 `cmd` 启动、不抑制输出 | ✅ 本批共 **9 次 scons 运行**（其中第 2 次因我自己写的测试代码有一个标识符写错而编译失败，`exit code 2`，修好即重跑），**全部串行**、无并发、无第二个 scons；输出进日志并回显；`scons: <路径> (from <来源>)` 每步可见（D-5） |
| 证据 `curl.exe -s -o` + sha256 | ✅ 两个 MCP 证据脚本内部一律 `curl.exe -s --max-time … -o <file>`，并落 `.sha256`；本报告引用的 sha256 均来自这些落盘文件 |
| `.ps1` 纯 ASCII | ✅ 本批**新增/修改的 8 个 `.ps1`**（`mcp053`、`mcp054`、`mcp057_rb2_failure_demo`、`mcp057_settings_publish_evidence`、`mcp059_gates`、`mcp059_d2_failure_demo`、`mcp059_d5_scons_probe_demo`、`mcp059_section_switch_evidence`）全部逐字节纯 ASCII（机器核对：>127 的字节数 = 0）。**既有违规 2 处**（`accept_m1.ps1` byte 198 = 0xC2、`check_contract_subset.ps1` byte 762 = 0xC2）**本批未触碰**，如实登记 |
| 只改 `modules/mcp_server/**` 与**必要引擎文件** | ✅ 本批**未改任何引擎文件**（`core/**` 零改动）；全部改动落在 `modules/mcp_server/**` |
| hof-rs 只读 | ✅ 未触碰 `F:\moonbit-hof-rs`（只读它作为生成器的冻结输入） |
| 不得改 `DESIGN-DETAIL` | ✅ **未改** |
| 红相位输出当场保存 | ✅ `%TEMP%\t059\red_phase.txt`（本批 3 个新用例）；TASK-057 的 4 个依旧无红相位，**不伪造** |
| 门⑥ 三段式 + §22.3b 规则 4 | ✅ §7 |

---

## 9. 改动文件与 sha256

```
5fd6839643051687a95e7695f24969cf50763f5d9f5e64abcac3f14d52dd4b3b  83767  tools/tool_helpers.h
de4f05e6220135c9065af5d5c7079c026112d0fa2e1cf7950ec5ff1f86c7208c 143909  tools/tool_helpers.cpp
8f0a1614575eb6533f1f0e7f41bf288d49090d1fcb9a0b6e84975972d1f21856  15519  tools/project_setting_write.cpp
70d1d65fffafb02a8ec8b55739c9f725d9f674802d104fcd1e7a10dbbc9d3d97   6019  tools/project_autoload_write.h
d54401d279a65cda5c178ba8c7047f5c887b8696fcc019b10214f254a4f84b9f  14490  tools/project_autoload_write.cpp
288a8a06c5166933723f46f1b41ad7a7a757afbec50a7e5196dc39ab14c909d9  64665  tools/editor_input_simulation.cpp
ea4aaa15070137757d49607cf58ef86c639e757c8df5defec9aa5ce8855b5eef  50737  tools/editor_write_scene_editor.cpp
3ad619c71c38d8c709cec67033ab49c15d2898a45dc6dd649121e0f37a6d30db 1227585 tests/test_mcp_server.h
7df2242d01f47e89ab413fa183b28e9e715076fb0d4e98499ca31197b1139044 129218  scripts/gen_renamed_contract.py
c169bb676ec61c190a772b976bc8301aefc3c4b43c3545deae2cb931b6963334 148333  docs/tools_list.renamed.json
33880d5ccfb0158e2992a03b9ed75c09c2c71e798612f03df07fe3f71d9dc77e   6060  docs/tool-groups-added.json
602d18a2713b7831f730a056c27fc207543dbe4d2bdc45a50b295b559e44e6f5  12881  scripts/check_tautologies.py
d5b35c1f9ba44bce73e19cd9548e6987d1248e7cf8ecc812507ab7f969f59815   2603  scripts/mcp059_sync_literals.py
0ac1527bd03c38cc851d6a885fe713be1b06be9b0975a119c2feec7d15655aa9   8145  scripts/mcp059_contract_pre_post.py
e86a120382dd2eb820f7ed982934e01a630a6dd0503ed2f9c498a4695da60dd6  31754  scripts/mcp059_section_switch_evidence.ps1
81395be1e40c858139f863cb10db07c56a9f41dc911ddbe752ed6aff1cbabeb2   9299  scripts/mcp059_d2_failure_demo.ps1
15df2ae8f4252ed73f3a91901cc972794bbce3295385a069e4ec903d19e7ab94   8365  scripts/mcp059_d5_scons_probe_demo.ps1
71dd124bdf7a03326f20bb877096f45ca42a6e3c870fed46cc621974536311ad   7568  scripts/mcp059_gates.ps1
e7f993b0bed50c07713a7a5342cdd2079ff6a9a631ca106dd3b9129a6be880cb  25376  scripts/mcp057_settings_publish_evidence.ps1
54e68a111f3d074b15b0fe74d64e23fcb6ed2d65cd556d31948876126ae41969   7281  scripts/mcp057_build_mono.cmd
dc9affba209975892bc9b8b7d4df53b498ac8c6ba67b1781a1b8530718f8e7a7   8876  scripts/build_local.cmd
```

另改（D-8）：`scripts/mcp057_rb2_failure_demo.ps1`、`scripts/mcp053_added_tools_evidence.ps1`、
`scripts/mcp054_forensics_and_csharp_evidence.ps1`。

### 提交序列（英文提交信息，逐条对应本报告的决策条目）

| sha | 内容 |
|---|---|
| `d569b58d28` | D-4 实现：三个工具切到按节写 + 契约 v1.18.0 + 5 条 `replace` 描述 + 5 个 C++ 字面量重同步 + 3 个新 doctest |
| `60584b317e` | D-2/D-1/D-5 脚本：恒真断言改真 + `check_tautologies.py` + 失败演示 + 去重 + scons 探测 + 工具路径证据 + 契约 pre/post |
| `739e0bb555` | 判定包另存为 `REPORT-059-JUDGEMENT-PACK.md`（逐字保留） |
| `cd7224274` | D-8：三处检查停止钉死生成器版本；`mcp059_contract_pre_post.py` 默认 `--rev` 修正；`mcp059_gates.ps1` |

**决策日志说明（偏离，见 §10.1）**：本项目的决策日志在 **harness 仓库** `F:\moonbit-hof-rs\DECISIONS.md`，
按手册 §0/§7.2 对本模块的执行者**只读**，且**明确禁止**在本 fork 内新建竞争性日志/规范文档。
因此本批**未**追加 `DECISIONS.md`，也**未**创建任何 `docs/spec/**`；决策依据全部写在本报告与
`tools/tool_helpers.h` / `gen_renamed_contract.py` 的注释里。

---

## 10. `deviations`（逐条显式列出）

1. **未写决策日志 `F:\moonbit-hof-rs\DECISIONS.md`**：该文件对本模块执行者**只读**，且手册 §7.2 禁止本 fork
   创建竞争性文档。决策记录改落在本报告 §1 与源码注释。**若决策者要求，请在下一批明确授权写入口径。**
2. **未执行 `mcp057_gates.ps1`**：其步骤是 `mcp059_gates.ps1` 的真子集且已逐条实跑（§8.4 末条），
   重复执行不产生不同的检查。**明写在此，不谎报**。
3. **`mcp054-/mcp056_evidence` 在电池之外单独跑**，其写入的被跟踪证据由我用 `git checkout --` 还原
   （而非电池的 R-B3 守卫），因为任务把它们点名在电池清单之外。还原后用 `git diff --stat = 0 行` 验证。
4. **`mcp059_contract_pre_post.py` 的第一版以 `HEAD` 为默认 before 侧**，被第一次门跑抓出并修正（§6 末）。
   保留该经过，因为它是"新写的检查自己也要被检查"的一个实例。
5. **引擎侧收窄不在门⑥ 范围**（脚本自己声明）：本批未改引擎文件，故不产生缺口；此处仍显式登记边界。
6. **未做 D-7 要求的原子替换**（任务书允许保留现状）：理由与窗口描述见 §4.2。
7. **契约 pre/post 的"175 工具响应逐字节"** 由 `mcp059_contract_pre_post.py`（名字/顺序/schema）＋门①（在线逐字）
   ＋ 回归电池（被跟踪证据 `newly modified=0`）三条腿构成，**不含**一个新写的"175 工具逐调用响应快照"骨架；
   此处**不声称**做过后者（§5 末）。

---

## 11. `blockers`

**无阻塞项。** 六件事全部落地：门电池 22 步 exit 0、15 步回归电池 exit 0（含 `accept_m1` ×2 清单一致）、
两条点名脚本单跑通过、工作树只剩既有未跟踪物。

需要**决策者裁决**的只有规范层事项：

1. **D-7 的窗口**是否要在下一批用 `MoveFileEx(MOVEFILE_REPLACE_EXISTING)` 消除（需要动 `core/io` 或
   `core/config` 并重跑并发矩阵）；
2. **`project_remove_autoload` 的最终形态**：本批选择「保留整文件重写 + 诚实描述」。若将来要求它也不丢注释，
   需要新增「枚举命名空间构造 `CustomMap` + 删键」的引擎能力（**另一个引擎补丁**，不是本批范围）。
3. **`editor_reload_plugin` 的保存**由编辑器自己发起，本模块无法按节化；若要改，需要动
   `ProjectSettingsEditor`（引擎编辑器侧），风险明显更高。

---

## 12. `next_step_recommendation`

1. **把 `check_tautologies.py` 加进 TASK-057 的 `mcp057_gates.ps1`**（或正式并入唯一一份门电池），
   否则"下一条门"仍可能只跑 `mcp057_gates.ps1` 而绕过它。
2. **给 `mcp053`/`mcp054`/`mcp057` 的 battery 与 `mcp059_gates.ps1` 去重并成一份**：当前每批新增一份
   `mcpNNN_gates.ps1`，清单高度重叠，是"检查清单漂移"的温床（D-8 就是清单内部不一致的一种）。
3. **把 `PRE_BATCH_REV` 这类"批前锚点"从代码常量改成可查询的**（例如 `git rev-list -n1 --before=<批起始日期>`），
   否则下一个比较器仍会踩"HEAD 已是 after 侧"这个坑。
4. **D-8 的类应进 `check_tautologies.py` 的扩展**：本次三处的形态是"检查里钉死一个会变的常量"。
   可加一组声明拼写（脚本里的版本/计数/哈希字面量与源码里的定义比对），机器化"被钉死的常量"这一类。
5. **未做**：原子替换（D-7）、`project_remove_autoload` 的按节删键、`editor_reload_plugin` 的按节化、
   175 工具响应快照骨架。

---

## 附：证据路径

| 内容 | 路径 |
|---|---|
| 门电池控制台（22 步全 0） | `%TEMP%\t059_gates_console.txt`；分步日志 + `summary.txt` 在 `%TEMP%\mcp059\gates\20260925-044357\` |
| 15 步回归电池控制台 | `%TEMP%\t059_battery.txt`；分步日志 / R-B3 清单在 `%TEMP%\mcp_server_regression\20260925-045018\` |
| 红相位（当场保存） | `%TEMP%\t059\red_phase.txt` |
| 绿相位（当场保存） | `%TEMP%\t059\green_phase.txt` |
| 切换后模块套件 | `%TEMP%\t059\module_after_switch.txt` |
| 工具路径活证据 | `%TEMP%\mcp059\switch\20260925-044743\`（`summary.txt` + 每请求 `.request.json`/`.response.json`/`.sha256`） |
| D-2 失败演示 | `%TEMP%\mcp059\d2-demo\20260925-044825\`（`baseline/manufactured/restored.console.txt` + `.summary.txt`） |
| D-5 scons 探针演示 | `%TEMP%\mcp059\d5-probe\20260925-044552\` |
| 补丁 2 引擎侧证据 | `%TEMP%\mcp057\settings-publish\20260925-044758\` |
| 契约 pre/post | `%TEMP%\t059_prepost.txt`；脚本 `scripts\mcp059_contract_pre_post.py` |
| `mcp054 -Label green` | `%TEMP%\t059_mcp054.txt`（`[green] 53/53 checks passed`） |
| `mcp056_evidence -Phase both` | `%TEMP%\t059_mcp056ev.txt`（`both: 22/22 checks passed`） |
| 构建日志 | plain：`%TEMP%\mcp_server_build_local.log` / `%TEMP%\t059_build_plain_h1.txt`；mono：`%TEMP%\mcp057\mono_build.log` |
| 判定包（附件，逐字保留） | `modules/mcp_server/docs/reports/REPORT-059-JUDGEMENT-PACK.md` |

**返回决策者：见本文件抬头（§0/§1.2/§8.2）与提交说明。**
