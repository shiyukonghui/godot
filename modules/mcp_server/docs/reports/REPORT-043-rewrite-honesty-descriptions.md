# REPORT-043 — 描述诚实化：把「整文件重写 / 注释丢失」写进受影响的工具描述

> 任务书：`docs/tasks/TASK-043-rewrite-honesty-descriptions.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`。
> 本报告只报告**模块**的改动与证据；**未改** `docs/DESIGN-DETAIL.md`（sha256 与 REPORT-042 逐字相同）、
> **未改** `docs/tool-rename-map.json` / 组清单 / `docs/TOOL-NAMING.md`，**未新建**任何竞争性规范文档
> （PLAYBOOK §7.2）。所有改动都在 `modules/mcp_server/**` 内；**9877 只被观察**（证据行给出 `classification`），
> 本批**没有**终止/重启任何进程；**未 push**。
>
> **一句话**：经源码普查（不猜）确认**恰好 5 个**工具会经引擎写出口保存 `project.godot`；给这 5 条的描述
> **句尾 append** 同一句英文事实（整文件重写 / 注释丢失 / 其余逐字保留且幂等 / 需要就自行备份），
> 走 `DESCRIPTION_OVERRIDES`（`mode=append`，生成器 1.10.0 → **1.11.0**），重生成契约并全部指纹；
> **行为零改动**（`tools/**` 的 diff 恰好是 5 删 5 增，全是描述字面量本身，已机器断言）；
> 线上 9888 的 `tools/list` 与契约**逐字相等**；门①对 4 个归属组各跑一次、**被改工具全部 `description=True`**。

---

## 0. 结论速览与锚点（D86）

| 项 | 值 |
|---|---|
| 仓库 / 分支 | `F:\RustProjects\godot-mcp-pro\code\godot` / `feature/mcp-server-module`（**未 push**） |
| **① 描述 + 生成器 + 证据脚本锚点** | `47b5008bac` — `mcp_server: TASK-043 - the five tools that rewrite project.godot now say so in their description (generator 1.11.0, appends only)` |
| **② 门驱动/归属组锚点** | `d748214ffc` — `mcp_server: TASK-043 gates - run the verbatim contract gate once per owning group, and snapshot the pre-change contract by revision and sha` |
| **门的被测提交（全部门与线上证据测自它）** | `d748214ffc` |
| **门的被测二进制** | `4.8.dev.custom_build.d748214ff` == `git rev-parse --short=9 HEAD`（`scripts\build_local.cmd -Force`，`tests=yes`，**从 cmd 启动**，串行、未抑制输出） |
| 普查结果 | **恰好 5 个**工具会保存 `project.godot`：`project_set_setting` / `project_add_autoload` / `project_remove_autoload` / `editor_add_input_action` / **`editor_reload_plugin`**（第 5 个是**间接**写入，靠源码链 + 本批实测确认，见 §2.2 与 §7） |
| 措辞 | 同一句英文，`mode=append`（原文逐字保留在句首）；**条件句**（when this call saves），因为其中 3 个工具有「成功但不写文件」的路径 |
| 契约 | 110 770 B `c844ec8a…` → **118 032 B `443f1df2…`**；结构化 diff 只有 5 条 `description` + `_meta`（`generator_version` / `overrides`），**`problems=0`**；生成器幂等（连跑两次 sha 相同） |
| 行为改动 | **零**（见 §5：`tools/**` diff = 5 删 5 增，逐行都是 `ToolBuilder builder("…", String::utf8(…))` 的描述字面量） |
| 线上核实 | 9888 `tools/list` = 45 186 B，sha256 `23f3bd6b…`；5 条描述与契约 `-ceq` 相等且以新句结尾；其余 143 条逐字未动（两处 sha 相同） |
| 门结果一句话 | **27/27 步 exit 0**（含门①×4、门③ 277/277、门④ 1703/1703、门⑤ 22/22 ×2、门⑥ 三段、门②a–i、7 个回归脚本），详见 §8/§9 |
| **本报告提交** | `45076b352b` —— 本报告 + `docs/reports/evidence/task043/**`（**没有一个文件进入二进制**）；它的**自我记录**提交见 §11 |
| 契约/映射/组清单/DESIGN-DETAIL | 契约按生成器重生成（不手改）；映射/组清单/DESIGN-DETAIL **未改** |

---

## 1. 交付面

### 1.1 提交

| sha | 说明 |
|---|---|
| `47b5008bac` | ①：`gen_renamed_contract.py`（v1.11 段落 + `GENERATOR_VERSION` 1.10.0→1.11.0 + 5 条 append override）、重生成 `docs/tools_list.renamed.json`、4 个 `.cpp` 的 **5 行描述字面量**（其中 `editor_input_simulation.cpp` 的 `// BEGIN generated` 段由 `gen_b2_game_schema.py --in-place` 重生成）、6 个新证据脚本 |
| `d748214ffc` | ②：门驱动 `mcp043_gates.ps1` 改为「按归属组各跑门①」+ 先用 `git show 806d5396b:…` 快照改前契约（按 revision **和** sha256 双钉），以及 `mcp043_group_lookup.py`。**← 门批次测的就是这个提交** |
| `45076b352b` | 本报告 + `docs/reports/evidence/task043/**`（含 `.gitattributes`，该子树 `* -text`，证据字节不做换行翻译） |
| `4b581c782c` | 只改本报告的 §0/§1.1/§11，把上面这个 sha 与 D86 的实测结果写进来（**不触碰** `tools/`、`tests/`、`scripts/`） |

### 1.2 改动文件与 sha256

| 文件 | 字节 | sha256 | 改动 |
|---|---|---|---|
| `docs/tools_list.renamed.json` | 118 032 | `443f1df2e9a3c5b0a2ad1c4ce532a4cfb6f33d22d0401a02448a0ca0bede914f` | 生成器产出：5 条描述 + `_meta`（**没有手改**） |
| `scripts/gen_renamed_contract.py` | 64 767 | `18046bc29f9f47c8869df6866fa46cb41747437c6c936e47e0ab50cf12d0a744` | v1.11 docstring 段 + 版本递增 + 5 条 override |
| `tools/project_setting_write.cpp` | 14 223 | `c269166bc70afe2f01a3473314759da22f8cd2d09fcb4a62ffc08cc342fe947c` | 1 行描述字面量 |
| `tools/project_autoload_write.cpp` | 11 690 | `5b9ba76d2cdb37038e7eeb94aaabf159de1ee96a98e2adbdb5c2043a4f9e015a` | 2 行描述字面量 |
| `tools/editor_write_scene_editor.cpp` | 50 108 | `3a1c73f1219d313cd7a79bb42bc7720b97602b361ad79f3ad148a2a787f463e0` | 1 行描述字面量 |
| `tools/editor_input_simulation.cpp` | 58 206 | `baccf99b88635fefa9c79aa634927c87527539e2b675cddb89c8ae84fdbdfb83` | 1 行描述字面量（生成段，由生成器重生成：57 710 → 58 110 B） |
| `scripts/mcp043_survey.py`（新） | 2 109 | `f4786d132ff35d98ef4a982cebdb2f96354b802ab17efe050795871f59e44091` | 普查助手（old_name / 描述逐字导出） |
| `scripts/mcp043_group_lookup.py`（新） | 1 215 | `762b853d7f95d2498abacc26650d250b733ada61856b36fdee32b0f2d61afe7a` | 5 个工具各归哪个组清单 |
| `scripts/mcp043_contract_diff.py`（新） | 5 469 | `481d2c52e63ff2d44f80e7758576d6bfd39d2e5eb78707a334826158102f2c06` | 结构化契约 diff + 形状断言 |
| `scripts/mcp043_registration_literals.py`（新） | 3 601 | `154320826d6047c754c11f753477bc45865f412038c7146703544491dd42a7b8` | 5 个 C++ 注册字面量 == 契约 |
| `scripts/mcp043_reload_plugin_rewrite_probe.ps1`（新） | 14 810 | `cdae3ce1e7f6c2d0dc00be78ae304688fafb582d406ca8b3f8bc8b4eb2a1814c` | §7 的实测探针（14 条检查，纯 ASCII） |
| `scripts/mcp043_description_evidence.ps1`（新） | 10 233 | `373921fe7f4fe77658a99ad6b21ca39759811ec1a29a3deb3c1485dfb07e9990` | §6 的线上核实（16 条检查，纯 ASCII） |
| `scripts/mcp043_gates.ps1`（新） | 8 578 | `7dbad381fbb2b78470b8047caba3b412de6f7bb4f2e0b1556f0974528694be82` | 串行门驱动（27 步，纯 ASCII） |

> 新增/改动的 3 个 `.ps1` 非 ASCII 字节 = **0**，`PSParser` 报 `parse errors=0`；3 个新 `.py` 非 ASCII 字节 = **0**。

### 1.3 未改动的规范面

| 文件 | 字节 | sha256 |
|---|---|---|
| `docs/DESIGN-DETAIL.md` | 71 551 | `7e84bf874934aaff9129b2558832247adf8153bb7deb26495ffb3291fc4e1784`（**与 REPORT-042 逐字相同**） |
| `docs/tool-rename-map.json` | — | `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd`（`_meta.map_sha256` **未变**，机器可查） |
| `docs/tool-groups*.json` / `docs/TOOL-NAMING.md` | — | **未改**（组清单不含契约 sha；`TOOL-NAMING.md` 由 `docs/scripts/gen_table.py` 从**映射**渲染，与本次无关） |

**指纹落点**：契约 sha / `_meta.overrides` 条数 / 生成器版本都在契约 `_meta` 里（由生成器产出，见 §4）；
`docs/**` 与 `scripts/**` 里**没有**任何硬编码的「改名后契约 sha」需要同步（已用
`findstr sha256` + `git grep c844ec8a` 核对：命中的只有**历史报告**，报告是 append-only，不改写）。
`DESIGN-DETAIL.md` 只在 §548/§802 描述 override **机制**，不含具体 sha 或条数。

### 1.4 9877 纪律

全部门与回归脚本的 9877 判定都走共享助手 `scripts/mcp_port_guard.ps1`，证据行形如
`listening=False pid_before=-1 pid_after=-1 ours=False same_pid=True asked_by_us=False classification=environment_fact_no_listener_before_or_after`
（`mcp043` 两个新脚本与门⑤、6 个回归脚本的原文见 §8/§9）。本批**没有**任何进程请求过 9877
（各脚本的 `our_ports=[…]` 只含 `0/9888/9889`）。

---

## 2. 普查：哪些工具真的会经引擎写出口保存 `project.godot`

### 2.1 方法与「唯一写出口」的机器事实

普查**从源码出发**，不问迁移源、不靠猜。目标是「模块里通往 `project.godot` 文件字节的调用链」。
模块里只有两条出口（`git grep` 全树确认，`tools/**` 内除这两条外没有 `save` / `save_custom` /
`queue_save` / `ConfigFile::save` 的调用）：

| 出口 | 定义 | 链 |
|---|---|---|
| **E1** | `MCPTools::publish_project_settings()` | `tool_helpers.cpp:571-573` → `publish_project_settings_to(project_settings_file_path())` → `tool_helpers.cpp:558-566` 传 `ProjectSettings::save_custom` 作 `AtomicWriteFunc` → `core/config/project_settings.cpp:1234-1341` → `_save_settings_text()` `:1162-1210` |
| **E2** | `MCPTools::persist_input_action()` | `tool_helpers.cpp:842-863` → `persist_input_action_to()` `:788-838` → `publish_project_settings_to()` → **同一个** `save_custom` |
| **E3**（引擎侧、间接） | `EditorNode::_update_addon_config()` → `ProjectSettingsEditor::queue_save()` | `editor/editor_node.cpp:4512-4531` → `project_settings_editor->queue_save()`（`:4530`，**不受 `p_config_changed` 约束**）→ `editor/settings/project_settings_editor.cpp:97-100`（1.5 s 一次性 `Timer`，建于 `:870-874`）→ `_save()` `:102-106` → `ProjectSettings::save()` → 同一个整文件 `save_custom()` |

`save_custom()` 只有整文件输出（`p_custom` 只能改「写哪些值」不能改「写哪一段」，
`project_settings.cpp:1294-1304`）；`ConfigFile::save()`（`core/io/config_file.cpp:191-211`）同样整文件；
注释不属于任何数据结构。→ **引擎无局部发布 API**（REPORT-042 §3.3 的源码锚点，本批未改这些文件）。

### 2.2 普查表（工具 / 源码行 / 写出口调用链）

| # | 工具（新名 / old_name） | 源码落点（as-built） | 写出口链 | 结论 |
|---|---|---|---|---|
| 1 | `project_set_setting` / `set_project_setting` | `tools/project_setting_write.cpp:146-241`（`set_project_setting`）← `_tool_set_setting` `:245-272`；注册 `:291-297` | `:217 settings->set_setting(key, converted)` → **`:218 publish_project_settings(r_error)`** → **E1** | **受影响** |
| 2 | `project_add_autoload` / `add_autoload` | `tools/project_autoload_write.cpp:96-166`；注册 `:248` | `:149 set_setting` → **`:150 publish_project_settings()`** → **E1** | **受影响**（「已存在且路径相同」的 `:121-135` 早返回**不写**） |
| 3 | `project_remove_autoload` / `remove_autoload` | `tools/project_autoload_write.cpp:168-196`；注册 `:255` | `:180 clear(key)` → **`:181 publish_project_settings()`** → **E1** | **受影响**（名字不存在 → `:174-178` `-32001`，**不写**） |
| 4 | `editor_add_input_action` / `set_input_action` | `tools/editor_input_simulation.cpp`（`_tool_add_input_action`）`**:665**`；注册（生成段）`:1098+` | **`:665 MCPTools::persist_input_action(map, trimmed, reason, &publish)`** → **E2** | **受影响**（无 `project.godot` / 名字带 `.`/`/` → `persisted:false`，**不写**） |
| 5 | `editor_reload_plugin` / `reload_plugin` | `tools/editor_write_scene_editor.cpp:356-407`；注册 `:1045` | **`:396-397 editor_node->set_addon_plugin_enabled(name, false, false)` / `(name, true, false)`** → `editor/editor_node.cpp:4543-4549`（禁用分支）/ `:4623-4627`（启用分支）→ 两分支末尾都走 `:4512-4531 _update_addon_config()` → **`:4530 queue_save()`** → **E3** | **受影响**（`:380-384` 没有任何已启用插件时 `-32000`，**不写**） |

### 2.3 被**排除**的候选（逐个给出否决理由，不是「没提就不管」）

| 候选 | 否决理由（源码事实） |
|---|---|
| `editor_rescan_project_filesystem` / `editor_open_scene` / `editor_save_scene` / 节点写族 / tilemap / 主题 / 材质 / 音频 / 动画 | 全树 `git grep` `publish_project_settings|persist_input_action|->save()|save_custom|queue_save|set_addon_plugin_enabled` 在 `tools/**` 的命中**只有**上表 5 条；这些工具写的是 `.tscn`（`publish_file_atomically`）或只在内存里改节点 |
| `project_create_script` / `project_edit_script` / `project_create_shader` / `project_create_theme` / `project_write_resource_scene` | 写文本/资源文件（脚本、shader、theme、`res://*.tres`），目标是**调用方给的路径**，不经过 `ProjectSettings` 写出口 |
| `project_set_node_property_across_scenes` | 先 `ResourceSaver` 落盘**场景**、再改内存节点；`project_cross_scene_write.cpp` 全文无 `ProjectSettings` 写入 |
| `editor_set_navigation_layers` / `editor_set_physics_layers` / `project_get_settings` 等读工具 | 只 `ProjectSettings::get_setting()` / `has_setting()` 读，或把层名读出来显示（`editor_navigation_write.cpp:186`、`physics_shared.cpp:92`、`input_recorder.cpp:79`），**不 publish** |
| `project_get_export_info` / `os_deploy_to_android_device` 等 | 写 `export_presets.cfg` / 导出产物，与 `project.godot` 无关 |
| 任何 `EditorInterface::set_plugin_enabled` / AutoloadSettings / ProjectSettingsEditor UI 路径 | 模块**从不**触碰（`git grep AutoloadSettings|autoload_changed|globals_changed|ProjectSettingsEditor|global_shader` 在 `tools/**` **零命中**）；E3 是模块唯一能触及 `queue_save()` 的路径 |

> **为什么第 5 个必须靠实测兜底**：`set_addon_plugin_enabled(..., false)` 的注释与调用形态**看起来**是
> 「不要改工程文件」（那个 `false` 是 `p_config_changed`），但 `_update_addon_config()` **没有**被它门控。
> 这是「读源码可能读反」的典型格子，所以本批对它做了独立实测（§7）：14/14 PASS，含一条对照
> （编辑器带插件启动**不**改文件），把因果钉死。

---

## 3. 描述措辞与 override 记录

### 3.1 append 的句子（5 条**逐字相同**，英文，句尾）

```
When this call saves, it rewrites the entire project.godot with the engine's own whole-file writer
(the engine has no partial-publish API), so every hand-written comment in that file is lost: the
remaining settings are re-emitted verbatim and a repeated identical call changes no bytes
(idempotent), and because the comments cannot be kept, back the file up yourself before calling if
you need them.
```

四个语义要点逐条对应任务书 §1.2：①重写整个 `project.godot`；②手写注释丢失；
③其余设置逐字保留 + 幂等；④需要就**自行备份**。**不加参数、不改 `inputSchema`、不承诺做不到的事**。

**为什么是条件句**：§2.2 里 3 个工具有「成功但不写文件」的路径（autoload 已存在且相同、无 `project.godot`、
没有已启用插件）。写成无条件句会变成**新的**不诚实。

**为什么是英文**（决策者若要中文口径，这是一处一次性返工）：任务书 §1.2 明写「（英文，与既有描述风格一致…）」，
本批按**显式指令**执行；代价是这 5 条描述与契约里其余中文描述在语种上不一致（见 §10.1 deviation 3）。

### 3.2 override 记录（`old_name` / `mode` / `reason`，逐条）

| old_name | mode | 受影响工具 | reason 要点（完整文本在 `scripts/gen_renamed_contract.py` 与契约 `_meta.overrides`） |
|---|---|---|---|
| `set_project_setting` | append | project_set_setting | E1 链逐行（`:217/:218` → `tool_helpers.cpp:571-573/:558-566` → `project_settings.cpp:1234-1341/:1162-1210`）+ 「无局部 API」+ 四要点 |
| `add_autoload` | append | project_add_autoload | 同上 + 明写条件句理由（`:121-135` 早返回不发布） |
| `remove_autoload` | append | project_remove_autoload | 同上 + 明写条件句理由（`:174-178` `-32001`） |
| `set_input_action` | append | editor_add_input_action | E2 链 + REPORT-042 §3.2 的字节实测（407→869 B、注释 4/4 丢、多行块逐字保留、第二次 sha 不变）+ 条件句理由（`tool_helpers.cpp:855-858`） |
| `reload_plugin` | append | editor_reload_plugin | E3 链（`editor_write_scene_editor.cpp:396-397` → `editor_node.cpp:4548/:4627` → `:4512-4531` → `project_settings_editor.cpp:97-100/:102-106`）+ 本批实测结论（§7）+ 条件句理由（无插件时 `-32000`） |

`_meta.overrides`：**18 → 23** 条（`gen_renamed_contract.py:895-896` 的真实输出：
`overrides = 23 (… description/set_project_setting:append … description/reload_plugin:append …)`）。

---

## 4. 契约 diff（结构化）与指纹

改前契约按 **revision + sha256 双钉**快照：`806d5396b:modules/mcp_server/docs/tools_list.renamed.json`
（门步 `gate2f_snapshot_before_contract`，**先**校验 sha == `c844ec8a…` 才继续）。

`python scripts/mcp043_contract_diff.py <before> <after> <out>` 的真实输出（`gate2g`，exit 0）：

```
changed tools = editor_add_input_action, editor_reload_plugin, project_add_autoload, project_remove_autoload, project_set_setting
meta keys moved = generator_version, overrides
overrides 18 -> 23
problems = 0
```

该脚本**不只是打印**，它逐条断言（`problems` 非空即 exit 1）：
①工具名集合不变；②每个被改条目的**键集合不变**；③除 `description` 外**任何字段都没有变**
（`name` / `inputSchema` 逐字）；④每条新描述 == 旧描述 + `" "` + 共享句子；
⑤`_meta` 只在 `generator_version`（== `1.11.0`）与 `overrides` 上动，`map_sha256` **未动**；
⑥新增 override 记录恰好 +5 且 5 条 `append` 全命中。→ `contract-diff.json`。

| 指纹 | 改前 | 改后 |
|---|---|---|
| 契约字节 / sha256 | 110 770 / `c844ec8af9ef00d2e6ec7008c9806b3e2b16757e78794d3ccca0704edf844256` | **118 032 / `443f1df2e9a3c5b0a2ad1c4ce532a4cfb6f33d22d0401a02448a0ca0bede914f`** |
| `git diff --numstat`（契约） | — | `36 6`（5 条描述行 + `_meta.overrides` 记录 + 版本行；JSON diff，非对象 diff） |
| `_meta.generator_version` | `1.10.0` | **`1.11.0`** |
| `_meta.overrides` 条数 | 18 | **23** |
| `_meta.map_sha256` | `2f552719…` | `2f552719…`（**未变**） |
| 生成器幂等 | — | 连跑两次输出 `output sha256 = 443f1df2…`（相同，`gen_renamed_contract.py` 第二次运行同样报 `self-checks = OK`） |

**未手改契约**：`docs/tools_list.renamed.json` 只由 `python scripts/gen_renamed_contract.py` 写出
（`gen_renamed_contract.py:882-885`）；`git status` 里它始终是生成器运行后的产物，报告 §4 的 sha
与生成器打印的 `output sha256` 逐字相同。

---

## 5. 行为零改动：`tools/**` 的 diff 形状（机器断言）

**先说清楚一处必须解释的矛盾**：任务书 §1.4 要「实现文件 diff 为空」，但流量上的 `description`
**就是** `tools/*.cpp` 里的注册字面量（`ToolBuilder builder("name", String::utf8(...))`），
契约改了而字面量不改，门①会直接红。因此「只改描述与生成器」（§1.3）与「实现文件 diff 为空」（§1.4）
不可能同时字面成立；本批选**守住行为不变、把 diff 收到 5 行描述字面量**，并给出比「diff 为空」
更可核对的机器断言（见 §10.1 deviation 1）。

`git diff -U0 806d5396b d748214ff -- modules/mcp_server/tools`（证据 `contract/tools-diff-U0.patch`）：

```
files=['modules/mcp_server/tools/editor_input_simulation.cpp', 'modules/mcp_server/tools/editor_write_scene_editor.cpp',
       'modules/mcp_server/tools/project_autoload_write.cpp', 'modules/mcp_server/tools/project_setting_write.cpp']
added=5 removed=5
tools=['editor_add_input_action', 'editor_reload_plugin', 'project_add_autoload', 'project_remove_autoload', 'project_set_setting']
problems=0
```

`tools-diff-shape.json` 里的断言（脚本在 `%TEMP%`，不进仓库，避免在门批次之后动 `scripts/**`）：
①4 个文件、5 删 5 增；②**每一条**删/增行都匹配 `ToolBuilder builder("<这 5 个之一>", String::utf8(`；
③增行去掉那句句子后与删行**逐字相同**（即「只多了一句」）；④5 个工具全覆盖。

`git diff --numstat 806d5396b d748214ff -- modules/mcp_server/tools` 的真实输出：

```
1	1	modules/mcp_server/tools/editor_input_simulation.cpp
1	1	modules/mcp_server/tools/editor_write_scene_editor.cpp
2	2	modules/mcp_server/tools/project_autoload_write.cpp
1	1	modules/mcp_server/tools/project_setting_write.cpp
```

即：**没有**处理函数体、`inputSchema`、include、注释、控制流的任何一行被改。

**两侧一致性的第三腿**：`python scripts/mcp043_registration_literals.py`（`gate2h`，`failures = 0`），
它把源码里的**5 个注册字面量**与契约**逐字**比对，两种拼写都认（raw-string / 转义字符串）：

```
project_set_setting        tools/project_setting_write.cpp     line=293   raw-string       EQUAL
project_add_autoload       tools/project_autoload_write.cpp    line=248   raw-string       EQUAL
project_remove_autoload    tools/project_autoload_write.cpp    line=255   raw-string       EQUAL
editor_add_input_action    tools/editor_input_simulation.cpp   line=1234  escaped-string   EQUAL
editor_reload_plugin       tools/editor_write_scene_editor.cpp line=1045  raw-string       EQUAL
failures = 0
```

`editor_input_simulation.cpp` 的注册段是生成段，由
`python scripts/gen_b2_game_schema.py --group editor_input_simulation --in-place tools/editor_input_simulation.cpp`
重生成（**第二次运行打印 `is already up to date`**，幂等；57 710 → 58 110 B）。

---

## 6. 线上核实（9888 的真实 `tools/list`）

`scripts/mcp043_description_evidence.ps1`（门步 `gate2a`，**16 checks / 0 failed**，exit 0）。
响应体**用 `curl.exe -s -o <file>` 落盘**（不经 PowerShell 管道，PLAYBOOK §7.1），再算 sha256：

```
[L10] tools/list bytes=45186 sha256=23f3bd6b9f4ddaa42858cd4804d7bd389e19d5f5af36d42d1a850eafef00a810
[PASS] L11_tool_count        live editor tools/list carries 148 tools
[PASS] L20_project_set_setting_live_equals_contract        live description == contract entry: True; lengths live=406 contract=406
[PASS] L21_project_set_setting_ends_with_the_appended_sentence   ends with the shared sentence: True; original wording still first: True
[PASS] L20/L21 project_add_autoload        （406 / True / True）
[PASS] L20/L21 project_remove_autoload     （406 / True / True）
[PASS] L20/L21 editor_add_input_action     （415 / True / True）
[PASS] L20/L21 editor_reload_plugin        （411 / True / True）
[PASS] L30_no_other_tool_description_moved 143 untouched live descriptions sha256=44f12a296fcaab13873960762172d925e7fdfaf45cd8e20df26daf00ee082ba2;
                                           same set from the contract sha256=44f12a296fcaab13873960762172d925e7fdfaf45cd8e20df26daf00ee082ba2
[PASS] Z01_port_9877_guard    listening=False pid_before=-1 pid_after=-1 ours=False same_pid=True asked_by_us=False classification=environment_fact_no_listener_before_or_after our_pids=[68332] our_ports=[0,9888] our_command_lines=2
```

两点值得单独说：

1. **`L30` 是「其余 143 条没动」的机器证据**：把编辑器端点能看到的、除这 5 条以外的每条
   `name=description` 拼起来算 sha，再从契约算一遍，两边相同。
2. **确定性**：两次运行（第一次单测、第二次门批次）的 `tools/list` sha256 **相同**
   （`23f3bd6b…`），与 PLAYBOOK §6.4 的「同一构建内确定性」一致。

---

## 7. `editor_reload_plugin`：间接写入的独立实测

`scripts/mcp043_reload_plugin_rewrite_probe.ps1`（门步 `gate2b`，**14 checks / 0 failed**，exit 0）。

**样本**：全新 scratch 工程，`project.godot` 带 **3 行手写注释** + `[editor_plugins] enabled=PackedStringArray("res://addons/mcp043probe/plugin.cfg")`
+ 一个真实 addon（`plugin.cfg` + `plugin.gd`）。

**关键检查（逐字）**：

```
[PASS] P04_import_left_the_file_alone        sha256 before=a42cab83… > after --import=a42cab83…       ← 对照 1（--import 不改）
[PASS] P11_editor_startup_did_not_rewrite_the_file
       sha256 before=a42cab83… after the editor came up with the addon enabled=a42cab83…             ← 对照 2（关键：带插件启动也不改）
[P20_reload_plugin] {"message":"编辑器插件已禁用并重新启用","plugins":["res://addons/mcp043probe/plugin.cfg"],"reloading":true}
[PASS] P21_whole_file_was_rewritten          sha256 a42cab83… -> 82e818a2…; bytes 504 -> 585
[PASS] P22_every_hand_written_comment_is_gone  comments lost 3/3; kept 0; first lost line: '; hand-written comment one: keep me'
[PASS] P23_the_engine_writes_its_own_header_instead   first line of the rewritten file: ; Engine configuration file.
[PASS] P24_other_settings_survive_verbatim   config/name kept=True; editor_plugins/enabled kept=True
[PASS] P25_second_reload_is_byte_identical   sha256 after the second reload=82e818a2… (first=82e818a2…)
[PASS] Z01_port_9877_guard                   … classification=environment_fact_no_listener_before_or_after our_pids=[68436] our_ports=[0,9888]
RESULT 14 checks, 0 failed; checks json sha256=3eb0bcd87ac0f3dd3493345c3f8e4d102e425226c8c5c8277434c11a67fbe1c5
```

**因果链**：`P11` 排除「编辑器启动自己就写了」；`P04` 排除 `--import`；`P20` 之后 5 s 内文件字节变化，
且变化形态与 §2.1/E3 预测**完全一致**（引擎固定 7 行头 + 3/3 注释丢失 + 其余设置逐字 + 第二次幂等）。
→ `editor_reload_plugin` 确实经引擎写出口重写整份 `project.godot`。

**这里也暴露一个可读性事实（写进报告，不改行为）**：该写入由 **1.5 s 一次性定时器**触发，
所以工具**返回之后**文件才变（`project_settings_editor.cpp:870-874`）；调用方若在返回后立刻读文件，
看到的可能还是旧字节。描述里用的是「when this call saves」，**没有**承诺「返回即已落盘」。

---

## 8. 门（真实输出与退出码）

### 8.0 门的绑定（R-1）

```
> modules\mcp_server\scripts\build_local.cmd -Force        (tests=yes，从 cmd 启动，串行，未抑制输出)
build_local: exit code = 0
> bin\godot.windows.editor.x86_64.console.exe --version
4.8.dev.custom_build.d748214ff
> git rev-parse --short=9 HEAD
d748214ff
```

驱动：`scripts/mcp043_gates.ps1`（每步独立日志 + 退出码；**两个引擎从不同时启动**；驱动**不调用 scons**）。
原始日志：`docs/reports/evidence/task043/gates/summary.txt` 与 `*.log`。**全 27 步 exit 0**：

| # | 步 | 门 | 退出码 | 耗时 |
|---|---|---|---|---|
| 1 | `gate2f_snapshot_before_contract` | 改前契约快照（revision + sha 双钉） | **0** | 0s |
| 2 | `gate3_module_doctest` | ③ 模块 doctest | **0** | 6s |
| 3 | `gate4_full_doctest` | ④ 全引擎回归 | **0** | 32s |
| 4 | `gate1a_contract_group_editor_write_scene_editor` | ① 逐字（含 `editor_reload_plugin`） | **0** | 21s |
| 5 | `gate1b_contract_group_project_setting_write` | ① 逐字（含 `project_set_setting`） | **0** | 20s |
| 6 | `gate1c_contract_group_project_autoload_write` | ① 逐字（含 add/remove autoload） | **0** | 20s |
| 7 | `gate1d_contract_group_editor_input_simulation` | ① 逐字（含 `editor_add_input_action`） | **0** | 20s |
| 8 | `gate6a_narrowing` | ⑥ 收窄点清单 | **0** | 1s |
| 9 | `gate6b_narrowing_coverage` | ⑥ `--coverage` | **0** | 0s |
| 10 | `gate6c_coverage_probes` | ⑥ 拼写探针 | **0** | 52s |
| 11/12 | `gate5_accept_run1` / `run2` | ⑤ `accept_m1.ps1` ×2 | **0** / **0** | 49s / 49s |
| 13 | `gate2a_description_evidence` | ② 本批线上核实（§6） | **0** | 10s |
| 14 | `gate2b_reload_plugin_probe` | ② 第 5 个工具的实测（§7） | **0** | 23s |
| 15 | `gate2c_probe037_d2d1r1r2` | ② 回归（收窄/写侧矩阵） | **0** | 9s |
| 16 | `gate2d_rewrite_evidence` | ② 回归：TASK-042 的 `project.godot` 链 | **0** | 21s |
| 17 | `gate2e_task041_evidence` | ② 回归：M-6 输入映射持久化 | **0** | 29s |
| 18 | `gate2f_port_guard_probes` | ② 9877 判定探针 | **0** | 1s |
| 19 | `gate2g_contract_diff` | ② 结构化契约 diff（§4） | **0** | 0s |
| 20 | `gate2h_registration_literals` | ② 字面量 == 契约（§5） | **0** | 0s |
| 21 | `gate2i_group_lookup` | ② 归属组普查 | **0** | 0s |
| 22–28 | `regress_mcp032/033/034/035/036/040_probes/040_racing` | 回归 | **0**×7 | 10/14/15/14/23/25/47s |

### 8.1 门① 契约子集逐字（4 组 × 两个端点，全 exit 0）

门①是**按组逐字**（`check_contract_subset.ps1:331-351`：只有**该组**的工具做 `name/description/inputSchema`
逐字比较，其余只断言「并集名字/条数」）。TASK-043 改了 **4 个不同组**的描述，所以按组各跑一次：

| 组 | 组内被改工具 | 逐字证据行（编辑器 9888） | 游戏 9889 | 结果 |
|---|---|---|---|---|
| `editor_write_scene_editor`（10 条） | `editor_reload_plugin` | `editor_reload_plugin: name=True description=True inputSchema=True` | 正确缺席 | `3/3 checks passed` |
| `project_setting_write`（1 条） | `project_set_setting` | `project_set_setting: name=True description=True inputSchema=True` | **`description=True`**（scope=both） | `3/3` |
| `project_autoload_write`（2 条） | `project_add_autoload` / `project_remove_autoload` | 两条都 `description=True` | **两条都 `description=True`** | `3/3` |
| `editor_input_simulation`（6 条） | `editor_add_input_action` | `editor_add_input_action: name=True description=True inputSchema=True` | 正确缺席 | `3/3` |

四组都打印 `implemented_union=148 tools (editor endpoint) / 69 tools (game endpoint)`。
**被改 5 个工具的 `description` 在两个端点上都被逐字核对过**（3 个 `project_*` 有游戏端点那一行，
另 2 个是 editor 专有，游戏端点断言「正确缺席」）。

### 8.2 门③ 模块 doctest（exit 0）

```
[doctest] test cases:   277 |   277 passed | 0 failed | 1429 skipped
[doctest] assertions: 15948 | 15948 passed | 0 failed |
[doctest] Status: SUCCESS!
```

与 TASK-042 基线**逐字相同**（277 / 15948）——本批没有增删任何测试（只改描述），这正是「行为不变」的预期形态。

### 8.3 门④ 全引擎回归（exit 0）

```
[doctest] test cases:   1703 |   1703 passed | 0 failed | 3 skipped
[doctest] assertions: 440230 | 440230 passed | 0 failed |
[doctest] Status: SUCCESS!
```

与 TASK-042 基线**逐字相同**（1703 / 440230），**0 failed**。

### 8.4 门⑥ 收窄点三段式（GDR-24，三段全 exit 0）

* `check_narrowing_points.py` → **exit 0**：`scanned 73 / pinned 73`（17 个文件）；
* `check_narrowing_points.py --coverage` → **exit 0**：仍声明 **17 种**拼写（集合与 TASK-031 相同，本批未动收窄代码）；
* `mcp031_gate6_coverage_probes.ps1` → **exit 0**：**101/101 checks passed**，探针后源码 sha256 逐字节还原。

> **如实记录（继承 REPORT-042 §6.4 的遗留）**：该工具仍报告 **11 条 pinned 行号漂移**
> （`marker id + occurrence` 才是 pin 的键，脚本自己声明这不是失败）。本批**没有**去刷新它们
> （理由同 TASK-042：门批次开跑后再改门脚本会让「门的被测提交」失效；而且它不影响 exit 0）。

### 8.5 门⑤ `accept_m1.ps1` ×2（exit 0 / exit 0）

```
22/22 cases passed        （run 1 与 run 2 逐字相同：PASS 清单 22 条，`identical=True`）
[PASS] guard_user_port_9877
       listening=False pid_before=-1 pid_after=-1 ours=False same_pid=True asked_by_us=False classification=environment_fact_no_listener_before_or_after
implemented tools = 148 (editor endpoint) / 69 (game endpoint); contract = 171
```

### 8.6 门② 逐项（§6/§7 已给细节）

| 证据 | 结果 |
|---|---|
| `mcp043_description_evidence.ps1` | **16 / 0**，exit 0；`tools/list` 45 186 B `23f3bd6b…` |
| `mcp043_reload_plugin_rewrite_probe.ps1` | **14 / 0**，exit 0 |
| `probe037_d2_d1_r1r2.ps1` | **39 / 39**（写侧矩阵，含 `project_set_setting` 的 clamp 读回） |
| `mcp042_projectrewrite_and_honesty_evidence.ps1` | **30 / 0**（TASK-042 的整文件重写链，本批未破坏） |
| `mcp041_inputmap_persistence_evidence.ps1` | **32 / 0**（M-6） |
| `mcp042_port_guard_probes.ps1` | **21 / 0** |
| `mcp043_contract_diff.py` | `problems = 0` |
| `mcp043_registration_literals.py` | `failures = 0` |
| `mcp043_group_lookup.py` | `rows=5` |

**三类证据齐备**：成功路径=§6 的五条描述线上相等 + §7 的重写实测；**缺参/非法输入**=回归
`mcp041` 的 `mcp041.dotted`（`persisted:false` + 原因）与 `mcp043` 探针里「无插件时 `-32000`」；
**底层失败**=「进程没有 `project.godot`」的诚实 `false` + 原因（TASK-041/042 证据链，本批复跑）。
**端到端活证据链**：`editor_reload_plugin` → `project.godot` sha256 逐字节变化 → 注释 3/3 丢失
→ 第二次调用字节不变（§7）；以及 TASK-042 链的复跑：`editor_add_input_action` → 字节变化 →
**真实游戏进程** `InputMap` 能读回。

---

## 9. 回归脚本：逐条归因（全部 exit 0）

| 脚本 | 检查数 | 结果 | 9877 证据行（`classification` 部分） | 归因 |
|---|---|---|---|---|
| `mcp032_d3_d4_d6_evidence.ps1` | 38 | **38 / 0** | `environment_fact_no_listener_before_or_after our_ports=[0,9888,9889]` | 与 TASK-042 同（当时 38/0）；其 `d6_live_description_keeps_the_old_wording` 是 `get_game_node_properties` 的既有描述断言，本批未触及 |
| `mcp033_b5_animation_evidence.ps1` | 74 | **74 / 0** | 同上 | 无新回归 |
| `mcp034_b5_audio_particle_theme_evidence.ps1` | 113 | **113 / 0** | 同上 | 无新回归 |
| `mcp035_b5_tilemap_shader_physics_evidence.ps1` | 66 | **66 / 0** | 同上 | 无新回归 |
| `mcp036_b5_navigation_theme_export_android_evidence.ps1` | 58 | **58 / 0** | 同上（`our_ports=[9888,9889]`，含两条 `--import` 登记） | 无新回归 |
| `mcp040_defect_probes.ps1 -Label task043` | 47 | **47 / 0** | `port_9877_owner_unchanged`（-1→-1） | 无新回归 |
| `mcp040_racing_regression.ps1` | 35 | **35 / 0** | 同上 | 无新回归 |

**没有一个脚本出现「新回归」；没有任何用例被删除或放松。**

---

## 10. deviations / blockers / risks / next_step

### 10.1 deviations（与任务书/手册的显式偏离）

1. **「实现文件 diff 为空」（任务书 §1.4）与「只改描述与生成器」（§1.3）不可能同时字面成立**：
   客户端读到的 `description` 就是 `tools/*.cpp` 的注册字面量，改契约不改字面量 → 门①必红。
   取舍：**守住「行为零改动」**，把 `tools/**` 的 diff 收到 **5 删 5 增、全是描述字面量**
   （证据 `contract/tools-diff-U0.patch` + `tools-diff-shape.json` 的机器断言），
   并额外给出「字面量 == 契约」的第三腿（§5）。**若决策者要的是「`tools/` 一个字节都不动」，
   那本批只能改契约而不改流量描述——门①会失败，需要先改门①的语义，请裁决。**
2. **普查多了 1 个工具（第 5 个 `editor_reload_plugin`）**：任务书 §0 的括号只点名了
   `project_set_setting` 家族与 `editor_add_input_action`，但它经 `_update_addon_config()` →
   `queue_save()` 真的重写整份 `project.godot`（源码链 + **本批实测 14/14**，§7）。
   按「副作用不得沉默」把它一并写进描述。
3. **新句子是英文**（任务书 §1.2 明写「英文」），而契约里其余描述是中文 → 语种不一致。
   按显式指令执行；若决策者要中文口径，只要改 5 条 `value` + 重跑生成器/字面量/门①即可（一次性返工）。
4. **门①改跑 4 次（每归属组一次）**，而不是任务书写的那一次：门①只对**所选组**做逐字比较
   （`check_contract_subset.ps1:331-351`），单跑 `editor_input_simulation` 只覆盖 5 个被改工具中的 1 个。
   为了满足「门① 逐字通过（**含被改工具**）」而按组各跑一次。
5. **新增了一个「改前契约快照」门步**（`gate2f_snapshot_before_contract`），把 `806d5396b:` 的这个文件
   按 **sha256 双钉**落到 `%TEMP%`，作为结构化 diff 的左手边——否则 `gate2g` 会依赖手工遗留的临时文件。
6. **diff 形状断言脚本放在 `%TEMP%`，不进仓库**：这样 `scripts/**` 在门批次之后**不再变化**，
   D86 的「门批次之后没有再改过门脚本」这条论证得以保持原样。代价是该断言不是仓库内脚本，
   但它的**输入与输出都在证据里**（`tools-diff-U0.patch` + `tools-diff-shape.json`），可逐字复核。
7. **没有刷新门⑥ 的 11 条 pinned 行号**（§8.4）：继承 REPORT-042 的遗留与理由。

### 10.2 blockers

**无**。9877 无监听者是**环境事实**（所有脚本都把它判成
`environment_fact_no_listener_before_or_after` 并 PASS，而不是失败）；全部门与回归 exit 0。
本批没有出现 `--import` 的间歇性崩溃（3 个新脚本各一次 `--import`，全部第 1 次尝试即 exit 0）。

### 10.3 risks（交给决策者）

1. **`editor_reload_plugin` 的写入是延迟的**（1.5 s 一次性定时器，`project_settings_editor.cpp:870-874`）：
   描述说的是「when this call saves」，**没有**承诺「返回即已落盘」。若调用方需要「返回即确定」，
   这本身是一个独立的诚实性缺口（本批**只描述、不改行为**）。
2. **描述里的「幂等」是字节级**：同参重复调用不改变字节（§7 `P25`、REPORT-042 §3.2 `A27`）。
   但「其余设置逐字保留」指的是**值**；节/键的**顺序**由 `RBMap` 决定（REPORT-042 §3.2 标注为
   **源码推断、未实测**），手工把节排成非字典序的文件重写后会被排回字典序。描述里没有声称顺序。
3. **英文句子与中文契约的语种混搭**（§10.1 deviation 3）：可能被一致性审查判为风格缺陷。
4. **门⑥ 的 11 条 pinned 行号漂移**仍在（§8.4）：不影响 exit 0，下次改这几个文件时会继续漂。
5. **`docs/tool-groups-b2.json` 的过期 `notes` 仍未改**（继承 REPORT-041/042 的报缺陷项，本批未动组清单）。
6. **任务书 §1.4 的字面要求无法同时满足**（§10.1 deviation 1）：需要决策者确认「改描述字面量」算不算
   允许的改动范围。本批的立场写在 §5：只改描述本身，行为零改动，并给出机器证据。

### 10.4 next_step_recommendation

1. **裁决 §10.1 deviation 1**：确认「描述字面量属于描述、可以改」；否则需要先改门①的语义
   （让它从契约渲染流量描述），那是另一批设计变更。
2. **裁决 §10.1 deviation 3**：要不要把这 5 条描述改成中文口径（一次性返工，产出同样的门证据）。
3. **裁决 risk 1**：`editor_reload_plugin` 是否应该让「保存已完成」可观测（例如响应里给一个
   `settings_save_scheduled` 字段）——这是行为变更，需要单独立项。
4. **顺手清理**：下次动门⑥ 相关文件时把那 11 条 pinned 行号刷新一次（risk 4）。

---

## 11. 结论锚点（D86）与证据清单

* **描述与生成器的结论**（§3–§5）：测自 `47b5008bac`（生成器 + 契约 + 5 行字面量 + 证据脚本）。
* **普查表与第 5 个工具的实测**（§2/§7）：源码链是 as-built（`47b5008bac` 的工作树）；
  实测测自 `d748214ffc` 的二进制（`4.8.dev.custom_build.d748214ff` == `git rev-parse --short=9 HEAD`）。
* **门与线上证据**（§6/§8/§9）：**全部**测自门批次提交 `d748214ffc`。
  可核对（**本报告提交之后实测**，逐字如下）：
  ```
  > git diff --stat d748214ffc HEAD -- modules/mcp_server/tools modules/mcp_server/tests modules/mcp_server/scripts
  （空 ⇒ 门的被测代码 == 门批次提交 d748214ffc）
  > git diff --numstat d748214ffc HEAD -- modules/mcp_server/scripts
  （空 ⇒ 门批次之后没有再改过任何门脚本，包括新增）
  > git diff --numstat 806d5396b d748214ffc -- modules/mcp_server/tools
  1	1	modules/mcp_server/tools/editor_input_simulation.cpp
  1	1	modules/mcp_server/tools/editor_write_scene_editor.cpp
  2	2	modules/mcp_server/tools/project_autoload_write.cpp
  1	1	modules/mcp_server/tools/project_setting_write.cpp
  ```
* **本报告提交**：`45076b352b`，只加 `docs/reports/REPORT-043-*.md` 与 `docs/reports/evidence/task043/**`
  （**没有一个文件进入二进制**）；证据子树的字节保真由 `evidence/task043/.gitattributes` 的 `* -text` 保证。
  **字节保真的逐字复核**（提交后用 `git cat-file blob` 重算，与 `INDEX.md` 的记录相比）：
  ```
  > git cat-file blob HEAD:.../task043/live/tools_list.response.json         45186 B  23f3bd6b9f4ddaa42858cd4804d7bd389e19d5f5af36d42d1a850eafef00a810
  > INDEX.md 记录                                                            45186 B  23f3bd6b9f4ddaa42858cd4804d7bd389e19d5f5af36d42d1a850eafef00a810  （相同）
  > git cat-file blob HEAD:.../task043/reload/project.godot.rewritten          585 B  82e818a261317681fb78f533c54cbf583a63e76226526b0e255c4c598191d66c  （相同）
  > git cat-file blob HEAD:.../task043/gates/summary.txt                      1432 B  9449ad7505729d6a3125315850e18dbb800d4b9698866a5475afc5380d245a72  （相同）
  > git cat-file blob HEAD:.../task043/contract/contract-diff.json           29489 B  3f16fe301579cd1a20c5746caee7a4285fca62aa414ad858e6caa092ed351751  （相同）
  ```
* **本报告的自我记录提交**：`4b581c782c`（只改本报告文本；它之后
  `git diff --stat d748214ffc HEAD -- modules/mcp_server/{tools,tests,scripts}` 仍为空）。
  本行所在的最后一次提交只再改这一段纯文本（把上一条的 sha 写实），**不再自我引用**；
  最终提交的 sha 由执行者回报给决策者。

原始证据（本报告内联的每一条都能在这里找到原文）：

| 位置 | 内容 |
|---|---|
| `.../task043/INDEX.md` | 44 个证据文件的**字节数与 sha256**（另加本子树 `.gitattributes` 与 `INDEX.md` 自身） |
| `.../task043/gates/summary.txt` | 门批次 27 步的退出码与耗时（§8.0 那张表） |
| `.../task043/gates/gate{1a,1b,1c,1d}*.log` | 门① 四组的逐条 `name/description/inputSchema` True 与 `3/3` |
| `.../task043/gates/gate3_module_doctest.log` / `gate4_full_doctest.log` | `277/277 + 15948` 与 `1703/1703 + 440230` |
| `.../task043/gates/gate6{a,b,c}*.log` | `scanned 73 / pinned 73`、17 种拼写、`101/101` |
| `.../task043/gates/gate5_accept_run{1,2}.log` | `22/22` ×2（PASS 清单一致） |
| `.../task043/gates/gate2f_snapshot_before_contract.log` | 改前契约快照的 sha 双钉行 |
| `.../task043/gates/gate2{a..i}_*.log` | §6/§7/§4/§5 的每一份原始输出 |
| `.../task043/gates/regress_*.log` | 7 个回归脚本的逐条 PASS 与 9877 证据行 |
| `.../task043/contract/tools_list.{before,after}.json` | 契约改前（110 770 B）与改后（118 032 B） |
| `.../task043/contract/contract-diff.json` | 结构化 diff + 6 条断言（`problems: []`） |
| `.../task043/contract/tools-diff-U0.patch` + `tools-diff-numstat.txt` + `tools-diff-shape.json` | §5 的 5 删 5 增与形状断言 |
| `.../task043/contract/registration-literals.json` | 5 个字面量 == 契约（含文件/行号/拼写） |
| `.../task043/contract/survey.txt` | 5 个工具的 `old_name` / 契约描述逐字 |
| `.../task043/contract/groups.txt` | 5 个工具各归哪个组清单 |
| `.../task043/live/tools_list.response.json` | 9888 的**原始** `tools/list` 响应体（45 186 B，`23f3bd6b…`） |
| `.../task043/live/mcp043-description-checks.json` | 16 条检查的 id/pass/evidence |
| `.../task043/reload/mcp043-reload-probe-checks.json` | 14 条检查（含 504 B → 585 B 的两个 sha） |
| `.../task043/reload/P20_reload_plugin.response.json` / `P25_reload_again.response.json` | 两次 reload 的原始响应体 |
| `.../task043/reload/project.godot.rewritten` | 重写后的整份文件（可逐行核对「只丢注释」） |
