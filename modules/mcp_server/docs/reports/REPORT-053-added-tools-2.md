# REPORT-053 — C 档 2：`project_write_text_file` 错误码改判 + 两个新增工具 + M-5 采样步

> 任务书：`docs/tasks/TASK-053-added-tools-2.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`；
> 规范：`DESIGN-DETAIL.md` **§26/GDR-28**（含**第 10 条错误码裁决**）。证据来源：`docs/reports/REPORT-AUDIT-RACING-BACKLOG.md`（C-4③④、M-5）。
> 执行者只写**报告**；决策日志按 PLAYBOOK §0 属于 harness 仓库 `F:\moonbit-hof-rs\DECISIONS.md`（本 fork **只读**），
> 因此本文件的 §7「决策记录」是本批决策的可查载体，本 fork 内**没有**新建 `DECISIONS.md` 或竞争性规范文档。
>
> **本报告只允许改 `modules/mcp_server/**`**（已遵守）；hof-rs 全程只读；**没有改 `DESIGN-DETAIL.md`、`tool-rename-map.json`
> 与五份既有批次清单**；**没有占用/杀/重启 9877**（每次运行前后只*观察*它的 pid）：端口只用 9888/9889；**没有 push**。
> 实现提交：`96c1693d3d`（报告单独一条提交）。

---

## 0. 结论摘要（按 D86 标锚点）

| 项 | 结论 | 锚点 |
|---|---|---|
| §1 错误码改判：占用目标 + `overwrite:false` → `-32000` + `data.suggestion` 点名 `overwrite:true` | **完成** | §2.1、§5.1；实测 `a07`：`code=-32000`，suggestion 逐字含 `overwrite": true`，拒绝前后**逐字节相同**（sha `87635cc3…`） |
| §2.1 `project_validate_scripts`（批量校验，`mutating=false`） | **完成** | §2.2、§5.2；实测 `a10`：`count=4 / valid=1 / invalid=1 / unavailable=2`，三类分类逐项正确 |
| §2.1 「语言不可用」与「校验失败」区分（沿用 TASK-050 的 `-32000` 口径，不得记 `valid:false`） | **完成** | §2.2、§5.3；`.cs` 项 `category=language_unavailable`、`valid=false` 但**无 `error_text`**、带 `suggestion`；与 singular 工具同句（`a18` `same_message=True`） |
| §2.2 `editor_set_node_script_batch`（批量挂脚本，`mutating=true`，全成功或全回滚） | **完成** | §2.3、§5.4；`a23` 成功 2/2 读回、`a27` `keep_existing` 跳过 2、`a33` 回滚 `rolled_back:true`、`a36` abstract 由**读回**拦下 |
| §2.2 `keep_existing:true` 跳过并计入 `skipped[]` + 原因（不得静默覆盖） | **完成** | §2.3；`a27` + `a28`（再存盘后场景文本 sha 未变） |
| §2.3 M-5 采样步（既有采样读取工具 + 默认保持现语义） | **完成** | §2.4；工具点名 `running_game_get_node_property_samples`，参数定名 `sample_stride` |
| §2.3 「默认下响应与改动前逐字节相同」 | **完成** | §2.4、§5.5；`b07` 295 B / sha `eef36e62…` == **改动前**在 `c4823798a` 上抓的基线（连跑 3 次同 sha） |
| §2.3 「显式步长下点数/字节数」前后对照 | **完成** | §2.4、§5.5；180 观察点：无步长 **6147 B / 180 点** → `sample_stride=10` **781 B / 18 点**（−87%） |
| 契约 173 → **175**（不是任务书 §3 写的 176，见 D-053-1） | **完成** | §1；契约 137 749 B sha `65c83ab8…`，generator **1.15.0**，`added_count=4` |
| 沿用 `ADDED_TOOLS`，不改既有条目与五份批次清单 | **新增 2 条走 `ADDED_TOOLS`**；M-5 走既有 `SCHEMA_OVERRIDES`（见 D-053-2） | §1.2、§1.4；结构化 diff **34 checks / 0 problems**，除 M-5 条目外 172 条逐字不变 |
| `--check-completeness` / `--added` | **PASS** exit 0 ×2 | §1.3；打印 `171 + 4 = 66 + 105 + 4` |
| 门① 契约子集逐字（171 移植逐字 + 4 新增逐字，9888/9889） | **PASS** 3/3 | §4.1；`editor=152 / game=72 / contract=175` |
| 门② 三类证据 + 跨工具链 | **PASS** 72/72（exit 0） | §4.2、§5 |
| 门③ 模块 doctest | **PASS** 325/325 用例、23 430/23 430 断言（基线 315/22 935） | §4.3 |
| 门④ 全引擎回归 | **PASS** 1751/1751 用例、447 653/447 653 断言、0 failed（基线 1741/447 217） | §4.4 |
| 门⑤ `accept_m1.ps1` 连跑两次 | **PASS** 22/22 ×2，两次 PASS 清单一致 | §4.5 |
| 门⑥ 三段式 + §22.3b 规则 4 | **PASS** exit 0 / exit 0 / 101 探针全过 | §4.6；收窄点 **75/75 未变**（本批未新增收窄点） |
| 回归 21 步（`mcp041/042/043` + `mcp010/019/027` + `mcp044/045/046` + `mcp050` + `mcp051` 的四个可复用脚本 + `mcp052`） | **PASS** 21/21 exit 0（其中 1 步是**不可用性归因**，见 §6），逐条归因见 §6 | §6 |
| 构建绑定 HEAD | plain `4.8.dev.custom_build.c4823798a`、mono `4.8.dev.mono.custom_build.c4823798a`，都 == HEAD | §3.0 |
| 必须由决策者裁定 | **3 项**：§3「契约 176」与 §2 的算术冲突（D-053-1）、「不改已有条目」与 M-5 加参数的冲突（D-053-2）、**C# 后端 `reload()` 恒返回 OK** 使 `.cs` 永远 `ok`（D-053-3） | §7、§8 |

---

## 1. 契约与机制（GDR-28 沿用，不改机制）

### 1.1 生成器：第三张表继续用，第四张表照旧

`ADDED_TOOLS` 追加两条（**条目原文由决策者给定**，逐字落地），`GENERATOR_VERSION` **1.14.0 → 1.15.0**；
`DESCRIPTION_OVERRIDES`/`ADDED_VERB_EXTENSIONS` **未动**（本批两个名字用的动词 `validate` / `set` 本来就在映射的 37 词闭集里，
所以 `MCP_ADDED_TOOL_VERBS` 仍是 `{build, write}`，**未动**）。

生成器输出（真实）：

```
output tools = 175
added = 4 (project_build_csharp, project_write_text_file, project_validate_scripts, editor_set_node_script_batch)
overrides = 29 (... inputSchema/monitor_properties:replace ...)
output sha256 = 65c83ab8615d547a528410b34f8f6faef7b8b871b17217a533b9a35b82d9e69d
self-checks = OK (lint 175/175, unique 175/175, disposition enum OK)
```

**幂等**：连跑两次 `output sha256` 相同（`65c83ab8…`），文件 137 749 B。

### 1.2 两条新增条目（逐字，与契约一致）

| 名字 | channel/verb/scope/mutating | 描述 sha256（wire） |
|---|---|---|
| `project_validate_scripts` | `project` / `validate` / `both` / `false` | `e637d02ae071e36c1482f26108bb2172436914f36649249a2bc33261da516b79` |
| `editor_set_node_script_batch` | `editor` / `set` / `editor` / `true` | `723287d192214f5c4e2b3178cb896435937d16459ed6c77c8c16b605882cd72b` |

两者的 `inputSchema` 与 `description` 在 **9888 与 9889** 上都与契约逐字一致（门①；`a03` ×2）。
`scope` 的可见性也在线上分了叉：`editor_set_node_script_batch` 只在 9888（`a04`：9888 `True`、9889 `False`），
`project_validate_scripts` 两端都服务（`a02/b02`：152 / 72）。

### 1.3 组清单：新增两颗组，五份历史清单不动

`docs/tool-groups-added.json`：`total 2 → 4`，`counts.added_tools 4`、`groups 4`，**未动**五份批次清单与映射。
`check_tool_groups.py --added` 与 `--check-completeness` 都 **exit 0**：

```
ASSERT  manifest = contract _meta.added_tools, both directions: PASS (missing=0, foreign=0)
ASSERT  every added tool appears exactly once: PASS (duplicates=0)
ASSERT  171 + 4 = 66 + 105 + 4: PASS (contract = B1/B2 union + B3/B4/B5 union + added)
BYTES ADDED 5442  SHA256 0735fe2957cdbe98a25dcd4f473060b30881f25dd26153489ef97b2cc220776d
12 个字节量级相同的 B1..B5 sha 与 TASK-051 一致（文件未动）
```

### 1.4 结构化 diff 与「不改已有条目」的准确含义

`scripts/mcp053_contract_diff.py`（本批新增；TASK-052 的 `mcp052_contract_diff.py` 断言的是 171→173 那一对修订，
不是本树的门）**34 checks / 0 problems**，关键几条：

```
[PASS] only_the_m5_entry_moved :: ported entries that changed = ['running_game_get_node_property_samples']
[PASS] m5_added_property_is_the_stride :: added properties = ['sample_stride'] (expected [sample_stride])
[PASS] m5_dropped_no_property :: dropped properties = []
[PASS] m5_existing_properties_byte_identical :: properties that moved = []
[PASS] m5_schema_required_untouched :: required ['node_path', 'properties'] -> ['node_path', 'properties']
[PASS] overrides_grew_by_the_m5_schema_record :: new = [('inputSchema', 'monitor_properties')]
[PASS] meta_unchanged_map_sha256 / generated_from_sha256 / excluded / merged ...
```

→ 「173 条既有条目」里 **172 条逐字节不变**，动的 1 条是 M-5 的 schema（新增 1 个可选属性，`required` 一字未动）。
这一条与任务书「**不改**已有条目」的字面冲突见 **D-053-2**。

---

## 2. 三个改动（行为与设计依据）

### 2.1 `project_write_text_file`：错误码改判（TASK-053 §1 / GDR-28 第 10 条）

- 旧：`-32001`（`MCPToolError::not_found` 家族）——GDR-14 把 `-32001` 读作「**你要找的东西不在**」，而目标**在**；
  REPORT-052 §7.2 当时就按任务书实现并**报了冲突**，本批由决策者改判。
- 新：`MCPToolError::tool_state(...)` = `-32000` + `data.suggestion`，suggestion 逐字点名 `overwrite: true`。
  也不用 `-32602`：`overwrite` 已声明、`false` 是合法取值，错的是**状态**不是参数。
- 代码位置 `tools/project_text_write.cpp`（`_already_exists`），注释里写清改判依据与「为什么另两个码都不对」。
- **同步更新**了受影响的期望：`tests/test_mcp_server.h` 的 TASK-052 用例（`-32001 → -32000`，并新增
  `code != -32001 / code != -32602`、suggestion 逐字含 `overwrite": true`、**逐字节**比对拒绝前后文件）、
  `scripts/mcp052_added_tools_evidence.ps1` 的 `a16` 期望（并保留 sha 不变的断言）。

### 2.2 `project_validate_scripts`（新增，`project`/`validate`/both/`mutating=false`）

**契约面**：`paths`（array of string，可选；省略 = 扫描工程）、`include_errors_only`（boolean，默认 `false`）。

**行为**（`tools/project_validate_scripts.*`）：

- 逐文件给 `path` / `language` / `valid` / `category`（`ok` | `invalid` | `language_unavailable`）/ `error_text`（仅 `invalid`）/ `message`；
- 返回 `count` / `valid_count` / `invalid_count` / `unavailable_count`，**四者恒等式**：
  `count == valid_count + invalid_count + unavailable_count`（每一项都被计数）；
- `include_errors_only` 只过滤 `results`，**不过滤计数**，并回显 `errors_only` 与 `returned`；
- `truncated` / `dropped` / `limits.max_scripts=64`：与 `project_read_resource` 同形的显式截断标记；
- 请求形状先于任何文件读取判定：`paths: []` → `-32602`（「至少一个」）、非数组/非字符串元素/空白元素 → `-32602`（点名下标）、
  越界路径（`user://`、`..`）→ `-32602` + `data.suggestion` 说明规则、**文件不存在 → `-32001`（点名 `paths[i]`）**；
- **扫描集固定为 `{gd, cs}`**：`project_create_script`/`project_edit_script` 就是这么两种；**不派生自**
  `get_recognized_extensions()`，否则 non-mono 构建里 `.cs` 会从扫描里**静默消失**，与「诚实报告能力缺失」相反；
  `.gdshader` 不进扫描（引擎没有它的 `ScriptLanguage`；显式 `paths` 指它仍会得到 `language_unavailable`）。

**「一份判定」**：新增 `MCPTools::validate_script_source()`（`project_read_files.*`），
`project_validate_script`（singular）也改为调它 → 同一个文件在同一个进程里**不可能有两个答案**（`a18` 实测同句）。

**分类与计数的唯一取舍（显式声明）**：进程**根本没有**初始化任何脚本语言时（`--test` 进程），singular 的既有行为是
「只做括号平衡检查、message 明说没有编译」。批量工具必须把每个文件落进三类之一，所以该模式下按括号结果记
`ok`/`invalid`，并把同一句免责声明放进 `message`（**不**另开第四类，否则计数器不再穷尽）。
真实编辑器/游戏进程永远处于 `COMPILE` 模式，此分支只在 `--test` 里可见（§7.7 的「声明的确定性转换」）。

### 2.3 `editor_set_node_script_batch`（新增，`editor`/`set`/editor/`mutating=true`）

**契约面**：`script_path`（string，必填）、`node_paths`（array of string，必填，≥1）、`keep_existing`（boolean，默认 `false`）。

**行为**（`tools/editor_set_node_script_batch.*`）：

- 先验后写：参数 → 编辑器守卫 → 编辑场景 → 脚本路径归一 → **逐节点解析**（缺一个即 `-32001`）→ 脚本存在/可加载/是 `Script`；
  全部通过后才动场景；
- 提交阶段**逐节点读回**（`apply_node_script()`：写后 `get_script()` 必须就是那个脚本，按 `get_path()` 比对）；
  任一失败 → 逆序**撤回**已落地节点（`restore_node_script()` 再读回）、`rolled_back:true`、失败项点名 `index`/`node_path`；
- `keep_existing:true`：已挂脚本的节点**跳过**并进 `skipped[]`（带 `reason` 与 `previous_script_path`），**不覆盖**；
  `false`（默认）才替换，且回答里给出被替换掉的 `previous_script_path`；
- 成功形状 `{status:"ok", script_path, keep_existing, count, attached:[{index,node_path,script_path,previous_script_path,attached:true}], skipped:[...], errors:[]}`；
- 失败走既有批量工具同族语义：JSON-RPC `error` + `data.suggestion` + `data.batch{status:"rolled_back", rolled_back:true, reverted:[...], errors:[...], on_error:"all_or_nothing", count:0, ...}`。
  **一处形状差异（显式）**：`editor_add_nodes_batch` 的 `batch.rolled_back` 是**列表**，而本工具契约原文要求 `rolled_back:true`（布尔）
  → 布尔照写，被撤回的列表叫 `reverted`，两者都在同一 envelope 里，读者不会混淆。

### 2.4 M-5：`running_game_get_node_property_samples` 的 `sample_stride`

**工具点名**：`REPORT-AUDIT-RACING-BACKLOG` §3.5 在 M-5 里点名的**既有采样读取工具**是
`running_game_get_node_property_samples`（该节 G07 就是用它绕开「两次调用」；§④ 也说「单响应会变大…需要 max_samples 或截断策略」）。
源码位置 `tools/running_game_frame_observation.cpp`。

**参数定名 `sample_stride`（integer，默认 1，≥1）**，语义与定名理由：

- 它管的是**回传网格**（每第 N 个观察点回传一个，第 0 个恒回传），**不是**观察网格。
  观察网格仍由既有 `frame_interval` 决定（每几帧观察一次）——两个旋钮分开，是因为
  `RACING-TEST-PLAN.md` 的 AC-4/AC-5 连续性断言**必须** `frame_interval:1`（每帧观察，否则「没瞬移」判不出来），
  而那正是审计说 3 属性×180 帧回 23 020 B 的那种调用：步长让它保住每帧观察、只把载荷降到 18 点；
- 名字不用 `sample_interval`：本 schema 里 `interval` 已经指帧间隔（`frame_interval`）；
  也不用 `sample_step`：`running_game_run_test_scenario` 的 `steps` 已经占用了「step」这个词。
  「stride」在本工具里只有一种读法：**observed_count 个观察点，每 sample_stride 个回传一个**；
- **默认（省略或 1）响应逐字节不变**：只有 `sample_stride > 1` 时才追加 `sample_stride` 与 `observed_count` 两个键；
  `frame_count` 的既有含义（回传样本数）不变成观察数；
- 参数校验：`0`/负数 → `-32602`（"must be at least 1: a stride of %d would return no sample at all"），非整数 → `-32602`；
  判定规则导出为 `MCPTools::sample_is_returned(index, stride)`（`--test` 进程没有 SceneTree，规则必须可单测）。
- 实现经生成器 `SCHEMA_OVERRIDES["monitor_properties"]`（`mode: replace`，reason 逐字引用被替换的 `required` 与「4 个属性一字未动」），
  再跑 `scripts/gen_b2_game_schema.py --group running_game_frame_observation --in-place` 重生成注册字面量。

---

## 3. TDD 红 → 绿

### 3.0 构建绑定 HEAD（R-1）

| 步骤 | 命令 | 结果 |
|---|---|---|
| plain（门 0，从 **cmd** 启动） | `modules\mcp_server\scripts\build_local.cmd -Force`（内部 `scons platform=windows target=editor module_mono_enabled=no tests=yes -j8`） | **exit 0**，`INFO: Time elapsed: 00:00:37.81`；`bin\godot.windows.editor.x86_64.console.exe --version` = `4.8.dev.custom_build.c4823798a` **== HEAD `c4823798a`**；exe 195 556 864 B sha256 `159ed8235d3b097746a3e82bbf3d44c01ec9a7a03e271f89f7aa6d698cbf9524` |
| mono（**串行**，Mono 变体才有的 `.cs` 判定证据） | `cmd /c "D:\Anaconda\Scripts\scons.exe platform=windows target=editor module_mono_enabled=yes tests=yes -j8"` | **exit 0**，`Time elapsed: 00:01:39.24`；`…mono.console.exe --version` = `4.8.dev.mono.custom_build.c4823798a` **== HEAD** |
| 门 0 之前的**改动前基线** | `scripts/mcp053_m5_baseline_capture.ps1`（在**改前**二进制上跑） | 295 B sha `eef36e62…`，连跑 3 次同 sha（`docs/reports/evidence/task053/m5-baseline/`） |

> 两次构建**串行**（先生成 plain 并跑完所有 plain 相关门，再构建 mono），构建输出不抑制（日志：
> `%TEMP%\mcp_server_build_local.log`、`%TEMP%\mcp053-mono-build.log`）。
>
> **关于「== HEAD」的时间点**：`--version` 里的 `c4823798a` 是**构建时的 HEAD**（本批改动之前的基线修订）；
> 门②的 `engines_match_head` 与 TASK-052 的同名检查（`mcp052_added_tools_evidence.ps1:267`）一样，
> 比较的是 `git rev-parse HEAD` 与二进制自报值，因此**必须在提交本批改动之前跑**。
> 本批的两条提交（`96c1693d3d` 实现、`db0566242b` 报告）之后 HEAD 会前移，此时复跑证据脚本的这两条检查会报出
> 「二进制 = 基线修订、HEAD = 基线 + 本批提交」，那是**预期**的（二进制绑定的是「基线修订 + 被提交的工作树」，
> 这两者是同一棵树的两种说法）；要复跑，请用 `git stash`/`git worktree` 造出「HEAD 回到基线 + 工作树是本批内容」的状态，
> 或直接读本报告的 §4.3/§4.4 数字并复跑门③④（它们只依赖二进制，与 HEAD 无关）。

### 3.1 红 → 绿（真实输出）

- **红**（改实现前，tests 先行）：第一次 `build_local.cmd` 后 `--test --test-case="[MCPServer]*"` 的 TASK-053 用例
  在 `project_validate_scripts` / `editor_set_node_script_batch` 上得到 `-32601 Unknown tool`（注册缺失），
  以及 `writing the batch` 相关的期望不满足；构建期还实测到两个**真错**（`editor_set_node_script_batch.h` 缺
  `Script`/`Node` 完整类型；`sample_is_returned` 只有声明没有定义 → `LNK2019`）——都是红阶段暴露、绿阶段修掉的。
- **绿**：门③ **325/325 用例、23 430/23 430 断言、0 failed**；门④ **1751/1751、447 653/447 653、0 failed**。
- 新增用例 **10 条**（本批），断言净增 **495**（门③）/ **436**（门④，不含其它批次被跳过的差异口径）。

---

## 4. 门（真实输出 + 退出码）

### 4.1 门① 契约子集逐字

```
PASS  editor_9888_contract_subset   editor port=9888 tools=152 ... project_validate_scripts: name=True description=True inputSchema=True
PASS  game_9889_contract_subset     game port=9889 tools=72 ... project_validate_scripts: name=True description=True inputSchema=True
PASS  guard_user_port_9877          pid_before=-1 pid_after=-1
group=project_validate_scripts tools=1 contract=175
implemented_union=152 tools (editor endpoint) / 72 tools (game endpoint)
3/3 checks passed        [exit 0]
```

（`-Group project_validate_scripts`：该名字只在新清单里，用它正好同时证明「组名查找覆盖第六份清单」与「并集断言=实现集」。）

### 4.2 门② 三类证据 + 跨工具链

`scripts/mcp053_added_tools_evidence.ps1`：**72/72 checks passed、exit 0**，逐条见 §5；
100+ 个真实请求/响应体（`curl.exe -o`）落盘并带 sha256，已复制进仓库：
`docs/reports/evidence/task053/wire/`（110 个文件）+ `evidence.log.txt` + `results.json`。

### 4.3 门③ 模块 doctest

```
[doctest] test cases:   325 |   325 passed | 0 failed | 1429 skipped
[doctest] assertions: 23430 | 23430 passed | 0 failed |
[doctest] Status: SUCCESS!
```
（基线 315/22 935；只增不减。）

### 4.4 门④ 全引擎回归

```
[doctest] test cases:   1751 |   1751 passed | 0 failed | 3 skipped
[doctest] assertions: 447653 | 447653 passed | 0 failed |
[doctest] Status: SUCCESS!   [EXIT=0]
```
（基线 1741/447 217，EXIT=0。）

### 4.5 门⑤ `accept_m1.ps1` 连跑两次

```
run1: 22/22 cases passed ; implemented tools = 152 (editor) / 72 (game); contract = 175; guard_user_port_9877 PASS
run2: 22/22 cases passed ; implemented tools = 152 (editor) / 72 (game); contract = 175; guard_user_port_9877 PASS
```
两次 PASS 清单一致（`gate_scope_declared` 校验的是派生值 `contract == 171 + _meta.added_count` → `175`）。

### 4.6 门⑥ 收窄点三段式（GDR-24 / §22.3b 规则 4）

| 腿 | 命令 | 结果 |
|---|---|---|
| ① 机器检查 | `python scripts\check_narrowing_points.py` | **exit 0**；`scanned 75 / pinned 75`，16 个文件；**11 条既有行号漂移**（与 TASK-051 的基线**完全相同**，非本批引入；pin 用 marker id + occurrence，故不失败） |
| ② 覆盖声明 | `python scripts\check_narrowing_points.py --coverage` | **exit 0**（declare 的拼写集与不覆盖项照旧） |
| ③ 探针回归 | `powershell -File scripts\mcp031_gate6_coverage_probes.ps1` | **101/101 checks passed**（插入→exit 1 探针每个拼写都有；日志 sha `a1515e0a…`） |

**本批没有新增任何收窄点**：`scanned` 与 `pinned` 与 TASK-051 的基线**同为 75**（新代码里没有 `(float)`/`(real_t)`/`Vector2(` 之类的声明拼写；
`sample_is_returned` 的 `%` 是整数取模，`truncate_marked` 的字节裁剪用 `uint8_t` 位与，均不在声明的拼写集里）。
按 §22.3b 规则 4：三段式的「代码审阅」一栏 = 本批新增的两处写路径
（`editor_set_node_script_batch` 的 `set_script`、`sample_stride` 的整除）都**不产生数值收窄**，故不需要新 marker。

---

## 5. 门② 的证据（逐条）

### 5.1 错误码改判（§1）

| # | 请求 | 响应（真实） | 判定 |
|---|---|---|---|
| `a06` | `project_write_text_file{path:res://mcp053-note.cfg, content:"key=mcp053\n"}` | `{"bytes":11,"created":true,"path":"res://mcp053-note.cfg","sha256":"87635cc3…"}` | 成功路径 + 读回 sha == 磁盘 sha |
| `a07` | 同路径、无 `overwrite` | `{"error":{"code":-32000,"message":"Project file 'res://mcp053-note.cfg' already exists and 'overwrite' is false","data":{"suggestion":"Pass \"overwrite\": true to replace the existing file, or choose another path"}}}` | **`-32000` + suggestion 点名 `overwrite:true`**；`sha_before == sha_after`（`87635cc3…`），11 B 未变 |
| `a08` | 同路径 + `overwrite:true` | `{"bytes":11,"created":false,…sha256":"95713e9c…"}` | 唯一能通过的路径确实通过 |
| `a09` | `path:"res://scripts/valid.gd"` | `-32602` + `Use project_create_script or project_edit_script to write a GDScript file` | 专用家族拒绝**未回退** |

### 5.2 `project_validate_scripts`

| # | 类 | 证据 |
|---|---|---|
| `a10` | 成功 | 4 个路径一次调用：`count=4 valid=1 invalid=1 unavailable=2`；`valid.gd=ok`、`broken.gd=invalid/ERR_PARSE_ERROR`、`legit.cs=language_unavailable`、`shader.gdshader=language_unavailable`；`returned=4 truncated=false dropped=0 limits.max_scripts=64` |
| `a10b` | 成功 | `ok` 项带 `language=gd` 与 `message="Script compiles successfully"`（真编译，不是猜） |
| `a11` | 成功 | `include_errors_only=true` → `returned=3`、计数仍 `4/1/1/2`、回显 `errors_only=true` |
| `a12` | 成功（省略 paths） | 扫描 scratch 工程：`count=6`（abstract.gd/broken.cs/broken.gd/legit.cs/other.gd/valid.gd），`count == valid+invalid+unavailable`，**没有 `.gdshader`**，`max_scripts=64` |
| `a13` | 缺参/形状 | `paths:[]` → `-32602`「must name at least one script」+ 注册表补的 suggestion（列出接受参数） |
| `a14` | 形状 | `paths:"res://…"` → `-32602`「must be an array of strings, got String」 |
| `a15` | 越界 | `paths:["user://outside.gd"]` → `-32602` + suggestion「must address the project ('res://...')…」 |
| `a16` | 底层 | `paths:["res://scripts/valid.gd","res://scripts/no_such.gd"]` → `-32001`，message 点名 `paths[1]`，suggestion 指 `project_list_scripts` |
| `a17` | 未知参数 | `nope` → `-32602`「Unknown parameter 'nope'」 |
| `a18/a19` | **两类工具一致** | singular `.cs` = `-32000`，plural 该项 = `language_unavailable`，`same_message=True`（同一句），且**没有 `error_text`**（不把「没有后端」写成「编译失败」） |
| `a20` | 只读 | 调用前后**整个 scratch 工程的逐文件 sha 树哈希相同**（前后都是 `6df215df…`） |

### 5.3 C# 的「语言不可用」是**构建的属性**（跨构建对照）

| 构建 | 文件 | 结果 |
|---|---|---|
| plain（non-mono）9888 / 9889 | `legit.cs` | `language_unavailable` + suggestion 点名 `module_mono_enabled=yes`（`ab6/a10/a19`，9889 亦同） |
| mono 9888 | `legit.cs` | `category=ok valid=true`（`c02`），singular 同样 `valid:true`（`c04`） |
| mono 9888 | `broken.cs`（**语法错**） | **仍然 `category=ok valid=true` + `"Script compiles successfully"`**（`c03`），singular 同样（`c05`）→ **D-053-3 的缺陷证据** |

### 5.4 `editor_set_node_script_batch`（含独立读回的跨工具链）

```
editor_open_scene{res://scenes/main.tscn}            → opened=true
editor_add_nodes_batch{[Node2D Mcp053A, Mcp053B]}    → status=ok count=2
editor_set_node_script_batch{res://scripts/valid.gd, [Mcp053A,Mcp053B]}
                                                     → status=ok count=2，两项 attached=true、previous=""（a23）
editor_save_scene{res://scenes/main.tscn}            → saved=true
project_read_scene_file_content{…main.tscn}          → "script = ExtResource(" ×2、res://scripts/valid.gd ×1（a25，**由另一个工具读磁盘字节**）
```

| # | 类 | 证据 |
|---|---|---|
| `a21`–`a25` | 成功 + 独立读回 | 见上；`previous_script_path` 空字符串（原本无脚本） |
| `a27` | `keep_existing` | `count=0 attached=0 skipped=2`；每项 `reason="the node already carries a script and 'keep_existing' is true"`、`previous_script_path=res://scripts/valid.gd` |
| `a28` | `keep_existing` 不动盘 | 再存盘后场景文本 sha **未变**（前后都是 `811eec80…`） |
| `a30` | 覆盖 + 点名 | `attached=[Mcp053A:valid.gd→other.gd Mcp053B:…]` |
| `a32` | 覆盖落盘 | 磁盘上 `other.gd ×1`、`valid.gd ×0` |
| `a33` | 失败=全回滚 | 缺节点 → `-32001` + `batch{status=rolled_back, rolled_back=true, on_error=all_or_nothing, count=0, errors=[1:Nope], reverted=0}`；`a35` 场景仍只有 `other.gd` |
| `a36` | **读回**拦下 engine 拒绝 | 抽象脚本 → `-32000`「Node 'Mcp053A' did not accept the script …」+ `rolled_back:true` + `errors=[0:…]`；`a38` 存盘后 `abstract.gd` 出现 **0** 次 |
| `a39`–`a45` | 参数/底层 | 缺 `script_path`→`-32602`；`node_paths:[]`→`-32602`；`node_paths:"X"`→`-32602`；`keep_existing:"yes"`→`-32602`；`user://x.gd`→`-32602`+suggestion；未知参数→`-32602`；脚本不存在→`-32001` |
| `a22`+`b01` | scope 隔离 | 9888 有 `editor_set_node_script_batch`、没有 `running_game_get_node_property_samples`；9889 反之（`b03`），两个方向各有一条 `-32601`（`a05`/`b05`） |

### 5.5 M-5（默认逐字节相同 + 显式步长点数/字节数）

| 调用 | 响应 | 字节 | sha256 |
|---|---|---|---|
| **改动前**（`c4823798a` 的二进制）`{node_path:/root/Main, properties:[name], frame_count:5, frame_interval:1}` ×3 | `{"frame_count":5,"node_path":"/root/Main","samples":[…5 点…]}` | **295** | `eef36e62…b67a`（3 次相同） |
| **改动后**同参（`b07`） | 同形状，**没有** `sample_stride`/`observed_count` 键 | **295** | `eef36e62…b67a` ← **逐字节相同** |
| 改动后 `frame_count:180, frame_interval:1`（`b08`，无步长） | 180 点 | **6147** | `438db9c0…` |
| 改动后 同参数 + `sample_stride:10`（`b09`） | `frame_count=18 observed_count=180 sample_stride=10`，样本帧号 `0,10,…,170` | **781** | `3002a382…`（**−87%**，点数 180→18） |
| `sample_stride:0`（`b10`） | `-32602`「must be at least 1: a stride of 0 would return no sample at all」+ suggestion | 371 | — |
| `sample_stride:"every"`（`b11`） | `-32602`「must be an integer, got String」 | 338 | — |

---

## 6. 回归与逐条归因

驱动：`scripts/mcp053_regression_battery.ps1`（**严格串行**），日志在
`docs/reports/evidence/task053/regression/`，五个批次的 `summary-*.txt` 是退出码清单。

**先说一个自己抓到的假绿**（写进报告，避免下一个人再踩）：该驱动第一版把 `$Scripts = Join-Path $PSScriptRoot`
写成了缺参数调用，于是每个 `powershell -File <垃圾路径>` 都**立即 exit 0**，16 步全部「通过」、日志 0 字节。
现在驱动会**把「日志 0 字节」判为失败（exit 97）**，并在每行打印日志字节数——所以下面的表里每一行都有真实字节数与真实耗时。

| # | 脚本 | exit | 用时 | 自身汇总 | 归因（契约 173→175 之后） |
|---|---|---|---|---|---|
| 1 | `mcp031_gate6_coverage_probes.ps1` | 0 | 55s | 101/101 | 与 TASK-051 相同；本批不新增收窄点 |
| 2 | `mcp010_b2_observation_evidence.ps1` | 0 | 34s | `phase game: 29/29` | 其计数已**派生**（TASK-052 已改为读第六份清单 + 新增工具按组 scope 兜底），故 175/152/72 自动成立；无 `[FAIL]` |
| 3 | `mcp019_b4_evidence.ps1` | 0 | 25s | 66 checks / 66 passed / 0 failed | 只断言自己那 7 个工具与报告桥，无契约计数；未受影响 |
| 4 | `mcp027_object_shape_and_paths_evidence.ps1` | 0 | 25s | `phase green: 60/60` | 对象形状/路径读出；未受影响 |
| 5 | `mcp050_parameter_guidance_evidence.ps1 -Label green` | 0 | 22s | `port 9877 guard: pass` | TASK-050 的 `-32000` 口径证据（含 `.cs` 拒绝）在本树复跑通过 |
| 6 | `mcp050_contract_diff.py`（钉在 `889466b85c`→`b8b6553d90`） | 0 | 0s | `problems = 0`，overrides 23→24 | 这对修订是**它自己的**，不受本树 175 影响（保留其独立性） |
| 7 | `mcp041_gates.ps1` | 0 | 403s | **内部 34 步全 EXIT 0**：gate1/3/4/5×2/6 + `mcp032/033/034/035/036/probe037/mcp040_probes/mcp040_racing` | 该电池**自己重跑了门①③④⑥ 与门⑤ 两次**（这会成为本批最强的回归信号之一） |
| 8 | `mcp042_gates.ps1` | 0 | 419s | **内部 38 步全 EXIT 0** | 另含 `projectrewrite` 诚实性证据 |
| 9 | `mcp043_gates.ps1` | 0 | 544s | **内部 58 步全 EXIT 0** | 另含描述/组查找证据 |
| 10 | `mcp044_capture_evidence.ps1 -Phase editor` | 0 | 60s | 40/40 | 截图/比对，与新增工具无关 |
| 11 | `… -Phase headless` | 0 | 9s | 8/8 | 同上 |
| 12 | `… -Phase game` | 0 | 8s | 9/9 | 同上 |
| 13 | `… -Phase diff-image` | 0 | 12s | 5/5（`ratio=0.02000167`，113 929 B） | 同上 |
| 14 | `mcp045_pixel_compare_cost.ps1 -Label post` | 0 | 31s | 15/15 | 成本曲线；`off` 中位 24.9 ms（与 TASK-045/046 同量级） |
| 15 | `mcp046_capture_encode_cost.ps1 -Label post` | 0 | 50s | 23/23 | 背靠背中位 107.5 ms（TASK-046 基准 99.0–101.4 ms，同一量级） |
| 16 | `mcp052_added_tools_evidence.ps1`（mono，`-Batch added`） | 0 | 38s | **53/53 checks passed** | TASK-052 自己的 53 条证据在本树上复跑通过 → **必须改**的三处期望见 §6.1 |
| 17 | `mcp051_gate1_groups.ps1` | 0 | 103s | `GATE1 <组> EXIT 0 3/3 checks passed` 逐组 + `DONE` | 门① 的逐组版本；与 §4.1 一致（152/72/175） |
| 18 | `mcp051_b_tier_evidence.ps1` | 0 | 23s | `facts: 8`、`port 9877 guard: pass=True` | B 档参数证据；无 `problems` |
| 19 | `mcp051_wire_verbatim_check.py` | 0 | 0s | `problems = 0` / `WIRE CHECK OK` | 线上逐字与契约比对（含 O-9 scope 事件的 15/15 一致） |
| 20 | `mcp051_final_sweep.py` | 0 | 1s | `problems = 0` / `SWEEP OK` | 生成器的「BEGIN/END generated」段全部 already up to date（**未被顺手改过**） |
| 21 | `not_a_regression_mcp051_contract_diff_pins_task051` | 0 | 0s | 8 行 `PROBLEM`（见下） | **不可用性归因**，不是回归：`mcp051_contract_diff.py` 按**内容**钉死 TASK-051 自己的修订对（171 条 / generator 1.12.0→1.13.0 / overrides 24→28），任何后续树都不可能满足 |

第 21 步的 8 行（逐字，说明它测的是 TASK-051 的变更集而不是本批）：

```
PROBLEM tool count is 175, expected 171
PROBLEM changed tools = [], expected exactly ['editor_add_nodes_batch', 'editor_list_signal_connections', 'editor_play_scene', 'editor_simulate_input_sequence', 'running_game_run_test_scenario']
PROBLEM _meta moved in [], expected only generator_version + overrides
PROBLEM generator_version before is '1.15.0', expected '1.12.0'
PROBLEM generator_version after is '1.15.0', expected '1.13.0'
PROBLEM overrides before = 29, expected 24
PROBLEM overrides after = 29, expected 28
PROBLEM override records moved for [], expected exactly ['batch_add_nodes', 'find_signal_connections', 'play_scene', 'run_test_scenario', 'simulate_sequence']
```

同理，`mcp051_gates.ps1`（整体）与 `mcp052_contract_diff.py` 也是**按自己的修订对钉死**的：前者内部的
`contract_structured_diff` 步比较的是 `HEAD` 与工作树，后者断言的是 171→173 那一对。两者都是**历史门**，
不是本树可复用的回归项；TASK-053 对应的可复用等价物是 `scripts/mcp053_contract_diff.py`（§1.4，34/34）。
`mcp051_gates.ps1` 其余步骤（门③④⑤×2⑥）已由本批的门与 `mcp041` 电池（内部又跑一遍）覆盖。

### 6.1 因「契约 173 → 175 / 错误码改判」而**必须**调整的期望值（逐条，全部有理由）

| 位置 | 改动 | 理由（不是「顺手改断言」） |
|---|---|---|
| `tests/test_mcp_server.h`（TASK-052 的 overwrite 用例） | `-32001` → `-32000`，并加 `!= -32001` / `!= -32602`、suggestion 逐字含 `overwrite": true`、**逐字节**比对拒绝前后 | 本批**裁决**改了错误码（§1）；只改实现尺寸会让用例继续断言被推翻的语义 |
| `tests/test_mcp_server.h` 计数（10 处 `editor_registry`、22 处 `visible(false)`、15 处 `get_tool_count`、9+9 处 list size、1 处 trace fixture、1 处 `build_tools_list(true)`、7 处 `visible(true)`、1 处 `tool_count`、1 处 `get("tools")`） | 71→72、150→152、173→175、48→49 等 | `project_validate_scripts` 是 `both`（+1 到每一处），`editor_set_node_script_batch` 是 `editor`（只 +1 到编辑进程表）→ 计数**不是**统一 +2，逐处按 scope 推导；GDR-7 要求绝对数字而非下界 |
| `scripts/mcp052_added_tools_evidence.ps1` `contract_meta_added_tools` | 2 → 4（顺序含两条新名） | `_meta.added_tools` 是有序表，末尾多了两条（TASK-052 的主体两条未变） |
| 同上 `endpoint_expectations_derived` | 150/71 → **152/72** | 派生值随参数化契约移动；此处它自己就是「派生而非硬编码」的断言 |
| 同上 `a16` 期望 | `-32001` → `-32000`，suggestion 断言收紧到含 `overwrite": true` | 同第一行；sha 不变断言**保留** |
| `tests/test_mcp_server.h` 三处历史注释（171/173 的叙述） | 补一句 175 的来源 | 注释与断言必须自洽（不改历史描述本身） |

### 6.2 归因（有没有「因为本批而变色」）

**没有一条回归因为本批变色**：21 步全部 exit 0（第 21 步是上表说明的**不可用性归因**，不是回归）；所有 `[FAIL]` 扫描为 0
（扫到的 `failed=…` 都是引擎*数据*里故意失败的断言用例，例如 `run_test_scenario` 的 `failed:2`、
`get_test_report` 的 `all_passed:false`，都是**预期的负面样例**，其外层 checks 是 `[PASS]`）。
唯一因本批而**修改**的是 §6.1 列出的期望值，逐条都有理由。

### 6.3 证据目录的干净度（环境事实，已处理）

三个回归脚本会把自己的 evidence 写回**它们各自的 TASK 目录**，复跑会改动已提交文件：

- `mcp050_parameter_guidance_evidence.ps1` → `docs/reports/evidence/task050/green/*.json`（8 个文件）；
- `mcp051_gate1_groups.ps1` + `mcp051_b_tier_evidence.ps1` → `docs/reports/evidence/task051/**`（25 个文件 + 1 个新文件 `red/e20_child_status.json`）。

本批在核对完其汇总后**全部 `git checkout` 还原并删掉那个新文件**（`git status` 现在只剩本批自己的改动），
只把这两次运行的 stdout 留档在 `docs/reports/evidence/task053/regression/`（§6 的表就是从这里读的）。
`mcp041/042/043` 的电池与 `mcp044/045/046` 只写 `%TEMP%`，未触碰仓库。

---

## 7. 决策记录（本批的「为什么长这样」；决策日志本体在 harness 仓库，本 fork 只读）

### 7.1 `sample_stride` 为什么是「回传网格」而不是第二个 `frame_interval`
见 §2.4。核心权衡：如果把新参数做成「第二个帧间隔」，它就与既有 `frame_interval` 重复（同一件事两个旋钮，
GDR-25 明确反对「两个都能控制同一件事」）；做成回传网格，才能保住审计里被点名的那个**必须每帧观察**的调用，
同时把载荷降到 1/N。代价（已写进 schema 描述与报告）：观察本身不省钱，省的是响应；想看稀疏序列又不想付每帧观察的
CPU 时，仍应调大 `frame_interval`。

### 7.2 批量校验为什么是「请求形状先判、缺失文件算整体拒绝」
三类分类必须穷尽（`count == valid+invalid+unavailable`）。「文件不存在」不是脚本的判定，是**请求**的属性，
所以它和越界一样在**任何文件被读之前**拒绝（`-32001` 点名 `paths[i]`）。若把它记成 `invalid`，
就等于把「你写错了路径」冒充成「这个脚本编译不过」——正是 TASK-050 N-2 要消灭的那类冒充。

### 7.3 批量挂脚本为什么只有**一个** `script_path`，以及回滚的真实边界
契约原文就是「one script」。它的后果是：`Object::set_script()` 的接受/拒绝**只取决于脚本本身**，
所以同一批里「前面接受、后面拒绝」在**一次同步调用**里构造不出来——唯一可构造的 engine 拒绝（抽象脚本）
落在 `index 0`，`reverted` 因此为空。撤回机制本身用 `apply_node_script()`/`restore_node_script()` 直接单测
（doctest「take-back puts back exactly what the write replaced」：两次落地 → 逐个恢复并读回，含 null 恢复）。
**没有**为了让回滚「看起来有东西可撤」而人为制造失败。

### 7.4 抽象脚本是「读回」的证据来源（不是防御性检查）
`Object::set_script()` 是 `void`，抽象脚本时 `ERR_FAIL_COND_MSG` **提前返回**（`core/object/object.cpp:1049-1058`），
节点保持原样、不报错。所以「写成功」这件事**只能**由 `node->get_script()` 读回证明：
`a36`/`a38` 实测到「调用返回成功但节点没有脚本」这一族缺陷被拦住（有 `@abstract` 脚本作真值反例）。

### 7.5 `error_text` 截断的规则
按 **UTF-8 字节**上限 400 截断并在尾部标 `...(truncated, N bytes total)`；切点回退到字符边界
（不切断多字节字符）。理由：本模块所有长度都是字节（PLAYBOOK §6 第 9 条），且「截断要标明」是 §2.1 的硬要求。
引擎当前只产出 `ERR_*` 短标识符，所以**线路上不可构造**（见 §8），规则用 `truncate_marked` 单测覆盖（含 UTF-8 边界）。

### 7.6 生成器里「新增」与「改一条既有」必须分开写
M-5 加一个属性**不是**新工具：它走 `SCHEMA_OVERRIDES`（`mode=replace` + reason 里逐字引用 `required`），
于是 `_meta.overrides` 多一条 `inputSchema/monitor_properties`，条目数**不变**。这与 GDR-28 第 1 条（新增条目由决策者撰写并追加）
是两件事，混在一起会让「描述被修正」「工具以前不存在」不可分辨——这是 TASK-052 建立该机制时的原话，本批继续遵守。

---

## 8. 交给决策者的待确认项（规范缺口 / 冲突）

### D-053-1（**必须先裁定**）：任务书 §3 的「契约 173 → **176**」与 §2 的算术不一致

- 事实：契约 **175** 条。`_meta.count = len(result.tools)`，生成器 `EXPECTED_OUTPUT = 174 - 2 - 1 + len(ADDED_TOOLS)`；
  `ADDED_TOOLS` 现为 **4** 条（TASK-052 的 2 条 + 本批 §2.1/§2.2 的 2 条）→ **171 + 4 = 175**。
- 冲突点：§3（以及你的口述）写「173 → 176」（+3），但 §2 只给了**两条**条目原文，且 §2.3 明写 M-5「**不改工具数量**」；
  §2 的标题「三个新增工具」把 M-5 也算了一个，但 §2.3 没有任何可写进 `ADDED_TOOLS` 的条目原文。
- 我的处置：**按 §2 的字面实现**（+2 = 175）。GDR-28 第 1 条把新增条目的撰写权留给决策者，我不会自撰第三条条目来凑数。
- 需要你做的：确认「176」是笔误（我建议在规范里改成 175），**或者**给出第三条条目的 `name`/`description`/`inputSchema` 原文，
  我再补一条 `ADDED_TOOLS` + 一个组 + 证据（工作量很小，但必须由你落笔）。

### D-053-2：「不改已有条目」与 M-5「给既有工具加参数」在字面上互斥

- 事实：M-5 要「给既有工具加参数」，而参数一进 `inputSchema` 就必然改**那一条**既有条目。
- 我的处置：用**早已存在、有 `_meta.overrides` 审计记录**的 `SCHEMA_OVERRIDES`（`mode=replace`），
  只新增 1 个可选属性、`required` 与既有 4 个属性逐字不动，其余 172 条逐字不变（§1.4 的 34 checks 是证据）。
- 需要你做的：确认「不改已有条目」的正确读法是「不改名字/描述/删条目，改动必须走 override 并留痕」；
  若你要求连 schema 也不能动，那 M-5 只能做成**新增工具**（那时条目数才会变成 176，正好与 D-053-1 咬合）。

### D-053-3（**真缺陷，建议单独立项**）：Mono 构建里 `.cs` 的 `valid` 永远为真
- 实测（`c02`/`c03`/`c05`）：mono 编辑器里 **语法错误的 `broken.cs` 也得到 `category=ok`、`valid:true`、
  `message="Script compiles successfully"`**；singular 工具同样（`c04`/`c05` 一致）。
- 根因（源码级）：`modules/mono/csharp_script.cpp:2588-2621`，`CSharpScript::reload()` 注释明写
  *"In the case of C#, reload doesn't really do any script reloading"*，并且**无条件 `return OK`**（2620 行）；
  真正的合法性在 `ScriptManagerBridge_AddScriptBridge` 里写进私有 `valid` 字段，**不反映在返回值上**。
  模块的共享判定用的是 `reload()` 的返回值 → C# 永远「编译成功」。
- 影响：TASK-050 建立的「`valid` 只在真的用该文件自身语言编译过时才是结论」这句**对 C# 是假的**；
  契约描述（`project_validate_script` 的 append 段）现在也因此在 C# 上过度承诺。同一族的诚实性缺陷（N-2 的兄弟）。
- 我**没有**单方面改：这属于 TASK-050 的裁决面；单改 plural 会让同一文件在同一进程里出现两个答案（比缺陷更糟）。
- 建议选项（供你裁）：(a) 把契约描述里的「编译过」收窄到「GDScript 等真编译返回校验的语言」，
  C# 只承诺「能加载」；(b) mono 构建里对 `.cs` 不给 `valid`（按 `language_unavailable`/`-32000` 诚实拒绝，
  并说明「C# 的判定要跑 `project_build_csharp`」）；(c) 用 `Script::can_instantiate()` 之类的旁证补充——注意它语义是「可实例化」，
  不是「可编译」，选它要另写规范。

### D-053-4（已按设计选择处理，记录备查）：`.gdshader` 不是脚本
引擎的 `ShaderLanguage` **不是** `ScriptLanguage`（`servers/rendering/shader_language.h:51`），
所以 `.gdshader` 在 singular 工具里得到的是 `-32000`「no script backend for '.gdshader'」。
批量工具的**扫描集**因此定为 `{gd, cs}`（模块自己的脚本写入工具就是这两种），显式 `paths` 给 `.gdshader` 仍会逐项诚实地报
`language_unavailable`（`a10` 实测）。若你希望扫描覆盖 `.gdshader`，需要先有一个「shader 校验」的口径。

### D-053-5（环境事实，非缺陷）：首次 `--import` 0xC0000005 仍会出现
本批第一次跑证据脚本时，scratch 工程的首次 `--import` 以 `0xC0000005`（exit `-1073741819`）失败，
`mcp_import_guard.ps1` 的重试第 2 次成功（`exit=0 attempts=2`），后续几次都是 1 次成功。
与 REPORT-028 的结论一致：**频率未知、不可归因于本批**；纪律是「检查退出码 + 有界重试」，已满足。

---

## 9. 未构造 / 未覆盖项（显式声明，不是省略）

| 项 | 为什么不可构造 | 替代证据 |
|---|---|---|
| 「回滚时确有**已落地写入**被撤回」（`reverted` 非空） | 全批只有一个 `script_path`，`Object::set_script()` 的拒绝只取决于脚本本身 → 一次同步调用里批内节点**同质**；可构造的 engine 拒绝（抽象脚本）必落在 `index 0` | 撤回原语用 doctest 直测（`apply_node_script` ×2 成功后 `restore_node_script` 逐个恢复并读回，含 null 恢复）；工具级证据给「拒绝后场景逐字节未变」（`a33`/`a35`/`a36`/`a38`） |
| C# 的 `invalid` 判定 | `CSharpScript::reload()` 恒 `OK`（D-053-3） | mono `c02`（合法 `.cs` → `ok`）+ `c03`/`c05`（**实测并记录**这条限制，不假装通过） |
| `error_text` 截断（400 B）在**线路**上触发 | 引擎只给 `ERR_*` 短标识符；没有能产出超长 error_text 的语言路径 | `truncate_marked` doctest：短文本原样、ASCII 截断、UTF-8 边界（`"中文中文"` 切 5 字节 → 只留 1 个完整字 + 标注 12 B） |
| 9888 上调用 `running_game_get_node_property_samples`（默认/步长） | scope=game，编辑器端点**不注册**它 | 9889 上的完整对照（§5.5）+ 9888 的 `-32601`（`a05`） |
| 扫描时 `dropped > 0`（超 64 个脚本）的**线路**证据 | 线路证据跑在只有 6 个脚本的 scratch 工程（`a12`：`truncated=false dropped=0`）；doctest 里跑的是 `res://`＝引擎源码树（2000+ 脚本），但只断言「`truncated` ⟺ `dropped>0`、`count<=64`、`count==三项之和`」 | doctest 的扫描用例（`count<=64` + 恒等式 + 标记一致） |
| 门⑤ 之外的多进程并发压力 | 纪律要求构建/端口串行 | 门⑤ ×2 + `mcp041` 电池内部又跑了一遍门⑤×2 |

---

## 10. 交接

- **代码**：`tools/project_validate_scripts.{h,cpp}`、`tools/editor_set_node_script_batch.{h,cpp}`（新增）；
  `tools/project_read_files.{h,cpp}`（抽出共享判定 `validate_script_source`）、`tools/project_text_write.cpp`（错误码）、
  `tools/running_game_frame_observation.{h,cpp}`（`sample_stride` + 导出的判定规则）、`tools/registration.cpp`（两行注册）。
- **契约**：`docs/tools_list.renamed.json`（175 条，sha `65c83ab8…`）、`docs/tool-groups-added.json`（4 组，sha `0735fe29…`）、
  `scripts/gen_renamed_contract.py`（v1.15.0，`ADDED_TOOLS` +2、`SCHEMA_OVERRIDES` +1）。
- **测试**：`tests/test_mcp_server.h`（+10 用例，计数按 scope 逐处推导）。
- **脚本**：`mcp053_added_tools_evidence.ps1`（门②，72/72）、`mcp053_m5_baseline_capture.ps1`（改动前基线）、
  `mcp053_contract_diff.py`（34/34）、`mcp053_regression_battery.ps1`（五个批次共 21 步串行回归）。
- **证据**：`docs/reports/evidence/task053/`（wire 110 文件 + log + results + 基线 + 回归日志）。
- **待你裁定**：D-053-1（175 还是 176，以及第三条条目是否由你补写）、D-053-2（override 是否算「改既有条目」）、
  D-053-3（C# `valid` 永远为真，建议单独立项）。**这三条都不阻塞本批的门与回归**，
  但 D-053-1 与 D-053-2 会影响下一批的计数口径，D-053-3 会影响你会不会把 `project_validate_scripts` 当成 C# 的验收手段。
