# REPORT-063 — 第 2 轮 4 条产品缺陷（端点静默失能 / 参数面 / 批量写不同值 / parse 行列）

> **D86 锚点**：实现提交 **`92a260b682`**（`mcp: fix the round-2 product defects (endpoint, node paths, batch updates, parse line)`），
> `git rev-parse --short=9 HEAD` = **`92a260b68`**；被测二进制
> `bin\godot.windows.editor.x86_64.console.exe` 的 `--version` = **`4.8.dev.custom_build.92a260b68`**（**== HEAD**）。
> 证据树 `docs/reports/evidence/task063/`（102 个文件，清单 `SHA256SUMS.tsv`，
> 清单自身 sha256 = `e5f8b2298e19867761ea9544857f5a0d26cffdfa75239917920918cc1e63fec8`，
> 由 `scripts/mcp063_evidence_manifest.py --check` 复核，exit 0）。
> 本报告的绿色门与被测二进制同锚点；报告本身随后作为 docs 提交落盘（不改动二进制对应的工作树内容）。
>
> **D-119 教训**：本文件与全部产物均写**绝对路径**下的仓库内位置，不写 `%TEMP%` 相对路径。

---

## 0. 范围、结论与纪律

**任务**：修第 2 轮 breakout 抓到的 4 条产品缺陷（`BREAKOUT-FINDINGS.md` §3 的 D-7 / D-5+O-2+O-3 / D-6+M-1 / D-10），
证据原文以 `docs/reports/evidence/task060/**` 为准。契约 **175 → 176**（`171 + 5`）。

| 条目 | 严重度 | 结论 | 证据（仓库内） |
|---|---|---|---|
| (a) 游戏端点 bind 失败却静默失能 | major | **已修（根因见 §1）**：ERROR 级日志写明请求端口/失败原因/端点已禁用；状态在进程内可查；失败原因由模块自己诊断；冲突场景明确报错、不伪造可用性 | `evidence/task063/evidence/a0{2,3,5}*`、`logs/game-busy.{out,err}.log`、`evidence/a09_game_tools_list.response.json` |
| (b) `path` / `node_paths` 参数面不一致 | major | **已修（保留参数名）**：两条 `DESCRIPTION_OVERRIDES` + 一条 `ADDED_TOOLS` 描述声明路径基准与单/复数差别；`-32001`/`-32602` 的 `data.suggestion` 指路；契约条数不变（176 中这三条名字未动） | `evidence/b05…b10*`、`gate1-contract-subset.log` |
| (c) 新增 `editor_set_node_property_updates` | major（能力缺口） | **已交付**：`ADDED_TOOLS`，契约 176；逐条读回；`stop_on_error` 两种语义明确；**过同一道 `ValueSlot` 闸门** | `evidence/c01…c18*` |
| (d) `editor_execute_gdscript` parse 错误不带行列 | major（可用性） | **已补行、并如实声明边界**：行可得（引擎错误处理器），**列不可得**（调用点丢弃 `start_column`），实测对照见 §4.5 | `evidence/d01…d05*` |

**纪律执行**：只改了 `modules/mcp_server/**`（**未改任何引擎文件**，见 §7 偏差 1）；未占用/杀/重启 9877（`port_9877_untouched` PASS，
分类 `environment_fact_no_listener_before_or_after`）；只用 9888/9889；未 push；构建全程串行、从 cmd 启动、不抑制输出；
`.ps1` 纯 ASCII；`DECISIONS.md` 在 harness 仓库且对本模块执行者只读，故本任务**未新建/未改动**任何决策日志文件（模块内以本报告与提交信息为决策留痕）。

---

## 1. (a) 端点静默失能：最小复现与根因（先给事实，再给修法）

### 1.1 任务书前提的一处纠正（必须先说）

任务书写「实测 `bind failed on 127.0.0.1:9889 (error=22)` → `error=22`（EINVAL）由什么造成？」。
**`error=22` 不是 EINVAL，也不是任何 socket errno**。该行由 `mcp_server.cpp` 打印引擎的 `Error` 枚举值：

- `core/error/error_list.h:69`：`ERR_ALREADY_IN_USE,` —— 逐项数是 **22**；
  实测 `VariantUtilityFunctions::error_string(22)` 输出 `ERR_ALREADY_IN_USE`（本次修复后的 ERROR 行即打印该名字，见 `logs/game-busy.err.log`）。
- 更关键的是它**连"端口被占"都不能证明**：`SocketServer::_listen`
  （`core/io/socket_server.cpp:47-52`）把 `NetSocket::bind` 的**任何**失败都压成同一个码：

  ```cpp
  Error err = _sock->bind(p_addr);
  if (err != OK) {
      _sock->close();
      return ERR_ALREADY_IN_USE;   // <- 22，真实 Winsock 错误在这里被丢掉
  }
  ```

  真实错误只在 `NetSocketWinSock::bind` 里以 `print_verbose` 打印
  （`drivers/windows/net_socket_winsock.cpp:287-289`），默认详细级别下**不可见**。
  因此「`error=22` = EINVAL」与「`error=22` = 端口被占」都是**过度解读**；这正是本条缺陷的第二半。

### 1.2 最小复现（本任务实测，可重跑）

`scripts/mcp063_product_defects_evidence.ps1` Phase A 用脚本自己起的真实监听者占住 9889，再让游戏进程请求该端口：

| 步骤 | 请求/动作 | 实测结果 | 证据文件（sha256 见清单） |
|---|---|---|---|
| A0 | 脚本起 `TcpListener(127.0.0.1:9889)` | `netstat` 报该端口被 pid 持有 → `a00` PASS | `logs/port-holder-9889.log` |
| A1 | `godot --headless --path <proj> --mcp-port=9889 --mcp-trace=…` | stdout `[MCP] role=game configured_port=9889 source=cmdline listen=true`、`[MCP] bind failed on 127.0.0.1:9889 (error=22)` | `evidence/a02_game-busy.out.log`（618 B） |
| A2 | 同一进程 stderr | **ERROR 级**，写明请求端口 / 原因 / 端点已禁用 / 处置建议 | `evidence/a03_game-busy.err.log`（612 B） |
| A3 | 进程是否退出 | **仍在运行**（绑定失败不拖垮引擎，符合要求"进程不会退出"） | `a03_the_process_is_still_alive` PASS |
| A4 | 该端口是否有响应 | 无响应（`curl` 非 0/0 字节）——端点确实禁用，而不是"慢" | `a04_the_disabled_endpoint_serves_nothing` PASS |
| A5 | 机器可读记录 | 追踪文件出现 `{"event":"endpoint_disabled","pid":…,"role":"game","requested_port":9889,"mcp_port":0,"error":22,"reason":"…"}` | `evidence/a05_game-busy.trace.jsonl`（587 B） |

修复后 stderr 原文（`evidence/a03_game-busy.err.log`，612 B，sha256 `60852d7f3ce975b543091dfe2fe16b970ada7cde0166bb4f7e38124c5fde7ef1`；
下段按 ASCII 转述关键字段，真实文件里的引擎路径段为 Windows 反斜杠形式）：

```
ERROR: [MCP] ENDPOINT DISABLED: the requested port 9889 could not be bound on 127.0.0.1
(ERR_ALREADY_IN_USE = 22); reason: another process is already listening on 127.0.0.1:9889
(a fresh bind of the same address failed too; the engine reports every bind failure as
ERR_ALREADY_IN_USE = 22, core/io/socket_server.cpp:47-52, which does not name the cause);
this process serves NO MCP endpoint (get_port()==0). Pass --mcp-port=<a free port> (or change
the godot_mcp/port setting) and restart, and make sure no earlier game process still holds 9889
   at: MCPServer::_start_service (modules\mcp_server\mcp_server.cpp:…)
```

### 1.3 根因判定（"什么条件必然导致失败"）

| 候选根因 | 判定 | 依据 |
|---|---|---|
| `--mcp-port` 端口解析错（把 9889 解析成非法值） | **排除** | `MCPPort::parse`（`mcp_server.cpp:75-107`）只接受 0..65535 的整数，实测日志 `configured_port=9889 source=cmdline listen=true`，且**同一二进制在端口空闲时真的绑上**（A7/A8/A9） |
| 游戏进程与编辑器抢同一端口 | **排除** | 编辑器默认 9877（`DEFAULT_EDITOR_PORT`），E-10 注入的是 `editor_play_scene` 选定的空闲端口；实测 9888/9889 分属两进程，9889 被占时 9888 不受影响 |
| **端口已被另一进程持有**（EINVAL 之外的真实原因） | **成立** | `SocketServer::_listen` 在 bind 失败时关闭套接字并返回 22；模块用**同一 bind 地址**再探一次仍失败 ⇒ 有进程在监听（`evidence/a03` 的 `reason:` 字段）；且 TASK-060 A-5 已实测"同一追踪文件里**前一代游戏进程仍在正常应答** `tools/list`"，即典型的"起了第二个游戏而没停第一个" |
| 引擎不允许 Windows `SO_REUSEADDR` 复用 | **成立但不构成缺陷** | `drivers/windows/net_socket_winsock.cpp:549-552` 显式拒绝（"would also enable reuse port, very bad on TCP"）。这是**正确**行为：正因如此，端口被占时不会静默"偷绑"，而是失败。已占端口**必然**失败，条件即"有进程在 127.0.0.1:9889 上 LISTEN" |

**结论**：E-10 注入路径本身没有错（`editor_play_scene` 对调用方指定的端口先做 `port_is_bindable` 探测，被占即拒绝；
不指定时自动挑一个已验证空闲的端口），实测 D-7 的进程是**被脚本/调用方直接以 `--mcp-port=9889` 启动**、而此时 9889 已被**前一代游戏进程**持有。
真正可修的产品缺陷是**失能不可见 + 原因不可诊断 + 状态不可查**，以及"最后一个能绑上的机会没把握住"的编排问题。

### 1.4 修了什么（逐条对应任务书要求 2–3）

| 要求 | 实现 | 位置 |
|---|---|---|
| ② 启动必须 **ERROR** 级日志，写明「请求端口 / 失败原因 / 端点已禁用」 | `WARN_PRINT` → **`ERR_PRINT`**，一行含 `ENDPOINT DISABLED` + `port N` + `%s = %d` + `reason:` + `get_port()==0` + 处置建议 | `mcp_server.cpp:714-726`（`_start_service` 绑定失败分支；原因诊断在 `:703-713`） |
| ② 状态**记录下来**、进程不退出 | 新增 `endpoint_state / requested_port / endpoint_state_reason`，三态枚举（`listening` / `not_requested` / `bind_failed`），进程内可查：`get_endpoint_state()`、`is_endpoint_bind_failed()`、`get_requested_port()`、`get_endpoint_state_reason()`、`debug_endpoint_state()`；并绑定到 GDScript（`get_endpoint_state` 等 4 个方法），**不进 `tools/list`、不进 `GET /mcp`**（不移动既有契约）；失败后**不**被 `_shutdown()` 清成"未请求" | `mcp_server.h:121-135`（状态字段）、`:196-222`（访问器）、`mcp_server.cpp:321-325`（`_shutdown` 只重置真正 listening 过的状态） |
| ② 失败原因**可诊断**（不再只说一个码） | 绑定失败后立即用模块自己的 `MCPTools::port_is_bindable` 以**同一地址**再探一次：仍失败 ⇒ "another process is already listening …"；反而成功 ⇒ "the engine answered ERR_ALREADY_IN_USE but the same address can be bound right now, so this was not a lasting occupancy"（两种说法都不冒充确定性） | `mcp_server.cpp:610-631` |
| ② 机器可读（无端点时的唯一通道） | 追踪打开时再写一条 **event** 行 `endpoint_disabled`（含 `requested_port`/`mcp_port:0`/`error`/`reason`），**不消耗 seq**、不改 O-12 的 generation marker（marker 在 bind 之前写，且有 doctest pin） | `mcp_trace.{h,cpp}`：`build_endpoint_disabled_fields` |
| ③ 不得静默继续、不得伪造可用性 | `get_port()` 仍为 0、`is_listening()` 仍 false、HTTP 端点确实不存在（A4 实测无响应）；不自动换端口、不假装 ready | 同上 |
| ③ 修根因（若可修） | **E-10 已正确**：见 §1.3。本轮把"最后一个能防住的机会"补上：对**占用者**给出可执行建议（换 `--mcp-port` / 停掉前一个游戏），并把"请求的端口"与"真的在服务的端口"分开记录。**没有**做的事：不偷偷改端口、不改引擎的 `socket_server.cpp` 错误压缩（那会改变全引擎行为，见 §7 偏差 1） | — |

**为什么不去改 `core/io/socket_server.cpp`（把真实 errno 透出来）**：那是引擎热路径上的全局语义改动
（所有 `TCPServer` 使用者都会看到新的返回码），且需要动 `Error` 枚举/调用方；本任务允许"必要的引擎文件"，
但**必要性不成立**——模块已能用自己的一次探测把"占用"与"非占用"分开，并且这是模块唯一需要的那一比特。
按"决策与大局观"纪律，把这条记为**上报决策者的候选改动**而非偷偷实施（§7 偏差 1）。

### 1.5 「修复后同一场景真的绑上」的证据

| 检查 | 实测 | 文件 |
|---|---|---|
| A7 空闲端口下游戏端点就绪 | `GET /mcp` 200 且 `frame_count` 可读 | `gate 2` 输出 `a07_free_game_binds` PASS |
| A8 启动日志 | 含 `[MCP] INFO: MCP server is ready on 127.0.0.1:9889 as the game process`，且**无** bind failed | `evidence/a08_game-free.out.log`（591 B） |
| A9 `tools/list` 条数 | **72**（= 176 条契约 − 104 条 editor-scope） | `evidence/a09_game_tools_list.response.json`（32101 B，sha256 `c37335a1db9c26b610608be1022dc53c16ed0e26fd9d1df51337aca55e479c84`） |
| 编辑器端点条数 | **153** | `gate1-contract-subset.log`、`evidence/b00_tools_list.response.json`（61514 B，sha256 `ce229ba276865386d5cfad87ad42209e5ffa8e6347c31a74e3692c93bccb482a`） |

---

## 2. (b) 参数面：描述声明基准 + 拒绝消息指路（参数名不动）

### 2.1 设计（为什么这样改）

- 参数名**保留**（`path` 单数、`node_paths` 复数）：改名会破坏 TASK-060 已入库的 300+ 次调用证据与既有调用方；
  任务书明确要求保留。
- 移动的是**文本**，且只用 append 模式，原中文句首逐字保留（生成器的 append-only 守卫会逐字符检查）。
- 三处描述共用**同一个字面量**，机械上不可能漂移：
  `scripts/gen_renamed_contract.py` 的 `NODE_PATH_RULE_SENTENCE`（生成器侧）与
  `tools/tool_helpers.h/.cpp` 的 `MCPTools::NODE_PATH_RULE_SENTENCE`（注册侧）。两侧由**门①**（实况 `tools/list` 逐字等于契约）钉在一起。
- 拒绝消息新增 `MCPTools::node_path_guidance(param, plural)`：明说**哪个参数名**、**什么形状**、**以被编辑场景根为基准**、
  `/root/...` 不接受、裸名只指直接子节点，并保留原句 "Use editor_get_scene_tree to list the nodes of the edited scene"。
- `-32602 Unknown parameter '…'` 一侧：注册表在既有"接受参数列表"后追加**节点路径别名提示**，
  提示表 `NODE_PATH_ALIAS_TOOLS` 是**显式工具表**（4 条），不是名字启发式 —— 因此 `editor_open_scene` 的 `path`
  与所有 `project_*` 的 `res://` 路径**不会**收到"场景根相对"的错误建议（有负向对照，见 §2.3 b10 与 §5 单测）。

### 2.2 契约变化（逐字）

| 工具 | 变化 | mode |
|---|---|---|
| `editor_set_node_property`（map `old_name=update_property`） | `修改属性` + 一空格 + `NODE_PATH_RULE_SENTENCE`（619 字符） | `DESCRIPTION_OVERRIDES`，**append** |
| `editor_get_node_properties`（map `old_name=get_node_properties`） | `获取节点属性` + 一空格 + 同一条 `NODE_PATH_RULE_SENTENCE` | 同上（同一字面量） |
| `editor_set_node_script_batch`（ADDED 条目） | 原文后追加**复数版**同规则句 | `ADDED_TOOLS` |

`inputSchema` 一字未动；契约条数不变（本条不新增工具；176 的增量来自 (c)）。
生成器版本 `1.18.0 → 1.19.0`（`source.generator_version` / `_meta.generator_version` / `GENERATOR_VERSION` 三方一致，`--generator-version` exit 0）。

### 2.3 线上证据（9888，逐条）

| 检查 | 请求 | 实测 | 文件 |
|---|---|---|---|
| b01 ×3 | `tools/list` | 三条 `description` 与契约**逐字相同**，且都含 `relative to the edited scene root` | `evidence/b00_tools_list.response.json` |
| b02 | 契约 `required` | 仍是 `path` / `path` / `node_paths`——**参数名没动** | 同上 |
| **b05**（本轮实测的 D-5 场景） | `editor_set_node_property{path:"/root/Main/Ball",…}` | `-32001`，`data.suggestion` = `Parameter 'path' takes ONE node path, resolved relative to the edited scene root (…'node_paths'…): 'Bricks/Car' 与 './Bricks/Car'… An absolute scene-tree path ('/root/Main/Bricks/Car') is not accepted…` | `evidence/b05_absolute_path.response.json`（673 B） |
| **b06** 正确写法成功 | `{path:"Main/Ball", property:"position", value:{x:576,y:320}}` | `code 0`，`new_value = {"x":576.0,"y":320.0}` | `evidence/b06_scene_relative_path.response.json`（214 B） |
| b07 读回 | `editor_get_node_properties{path:"Main/Ball", properties:["position"]}` | `{"node_path":"Ball","properties":{"position":{"x":576.0,"y":320.0}},"type":"Node2D"}` | `evidence/b07_read_back.response.json`（173 B） |
| b08 单数工具被喂 `node_path` | `editor_set_node_property{node_path:…}` | `-32602` message 逐字 `Unknown parameter 'node_path' for tool 'editor_set_node_property'`；suggestion 追加 `'node_path' is not a parameter of this tool: its node path is spelled 'path' (one node path), and every node path of the editor node tools is resolved relative to the edited scene root - an absolute scene-tree path such as '/root/Main/Car' is not accepted` | `evidence/b08_…response.json`（478 B） |
| b09 复数工具被喂 `path` | `editor_set_node_script_batch{path:…}` | `-32602`，suggestion 指明 `its node path is spelled 'node_paths' (an array of node paths)` | `evidence/b09_…response.json`（508 B） |
| b10 复数 + 绝对路径 | `{node_paths:["/root/Main/Ball"],…}` | `-32001`，suggestion 为**复数版**同一规则（`is an array of node paths` + `/root/Main/Bricks/Car` 不接受） | `evidence/b10_…response.json`（992 B） |

> 注：`/root/Main/Car` 的**字面例子**在描述/提示里写作 `/root/Main/**Bricks**/Car`（即被拒绝的绝对路径示例），
> 本轮证据脚本第一次跑时把断言写成了子串 `/root/Main/Car`（不含 `Bricks/`）→ 红；已按原文修正（见 `red-phase/README.md`）。

---

## 3. (c) 新增 `editor_set_node_property_updates`（契约 175 → 176）

### 3.1 契约条目（`ADDED_TOOLS`，逐字）

- 名 `editor_set_node_property_updates`；`channel=editor`、`verb=set`、`scope=editor`、`mutating=true`（`docs/tool-groups-added.json`）。
- `description`（英文，逐字，任务书指定）：
  `Set a different value on each of many nodes in the edited scene in one call, and answer per entry whether the value landed.`
- `inputSchema`：`updates`（array，required，`minItems:1`，元素 `{path:string, property:string, value:any}`，三者 required）、`stop_on_error`（boolean，`default:false`）。
  `minItems` 在注册侧用 **INT** 字面量构造（`_updates_schema()`），不用 `JSON::parse`——解析会把 JSON 数字变成 FLOAT，
  线上成 `1.0` 而契约是 `1`（`project_build_csharp` 的 `minimum/maximum` 已记录同一坑）。单测钉了 Variant 类型。
- 契约 `_meta`：`count=176`、`added_count=5`、`added_tools` 末位即该名、`generator_version=1.19.0`。
- 契约 sha256 `d4e53b43840b6537af9dfbefdc77e7fb4ed6202ee23f3016503a7a53953e7ecd`；
  `tool-groups-added.json` sha256 `67cd57d0214f0485d92e7894dd112991d05d2e6d6842031cd99f238153a3f994`。

### 3.2 行为（设计要点）

- **逐条读回**：每条成功项给 `{index,path,property,node_path,old_value,new_value,changed,ignored,stored_as_requested,status:"ok"}`；
  `changed` 是 `old_value != new_value` 的**读回比较**，不是对请求的转述。
- **`stop_on_error` 语义（两种都明说）**：
  - `false`（默认，也是契约描述承诺的形态 "answer per entry whether the value landed"）：**逐条**给结果，
    顶层 `status` 为 `ok` / `partial`、`message` 明说 "N of M update(s) landed"；已落地的**保留**在场景里。
  - `true`：**首错即停 + 已落地的回滚**（与模块其余批处理同口径），响应用 **`-32602`/`-32001` 等错误码**而不是一个"带错误的成功"，
    并在 `error.data` 里给 `{results, applied, rolled_back, rollback_failures, updated, count, stop_on_error}`；
    未尝试的条目**显式**标 `status:"skipped"`（不让调用方靠数数发现少了）。
    选回滚而非"明示不可回滚"的理由：本模块所有批处理（`editor_add_nodes_batch`、`editor_set_node_property_batch`、
    `editor_set_node_script_batch`）都是全或无，`true` 分支保持同一承诺；回滚值在写**之前**用
    `read_node_property_path` 读原始引擎值（不是序列化值，否则 `Vector2` 会被引擎拒绝），按**逆序**回写。
- **不是后门**：每次写都走 `MCPTools::write_node_property`——模块唯一的属性写路径，TASK-014 D-1 的属性存在性拒绝、
  TASK-018 的声明类型强制、TASK-022/023 的 `ValueSlot` 收窄闸门都在其中；本文件**没有**新增任何收窄点（门⑥ exit 0 可证）。
- **形状先于守卫**：元素的语法检查（非对象元素 / 未知成员 / 缺 `path|property|value` / 空串）经
  `validate_node_property_updates()` 放在 `require_editor_ui` **之前**，所以畸形请求在**任何**进程都是 `-32602`
  而不是被 `-32000` 遮住（PLAYBOOK §6.2）；导出入口自身再校验一次，直接调用者也无法绕过。

### 3.3 线上证据（9888，一次调用 4 个节点 4 个不同值）

`c01_four_values_one_call`（`evidence/c01_four_values_one_call.response.json`，1759 B）：

```json
{"status":"partial","message":"3 of 4 update(s) landed; 1 entry/entries were refused …",
 "count":4,"updated":3,"failed":1,"stop_on_error":false,"rolled_back":false,
 "results":[
   {"index":0,"path":"Main/UpA","property":"position","old_value":{"x":0.0,"y":0.0},"new_value":{"x":1.0,"y":1.0},"changed":true,"ignored":{},"stored_as_requested":true,"status":"ok"},
   {"index":1,"path":"Main/UpB",…"new_value":{"x":20.0,"y":2.0},"changed":true,…,"status":"ok"},
   {"index":2,"path":"Main/UpC",…"new_value":{"x":300.0,"y":3.0},"changed":true,…,"status":"ok"},
   {"index":3,"path":"Main/UpD","property":"position","status":"error","changed":false,
    "error":{"code":-32602,"message":"…'value'…"}}]}
```

- 4 个不同值一次写完：`(1,1)` / `(20,2)` / `(300,3)` + 一个**越界值** `1e20` → 该条 `-32602`，其余成功。
- **独立读回**（换一个工具）：`c02`（UpA=`(1,1)`）、`c03`（UpD 仍 `(0,0)`，越界那条**没动**它）。
- **stop_on_error=true**（`evidence/c05_stop_on_error_true.response.json`）：把 UpA 预置为 `(9,9)` 后，
  第 0 条写 `(100,100)` 落地、第 1 条越界失败 → 返回 `-32602`、`message` 以 `updates[1]` 开头、
  `data.rolled_back=true`、`data.updated=1`、`data.applied=[{index:0,status:"reverted"}]`、`results[2].status="skipped"`；
  `c06` 读回 UpA=`(9,9)` —— **回滚真的发生了**。
- **口径对比**：`c07` 用类型作用域老工具 `editor_set_node_property_batch{node_type:"Node2D",property:"rotation",value:0.5}`
  → `updated>=5`、一个值写遍所有 Node2D（该工具口径未动）。
- **同一道闸门（反证后门）**：`c08` 单点写 `position=1e20` → `-32602`；`c09` 新工具同值同属性 → 该条 `-32602`；
  `c10`/`c11` 未知属性 → 两边都是 `-32001`。
- **参数面（新工具自身）**：`c12` 缺 `updates`、`c13` 空数组、`c14` 元素非对象、`c15` 元素含未知成员、
  `c16` 元素缺 `path`、`c17` `stop_on_error` 类型错 → 全部 `-32602` 且消息/建议指名到 `updates[i]`；
  `c18` 未知节点 → 该条 `-32001` + 指向 `path` 的引导语。
- **scope 只看 9889 不存在**：`e00` 9889 的 72 条里**没有**该工具；`e01` 直接在 9889 调它 → `-32601`
  （`Method not found: editor_set_node_property_updates`）。全部 18 条 `c*` + 2 条 `e*` PASS。

---

## 4. (d) `editor_execute_gdscript` 的 parse 错误：行可得、列不可得

### 4.1 先查引擎源码（任务书要求的第一步）

| 问题 | 引擎事实（file:line） | 结论 |
|---|---|---|
| `GDScript` 是否暴露 parser 的 error_line/column？ | `GDScript::reload()`（`modules/gdscript/gdscript.cpp:741-913`）把 `GDScriptParser parser;` 作为**局部变量**，只返回 `Error`（`ERR_PARSE_ERROR` :830/:854，`ERR_COMPILATION_FAILED` :870）；`GDScript`/`Script`/`ScriptLanguage` 上**没有**任何公开的错误列表/行号访问器 | **拿不到** |
| 错误列表本身有哪些字段？ | `GDScriptParser::ParserError{message, start_line, start_column, end_line, end_column}`（`modules/gdscript/gdscript_parser.h:273-288`） | 引擎内部**有**行**和**列 |
| 有没有别的公开通道？ | `GDScript::reload()` 用 `_err_print_error("GDScript::reload", <path>, parser.get_errors().front()->get().start_line, "Parse Error: " + <message>, false, ERR_HANDLER_SCRIPT)`（`gdscript.cpp:828`；analyzer 分支 :850 逐个错误；compiler 分支 :864） | **行**进入了引擎错误处理器参数；**列被调用点丢弃** |
| 错误处理器是公开 API 吗？ | `core/error/error_macros.h:63-77` `add_error_handler` / `remove_error_handler`；`_err_print_error` 先做默认打印再由 `error_macros.cpp:133-141` 通知处理器 | **是**，且注册处理器是**纯增量**（日志一字不少） |
| 直接 include `modules/gdscript/**` 拿 `GDScriptParserRef`/`GDScriptCache`？ | 可行但会引入**模块间依赖**（本模块刻意用 `ClassDB::instantiate("GDScript")` 避开它，见 `editor_script_write.cpp:119-122` 的注释） | 放弃，记入边界 |

### 4.2 实现

- `tools/tool_helpers.{h,cpp}`：`GDScriptReloadReport` + `reload_gdscript_capturing(Script *, int body_start_line)`
  —— 在**一次** `Script::reload()` 前后挂/摘一个临时 `ErrorHandlerList`，只接受
  `function == "GDScript::reload"` 且 `type == ERR_HANDLER_SCRIPT` 的诊断（reload 期间还会经过
  `GDScriptCache`/`ResourceLoader`/linter，不做过滤就会把无关告警当 parse 错误），收集**有界**的（12 条）诊断文本与首条行号。
- `build_execute_gdscript_source(..., int *r_body_start_line = nullptr)`：通过**数头部换行**得到"调用方第一行在生成源码中的行号"，
  因此被提升到类级的 `func`（每行 +1）自动计入，映射不会与源码漂移。
- 行映射：`caller_line = generated_line - body_start_line + 1`；落在头部则**不**归罪给第 1 行，而是如实说明"引擎报的是工具自身 wrapper 的行"。
- `gdscript_reload_failure_text()`：编辑器与游戏两个执行器**共用**同一文本函数（游戏侧 `running_game_execute_gdscript` 有同一缺口，一并修）。
- `error.data` 追加 `parse_error{line, generated_line, in_caller_code, message, messages[]}` 与
  `parse_error_column`（**恒为 null**，让"没有列"这件事是**被声明**的，而不是调用方无从判断）。
  `-32602` 的 `data.suggestion` 仍由注册表补（既有行为不变）。

### 4.3 实测对照：能定位到什么程度

| 情形 | 请求 | 返回（真实） | 文件 |
|---|---|---|---|
| 第 1 行有非法 token | `{code:"var x = )\nreturn x"}` | `-32602`；message `Parameter 'code' does not compile at line 1 of 'code': Parse Error: Closing ")" doesn't have an opening counterpart.`；`data.parse_error.line=1`、`in_caller_code=true`、`message` 以 `Parse Error` 开头、`messages` 非空；`data.parse_error_column = null` | `evidence/d01_parse_error_line_one.response.json` |
| **第 2 行**有非法 token | `{code:"var x = 1\nvar y = )\nreturn x"}` | message 含 `line 2 of 'code'`；`data.parse_error.line=2` | `evidence/d02_parse_error_line_two.response.json` |
| 有效体仍可跑 | `{code:"return 41 + 1"}` | `code 0`，`result=42`、`result_type="int"` | `evidence/d03_valid_body_runs.response.json` |
| 缺参仍是 `-32602` | `{}` | `-32602` | `evidence/d04_missing_code.response.json` |
| **边界对照**：文件级校验器不受影响 | `project_validate_script{path:"res://scripts/syntax_error.gd"}` | `code 0` + payload `valid:false`、`error_text` 含 `ERR_PARSE_ERROR`（它的口径本来就不是执行器的 `-32602`，本轮未动） | `evidence/d05_file_syntax_error_unchanged.response.json` |

**边界的准确表述**：本模块能给出**行**（并且能映射回 `code` 自己的行序），**不能**给出**列**——
`ParserError.start_column` 存在，但 `GDScript::reload` 调 `_err_print_error` 时只传 `start_line`，
任何错误处理器都拿不到列；除非改为直接依赖 `modules/gdscript/**`（本模块刻意不做，且那会让 `mcp_server` 在
`module_gdscript_enabled=no` 的构建里无法编译）。因此 `data.parse_error_column` **恒为 `null` 且键存在**。

---

## 5. 五道门 + 门⑥（真实输出与退出码）

| 门 | 命令 | 结果 | 退出码 | 证据 |
|---|---|---|---|---|
| ① 契约子集逐字 | `powershell -NoProfile -ExecutionPolicy Bypass -File modules/mcp_server/scripts/check_contract_subset.ps1` | 3/3 PASS；`editor port=9888 tools=153`、`game port=9889 tools=72`、`group=project_read_template tools=6 contract=176`、`implemented_union=153 / 72`、6 条逐字 `name=True description=True inputSchema=True`、`guard_user_port_9877` PASS | **0** | `evidence/task063/gate1-contract-subset.log` |
| ② 三类证据 + 跨工具活证据链 | `powershell … -File modules/mcp_server/scripts/mcp063_product_defects_evidence.ps1` | **53/53 PASS**（成功/缺参/底层失败三类齐备：`b06/b07` 成功、`c12-c17` 缺参与类型、`b05/b10` 底层 `-32001`、`c08-c11` 闸门反证；活证据链见 §2.3/§3.3/§4.3） | **0** | `evidence/task063/run.log`、`mcp063-checks.json`、102 文件 sha256 清单 |
| ③ 模块 doctest | `bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"` | `342 cases / 342 passed / 0 failed`，`23924 assertions / 23924 passed`（其中本轮 **7 条新用例 / 192 断言**，红相位见 `red-phase/`）；**在最终锚点二进制 `92a260b68` 上重跑过** | **0** | `evidence/task063/gate3-module-doctest.log` |
| ④ 全引擎回归 | `… --headless --test` | `1768 cases / 1768 passed / 0 failed / 3 skipped`，`448171 assertions / 448171 passed`（本轮新增 7 条用例，故 passed 只增不减：1768 − 7 = 1761 即改动前用例数） | **0** | `evidence/task063/gate4-full-engine-test.log` |
| ⑤ 收口 | `powershell … -File modules/mcp_server/scripts/accept_m1.ps1` **连跑两次** | 两次均 **22/22 cases passed**；`implemented tools = 153 (editor) / 72 (game); contract = 176`；两次 PASS 清单 `diff` **完全一致**（22 行） | **0 / 0** | `evidence/task063/gate5-accept_m1_run{1,2}.log`、`…-pass-list.txt`（两份 diff 空） |
| ⑥ 收窄点 | `python modules/mcp_server/scripts/check_narrowing_points.py`；`… --coverage`；`powershell … -File modules/mcp_server/scripts/mcp031_gate6_coverage_probes.ps1` | 三段式：主检查 **exit 0**（`PASS: every narrowing point … annotated and pinned`）、`--coverage` **exit 0**（17 个声明拼写 + 声明不覆盖项）、探针 **`101/101 checks passed`**（每个声明拼写一条"插入→exit 1"探针）；**新文件 `editor_node_property_updates.cpp` 不新增任何收窄点**，`--list` 中该文件 0 条 | **0 / 0 / 0** | `evidence/task063/gate6-{narrowing,coverage,coverage-probes}.log` |

### 5.1 契约机器检查（任务书要求 exit 0）

| 命令 | 结果 | 退出码 |
|---|---|---|
| `python modules/mcp_server/docs/scripts/check_tool_groups.py --check-completeness` | `171 + 5 = 66 + 105 + 5: PASS`；`every one of the 176 contract names is in exactly one of the four buckets: PASS`；末行 `TOOL-GROUPS-COMPLETENESS CHECK PASS` | **0** |
| `python modules/mcp_server/docs/scripts/check_tool_groups.py --added` | 5 组；`manifest = contract _meta.added_tools, both directions: PASS`；`every added tool appears exactly once`、`every name exists in the 176 entry contract`、`channel and verb derived from every tool name agree with the group declaration`、`sizes <= 10` 全 PASS；`BYTES 7739`、`SHA256 67cd57d0…`；末行 `TOOL-GROUPS-ADDED CHECK PASS` | **0** |
| `python modules/mcp_server/docs/scripts/check_tool_groups.py --generator-version` | `GENERATOR_VERSION == _meta.generator_version == source.generator_version: PASS (1.19.0)`；末行 `GENERATOR-VERSION CHECK PASS (1.19.0)` | **0** |
| `python modules/mcp_server/scripts/gen_renamed_contract.py` | `output tools = 176`、`added = 5`、`overrides = 29`、`self-checks = OK (lint 176/176, unique 176/176, disposition enum OK)`；输出 sha `d4e53b43…` | **0** |
| `python modules/mcp_server/scripts/mcp063_evidence_manifest.py --check` | `SHA256 OK: 102 file(s)` | **0** |

### 5.2 构建（串行、cmd 启动、未抑制输出）

| # | 命令 | 结果 |
|---|---|---|
| 1 | `modules\mcp_server\scripts\build_local.cmd -Force` | exit 2 —— **红相位**：`editor_node_property_updates.cpp(254/262): error C2664`（`Node *` → `Object *` 需完整类型）。已修（`.cpp` include `scene/main/node.h`），原始日志在 `evidence/task063/build-local.log`（第 2886-2893 行） |
| 2 | `… build_local.cmd -Force` | exit 0（编译含新用例的 `tests/test_mcp_server.cpp`） |
| 3 | `… build_local.cmd -Force` | exit 0（元素校验前移 + 用例修正） |
| 4 | `… build_local.cmd`（提交 `92a260b682` 之后） | exit 0，`--version` = `4.8.dev.custom_build.92a260b68` **== `git rev-parse --short=9 HEAD`** ✅ |

> 全程只有一个 scons 实例在跑（每条命令串行等待结束再下一条）；9877 从未被本任务启动/停止/重启。

---

## 6. 回归脚本逐条归因

**方法**：先对任务书点名的全部脚本做**静态筛查**（是否含 `175`/`152` 这类会被合法 175→176 移动的字面量、
是否含本轮被改写的三条描述文本），再对**能跑且与本轮改动同锚点**的脚本**实跑**。
筛查结果：56 个脚本里只有 **8 个**含这类字面量，其余**不含**任何本轮被移动的字面量。

### 6.1 实跑（本会话，同锚点）

| 脚本 | 结果 | 归因 |
|---|---|---|
| `mcp042_port_guard_probes.ps1` | **21 checks, 0 failed**，exit 0 | 与 (a) 直接相关；它同时 grep `accept_m1.ps1` 的分类关键字，本轮未动 accept_m1，绿 |
| `mcp043_group_lookup.py` | exit 0（`rows=5`） | 组清单查找；新增组后可解析，未断言旧总数 |
| `mcp043_registration_literals.py` | exit 0（`failures = 0`） | 5 条注册字面量与契约比较；本轮改写的三条不在其 5 条集合内 |
| `mcp043_survey.py` | exit 0（`5 samples`） | 采样器，无断言 |
| 门①③④⑤⑥ 与 `--check-completeness/--added/--generator-version` | 全绿（§5） | 已覆盖 `accept_m1` 驱动的 `mcp041_gates` / `mcp042_gates` / `mcp043_gates` / `mcp050…` 各 `*_battery` 的**核心断言**（实况 `tools/list` 与清单并集相等、逐字契约、scope 拆分、进程重启、端口占用、guard 9877） |

### 6.2 静态归因：**预期会被合法改动打红**（未重跑，原因在后）

| 脚本:行 | 钉住的字面量 | 本轮为何移动 | 影响面 |
|---|---|---|---|
| `mcp052_added_tools_evidence.ps1:315` | `($editorExpectedCount -eq 152) -and ($gameExpectedCount -eq 72)` | editor 视图 152 → **153**（新增一个 editor-scope 工具） | 1 条 check 会 FAIL；同脚本其余断言（契约条目逐字、added 两工具）不受影响 |
| `mcp053_added_tools_evidence.ps1:325` | `$contractNames.Count -eq 175` | 契约 175 → **176** | 1 条 |
| `mcp053_added_tools_evidence.ps1:362` | `($editorExpectedCount -eq 152) -and ($gameExpectedCount -eq 72)` | 同上 | 1 条 |
| `mcp054_forensics_and_csharp_evidence.ps1:288` | `$contractNames.Count -eq 175` | 同上 | 1 条（`:587` 的 `"tools":175` 是喂给分析器的**合成追踪行**，不是断言，不受影响） |
| `mcp053_contract_diff.py` | `EXPECTED_BEFORE_COUNT=173 / EXPECTED_AFTER_COUNT=175` | 该脚本是 TASK-053 173→175 的**一次性对照**，需要那一对 `before/after` 契约文件 | 非本树可重跑 |
| `mcp059_contract_pre_post.py:100` | `len(b_tools) == len(a_tools) == 175` | TASK-059 的 pre/post 对照（`--rev <PRE_BATCH_REV>`） | 非本树可重跑（需 checkout 旧 revision 的契约） |
| `mcp055_pre_post_compare.py:15` | 仅**注释**中的 "175 tools" | — | **无断言**，不受影响 |
| `mcp053_regression_battery.ps1:7`、`mcp059_section_switch_evidence.ps1:59/310/311` | 仅**注释** | — | **无断言**，不受影响（`mcp059_section_switch_evidence.ps1` 已被 TASK-059 D-8 改成"派生 + 不钉总数"：`p3_live_tools_list_is_deterministic`、`p3_live_tools_are_a_subset_of_the_contract`，预期绿） |

**为什么没有重跑这四个**（如实说明，不冒充已验）：

1. 四个脚本都属于**需要 mono 引擎**的那一类（各自在 `foreach ($pair in @(@('plain',…), @('mono', …)))` 里同时跑 plain 与 mono，
   `mcp052:263` / `mcp053:304` / `mcp054:273`）。本会话**没有**构建 mono 二进制：`bin\godot.windows.editor.x86_64.mono.console.exe`
   仍是 **2026-09-25 04:43**（锚点 `cd7224274a`，**不是** HEAD `92a260b68`）。用旧 mono 二进制跑出的结论**不能**作为本轮证据
   （PLAYBOOK §3 步 0 的同锚点要求），而 mono 全量构建是 `mcp057_build_mono.cmd` 的独立长任务，不在本任务预算内。
2. 两个 `*_contract_diff.py` / `*_pre_post.py` 是**一次性的 pre/post 对照**，需要它自己那一批的 `before` 契约文件
   （`git show <start>:…/tools_list.renamed.json`）；在 176 条的当前树上它们按定义不可能 green。按"证据不可核验就不声称"的原则，
   列为**不可重跑**而不是"回归失败"。
3. 其余被点名脚本（`mcp010/019/027/041/043…/050/051/056/057/061`）**不含**本轮移动的任何字面量（§6 开头的静态筛查）；
   它们需要 9888/9889 与数分钟到十几分钟各自的进程编排，本会话的等价覆盖由门①⑤（`accept_m1` ×2、`check_contract_subset`）
   与门④（全引擎 1768 用例）承担。

**建议给决策者的最小修法（D-8 先例，TASK-059 已因同类原因把"钉版本号"改成"三方可派生"）**：
把上表四条的**字面量断言**换成**派生断言**——`contract_is_N_entries` 改为
`$contractNames.Count -eq (171 + $addedNames.Count)`；`endpoint_expectations_derived` 改为
`($editorExpectedCount -eq $liveEditorCount) -and ($gameExpectedCount -eq $liveGameCount)`（各脚本里都能拿到
自己刚取回的实况 `tools/list`，那才是真正要断言的对象），并保留打印具体数字。本任务**没有**替它们改：
在没有 HEAD mono 二进制的情况下改完无法验证，按纪律宁可如实标注，也不留下未验证的修改（见 §7 偏差 2）。

---

## 7. 偏差与边界（如实列出，不掩改）

1. **没有修改任何引擎文件**（含看起来最"对症"的 `core/io/socket_server.cpp:47-52`）。理由见 §1.4 末段：
   把真实 errno 透出来会改变**全引擎** `TCPServer` 使用者的返回码语义，而模块用一次自探测就拿到了所需的那一比特；
   按"不要为了省事扩大爆炸半径"的原则，本条**上报决策者**：
   *候选改动*：`SocketServer::_listen` 在 bind 失败时把 `NetSocket` 的底层错误保留下来（例如新增
   `Error SocketServer::get_last_bind_error()` 或让 `bind` 的原错误穿透），代价是引擎 API 扩展 + 所有 `TCPServer` 调用方语义复核；
   *回滚点*：本模块对它的依赖只有"诊断文本更精确"一项，撤回该候选不影响本任务的任何断言。
2. **四个其他任务的证据脚本未修**（§6.2 末）：原因是没有 HEAD 锚点的 mono 二进制，改完无法验证。**这是本轮实测覆盖的缺口**，
   不是"已回归"。建议决策者安排一次 mono 构建后由那四个脚本的 owner 按 §6.2 的最小修法收口。
3. **`mcp053_added_tools_evidence.ps1` 的两条 check 会在下次有人跑它时红**——本报告已在 §6.2 逐条点名，供归因。
4. **红相位保存纪律的部分偏离**：见 `red-phase/README.md`——两次 doctest 红相位的输出是会话内逐字转述，
   未在当次落盘（两个**有文件**的红相位是完整的）。已按 PLAYBOOK「勘误要显式」记录而非删除。
5. **决策日志**：`DECISIONS.md` 在 harness 仓库且对本模块执行者只读（PLAYBOOK §0），本 fork 内**不得**新建竞争性日志。
   本轮决策留痕 = 本报告 + 提交信息 `92a260b682` + `docs/tool-groups-added.json` 的 `notes` + 生成器/代码内的长注释。
6. **`git` 工作树**：本报告与证据树随后作为 docs 提交；未跟踪残留仍是既有的 `.graphifyignore`、`build-m0.cmd`、
   `graphify-out/`、`install-deps-m0.cmd`（本轮未动）。
7. **未 push**（按纪律）。

---

## 8. 交付物清单

| 路径（仓库内） | 说明 |
|---|---|
| `modules/mcp_server/tools/editor_node_property_updates.{h,cpp}` | (c) 新组（新工具 + 参数形状校验 + 两种 stop_on_error 语义） |
| `modules/mcp_server/tools/tool_helpers.{h,cpp}` | (b) `node_path_guidance` / `NODE_PATH_RULE_SENTENCE`；(d) `GDScriptReloadReport`、`reload_gdscript_capturing`、`gdscript_reload_failure_text`、`build_execute_gdscript_source(..., r_body_start_line)` |
| `modules/mcp_server/tools/editor_node_write.cpp`、`editor_node_read.cpp`、`editor_set_node_script_batch.cpp` | (b) 三处拒绝消息 + 三处注册描述逐字对齐契约 |
| `modules/mcp_server/tools/editor_script_write.cpp`、`running_game_script_execution.cpp` | (d) 两个执行器共用同一诊断/行映射 |
| `modules/mcp_server/tool_registry.cpp` | (b) 未知参数建议的节点路径别名提示（显式工具表） |
| `modules/mcp_server/mcp_server.{h,cpp}`、`mcp_trace.{h,cpp}` | (a) ERROR 日志 + 原因诊断 + 记录状态 + `endpoint_disabled` 事件行 |
| `modules/mcp_server/scripts/gen_renamed_contract.py` | 契约生成器：`NODE_PATH_RULE_SENTENCE`、2 条 `DESCRIPTION_OVERRIDES`、`ADDED_TOOLS` +1、`GENERATOR_VERSION 1.19.0` |
| `modules/mcp_server/docs/tool-groups-added.json`、`docs/tools_list.renamed.json` | 清单 5 组 / 契约 176 条 |
| `modules/mcp_server/tests/test_mcp_server.h` | 7 条 TASK-063 用例（192 断言）+ 计数/描述 fixture 同步 |
| `modules/mcp_server/scripts/mcp063_product_defects_evidence.ps1` | 门② 的 53 条线上证据（纯 ASCII） |
| `modules/mcp_server/scripts/mcp063_evidence_manifest.py` | 证据树 sha256 清单与复核 |
| `modules/mcp_server/docs/reports/evidence/task063/**` | 102 个文件：响应原文、日志原文、追踪原文、门日志、红相位、`SHA256SUMS.tsv` |
| `modules/mcp_server/docs/reports/REPORT-063-round2-product-defects.md` | 本报告 |