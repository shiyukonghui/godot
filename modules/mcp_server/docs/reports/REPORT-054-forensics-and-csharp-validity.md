# REPORT-054 — C# 校验诚实化（D-053-3）+ O-12 代次标记 + O-11 分析器三处修复

> 任务书：`docs/tasks/TASK-054-forensics-and-csharp-validity.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`。
> 规范：`DESIGN-DETAIL` §24/GDR-26、§26/GDR-28 第 13 条、§22.3b。证据：`docs/reports/REPORT-AUDIT-RACING-BACKLOG.md`
> §5.11/§5.12、`REPORT-053-added-tools-2.md` D-053-3。
> 证据目录：`docs/reports/evidence/task054/`（`red/` 改动前，`green/` 改动后，`regression/` 回归）。

- **status**：实现完成；门①③④⑤⑥ + `--check-completeness`/`--added` 全绿；线上红/绿对照完整；回归见 §7。
- **commits**：`7cafa46e05`（本报告 + 代码 + 契约 + 测试 + 脚本 + 证据一笔提交），随后一笔仅更新本报告的
  「build vs HEAD」说明。
- **契约条数不变**：**175** 条（171 移植 + 4 新增），`_meta.generator_version` 1.15.0 → **1.16.0**，
  `_meta.overrides` **29**（条目未增未减），契约 sha256 `460004da50c6fa0a98bab07b04e6ca512297b6714ff8d9292b50ff5754aef027`。
- **构建**：plain `4.8.dev.custom_build.bd88b1b41`、mono `4.8.dev.mono.custom_build.bd88b1b41`，
  两者 `--version` 的 hash 前缀 == 建树时 `git rev-parse --short=9 HEAD` = `bd88b1b41`。
  **说明（避免误导重跑者，同 REPORT-053 的记载）**：门的日志里 `plain binary --version: …bd88b1b41` 与
  `git HEAD: bd88b1b41` 是**同时成立**的——那正是「被门检验的那棵树」。git 的提交号是**内容哈希**，
  提交动作本身把 HEAD 前移到 `7cafa46e05`，所以**现在**直接比对 `--version == HEAD` 会不等。
  要求「`--version == 当前 HEAD`」的重跑者，请先按 §5.1 的规则重建（`build_local.cmd -Force`；
  mono 侧记得先删 `mcp_trace` 对象）再跑门。
- **端口纪律**：9877 全程只有观测（开工/收工两次 `netstat` 均为无监听、pid 前后一致，两次运行都给出
  `port_9877_guard` PASS）；测试只用 9888/9889；未 push。

---

## 1. 〇号题材：C# 校验诚实化（D-053-3，最高优先）

### 1.1 先读引擎源码 → 选 (b)：没有真信号，下调声明

任务书要求二选一，**先读源码再定**。结论是 **(b)**：这个 API 里**不存在**能区分「语法错误的 `.cs`」与
「合法 `.cs`」的信号。逐条依据（本 fork 引擎源码，只读）：

| 事实 | 位置 | 内容 |
|---|---|---|
| `reload()` 恒 `OK` | `modules/mono/csharp_script.cpp:2588-2621` | 函数体里唯一的 `return` 在 **2620 行** `return OK;`；2593-2594 的注释逐字写着 *"In the case of C#, reload doesn't really do any script reloading"*；2589-2591 还有一条早退 `if (!reload_invalidated) return OK;` |
| 真信号是**私有**字段 | `modules/mono/csharp_script.h:137` | `bool valid = false;` 在 `private:` 段，**没有任何公开读取口** |
| 该字段的语义 | `csharp_script.cpp:2599` + `ScriptManagerBridge.cs:436-463` | `valid = ScriptManagerBridge_AddScriptBridge(this, &script_path)`；C# 侧 `AddScriptBridgeCore` 只在 `_pathTypeBiMap.TryGetScriptType(scriptPath)` 命中时返回 true → 它回答的是「**该路径的类之前已建进已加载的 .NET 程序集了吗**」，不是「这段源码能编译吗」 |
| 另外两个写点 | `csharp_script.cpp:845-854`、`:2218-2245` | 同样由 bridge 命中与否驱动（`reload_registered_script` 直接 `valid = true`） |
| 旁证不可用 | `csharp_script.cpp:2341-2356` | `can_instantiate()` 读 `valid`，但把「类没找到」与「abstract / generic type definition」（`csharp_script.h:122-124`）**混为一谈**，并在询问时打 `ERR_FAIL_V_MSG` 日志，不是编译判定口 |

**关键点**：模块的调用点（`tools/project_read_files.cpp` 旧 `validate_script_source`）只做
`set_source_code()` + `reload()`，**从不设置脚本路径**，而 `reload()` 用的是 `get_path()`（空串）→
即使去读那个私有字段，得到的也是「空路径没注册」，与文件内容毫无关系。

**因此**：(a) 不成立（没有「真能区分」的信号）；按任务书选 (b)，**不得把「引擎没报错」当「有效」**。
分类为 **`unverifiable`**，带 `reason` + 引擎依据（上表 `文件:行`）。

### 1.2 实现（共享判定 + 两个工具口径一致）

**共享判定**（`tools/project_read_files.{h,cpp}`，TASK-050/053 的同一处）：

```cpp
bool validate_script_language_has_compile_verdict(const String &p_language_name); // "C#" -> false
String validate_script_unverifiable_reason();          // 批量的 reason（引擎依据，527 B）
MCPToolError validate_script_unverifiable_error(const String &p_path);  // -32000 + data.suggestion
```

`validate_script_source()` 在语言**存在**之后新增一个分支（语言不可用分支**逐字未动**）：

```cpp
if (language != nullptr && !validate_script_language_has_compile_verdict(language->get_name())) {
    verdict.category = "unverifiable";
    verdict.valid = false;                 // 结构体内部哨兵；线上不发布 valid
    verdict.reason = validate_script_unverifiable_reason();
    verdict.message = validate_script_unverifiable_error(p_path).message;
    return verdict;
}
```

| 工具 | 分类 | 线上形态 |
|---|---|---|
| `project_validate_script`（单数） | `unverifiable` | **`-32000` + `data.suggestion`**（与 `language_unavailable` 同一处置形状，TASK-050 N-2 口径）|
| `project_validate_scripts`（批量） | `unverifiable` | 条目 `{category:"unverifiable", valid:null, reason, message, suggestion}`；新增计数器 `unverifiable_count`，`count` 仍恒等于四类之和 |

- `valid: null`（**不是** `false`）：`false` 是「编译失败」的判定，而这里恰恰无人能判；与单数工具
  「拒绝而不是答 `valid:false`」同理由。
- `reason` 是**引用**而不是句子：它是整条分类的依据，所以它有**自己的**长度上限
  `MAX_REASON_BYTES = 800`（`project_validate_scripts.cpp`），不被 `message` 的 400 B 规则腰斩
  （实测 reason = 527 B；若沿用 400 B 会在 `ScriptManagerBridge.cs:436-463` 处截断）。
- 两个工具发布的 `message`/`suggestion` 是**同一对字符串**（同一工厂），线上实测逐字相等（`m07`）。

### 1.3 描述同步澄清（override append + 重生成 + 指纹 + 门① 逐字）

- 单数 `validate_script`（移植条目，有 `old_name`）：走既有的 **`DESCRIPTION_OVERRIDES["validate_script"]`**
  （`mode=append`，`验证脚本语法` 逐字仍在句首），只追加一句英文并改写该条的 `reason`。
- 批量 `project_validate_scripts`（**`ADDED_TOOLS` 条目**）：它**没有 `old_name`**，`DESCRIPTION_OVERRIDES`
  按 `old_name` 取表，**结构上不可达** → 只能改 `ADDED_TOOLS` 里的自撰 `description`/`reason`
  （GDR-28 第 1/12 条的两条通道，added 条目走 added 通道）。**这是对任务书「描述若需改走
  `DESCRIPTION_OVERRIDES`」的一处显式偏离**，理由与替代通道见 §8-D2。
- 生成器 `GENERATOR_VERSION` **1.15.0 → 1.16.0**；`EXPECTED_OUTPUT` 公式不变；**幂等**（连跑两次同 sha）。
- C++ 注册字面量同步：`tools/project_read_files.cpp`（单数）、`tools/project_validate_scripts.cpp`（批量 raw string）
  逐字改为契约里的同一字符串，并用脚本**程序化校验**「字面量 == 契约条目」（不是肉眼抄写）。
- 契约结构化 diff：**只动 4 行** = 单数 description、单数 reason、批量 description、`_meta.generator_version`；
  `map_sha256` 未动、条目数未动、其余 173 条逐字未动（`git diff --numstat` = `4 4`）。

### 1.4 线上证据（响应逐字，均 `curl.exe -s -o` + sha256）

**① 改动前（red，mono 构建 `c4823798a`）——缺陷复现**

| 探针 | 请求 | 响应（节选） |
|---|---|---|
| `m02_mono_singular_broken_cs` | `project_validate_script{path:res://scripts/broken.cs}` | `{"valid":true,"message":"Script compiles successfully"}`（171 B，sha `7c1a66f5…`）|
| `m03_mono_plural_broken_cs` | `project_validate_scripts{paths:[broken.cs]}` | `{"results":[{"category":"ok","valid":true,"message":"Script compiles successfully",…}],"valid_count":1,"invalid_count":0}`（404 B，sha `cc348e76…`）|

`broken.cs` 内容逐字：`using Godot;\n\npublic partial class Broken : Node\n{\n    this is not valid C#\n}\n`
——**语法错误文件拿到 `valid:true`**，D-053-3 成立。

**② 改动后（green，mono 构建 `bd88b1b41`）——同一文件、同一请求**

| 探针 | 响应逐字（核心字段） |
|---|---|
| `m01_mono_singular_broken_cs` | `-32000` `message="Cannot validate 'res://scripts/broken.cs': a C# script has no compile verdict in this engine API, so the file was not verified and no 'valid' value is published"`（739 B，sha `f5bd4014…`）|
| `m02` 同探针 `data.suggestion` | `"Godot's CSharpScript::reload() never compiles the source it is given and always returns OK (modules/mono/csharp_script.cpp:2588-2621); the only signal it has is whether a class for the script's path is already in the loaded .NET assembly (ScriptManagerBridge.cs:436-463), which is 'was it built', not 'does this compile'. … compile the project with project_build_csharp …"` |
| `m03_mono_plural_broken_cs` | `{"category":"unverifiable","valid":null,"reason":"CSharpScript::reload() returns OK unconditionally (modules/mono/csharp_script.cpp:2588-2621) and never parses the source set_source_code() was given, … private CSharpScript::valid field (csharp_script.h:137) … (csharp_script.cpp:2599; ScriptManagerBridge.cs:436-463) …","suggestion":"…project_build_csharp…"}`；`valid_count=0 invalid_count=0 unavailable_count=0 unverifiable_count=1 count=1`（1627 B，sha `ceba01b0…`）|
| `m04_mono_plural_legit_cs`（合法 `.cs`） | 与 broken **同形**：`category=unverifiable`、`valid=null`（1624 B，sha `7505c0e6…`）|

**③ 单数/批量口径一致**：`m07` 断言 `singular.message == item.message` 且 `singular.suggestion ==
item.suggestion`，实测 **True/True**。

**④ 非 mono 下「语言不可用」口径不变（TASK-050）**：plain 构建（`bd88b1b41`）上

- `a03/a04`：`legit.cs` 与 `broken.cs` 都得到 `-32000`「this build has no script backend for '.cs'」
  + `data.suggestion` 点名 `module_mono_enabled=yes`（sha `1cc98e60…`/`ba0bc23e…`，与 red 跑逐字节相同）；
- `a05b`：`unverifiable_count` 键存在且为 **0**（旧二进制上该键**不存在**，见 red `a05b`）。

**⑤ 真的能编译的语言未被牵连**：mono 上 `valid.gd → ok/valid=true`（sha `54ee24a3…`）、
`broken.gd → invalid/valid=false, error_text=ERR_PARSE_ERROR`（sha `c2f52f47…`）。

> **线上结论（D86 锚点）**：
> - 锚点 A（red 44/44，`evidence/task054/red/results.json`）：`m01/m03` 证明缺陷真实存在；
> - 锚点 B（green 53/53，`evidence/task054/green/results.json`）：`m01..m10` 证明 `.cs` 不再得到任何 `valid`，
>   两个工具同口径，`.gd` 判定未动，非 mono 口径未动。

---

## 2. O-12：追踪代次标记（一行级）

### 2.1 实现

- `MCPTrace::build_trace_opened_fields(bool is_editor, int port, bool listen)`（`mcp_trace.{h,cpp}`）构造一行：

```json
{"event":"trace_opened","pid":…,"ts_ms":…,"uptime_ms":…,"started_ts_ms":…,
 "mcp_port":9888,"listen":true,"version":"4.8.dev.mono.custom_build.bd88b1b41","role":"editor"}
```

- 写点：`mcp_server.cpp` 解析出端口之后（`[MCP] role=…` 那一行之后、`listen()` 之前），
  通过 **`Recorder::record_event_line()`** 追加——即 TASK-044 的 side-channel 路径，**不占请求 `seq`**，
  也不动 `get_lines_written()`。监听失败时同样写（文件确实已打开，绑定失败正是追踪该记的事实）。
- `version` 的拼法逐字等同 `--version`（`main/main.cpp:319-325`：`GODOT_VERSION_FULL_BUILD` + "." +
  hash 前 9 位），使一行能把文件绑到具体二进制。
- **既有请求行字段与含义零改动**：未触碰 `_build_line`/`_append`/`Recorder::record`，只新增一个
  builder + 一次 `record_event_line` 调用（见 §3.3 的共享 obj 风险）。

### 2.2 线上证据（同一 `--mcp-trace` 文件，三个进程）

| | red（`c4823798a`）| green（`bd88b1b41`）|
|---|---|---|
| 文件行数 | **9**（0 marker + 9 请求）| **12**（**3** marker + 9 请求）|
| `seq==1` 出现次数 | **3** | **3**（每个代次仍从 1 开始）|
| `trace_opened` 行 | **0** | **3** |
| marker 的 pid / role / mcp_port / version | — | `77376,81940,83236` / `editor×3` / `9888×3` / `4.8.dev.mono.custom_build.bd88b1b41 ×3` |
| marker 是否带 `seq` | — | **否**（`t_green_the_marker_holds_no_request_seq` PASS）|
| 文件 sha256 | `c6ba103175f77d37b6cd2119274e216bf3335807566f2b43c189d46d1f3be97d` | `0be7f1b7724e907709e9ec6807b5bb737dc58018cee9fb243a9632cdca9abe29` |

→ O-12 的复现（3 个 `seq==1`、零代次标记）与修复（每进程一行、不占 seq）都在同一份 trace 上给出。

---

## 3. O-11：分析器三处取证修复（逐条前后对照）

对照对象：`audit-racing-backlog/ev-editor/trace-game.jsonl`（28 行，3 个**无标记**代次）、
`mcp-racing-test/trace-editor.jsonl`（298 行）、本任务 phase T 造的 `trace-generations.jsonl`
（9 请求 + 3 marker），以及一份合成旁路 trace。旧脚本 = `git show HEAD:…/analyze_mcp_trace.py`。

### 3.1 ① 摩擦窗口：排除「两次之间夹了别的工具调用」的伪摩擦

**前**：`for later in tool_calls[i+1:i+1+window]` 只要同工具、窗口内成功即算一对。
**后**：`session_key(失败) == session_key(成功)`（同一代次 + 同一连接，退化见 §3.4）**且**向前扫描遇到
**不同工具就停**（那个工具的后续成功属于另一次尝试，不是这次失败的解）。

| 同一份追踪 | 前 | 后 |
|---|---|---|
| `trace-editor.jsonl` | 13 对 | **12 对**；消失的正是 `editor_analyze_screenshot_diff` seq258→265 ——两次之间夹了 `editor_capture_screenshot / project_edit_script / project_validate_script / editor_stop_scene / editor_play_scene` **5 个别的工具**（一次 play/stop 之后的新场景），这是伪摩擦 |
| phase T（3 代次 + 1 伪例）| 3 对，含 run-2 的伪例 | **2 对**，run-2 的伪例消失，两个真实 episode 保留 |
| `trace-game.jsonl`（3 个**无标记**代次）| 3 对 | 0 对（见 §8-D1：文件无法切分时的保守行为）|

### 3.2 ② 可合并 n-gram：不跨连接/代次混统计 + unigram 不再被拆成字符

**前**：`mergeable()` 按 `connection` 分桶；`shapes()` 对 unigram 也 `list(gram)`。
**后**：分桶键 = `session_key`（含**代次**）；`[gram] if isinstance(gram, str) else list(gram)`。

| 同一份追踪 | 前 | 后 |
|---|---|---|
| `trace-editor.jsonl` `unigrams[0]` | `["e","d","i","t","o","r","_",…]`（字符数组）| `["editor_set_node_property"]`, count 57 |
| `trace-editor.jsonl` bigrams | **0**（每桶只有 1 条 → 结构性恒空，正是 O-11 记录的缺陷）| **10** |
| `audit` `unigrams[0]` | 21 个字符 | 1 个名字 |
| phase T | 单代次混淆 | 3 段，逐段统计 |

### 3.3 ③ 单工具占比 / 超大响应：排除 `event:"capture"` 与 `tools/list`

**前**：`anomalies()` 对**所有**行按 `result_bytes` 判「超大响应」，`tools/list`（整份契约）与
`event:"capture"`（诊断旁路）都会被算进去；`calls()` 也不排除 event 行。
**后**：`calls()` 排除 event 行；`large_responses` 排除 `event:"capture"` 与 `method=="tools/list"`，
并把被排除的条数计入 **`large_responses_excluded`**（诊断旁路不得污染自己的统计）。

合成 trace（1 marker + `tools/list` 2 000 000 B + 真 `tools/call` 2 000 000 B + `capture` 事件行）：

| | 前 | 后 |
|---|---|---|
| `large_responses` | `tools/list, tools/call`（2 条）| `editor_get_scene_tree`（1 条）|
| `large_responses_excluded` | 字段不存在 | **1** |

### 3.4 代次切段 + 连接退化的**显式声明**（O-12 与分析器的接口）

- `load()` 后按 `event=="trace_opened"` 切段：`generations`（段号，首段前为 0）+ `generation_report`
  （每段的 opened 标记、records、tools/call 数、connections、seq 范围）都进 JSON 与摘要。
- **连接退化声明**（`session_keys()`）：审计 §5.11 实测「正常 HTTP 工作流里每次请求都是新连接」
  （`connection = 2..9, 逐条不同`）→ 若一个段内每个工具调用各占一个连接，则 `connection` 不携带会话信息，
  该段**改用「代次」单独作键（按文件顺序）**，并在 `session_keys.degenerate_generations` 与摘要里
  **显式声明**（不是静默忽略）。这正是 §5.11 的修法②「当每桶只有 1 条时声明退化并按文件顺序分簇」。
- 若客户端保持连接（真实 MCP 客户端），则用严格的 `(代次, 连接)` 键。
- `calls_apart` 由「seq 差」改为「工具调用序位差」（跨代次 seq 会重置，旧算法会给出无意义数字）。

### 3.5 与脚本使用者的兼容

`mcp038_trace_evidence.ps1` 记录的 trace 行数因 marker 由 10 → 11，且旧断言会把 marker 的缺失 `seq`
读成 0；该脚本已同步更新（新增 `task054_generation_marker_is_written_once_and_takes_no_seq`，
`one_line_per_request` 期望 11），并在 §7 重跑归因。

---

## 4. 门的真实输出（最终 plain 二进制 `4.8.dev.custom_build.bd88b1b41` == HEAD）

| 门 | 命令 | 结果 |
|---|---|---|
| ① 契约子集逐字 | `check_contract_subset.ps1`（默认组）与 `-Group project_validate_scripts` | **exit 0**；editor 9888 = **152**、game 9889 = **72**、契约 **175**；该组 `name/description/inputSchema` 逐字 True；9877 guard PASS |
| ② 三类证据 | `mcp054_forensics_and_csharp_evidence.ps1 -Label red` / `-Label green` | **44/44** / **53/53**（成功 / 缺参 / 底层失败 三类 + 跨工具链 + 红绿对照，见 §1.4/§2.2/§3）|
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **exit 0**：`327 passed / 0 failed`（`23480 / 23480` 断言）。本轮新增 2 个用例（C# 判定/拒绝/依据、trace marker/no-seq）|
| ④ 全引擎回归 | `--headless --test` | **exit 0**：`1753 passed / 0 failed`（`447703 / 447703`）|
| ⑤ 批收口 | `accept_m1.ps1` 连跑两次 | **exit 0 ×2**，两次都 `22/22 cases passed`，PASS 清单一致；`implemented tools = 152 / 72`，`contract = 175` |
| ⑥ 收窄点三段式 | `check_narrowing_points.py` / `--coverage` / `mcp031_gate6_coverage_probes.ps1` | **exit 0 ×3**：`scanned 75 / pinned 75`（11 条行号漂移的 note，非失败）；覆盖集合 **17 种拼写**声明齐全、未覆盖边界显式打印；探针 **101/101** |
| 契约完备性 | `check_tool_groups.py --check-completeness` | **exit 0**：`ASSERT 171 + 4 = 66 + 105 + 4: PASS` |
| 新增清单 | `check_tool_groups.py --added` | **exit 0**：`TOOL-GROUPS-ADDED CHECK PASS`（4 组，sha `0735fe29…` 未变）、`every added verb …PASS`、`group sizes <= 10: PASS` |

门日志：`%TEMP%\mcp054\gates\`（driver `scripts/mcp054_gate_battery.ps1`，严格串行、无 scons）。

**门⑥ 三段式 + §22.3b 规则 4（新增点 × 闸门 × 证据）**：本批**未新增/修改任何收窄点**。
新增代码里的类型处理只有 `(int64_t)os->get_process_id()`（`int` 拓宽）、
`(int64_t)os->get_ticks_msec()`（`uint64_t` → `int64_t` 符号语义转换，非浮点/分量收窄）、
`now_ms - uptime_ms`（int64 算术）与若干 `String`/`Dictionary` 字段写入 → 扫描器 `scanned == pinned`（75/75）、
0 新增点、0 误报。**行为证据**：red/green 两组线上对照（§1.4/§2.2）就是本批的行为面证据；
**代码审查**：新增写值路径只有 `Recorder::record_event_line()`（既有、TASK-044 已覆盖），
未走任何属性写闸门。本批**不**以「门⑥ 变绿」作为唯一证据。

---

## 5. 构建与环境的实测事实（含两条新风险）

### 5.1 R-1 家族新成员：跨变体构建不会重编 `mcp_trace.o`（**已修工作流，风险已报**）

`mcp_trace.cpp` 新增了 `#include "core/version.h"`，其中的 `GODOT_VERSION_FULL_BUILD` 含
`GODOT_VERSION_MODULE_CONFIG`（mono 构建为 `".mono"`、plain 为 `""`），由 scons 生成到
`core/version_generated.gen.h`。**实测**：

| 时刻 | 事件 | 证据 |
|---|---|---|
| 21:17:05 | plain 构建编出 `mcp_trace.o`（此时 `MODULE_CONFIG=""`）| 对象时间戳 |
| 21:31:36 | mono 构建重写 `core/version_generated.gen.h` → `".mono"` | 头文件时间戳 |
| 21:33:11 | mono 可执行**链接完成**，`--version` = `4.8.dev.mono.custom_build.bd88b1b41`；但 `mcp_trace.o` **仍是 21:17 的 plain 版本** | 对象时间戳未动 |
| 结果 | mono 进程写出的 `trace_opened.version` = `4.8.dev.custom_build…`（**缺 `.mono`**）| `t_green_markers_…` 首次 FAIL 的 evidence |
| 21:38:43 | 手动删除该对象后重建 → 对象重编、mono 重链，marker 与 `--version` 一致 | `Compiling modules\mcp_server\mcp_trace.cpp … Linking Program …mono.exe` |
| 反向 | plain 构建（不删对象）重链后，plain 二进制里 marker 说 `.mono`，而它自己的 `--version` 说 non-mono → **TASK-054 的新 doctest 立刻红**（`4.8.dev.mono.custom_build.… != 4.8.dev.custom_build.…`）| `%TEMP%` 中该次 gate3 输出 |

→ **处置**：`modules/mcp_server/scripts/build_local.cmd -Force` 现在**同时删除**
`bin\obj\modules\mcp_server\mcp_trace.windows.editor.x86_64.obj`（与两个 test 对象同一理由：这是 scons
不维护的那条依赖边）。手工的 mono 构建必须做同样的事（本任务已做，并在 §9 交接里写明）。
**未做**：没有改 `SConstruct`/引擎构建系统（超出 `modules/mcp_server/**` 权限）；把「scons 不跟踪生成头」
这一根因作为**缺陷上报决策者**（§8-D3）。这不是「环境问题降级架构」，而是一条需要上游修的具体构建缺陷。

### 5.2 mono 构建产物与版本

- 手工 mono 构建（串行、不抑制输出）：`D:\Anaconda\Scripts\scons.exe platform=windows target=editor
  module_mono_enabled=yes tests=yes -j8` → **exit 0**（`INFO: Time elapsed: 00:01:38.08`，
  日志 `%TEMP%\mcp054\mono_build.log`，内含本轮 `Compiling modules\mcp_server\mcp_trace.cpp` 与
  `Linking Program bin\godot.windows.editor.x86_64.mono.exe`）。
- **展开说明（诚实记录）**：本任务第一次 mono 全量构建（21:2x）的 scons stdout 因 cmd 的 `%VAR%`
  提前展开写进了仓库根一个名为 `%LOG%` 的临时文件（该文件已被清除），因此**该次的完整日志不存**；
  随后按对象删除-重建的方式重做了一遍，日志与版本校验见上。**产物本身**是版本校验过的
  （`4.8.dev.mono.custom_build.bd88b1b41` == HEAD），红/绿证据都跑在它上面。

### 5.3 固定装置与端口

- `--import` 首次 `0xC0000005`（exit `-1073741819`）在 green 跑里**又出现一次**，重试第 2 次成功
  （`exit=0 attempts=2`），与 D-053-5/REPORT-028 的结论一致（间歇、不可归因本批）。
- 9877 用户编辑器：两次运行开工/收工 `netstat` 均无监听（pid `-1`→`-1`），`port_9877_guard` PASS；
  本任务**从未**启动/杀/重启它。
- 一个**与本任务无关**的陈旧进程曾挡住建链：pid 81880，命令行
  `bin\godot.windows.editor.x86_64.exe --headless --test --test-case="[MCPServer]*"`，创建于 19:47:13
  （早于本任务），无任何端口监听，持有 `bin\godot.windows.editor.x86_64.exe` 导致链接报
  `拒绝访问`。已 `Stop-Process` 该 pid（**不是 9877**，也无监听），随后构建 exit 0。

---

## 6. 契约与生成器

| 项 | 值 |
|---|---|
| 契约 | `docs/tools_list.renamed.json`，**175** 条，sha256 `460004da50c6fa0a98bab07b04e6ca512297b6714ff8d9292b50ff5754aef027` |
| `_meta` | `count=175`、`generator_version=1.16.0`、`added_count=4`、`overrides=29`、`map_sha256=2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd`（未动）|
| 结构性 diff | `git diff --numstat` = **4 4**（单数 description/reason、批量 description、`generator_version`）；其余 173 条与两张清单逐字未动 |
| 幂等 | 生成器连跑两次同 sha（`460004da…`）|
| C++ 字面量 | `project_read_files.cpp`、`project_validate_scripts.cpp` 的注册字面量与契约**程序化比对 = True** |
| 指纹/门① | 门① 在 9888/9889 上逐字 True（§4）|

---

## 7. 回归（逐条归因）

driver：`scripts/mcp054_regression_battery.ps1`（严格串行，无 scons），日志
`docs/reports/evidence/task054/regression/`，汇总 `regression/summary.txt`。

<!-- REGRESSION_TABLE -->

`regression/summary.txt`（第一遍）与 `regression/summary-rerun.txt`（归因修正后重跑）：

| 步骤（脚本） | exit | 结果 | 归因 |
|---|---|---|---|
| `task041_gates`（`mcp041_gates.ps1`） | **0** | 426 s；门③④①⑥⑤×2 + `mcp032..036`、`probe037`、`mcp040` 全过 | 无影响面 |
| `task042_gates`（`mcp042_gates.ps1`） | **0** | 428 s | 无影响面 |
| `task043_gates`（`mcp043_gates.ps1`） | **0** | 609 s；含 `mcp043_contract_diff.py`（自带定版快照对）/`registration_literals`/`group_lookup` | 契约条目数未变、描述按契约同步 → 无影响面 |
| `task053_individual`（=`mcp010/019/027/050` 脚本 + `mcp050_contract_diff`） | **0** | 199 s | `mcp050` 是 non-mono 上的 `.cs` 口径，逐字节未动（§1.4 ④）|
| `task053_capture`（=`mcp044/045/046`） | **0** | 214 s | 捕获开关/时序未动；marker 是**新事件行**，不影响响应字节 |
| `task053_task051`（=`mcp051_gate1_groups/b_tier/wire_verbatim/final_sweep`） | **0** | 160 s | 契约 175 条、`mcp051_wire_verbatim_check.py` 只比对 TASK-051 的 5 个工具（未动）|
| `task053_added`（`mcp052_added_tools_evidence.ps1`） | **1 → 0** | 第一遍 53 项里 **1 项 FAIL**：`b1_no_csproj_is_32001_with_a_suggestion`，且 `b1` 的线路上是 **`curl_exit=7 bytes=0`**（连不上）——**第一遍重跑前** mono 编辑器第一次启动较慢，脚本的 `Wait-ForEndpoint` 被上一相遗留的 `status.json` 骗过，在 socket 还没监听时就发了第一个请求。**修好探针后重跑 53/53 exit 0** | **脚本就绪探针缺陷，与本批代码无关**（`b1` 之后同一次运行的所有检查全过；同一根因导致下一行的 c01）|
| `task053_evidence`（`mcp053_added_tools_evidence.ps1`） | **1 → 0** | 第一遍 73 项里 **1 项 FAIL**：`c01_mono_editor_serves_the_same_contract_view`（`curl_exit=7 bytes=0`，同一根因）。**修好探针后重跑 73/73 exit 0**，且 `c01 curl_exit=0 bytes=53144`、`c02..c05`（本批改的 C# 期望）全 PASS | 同上；`c02/c03` 的旧期望已按本批行为更新（脚本内 TASK-054 注释）|
| `task038_trace_evidence`（`mcp038_trace_evidence.ps1`） | **0** | 28 s；trace 行数期望 10→**11**、新增 marker 断言 | 本批 O-12 的**预期变化**，脚本已同步并重跑 |

**探针缺陷与修正（TASK-054 发现并修）**：`Wait-ForEndpoint` 用 `curl -s -o <file>` 落盘后直接解析文件；
**连接被拒时 curl 不会重写 `-o` 的目标文件**，于是解析到上一相留下的 `status.json` 并返回「已就绪」。
已对 `mcp052_added_tools_evidence.ps1`、`mcp053_added_tools_evidence.ps1`、
`mcp054_forensics_and_csharp_evidence.ps1` 三处改为「每次尝试先删探针文件 + 要求 `curl` exit 0」。
**本任务自己的门② 红/绿也重跑过一遍**（`regression/task054_green_rerun.log`，53/53），
因此两套线上证据都由修正后的脚本产生。修复前后两遍的**其余步骤全部 exit 0**。

**其它副作用（已回滚）**：回归会重写旧任务的证据目录（`task050/task051/task053`）。
为不篡改历史记录，跑完后已把这四棵目录 `git checkout HEAD --` 还原
（并删掉新生成的 `task051/red/e20_child_status.json`）；本批留下的只有 `evidence/task054/**`。

---

## 8. 偏离、缺陷上报与不可构造项

### 8.1 与任务书的显式偏离

- **D1「同一连接」的读法**：任务书 O-11① 写「同一工具 + 同一连接 + 时间/序号窗口内」。若把
  `connection` 当**严格相等**条件，则本仓库所有实测 trace（每次 `curl` 一个新连接）**结构性得到 0 对**，
  真正的摩擦全被删掉（`trace-editor.jsonl` 13→0）。任务书同时写明「具体以 `REPORT-AUDIT-RACING-BACKLOG`
  §2.4 原文为准」，而 §5.11 的修法②正是「当每桶只有 1 条时声明退化并按文件顺序分簇」。
  → 实现为**会话键 = (代次, 连接)**，并在「一个段内每个工具调用各占一个连接」时**声明退化**、退回
  「代次（文件顺序）」作键。连接可用时（真实持久连接客户端）严格条件生效；退化时**显式打印**
  `session_keys.degenerate_generations`，不静默。**实测收益**：`trace-editor` 13→12（删掉的正是唯一伪例），
  phase T 3→2（删掉 run-2 伪例）；**实测代价**：审计那份**无标记的 3 代次**文件 3→0（§8.2 第 3 条）。
- **D2 批量条目的描述通道**：`project_validate_scripts` 是 `ADDED_TOOLS` 条目，没有 `old_name`，
  `DESCRIPTION_OVERRIDES` 结构上够不着 → 走 `ADDED_TOOLS` 的 `description`/`reason`（唯一通道，且仍留痕）。
- **D3 `reason` 的长度上限**：新增 `MAX_REASON_BYTES = 800`（`message` 仍 400 B）。理由：`reason` 是
  **引擎依据引用**，400 B 会在 `csharp_script.h:137`/`ScriptManagerBridge.cs:436-463` 处腰斩。
  这不是「为了好看放宽」，而是「引用不得被截断」；`message`/`suggestion`/`error_text` 的 400 B 规则未动。

### 8.2 上报决策者的缺陷 / 风险

1. **scons 不跟踪 `core/version_generated.gen.h` 对 `mcp_trace.o` 的依赖**（§5.1）：已用
   `build_local.cmd -Force` 规避，但**根因在构建系统**；手工 mono 构建必须记得删该对象，否则产生
   「marker 说错变体」或「新 doctest 假红」。建议：要么修 SConscript 的依赖边，要么把「变体切换必须
   删掉该对象」写进 PLAYBOOK 的构建纪律节。
2. **`CSharpScript::reload()` 恒 `OK`** 本身是**引擎级**缺陷（本任务只做到「不再撒谎」）：
   真正的 C# 校验只能靠 `project_build_csharp`（.NET 构建）。若将来要 `valid` 真值，需要
   `CSharpScript` 暴露编译/诊断状态或让 `reload()` 真的解析源码——都是引擎面改动，超出本模块权限。
3. **无标记的旧 trace 文件无法补救**：3 个真实代次共用一个 `seq` 空间且连接号重复，分析器不再
   跨它拼统计（3 对 → 0 对）。这是 O-12 的**预期保守行为**（宁可不报，也不把三次运行粘成一次），
   但需要决策者知道：对**旧的** trace 不能期待摩擦信号；**新的** trace（带 marker）已实测恢复
   （phase T：3 段、2 对真 episode、1 个伪例被排除）。
4. **旧取证脚本的「就绪探针」会假报就绪**（§7）：`mcp052`/`mcp053`/本任务的 `Wait-ForEndpoint`
   都把「解析到一个 `status.json`」当成「端点已监听」，而连接被拒时 `curl -o` **不重写**该文件。
   根因是脚本、不是被测代码，但它是**假绿/假红发生器**（同一机理也能让一个尚未起好的进程被当成 ready
   而让检查失败，或让一个已死的进程被当成 ready 而让后续请求失败）。三处已修（删探针 + 校验 curl 退出码），
   建议对 `mcp009..mcp053` 里同形的辅助函数做一次普查（本任务只改了实测踩到的三处）。

### 8.3 不可构造 / 未覆盖项（显式声明，不是省略）

| 项 | 为什么不可构造 | 替代证据 |
|---|---|---|
| `unverifiable` 分支的 **doctest** 覆盖 | 本仓库 `--test` 进程是 `module_mono_enabled=no`，`ScriptServer` 里没有名字为 `"C#"` 的语言，`validate_script_source()` 走不到该分支（强行注册一个假 `ScriptLanguage` 等于用测试替身替换被测判定）| 纯函数（判定表）+ 两个字符串（reason/refusal）在 doctest 里逐条断言；**分支本身用 mono 线上证据端到端覆盖**（`m01..m10`，§1.4）|
| 「`valid:false` 作为 C# 的诚实答案」 | 引擎给不出该判定（§1.1），构造它就是要撒谎 | 用 `-32000`/`unverifiable` 的**无判定**形态替代，并在两工具上证明同口径 |
| 非 mono 构建下的 `unverifiable` | 语言不可用分支先生效（TASK-050 口径）| `a03/a04/a06`：`-32000` + `language_unavailable`，`unverifiable_count=0` |
| 真实持久连接客户端的「同连接摩擦」 | 本仓库的测试 harness 是「一请求一 `curl`」（一请求一连接）| `session_keys()` 的严格分支由代码+doctest 审查覆盖；退化分支有线上实测（phase T）|
| 门⑤ 之外的多进程并发压力 | 纪律要求构建/端口串行 | 门⑤ ×2 + `mcp041/042/043` 电池内部各自再跑门⑤×2（§7）|

---

## 9. 交接

- **代码**：`mcp_trace.{h,cpp}`（`build_trace_opened_fields` + `core/version.h`）、`mcp_server.cpp`（写 marker，
  端口解析之后）、`tools/project_read_files.{h,cpp}`（`unverifiable` 判定 + 拒绝 + reason）、
  `tools/project_validate_scripts.cpp`（条目形态 + 第四计数器 + `MAX_REASON_BYTES`）。
- **契约**：`docs/tools_list.renamed.json`（175 条，sha `460004da…`）、`scripts/gen_renamed_contract.py`（1.16.0，
  1 条既有 description override 的 value/reason 改写 + 1 条 `ADDED_TOOLS` 描述改写；条目数不变）。
- **分析器**：`scripts/analyze_mcp_trace.py`（代次切段、会话键与退化声明、三条取证修复；
  §24 第 6 条「分析器启发式不是契约」仍然成立）。
- **脚本**：`scripts/mcp054_forensics_and_csharp_evidence.ps1`（门②红/绿，44/44 + 53/53）、
  `scripts/mcp054_gate_battery.ps1`（门①③④⑤⑥ + 完备性）、`scripts/mcp054_regression_battery.ps1`（§7）、
  `scripts/build_local.cmd`（`-Force` 增加删 `mcp_trace` 对象）、`scripts/mcp038_trace_evidence.ps1`、
  `scripts/mcp052_added_tools_evidence.ps1` / `scripts/mcp053_added_tools_evidence.ps1`
  （两处 `Wait-ForEndpoint` 就绪探针缺陷修正 + TASK-053 的两条旧 C# 期望按本批行为更新，改动处均带 TASK-054 注释）。
- **测试**：`tests/test_mcp_server.h`（新增 2 个用例；TASK-053 批量用例补第四计数器恒等式）。
- **证据**：`docs/reports/evidence/task054/{red,green,regression}/`（wire 请求/响应 + results.json +
  evidence.log.txt + 回归日志）。
- **给下一个执行者**：**切换 mono/plain 构建时先删**
  `bin\obj\modules\mcp_server\mcp_trace.windows.editor.x86_64.obj`（`build_local.cmd -Force` 已代劳 plain 一侧），
  否则 `trace_opened.version` 会说错变体、且新 doctest 会红（§5.1）。
- **提交**：本报告 + 上述代码/脚本/契约/测试/证据一条提交，信息引用本任务与 §5.1 的构建缺陷。
- **未 push**（纪律）。
