# RACING-FINDINGS — TASK-039 §D 汇总者产物（把观察变成可执行的改进清单）

> **角色**：§D 汇总者。只把观察**复算**成清单，**不修改任何实现**。
> **产物**：本文件（唯一写入物）。原始数据仍在 `%TEMP%\mcp-racing-test\`、`%TEMP%\mcp-racing-evid\`、
> `%TEMP%\mcp-observer\`；本次复算脚本与中间产物在 `%TEMP%\mcp-findings\`（不进仓库）。
> **纪律自证**：未修改 `modules/mcp_server/**` 任何实现（见 §6 AC-12 复测）；**未**启动/杀死任何引擎进程；
> **未**占用 9877（只跑了一次 `netstat`，结果：**当前 9877 无监听**）；本报告是新文件，未改动 §A/§B/§C 的任何一行
> （对它们的纠错**只写在本文件里**，`PLAYBOOK §7.3` 允许 append-only 勘误）。

---

## 0. 复算方法与不可变锚点（D86）

### 0.1 提交锚点（D86）

| 项 | 值 | 来源 |
|---|---|---|
| 仓库 | `F:\RustProjects\godot-mcp-pro\code\godot` | — |
| 分支 | `feature/mcp-server-module` | `git rev-parse --abbrev-ref HEAD`【实测】 |
| **HEAD（全部结论测自）** | `f34ee937f3d31c49ac42081bb91433c5fc5b36e3`（短 `f34ee937f`） | `git rev-parse HEAD`【实测】 |
| 引擎自报 | `4.8.dev.mono.custom_build.f34ee937f` | 游戏日志 `godot2026-09-23T23.18.32.log:1`【实测】 |
| 模块实现是否被改 | `git status --short modules/mcp_server/tools modules/mcp_server/tests` = **空** | 【实测，本次汇总时重跑】 |

### 0.2 我实际复算过的东西（不是转述）

| 输入 | 我的复算动作 | 结果 |
|---|---|---|
| `trace-editor.jsonl` | `certutil SHA256` + 逐行 JSON 解析 + `analyze_mcp_trace.py` 全量跑 | **123 067 B / 298 行 / sha256 `096B0CCD608D1026E5673339EF2632641EA0C5C1632A209C658CB631CBEC7B48`**；= 1 `initialize` + 1 `tools/list` + **296** `tools/call`，失败 **37**（36×`-32001` + 1×`-32602`）；无 NUL/控制/非 ASCII 字节（无稀疏孔洞） |
| `trace-game.jsonl` | 同上（文件仍被游戏进程持有，`certutil` 首次共享冲突，随后成功） | **40 054 B / 99 行 / sha256 `CA03D3EF23FB6C777B2CE3054434CC0283513EE24BCE8AB2A47D2A5909E7F02B`**；= 3 代进程拼接（`seq==1` 出现在第 63、86 行）+ **94** `tools/call` + 3 `initialize` + 2 `tools/list`，失败 **3**（`-32000`×3） |
| `CALL-LOG.jsonl`（§B 客户端全量日志） | 解析 400 行 + 逐行失败分类 + sha256 与仓库证据互查 | sha256 `9A038C3F16C1D0DD512DFC188858772E6D2DACA435AA78D525D6E5155B5C4841`（= §B §0）；400 行 = 294@9888 + 106@9889，失败 **43**（`-32001`:37 `-32602`:3 `-32000`:3）✓ = §B F-1 |
| 契约 `docs/tools_list.renamed.json` | 全量解析 171 条 + 按参数名统计 + 逐条对照 | 110 770 B，sha256 `C844EC8AF9EF00D2E6EC7008C9806B3E2B16757E78794D3CCCA0704EDF844256` ✓ = §A §0 |
| `docs/tool-groups.json` | sha256 | `0CFCAC80F0D999FA7DB713AE48F43FEBE96AE52E2C93633257EEED00FFDFBFAC` ✓ = §A §0 |
| 仓库证据 | 逐文件 sha256 + 与 CALL-LOG 的 `request/response_sha256` 按**哈希**互查 | `AC-9-tools_list-editor.json` 43 189 B `E31846B5…` ✓；`AC-9-tools_list-game.json` 23 362 B `A1762689…` ✓；`0003/0005/0061-editor_add_resource_to_node_property.response.json` = `231EB944…`/`F11D2D16…`/`BC27EB12…` 三条**都能在 CALL-LOG 里按 sha256 对上** |
| 观察者的独立探测 | 对 `%TEMP%\mcp-observer\` 三个响应体**重新算哈希** | `car-pmo.res.json` 247 B `C444B1B4…`✓、`game-pmo.res.json` 214 B `E863485E…`✓、`car-sig.res.json` 4 823 B `33B6D24B…`✓ —— **OBS-013/OBS-022 的三个锚点全部复算通过** |
| 源码（只读） | 按 §C/§B 给出的行号逐条读 | `mcp_trace.cpp:132-192`、`mcp_server.cpp:52,67-115,527-538`、`editor_write_scene_editor.cpp:615-706`、`editor_node_write.cpp:235-265`、`editor_node_read.cpp:185-265`、`editor_node_batch_write.cpp:95-170,200-310`、`running_game_observation.cpp:130-238,435-466`、`running_game_test_execution.cpp:139-175`、`tool_registry.cpp:331-378`、`scene/resources/packed_scene.cpp:760,1238`、`scene/2d/physics/{rigid,static}_body_2d.*` |
| 引擎/工程现场 | 读磁盘状态 | `%TEMP%\mcp-racing-test\scenes\main.tscn` **4 836 B sha256 `5892209C13782D417D8EF32F794BF94B7AAEBCDE00F40B1E75345EA8A49B7C3C`，`[connection]` 块数 = 0**；`import.attempt1/2.log` 3 826/3 616 B `90AAFEDB…`/`3F77BA2C…`✓ |

### 0.3 与 §B/§C 报告的锚点差异（必须先说清）

1. **`trace-game.jsonl` 的 sha256 与 §B §0 不同**：§B 记 `7CDD8B27…` / 39 852 B，**我测到 `CA03D3EF…` / 40 054 B**。
   原因**不是**文件被改，而是 §B 自己声明的 R-6（trace 仍在增长、快照过期）：文件最后一条是 `23:44:57.398` 的
   `tools/list`，而 `DEV-DONE.marker` 写于 `23:44:32`。**本报告一律用我的 `CA03D3EF…` 作为 `trace-game.jsonl` 锚点。**
2. **§C 的「最终追踪规模」已过期**：§C OBS-024 记 `trace-editor.jsonl` 101 939 B /「seq 已远超 246」，
   §C §3 记「205 条 / 失败 28」。**全量文件是 298 条 / 失败 37**。§C 的计数是它自己窗口（`seq≤205`）的
   **正确**快照，但不能当作「全程计数」引用。
3. **仓库证据只覆盖 400 次调用中的 130 次响应体**：我按 `response_sha256` 反查，130/400 命中仓库文件，
   其余 270 条只在 `%TEMP%\mcp-racing-evid\calls\`（**我核对时仍有 392 个 `.res.json`，尚未丢失**）。
   → 后续批次引用「未进仓库」的证据时，必须**当场复制进仓库**，否则 `%TEMP%` 被清理后不可复核。

---

## 1. 对 §C（观察者）结论的逐条复算 —— 含明确纠错

> 判定口径：**实测**=我用追踪原文/哈希/源码复算过；**无法复核**=证据已被覆盖或不存在；
> **证伪**=我的复算与 §C 的结论相反。行号一律指**当前文件**的物理行号（`lineno` = `seq` 是巧合，见 §2 AN-9）。

| §C 条目 | §C 的结论 | 我的复算 | 证据（lineno / seq / 错误码 / 字节 / 哈希） | 判定 |
|---|---|---|---|---|
| OBS-001 | 开工前 ≥10 分钟零流量；「开发者重建二进制」=推断 | 追踪首行 `ts_ms=1790175751840`（=`23:02:31.840`），此前确无任何记录；二进制 `LastWriteTime` 22:47 早于首行 | 追踪 lineno 1（`id=1002, seq=1, initialize, ok, rb=184`）；`bin\…mono.exe` 时间戳 | **实测**（无矛盾），保留 |
| OBS-002 / OBS-006 | `initialize` 连打 3 次 / 2 次才拿到响应，**第 3 次 / 第 2 次才是 `seq=1`**，且当时该行的 `id=1003`/`1002` | 当前 lineno 1 是 **`id=1002`**，`ts_ms=1790175751840`；§C 说「22:55 那行 id=1003」的那行**已不在文件里** | lineno 1 全文：`{"id":1002,"connection":1,…, "seq":1,"ts_ms":1790175751840}` | **现象无法复核**（证据被覆盖）；「编辑器尚未监听 → 连接层失败」仍是**实测+推断**的合理结论，但**不能再用 `seq=1` 定位它** |
| OBS-003 | 编辑器角色默认端口 = 9877，`--import` 也会尝试绑定；日志「只说 bind failed，不说默认值可能是你不想要的端口」 | ①**默认值成立且这是被显式记录的设计**：`mcp_server.cpp:52 static const int DEFAULT_EDITOR_PORT = 9877;`、`:71 config.port = p_is_editor ? DEFAULT_EDITOR_PORT : 0;`、`:531-536` 的注释**明文写着**「`--import` … binds 9877 unless told otherwise … used to do so silently; the INFO line makes that visible」；②两份导入日志**逐字复现**：`role=editor configured_port=9877 source=default listen=true` → `bind failed … (error=22)`；③**§C 的一处说法要纠正**：日志并非「不说来源」——紧邻上一行就是 `source=default`，可自诊断 | `%TEMP%\mcp-racing-evid\import.attempt1.log` 3 826 B `90AAFEDB75F415F8AE1C8F6DC9A9942E842C718E928391B5CB19C4EF9220A7F6`（UTF-16，行 5/6/7/15），`import.attempt2.log` 3 616 B `3F77BA2C327A8E9F7021A51E79FE1A70F986999D2EC046A0F05F1B531AB190BF`（行 5/6/7/15） | **实测**，但**改判**：不是新异常，是**已记录的设计 + 一处措辞纠正**；残余风险（默认值压在用户日常端口上）→ §2 AN-9 归为**流程/决策项** |
| OBS-004 | 用户 Godot 退出、9877 变空闲、风险升级 | 本次汇总时 `netstat -ano \| findstr :9877` **无输出**（当前空闲）；我未触碰 | 命令输出（exit 1） | **实测**，保留 |
| **OBS-005** | 「编辑器重启会**清掉**同一路径的旧追踪」，根因**推断**为写入端以 `O_TRUNC` 打开 | **机制被证伪**：`mcp_trace.cpp:132-192` 是**纯追加**（不存在→`WRITE_READ("wb+")` 建文件；存在→`READ_WRITE("rb+")` + `seek_end()`），全文件**没有**任何 truncate/delete 逻辑（`grep -n "Remove\|TRUNCATE"` 只命中 UTF-8 截断注释）。**真正的成因是测试脚本自己删文件**：`host_editor.ps1:26 Remove-Item $traceEditor`、`b1_bootstrap.ps1:105 Remove-Item $traceEditor`（**启动前**执行）。→ 「同一路径的旧追踪被清掉」**成立**，但**责任方不是模块** | 源码 `mcp_trace.cpp:142-192`；`%TEMP%\mcp-racing-src\host_editor.ps1` 第 25-26 行、`b1_bootstrap.ps1` 第 104-105 行；追加语义的**正面证据**：`trace-game.jsonl` 里 `seq==1` 出现在 lineno 63 与 86，**前两代的行仍在**（99 行 = 3 代拼接） | **现象实测 / 机制证伪 / 成因改判**；§C 的「`O_TRUNC`」推断**显式撤回**（§C 自己也写了「若要坐实需读源码」，我已读） |
| OBS-005 附带 | `seq` 是「每进程从 1 开始」；23:02:41 读到 0 字节与 23:03 读到 190 字节**自相矛盾** | ①`seq` 每进程重置**成立**（game 文件两处 `seq=1`）；②**0 字节读数同样无法与现状调和**：`trace-game.jsonl` 23:23:23 若真被清空，就不可能同时保留 lineno 1-62 里 `ts 23:18:33→23:24:38` 的行。→ **该 0 字节读数是测量伪影**（OBS-005 自己也标了矛盾） | `trace-game.jsonl` lineno 1 `ts_ms=1790176713921`、lineno 62 `ts_ms=1790177078596`（=`23:18:33.9`→`23:24:38.6`） | **实测**（`seq` 重置）+ **改判**（0 字节=伪影，非清空） |
| OBS-007 | 6 个 C# 脚本在首次 MCP 连接**之前**就落盘；「B 缺失工具」**已自行撤回**（6 次 `project_create_script` 全 ok） | ①`%TEMP%\mcp-racing-src\*.cs` 的**创建时间**确为 `22:53–22:54`（早于首行 `23:02:31`）；②撤回**成立**：追踪里 `project_create_script` **恰 6 次全部 ok** | `dir /tc` 六个 `.cs`（5 024/969/1 053/2 985/2 789/1 437 B）；editor 直方图 `project_create_script = 6`，全 ok | **实测**，§C 的自我勘误**成立**（且我给出的 6 次计数独立确认了它） |
| **OBS-008** | `editor_add_nodes_batch` 不能在**同一批**里先建父再建子；父路径按「请求开始前的树」解析 | **完全成立**，并拿到**源码级**确认：`editor_node_batch_write.cpp:251-258` `find_node(p_root, parent_path)` 在**构造节点之前**解析，失败即 `_transaction_fail(...)` | editor lineno 10（`seq=10`）`-32001` `nodes[1]: parent 'Track' not found`，`args_bytes=1507`，`result_bytes=603`，`duration_ms=0`；源码 `editor_node_batch_write.cpp:253-257` | **实测**（§C 的「推断引擎本可做到」也成立——循环里 `add_child` 顺序执行即可） |
| OBS-009 | 用 4 次批处理按深度分层才绕过；「`editor_get_scene_tree` 的 `max_depth` **默认值偏小**导致反复加深」 | ①分层绕过**成立**（`editor_add_nodes_batch` 共 10 次、其中 3 次 `-32001`）；②**「默认值偏小」证伪**：契约写的是 `"max_depth": {"default": -1, "description": "最大深度 (-1 无限)"}`，**默认就是无限**；调用方是**显式**传了 `6.0→8.0→12.0`（`args_bytes` 17/17/18 说明带参） | lineno 58/63/94/99/101/102/103/270；契约 `editor_get_scene_tree.inputSchema`；lineno 101/102/103 `max_depth:12` 三次同参 `rb=12308`（**确定性正面证据**） | **现象实测 / 归因证伪**；这条**从「可优化」降级为「不建议做」**（见 §3） |
| **OBS-010** | `editor_setup_physics_body` 同参先失败 2 次、36 秒后成功；错误消息够用（D3 正面案例） | **完全成立**（同 `args_bytes=69`、`false→true`） | lineno 12/13 `-32001` `Parent 'Track' not found` `ab=69 rb=176`；lineno 64 `ok` `ab=69 rb=249`；分析器 `repeated_same_args` 收录 | **实测**，保留（**D3 正面基线**） |
| OBS-011 | `editor_set_node_property` 连续 20 次 `-32001`；**「全部是 OBS-008 那次批处理失败的级联」**；错误消息不指向上游 | ①20 次 + 1 次（我故意的负例）**成立**（共 21 次失败，与 §B F-1 一致）；②**归因要收窄**：`seq 14-26`（13 次）是**批处理回滚后树为空**的级联；`seq 67-76`（7 次）是**树只重建了一半**的级联（`seq=63` 的 `get_scene_tree` `rb=7147` 证明树仍不完整）——**不是同一次批处理**；③**消息带 self-correction**：读侧节点找不到是 `data.suggestion="Use editor_get_scene_tree to list the nodes of the edited scene"`（源码 `editor_node_read.cpp:391-392`），**只有「不指向上游」这一半成立** | 21 条失败逐条在 `trace-editor.jsonl` lineno 14-26、67-69、73-76、242；分析器 `error_code_by_tool: editor_set_node_property {"-32001": 21}` | **实测（计数与消息）/ 归因部分纠正 / D3 结论降级为「上游不可见」** |
| **OBS-012** | 批处理失败是否**部分生效**：**未定论**（追踪不记响应体） | **可定论，且答案是否**：源码显示 `_rollback_envelope()` 回 `status:"rolled_back" / created:[] / count:0 / on_error:"all_or_nothing"`，且 `_transaction_fail` 逆序 `memdelete` 所有已建节点（`editor_node_batch_write.cpp:100-146`）；成功时是 `status:"ok"`（证据文件） | `editor_node_batch_write.cpp:97-127,131-146,493-495`；成功样例 `0009-editor_add_nodes_batch.response.json` = `{"count":1,"created":[…],"errors":[],"status":"ok"}` | **未定论 → 定论（非原子性担忧解除）**：**不是** A5 家族 |
| **OBS-013** | C# `[Signal]` 注册名是 PascalCase（`SpeedChanged`），`speed_changed` 不存在；**「调用方三次失败后放弃」「未解决」** | ①PascalCase**成立**（我重算观察者探测：`count=23`，含 `SpeedChanged`，不含 `speed_changed`）；②**「放弃/未解决」证伪**：**3 分钟后**（`seq 225-228`，`23:11:25.646`）调用方用 PascalCase **4 条全部 `connected:true`**，其中 `SpeedChanged→HUD`、`CheckpointPassed`、`LapCompleted`、`BodyCrossed` 全连上；③错误消息**带** `data.suggestion="Use editor_get_node_signals to list the signals this node has"`（证据文件），**不是**「错误消息不足以自纠」的反例，而是**D3 正面案例**（与 OBS-010 同类） | 探测 `car-sig.res.json` 4 823 B `33B6D24B…`；editor lineno 170/171/172 失败（`-32001`, `rb=196/205/201`）→ lineno 173/174 成功 → **lineno 225/226/227/228 成功**（`rb=162/171/167/173`）；`0045/0046/0047-editor_connect_signal.response.json` 含 suggestion | **现象实测 / 结论证伪并改判为 A6+D3 正面案例**（我在 §2 里把它从「未解决」移到「已解决」） |
| OBS-014 | `editor_save_scene` → `project_read_scene_file_content` 3 次同型对；建议给 `save_scene` 加 `verify` | **成立但少算**：全量是 **5 次**同型对（不是 3 次），因为 §C 的窗口止于 `seq=205` | 对：`43→44`(Δ76 ms)、`85→86`(Δ73)、`123→124`(Δ74)、`203→204`(Δ27)、`233→234`(Δ69)；`save_scene` 5 次 `rb=128` 恒等；`read rb` 267→2145→3399→6556→6120 | **实测**，数量纠正 |
| OBS-015 | 单点族连打：写 12 连 / 读 3 连 / 校验 6 连 / 挂脚本 8 连；`editor_set_node_property` 占 37/204≈18% | **成立**，全量口径：`editor_set_node_property` **57/296 = 19.3%**；`project_validate_script` 17（含 `127-132` 与 `274-279` **两段 6 连**）；`editor_set_node_script` 8 连（`133-140`）；`editor_get_node_properties` 15 | 直方图（全量）与逐条 dump；`seq 104-115` 12 连写 | **实测** |
| **OBS-016** | `connection == seq` 恒成立 ⇒ 分析器 `bigrams/trigrams` **结构性失明**；另 `unigrams[].sequence` 被渲染成**字符数组** | **两条全部复算通过** | ①我逐行核对：**298/298 相等，0 不等，distinct connection = 298**；分析器全量输出 `bigrams: none repeated / trigrams: none repeated`；②`analysis-editor.json`：`unigrams[0].sequence = ["e","d","i","t","o","r",…]`（`length:1`），而 `bigrams/trigrams = []` | **实测**；OBS-016 是本次试测**最有方法论价值**的一条 |
| OBS-017 B-1 | 契约 171 条里**没有**编译 C# 的工具；回退 `dotnet build` | **成立**（我用正则 `/(build\|compile\|reload\|restart\|headless\|create_project\|new_project)/i` 重扫 171 条，只命中 `editor_reload_plugin`——GDExtension 插件重载，不编译 C#）；`project_build_csharp` **未注册** | 重扫输出；`dotnet-build-1.log` 667 B `5F2C3135A3B3ED60ACB1BCEC49CF8DCC82208532FC903ED2905D109254AE83DD` | **实测**，保留 |
| OBS-017 B-2 | 让游戏以 `--headless` 起来：**未确认** | **确认成立**：`editor_play_scene.inputSchema` 只有 `mode`/`mcp_port`；`editor_playback.cpp:320` 只注入 `--mcp-port`；§B 的 `b7_headless_mode.ps1:39` 才自启 `--headless`（**游戏第三方进程的代次在追踪里可见**：`trace-game.jsonl` lineno 87-88 的 `-32000` 报「headless display server has no texture storage」，正是 headless 代） | 契约原文；`editor_playback.cpp:320`；trace-game lineno 87/88 | **未确认 → 实测成立** |
| OBS-018① | A5「报成功但状态未变」在 `seq≤205` 内**没找到** | **在 §C 窗口之外的 `seq=186/240` 找到了**（`editor_add_resource_to_node_property` 对 `Car` 报 ok 却什么都没写）→ **§2 AN-1 / §4 D-1** | editor lineno 186 `ok rb=180`、lineno 240 `ok rb=180`；读回 lineno 208/241/254 `-32001` | **改判：A5 存在**（§C 不是错，是窗口不够） |
| OBS-018② | `editor_list_signal_connections` 返回 94 862 B（`{}`），未达 1 MiB 不记 A4 | **成立**，并在全量最大值里排第一（其次 `tools/list` 43 189 B、`project_get_filesystem_tree` 16 995 B） | editor lineno 175 `rb=94862 dur=5 ab=2`；`0049/0050-…` 证据文件 | **实测**，保留 |
| OBS-018④ | `project_get_settings` 的 `prefix` 尾随斜杠改变结果集且**无文档** | **成立**：`{"prefix":"godot_mcp"}` `rb=105`（`seq=3`）vs `{"prefix":"godot_mcp/"}` `rb=254`（`seq=42/54/90/268`）；契约里 `prefix` **连 `description` 都没有** | editor lineno 3/42/54/90/268；契约 `project_get_settings.inputSchema = {prefix:{“type”:“string”}, include_default:{default:false}}` | **实测**，升为 D5 项（§2 O-9） |
| **OBS-020** | `editor_play_scene{mcp_port:9889}` 直接把游戏拉起来，**不需要绕过工具**；推翻 §A §2.5 的「缺工具」预判 | **成立**（响应含可链式字段 `endpoint/mcp_port/mcp_port_source/pid/playing`：`pid=44156`，另一次 `pid=70456`） | editor lineno 246 `seq=246 ok dur=1796 ab=36 rb=223`；`0001-editor_play_scene.response.json`（`pid:44156`）与 `0007-…`（`pid:70456`） | **实测**；§A §2.5 的**「必须绕过工具才能起游戏」被证伪**，只剩 headless 那半条成立 |
| **OBS-021** | `running_game_find_nearby_nodes` 的错误「**不列出**合法参数名 / 不含 `data.suggestion`」；`get_autoload_node` 的必填靠猜 | ①**前半证伪**：响应**带** `data.suggestion="Accepted parameters of running_game_find_nearby_nodes: group_filter, max_results, position, radius, type_filter"`（`tool_registry.cpp:371-376` 无条件给），**§C 因为追踪不记响应体而误判**——但仓库证据文件里就有；②**后半成立**：`running_game_get_autoload_node` 的 `-32602 Missing required parameter: name` **确实没有** `data.suggestion`（96 B 裸错误）；③§C 引用的**那一代游戏追踪已不存在**，只能靠 CALL-LOG + 证据文件复核 | `0015-running_game_find_nearby_nodes.response.json` 271 B（含 suggestion）；`0014-running_game_get_autoload_node.response.json` 96 B（无 suggestion）；CALL-LOG 行 255/256；`tool_registry.cpp:359-377` | **一条证伪 + 一条成立**；**方法论教训**：能落盘的证据文件必须读，不能只看追踪 |
| **OBS-022** | 跨端点矛盾：`physics_material_override` 在 `Car` 上编辑器说**不存在**、游戏说**存在（null）**；**最强假设=编辑器把「值为 null」误判为「属性不存在」**；严重度 high | ①**矛盾现象实测成立**（双 sha256 我重算通过，且游戏侧探测正好是 `trace-game.jsonl` **lineno 2**，`id=90003`，一字不差）；②**根因推断证伪**：`physics_material_override` 在本 fork **只存在于 `RigidBody2D`（`rigid_body_2d.cpp:754`）与 `StaticBody2D`（`static_body_2d.cpp:235`）**，`PhysicsBody2D`/`CollisionObject2D` **都没有** ⇒ `CharacterBody2D` **真的没有**这个属性，编辑器的 `-32001` **是对的**；③**「null 误判」直接反证**：同一份编辑器全量清单 `AC-8-car-property-list.json`（66 属性，sha `A1A5CE6C…`）里 `"material":null` **在列**（值为 null 的属性照样列）；④真正的问题是**游戏侧读**对「不存在的名字」回 `null`，源码里**明文声明为有意行为**（`running_game_observation.cpp:167-168`「A name the node does not have at all still answers null - that is this tool's documented named-path behaviour」+ `:194` 无条件 `r_out[name]=serialize_variant(p_node->get(name))`） | 探测 `car-pmo.res.json` 247 B `C444B1B4…`、`game-pmo.res.json` 214 B `E863485E…`；editor lineno 208/241/254 `-32001 rb=246/246/247`、lineno 238/240 `ok`；game lineno 2 `rb=214`；引擎源码 `rigid_body_2d.cpp:754`、`static_body_2d.cpp:235`、`physics_body_2d.h:36`、`character_body_2d.h:36`；`AC-8-car-property-list.json` | **现象实测 / 根因推断证伪 / 严重度 high → medium**；改判为**契约未记载的端间语义不对称**（§4 D-3） |
| **OBS-023** | OBS-005 在游戏端点**复现**：`trace-game.jsonl` 被清空为 0 字节、PID 变了 | ①PID 变化属实；②**「被清空」的机制同 OBS-005 一样被证伪**（模块只在文件**不存在**时才创建，见 OBS-005 行）；真正的删除者是**测试脚本**：`b3_play_and_smoke.ps1:17 Remove-Item $traceGame`、`b3b_fix_signals_and_replay.ps1:42 Remove-Item $traceGame`；③**当前文件是 3 代拼接**（`seq==1` 出现两次），**反向证明「不是每次重启都清空」**；④0 字节读数与现状不相容 ⇒ 伪影 | `%TEMP%\mcp-racing-src\b3_play_and_smoke.ps1:16-17`、`b3b_fix_signals_and_replay.ps1:41-42`；`trace-game.jsonl` lineno 1/63/86 三处 `initialize`，lineno 99 结尾 | **现象部分实测 / 机制证伪 / 成因改判为测试脚本** |
| OBS-024 | 收尾：编辑器 246 行 / 失败 32（全 `-32001`）；游戏 0 B | **过期的自报快照**：全量 = 编辑器 **298 行 / 失败 37**（36×`-32001` + **1×`-32602`**，即 §C 说的「全部 -32001」在全量口径下**不成立**）；游戏 **99 行 / 40 054 B**（含 3 代） | §0.2 的哈希与计数 | **实测（纠正计数）** |

### 1.1 对 §B（开发者日志）的复算与纠错

§B 的整体质量很高（`AC-9`、`D-1`、`D-2` 的关键论断我**独立复核全部成立**），以下 5 处必须纠正：

| # | §B 的说法 | 复算结果 | 证据 |
|---|---|---|---|
| B-a | §2 A 段 / F-4：「`project_search_file_names` 只支持子串（`*.cs` → 0）…**契约也没写** pattern 是子串还是 glob」 | **后半错**：契约原文写得很清楚——「只匹配文件名子串（大小写不敏感、上限 200），不读文件内容、不返回行号」。`*.cs` 返回 0 与文档**一致**，是调用方误用，不是文档缺口 | 契约 `project_search_file_names.description`（sha `C844EC8A…`） |
| B-b | §2 C 段 / §I：「`project_validate_script` 对 `.cs` 的 `valid:true` 是**弱保证**，证据是 `Main.cs` 里坏信号名照样 `valid:true`」 | **例子不成立**：`car.Connect("speed_changed", …)` 是**运行时**错误，任何**语法**校验器都不该抓它；用它证明「没有真的编译 C#」是**循环论证**。真正要问的是 `CSharpScript::reload()` 是否真编译——我**没有**为此得到确凿证据，标**未证** | 游戏日志 `godot2026-09-23T23.18.32.log:10-42` 是 `Object::connect` 的运行时 ERROR；`project_read_files.cpp:276-346` 的 `ScriptServer::get_language_for_extension("cs")` + `script->reload()` 路径 |
| B-c | §2 B 段表：「`16-27` 同上（脚本属性 `MaxSpeed`/`Index`/`TargetPath`）| ok」 | **行号错**：`seq 14-26` **全部失败**；脚本属性写**成功**在 `seq=141-151`（`MaxSpeed=320`、三个 `Index`、`Camera.TargetPath`） | editor lineno 14-26 `-32001`；lineno 141/145/147/149/151 `ok` |
| B-d | §F-1：「`editor_set_node_property` 21 次失败里 **20 次**是试图给『还没挂脚本的节点』写脚本属性」；§F-3 I-2 同样用它当证据 | **分类错**：21 次失败中 20 次的错误是 **`Node 'X' not found`**（树里根本没有该节点），**1 次**是我故意的 `no_such_property_zzq`；全量追踪里**没有**任何一条「属性不存在」型失败（除故意的负例）。→ 这 20 次是**批处理回滚/树未建全**的级联（见 OBS-011 纠错），**与「有没有挂脚本 / 有没有 `dotnet build`」无关**，`I-2` 的这条证据链**不成立**（I-2 可能仍然为真，但**本试测没有证明它**） | 21 条失败逐条消息；`error_message` 里 `Node '…' not found` ×20、`Property 'no_such_property_zzq'…` ×1 |
| B-e | §0 / §0 表：`trace-game.jsonl` = 39 852 B / `7CDD8B27…` | **过期快照**（§B 自己声明了 R-6）：最终为 **40 054 B / `CA03D3EF…`** | §0.2 |
| B-f ✅ | §7 D-1 的根因（`editor_write_scene_editor.cpp:697` 无存在性检查 + 699-703 无条件回显）与 D-2 的根因（`editor_node_write.cpp:257` 无 `CONNECT_PERSIST`） | **两处源码行号与结论逐字成立**，我另加了引擎侧与文件级证据 | `editor_write_scene_editor.cpp:697-703`；`editor_node_write.cpp:257`；`packed_scene.cpp:760,1238`；`main.tscn` sha `5892209C…` 且 `[connection]` 计数 = 0；`grep CONNECT_PERSIST modules/mcp_server/tools/**` = **0 命中** |
| B-g | §2 E 段：「我下一次（**28 分钟后**）直接用 PascalCase 成功」 | **时间差写错**：`seq=170` 失败在 `23:08:29.873`，`seq=225` 成功在 `23:11:25.646`，相隔 **≈2 分 56 秒**。（这条纠正很重要：它说明错误消息的 `data.suggestion` 让调用方在**一次工具往返规模**内就自纠了，不是「拖了半小时才绕过去」） | editor lineno 170 `ts_ms=1790176109873` → lineno 225 `ts_ms=1790176285646` |

### 1.2 对 §A（试测方案）的判据缺陷（预登记错了，不是模块错）

| # | §A 的条目 | 复算结果 |
|---|---|---|
| A-a | `E-5`：「9889 的集合 ⊂ 9888」 | **证伪**（§B 已发现，我确认）：编辑器 148 条、游戏 69 条，其中 **23 条 `running_game_*` 只在游戏端注册**，编辑器独有 102 条，148+23=171。两边与契约**逐字 0 处不一致** | `AC-9-tools-list-comparison.txt`；`AC-9-tools_list-editor.json` `E31846B5…`、`AC-9-tools_list-game.json` `A1762689…` |
| A-b | `AC-6`：「三个编辑器侧工具对『连接存在』的答案**一致**」 | **判据本身不可满足**：契约 `editor_list_signal_connections.description` 明写「**收全部连接（不过滤非持久连接）**」，`editor_analyze_signal_flow.description` 明写「**只收集持久连接（CONNECT_PERSIST=2）**」。两者答案**必然不同**且**都已文档化**。→ 这是**计划判据缺陷**，不是「工具间矛盾」 | 契约两条 `description`；editor lineno 175（`rb=94862`）vs lineno 176/177（`rb=145`） |
| A-c | §3.1 覆盖清单里的 `running_game_get_test_report` | **不存在**（真名 `editor_get_test_report`，已注册）。→ 计划清单的错误 | 171 条名字集合比对：`running_game_get_test_report registered=False`，`editor_get_test_report registered=True` |
| A-d | §4.1 `A4`：「同一工具相同 args 的 `result_bytes` 相差 > 10 倍且无解释」算异常；`A8` 用 `result_bytes` 判不确定性 | **两条判据都会假阳性**：①`editor_get_scene_tree{max_depth:6}` 在 `seq=9` 是 **537 B**、在 `seq=270` 是 **13 412 B**（>24×）——**场景长大了**，不是异常；②`tools/list` 游戏端 `seq=23`（`id=1016`）**23 362 B** vs `seq=14`（`id=1`）**23 359 B**，差 **3 字节 = `len("1016") − len("1")`**，**载荷逐字相同**（两边都 `tools=69`）——`result_bytes` 是**含 JSON-RPC `id` 的信封长度**，判不确定性前必须先扣掉 id 长度 | editor lineno 9/270；game lineno 85（`id=1016, rb=23362, tools=69`）与 lineno 99（`id=1, rb=23359, tools=69`） |
| A-e | §4.1 `A4` 的 1 MiB 阈值 | 全程最大响应 `editor_list_signal_connections` **94 862 B**（`seq=175`，`args={}`），**未破线**。§B 的「A4 候选」判断正确 | editor lineno 175 |
| A-f | §4.1 `A2`（非 deferred `duration_ms > 2000`）、`A3`（`pending_ms > timeout_ms`） | **全程 0 命中**：非 deferred 最慢是 `editor_play_scene` 1 796/1 453/1 383 ms；所有 >2 s 的调用都带 `pending_ms`（deferred：`get_node_property_samples` 2 985/2 001 ms，`capture_signal_emissions` 9 019 ms，`run_test_scenario` ≤1 607 ms）；`pending_over_ceiling` = 0 | 全量重算（见 §0.2 脚本输出） |
| A-g | §2.5 模式 B：「想要被观测的游戏以 headless 起来**没有任何工具能做**…这本身就是缺失工具线索」 | **前半成立、后半的「只能绕过工具自启游戏」不成立**：窗口化起游戏**有**工具（`editor_play_scene`），只有 headless/`extra_args` 缺 | §1 OBS-020；契约 `editor_play_scene.inputSchema` |

---

## 2. 四张表

> 每条给：**调用序列 / trace 行号（`lineno` = 物理行）/ 错误码 / 耗时 / `result_bytes` / 文件 sha256**。
> **证据强度**排序口径（§A §4.4）：`S1` = 带 sha256 的落盘响应 **且** 有 trace 行 **且** 有源码定位；
> `S2` = 上面三者有其二；`S3` = 只有 trace 行或只有日志自述。**影响面**：`H` 影响正确性/数据，
> `M` 影响一次典型工作流的往返或可自纠性，`L` 只影响手感。

### 2.1 ① 异常（含「报成功但状态未变」「工具间矛盾」「错误消息不足以自纠」）

| # | 类别 | 现象（实测） | 证据（序列 / 行号 / 码 / 耗时 / 字节 / sha256） | 实测 vs 推断 | 最小建议 | 强度 | 影响 | 序 |
|---|---|---|---|---|---|---|---|---|
| **AN-1** | **A5 报成功但状态未变** | 对 `Car`（`CharacterBody2D`，**没有** `physics_material_override`）写资源：**报 ok**，读回**仍是 `-32001`**，磁盘场景**无任何变化** | `editor_add_resource_to_node_property{node_path:"Car",property:"physics_material_override",…}`：lineno **186** `ok rb=180 dur=0`、lineno **240** `ok rb=180 dur=0`；读回 lineno **208/241/254** `-32001 rb=246/246/247 dur=0/0/1`；正面对照同工具 `Track/WallOuter` lineno 238 `ok rb=192`（读回 lineno 239 `ok rb=254`）；响应 sha `BC27EB12…`(0061)/`F11D2D16…`(0005)/`231EB944…`(0003)；全量属性表 `AC-8-car-property-list.json` 66 项无该属性 `A1A5CE6C…`；源码 `editor_write_scene_editor.cpp:697`（`node->set` 无检查）+ `:699-703`（无条件回显） | **实测**（含源码）；「引擎本可拒绝」=源码事实 | 写入前 `object_has_property()`（`tool_helpers.cpp:816`），无则 `-32001`+`data.suggestion`；并把 `old_value/new_value` 加进返回（与 `project_set_theme_*` 一致）。**≈5 行** | **S1** | **H** | **1** |
| **AN-2** | **A7 工具间矛盾（同端点）** | **同一个节点、同一个端点**：`running_game_get_node_properties` 对不存在的名字回 **`null`（ok）**，`running_game_set_node_property` 对同一个名字回 **`-32001 not found`** | game lineno **2**（`seq=2`, `id=90003`, `ab=91`, `rb=214`, `ok`）vs game lineno **22**（`seq=22`, `ab=76`, `rb=228`, `-32001 Property 'no_such_property_zzq' on node '/root/Main/Car' not found`）；探测锚点 `game-pmo.res.json` 214 B `E863485EA43B5943A80D4CD3DCDA393B092034F82D674FBF8EF8174CD51A8849`；源码 `running_game_observation.cpp:167-168,194` vs `running_game_node_write.cpp:1158` | **实测**；「有意行为」=源码注释明文 | ①契约 `running_game_get_node_properties.description` **写明**「未声明的名字回 null」；或②按写侧一致化（**需决策**，见 §3「不建议做」） | **S1** | **M** | **2** |
| **AN-3** | **A5 报成功但状态未变（持久化维度）** | `editor_connect_signal` 回 `{"connected":true,…}`，`editor_save_scene` 回 `saved:true`，但落盘 `.tscn` **没有任何 `[connection]` 块**，重开后连接消失；运行时的直接后果是「车不会计时」 | editor lineno **173/174** `ok rb=167/179 dur=0`（响应里**无 `persisted` 字段**，`0048/0049-…response.json`）；`editor_save_scene` lineno 203 `ok rb=128`；磁盘 `main.tscn` 4 836 B **`[connection]` 计数 = 0**，sha256 `5892209C13782D417D8EF32F794BF94B7AAEBCDE00F40B1E75345EA8A49B7C3C`；源码 `editor_node_write.cpp:257`（`connect(signal, callable)` 无 `CONNECT_PERSIST`）、`packed_scene.cpp:760,1238`、`grep CONNECT_PERSIST modules/mcp_server/tools/**`→0 | **实测**（源码 + 文件字节） | `connect(..., CONNECT_PERSIST)` + 加 `persist:bool=true` 参数 + 响应加 `persisted`（对标 `editor_add_input_action` 已老实回 `persisted:false`） | **S1** | **H** | **3** |
| **AN-4** | **A7 工具间说法矛盾（跨端点）→ 已解释** | 同一属性名：编辑器读 **`-32001`**、游戏读 **`null`（ok）**；且编辑器说 `Car` 上没有它，`WallOuter` 上有 | editor lineno 208/241/254 `-32001`；editor lineno 239 `ok rb=254`；game lineno 2 `ok rb=214`；锚点 `C444B1B4…` / `E863485E…`；根因见 §1 OBS-022（引擎里该属性只在 `RigidBody2D`/`StaticBody2D`） | **现象实测 / 矛盾归因实测（属性确实不存在）/ §C 的 null 误判推断证伪** | 无需修代码：把两侧语义写进契约；若要统一，需先决定「哪个端点是对的」 | **S1** | **M** | **4** |
| **AN-5** | **D3 错误消息不对称（不足自纠的一侧）** | `-32602 Missing required parameter: <name>` **不带** `data.suggestion`；而**同一注册器的** `Unknown parameter '<x>'` **带**（且会列出全部合法参数） | `0014-running_game_get_autoload_node.response.json` **96 B**（`{"error":{"code":-32602,"message":"Missing required parameter: name"}}`）vs `0015-running_game_find_nearby_nodes.response.json` **271 B**（含 `"suggestion":"Accepted parameters of …: group_filter, max_results, position, radius, type_filter"`）；源码 `tool_registry.cpp:359-377`（unknown 侧给 suggestion）vs `tool_builder.cpp:210-224` 等（missing 侧不给） | **实测** | `require_*` 的失败也附 `data.suggestion = "Accepted parameters of <tool>: …"`（**注册器已持有 schema，零成本**） | **S1** | **M** | **5** |
| **AN-6** | **D5 契约缺口 + 一次失败即换路** | `editor_simulate_input_sequence{events:[{keycode:"W",pressed:true},{…}]}` → `-32602 Missing required parameter: events[0].type`；契约里 `events` 是**无 item schema 的裸 array**（只有散文说「每个事件包含 type 和对应字段」），调用方**一次失败后就用别的工具**了 | editor lineno **257** `ab=75 rb=106 dur=0`；CALL-LOG 行 307 同条（`response_sha256=8e3162d3…`）；契约 `editor_simulate_input_sequence.inputSchema`（`events` 只有 `{"type":"array"}`）；对照 `running_game_play_input_recording.events` **同样无 item schema** | **实测** | 两条工具的 `events` 加 `items`（声明 `type` 的 enum 与各类事件的字段），或在错误里回一个最小可用样例 | **S1** | **M** | **6** |
| **AN-7** | **无界列举（未达 A4 阈值）** | `editor_list_signal_connections{}` 回 **94 862 B**：434 条连接里约 **432 条是编辑器内部**（`ScriptEditor::*`/`SceneTreeEditor::*`/`Viewport::*`），只有 `signal_name` 过滤是精确的 | editor lineno **175** `ab=2 rb=94862 dur=5`；契约该工具 `description` 明写「收全部连接（不过滤非持久连接）；`node_path` 与 `signal_name` 均按**子串**匹配」 | **实测**；「434 条中 432 条内部」=§B 自述，本次**未逐条复算**（标推断） | 加 `scope:"scene"\|"all"`（默认 `scene`）或 `include_editor_internal:bool=false`；**保留** `signal_name` 精确过滤能力 | **S2** | **M** | **7** |
| **AN-8** | **证据完整性（成因已定，模块无责）** | 同一路径追踪的**代次会消失**：`trace-editor.jsonl` 只剩 1 代（首行 `id=1002`），`trace-game.jsonl` 丢了 `23:13:59` 那代却留着后面 3 代 | 源码 `mcp_trace.cpp:132-192`（纯追加、无 truncate）；删除者：`host_editor.ps1:26`、`b1_bootstrap.ps1:105`、`b3_play_and_smoke.ps1:17`、`b3b_fix_signals_and_replay.ps1:42` 的 `Remove-Item`；追加语义正面证据：`trace-game.jsonl` lineno 63/86 两处 `seq=1` | **实测（源码+脚本）/ 因果为强推断** | 模块最小改动：`Recorder::open()` 成功后**先写一行** `{"event":"trace_opened","pid":…,"path_existed":…,"existing_bytes":…}` —— 让「代次被换掉」**可被发现**；测试脚本侧改为**按 run 命名**（`trace-game-<run>.jsonl`） | **S1** | **M** | **8** |
| **AN-9** | **流程/纪律风险（不是模块新异常）** | 编辑器角色**默认**监听 **9877**，`--import` 这类纯离线运行也会尝试绑定；若用户 Godot 没开，**会被真的占用** | `mcp_server.cpp:52`（`DEFAULT_EDITOR_PORT = 9877`）、`:71`、`:531-536` 注释；`import.attempt1.log` 行 5-7/15、`import.attempt2.log` 行 5-7/15；两份 3 826/3 616 B `90AAFEDB…`/`3F77BA2C…` | **实测**；「用户没开时会被占用」=**推断**（纪律禁止我复现） | ①`--import`/`--test`/`--headless` 路径默认 `listen=false`，或默认端口改高位；②至少在 role 行加一句 `data.suggestion` 级提示（现有 `source=default` 已**可诊断**，只是不够显眼）。**需决策层定** | **S1** | **H（纪律级）** | **9** |
| **AN-10** | **契约/实现不一致（低）** | `steps[].pressed` 与 `steps[].strength` **被实现读取并生效**，但契约 `steps[].properties` **九个键里没有它们**；嵌套参数**不受**未知参数闸门约束，所以**静默放行** | 契约 `running_game_run_test_scenario.steps[].properties` = `action/expected/keycode/node_path/operator/property/seconds/text/type`；`running_game_test_execution.cpp:141-148` 读 `pressed`/`strength`；**成功调用证据**：CALL-LOG 多条 `{"steps":[{"pressed":false,"type":"input","keycode":"W"}]}` `ok=true`；闸门只查顶层（`tool_registry.cpp:331-354`） | **实测** | 契约补两个键（`pressed:boolean`、`strength:number`）＋在 `_reject_unknown_arguments` 里说明「嵌套成员不在本闸门范围」是**已知边界** | **S1** | **L** | **10** |

> **明确不算异常**（复核后仍成立，记下来防止误报）：`-32602` 缺参/类型错（`PLAYBOOK §6.2`）；
> 带 `data.suggestion` 的 `-32001`（`§6.1`）；headless 截图 `-32000`+suggestion（§A E-1，我实测命中：
> game lineno **87/88** `-32000` `"The running game has no framebuffer to read (the headless display server has no texture storage)"`）；
> `editor_add_nodes_batch` 的 `rollback`（源码级 all-or-nothing，见 OBS-012）；
> `editor_list_signal_connections` vs `editor_analyze_signal_flow` 的差异（**契约两侧都明文写了**，见 §1.2 A-b）。

### 2.2 ② 缺失工具（要实现什么能力 / 当前靠什么绕过 / 建议新增的**名与签名草案**）

| # | 想做什么 | 当前靠什么绕过（证据） | 建议工具名 + 签名草案 | 强度 | 影响 | 序 |
|---|---|---|---|---|---|---|
| **M-1** | **从零创建一个 Godot 工程**（`project.godot`/`.csproj`/`NuGet.config`） | 手写三个文件（UTF-8 无 BOM）：`project.godot` 674 B `534FCC66911E361A43D4352184355E2F6CC1C15BD38405D9D4FF475F0A79C1B6`、`NuGet.config` 232 B `A9FECF977A9169A42180AC7CA9E0C0F152F8D28E0F75E454240BED90B02130D6`、`mcp-racing-test.csproj` 305 B `E58B1C6E6988765D3FFDCC783739892F287F315C89CCBD73CFC265A9B30462CE`。契约 171 条里 `project_create_project` **未注册**（鸡生蛋：没有工程连不上端点） | `project_create_project{path:string, name?:string, dotnet?:bool=false, main_scene_type?:string="Node2D"}` → `{created:bool, project_file:string, csproj?:string, nuget_config?:string, sha256:{…}}` | **S1** | **H** | **1** |
| **M-2** | **编译 C# 程序集**（`[Export]`/`[Signal]` 只有在 assembly 建好后可见） | 工具外 `dotnet build -c Debug`（`dotnet-build-1.log` 667 B `5F2C3135…`；装配件 38 912 B `C3C0C33592C55619279C9E799DF79CB2F2DE40805C1BE789A153B4C423FE6613`）。契约里 `/(build\|compile)/i` **只命中 `editor_reload_plugin`**（GDExtension 插件重载，不编译 C#） | `project_build_csharp{configuration?:"Debug", target?:string}` → `{ok:bool, assembly_path:string, sha256:string, warnings:string[], errors:string[], duration_ms:int}`；并在 `editor_connect_signal`/`editor_set_node_script` 检测到**陈旧装配件**时给 `data.suggestion` | **S1** | **H** | **2** |
| **M-3** | **让被观测的游戏以 `--headless` 起来 / 给子进程加命令行参数** | 工具外 CLI 自启：`b7_headless_mode.ps1:39 @('--headless','--path',…,'--mcp-port=9889','--mcp-trace='+$trace)`；`editor_play_scene.inputSchema` 只有 `mode`/`mcp_port`，`editor_playback.cpp:320` 只注入 `--mcp-port` | `editor_play_scene{mode?="main", mcp_port?:int, headless?:bool=false, extra_args?:string[]=[]}` → 原响应 + `{args_injected:string[], headless:bool}`（引擎侧 `EditorRunBar::play_*(..., p_play_args)` 本就收数组） | **S1** | **M** | **3** |
| **M-4** | **给工具起的游戏子进程指定追踪文件** | 唯一可行路径是**契约里没写**的工程设置键：`project_set_setting{key:"godot_mcp/trace_file", value:"…\\trace-game.jsonl"}`（§B B-3，隐式依赖 I-4）；`editor_play_scene` 只注入端口 | 并入 M-3：`editor_play_scene{trace_file?:string}` → 回显 `trace_file_resolved`；并把 `godot_mcp/trace_file` 写进 `editor_play_scene` 的 `description` | **S2**（§B 自述 + 源码 `mcp_trace.cpp` 优先级注释） | **M** | **4** |
| **M-5** | **一次调用里「边注入输入边连续采样」** | 两次调用绕开：先用 `run_test_scenario{steps:[{type:"input",keycode:"W"}]}`（**只按不松、键状态跨调用保留**——这个语义**没有任何文档**），再 `get_node_property_samples{frame_count:180}`，最后 `pressed:false`。game lineno 9（`ab=88 rb=313`）→ lineno 17（`ab=135 rb=23020 dur=2985`） | 给 `running_game_run_test_scenario` 加采样步：`{type:"sample", node_path:string, properties:string[], frame_count:int, frame_interval?:int}` → `results[i].samples[]`；**或**独立 `running_game_run_scenario_with_samples{steps:[], samples:{node_path,properties,frame_count,frame_interval}}`。**风险**：单响应变大（本用例 3 属性×180 帧 = 23 020 B） | **S1** | **M** | **5** |
| **M-6** | **把 InputMap action 持久化进 `project.godot`** | **没有绕过、也没有工具**：`editor_add_input_action` 回 `{"created":true,"persisted":false,"target":"editor"}`（lineno 200/201；`0075/0076-…response.json` 197/194 B），游戏进程 `action_exists=False`。主路径改走裸 `keycode`（设计上的降级，不阻塞验收） | `editor_add_input_action{action:string, key?:string, events?:[], persist?:bool=true}` → `{created, persisted, project_setting_written:bool}`；或独立 `project_set_input_action{action, events:[{type:"key",keycode,shift/ctrl/alt/…}], persist:true}`。**注意** Godot 4 的 `input/*` 是含 `InputEventKey` 对象的 `Array`，JSON 表达不了 → 需要工具侧构造 | **S1** | **M** | **6** |

### 2.3 ③ 可合并（哪几步高频共现 / 合并后的名与签名草案 / 合并风险）

| # | 高频共现（实测频次） | 合并后的签名草案 | 合并风险（必须保留什么） | 判为「可合并」的理由 | 强度 | 影响 | 序 |
|---|---|---|---|---|---|---|---|
| **C-1** | `editor_save_scene{}` → `project_read_scene_file_content{res://scenes/main.tscn}`：**5 次**（lineno 43→44、85→86、123→124、203→204、233→234，Δ 27-76 ms） | `editor_save_scene{verify?:bool=false}` → 原响应 + `{sha256:string, bytes:int}` | ①丢不掉独立读文件的能力（**保留** `project_read_scene_file_content`）；②`sha256` 必须与读文件工具**同口径**（`PLAYBOOK §3` 的教训：只比读回值不够，要比**文件字节**） | 「保存后立刻自证落盘」在这台试测里是**固定套路**（每次改场景后都做），而引擎/模块一次就能算文件的 sha256 | **S1** | **M** | **1** |
| **C-2** | `editor_open_scene` → `editor_get_scene_tree`：**3 次**（lineno 8→9、57→58、93→94）；`editor_get_scene_tree` 共 10 次 | `editor_open_scene{path:string, include_tree?:bool=false, max_depth?:int=-1}` → 原响应 + `{tree?:{…}}` | 响应会变大（`rb` 从 129 B → 最多 13 412 B，lineno 270）；`include_tree=false` 时行为**逐字不变** | 「打开场景后马上要看树」是**隐式依赖 I-1** 的自然延续（不开场景任何 `editor_*` 节点工具都不可用） | **S2** | **L** | **5** |
| **C-3** | `editor_add_nodes_batch` 被**按深度拆成多批**：共 10 次，其中 3 次 `-32001`（lineno 10/61/62）；开发者用 4 批（6/9/4/5 个）才建完 28 个节点 | `editor_add_nodes_batch{nodes:[…], resolve_within_batch?:bool=true}`（同批内按数组顺序**边建边注册**父节点） | 必须保持**全或无**与「第 i 项失败」的定位（源码已有 `data.batch.{status,errors,rolled_back,on_error}`）；`resolve_within_batch=false` 时保持现语义 | 这不是「两个工具合并」，而是**同一个工具的 4 次调用本可以是 1 次**；引擎 `add_child` 顺序执行天然支持 | **S1** | **H** | **2** |
| **C-4** | `editor_set_node_property` **57 次 = 全部调用的 19.3%**，单段最多 **12 连**（`seq 104-115`）；`project_validate_script` 17 次含**两段 6 连**（`127-132`、`274-279`）；`editor_set_node_script` **8 连**（`133-140`）；`editor_get_node_properties` 15 次（多为单节点单属性） | ①`editor_set_node_property_batch{updates:[{path,property,value}]}` → `{applied:[{path,property,ok,old_value,new_value}], failed:[{index,path,error}]}`；②`editor_get_node_properties_batch{paths:[string], properties?:[string]}` → `{results:[{path,properties}]}`；③`project_validate_scripts{paths:[string]}` → `{results:[{path,valid,message}]}`；④`editor_set_node_script_batch{assignments:[{node_path,script_path}]}` | 每个**必须**保留逐项结果与索引（`nodes[i]` 风格，`editor_add_nodes_batch` 已有此粒度）；**不得**因为一项失败就丢掉其余项的结论（除非显式声明 all-or-nothing） | 这些调用**必然成组**（写多个节点、校验全部脚本、给全部有脚本的节点挂脚本，没有「只做其中一个」的场合）；引擎侧一次遍历即可 | **S1** | **H** | **3** |
| **C-5** | `editor_open_scene` → `editor_get_scene_tree` → `editor_add_nodes_batch` 在每个「改场景」回合都出现（`open_scene` 6 次 + `get_scene_tree` 10 次 + `add_nodes_batch` 10 次） | **不建议**把三步并成一个工具（见 §3「不建议做」）；只做 C-2 + C-3 两个**最小**合并 | —— | 三步并一会在失败时**无法定位**是打开、读树还是建节点失败；Open→Tree 的合并已经覆盖 90% 的价值 | **S2** | **L** | **6** |
| **C-6** | `editor_stop_scene{}` 4 次**连续尾调用**（lineno 294/295/296/297，`ab=2`，`rb=128`） | **不建议合并**（无参幂等调用的重复是调用方脚本的收尾习惯，不是工具面缺陷） | —— | §A C2 要求「必然成对出现」不满足：`stop_scene` 也单独出现（lineno 252/262） | **S2** | **L** | 不建议 |

### 2.4 ④ 可优化（参数 / 返回形状 / 错误消息 / 往返次数；逐条给**最小改动建议**）

| # | 类型 | 现状（实测） | **最小改动建议** | 强度 | 影响 | 序 |
|---|---|---|---|---|---|---|
| **O-1** | 错误消息（对称性） | `Missing required parameter: <name>` 无 `data.suggestion`（96 B / `0014-…`）；`Unknown parameter` 有（271 B / `0015-…`） | 在 `require_*` 的失败路径补 `data.suggestion`（列出该工具的合法参数）——注册器已持有 `inputSchema`，**零成本** | **S1** | **M** | **1** |
| **O-2** | 返回形状（可判定性） | `editor_add_resource_to_node_property` 只回 `{node_path, property, resource_type}`，**没有 `old_value/new_value`**，所以「有没有真的写」不可判定 | 回 `{…, old_value, new_value}`（与 `project_set_theme_color`/`project_set_theme_stylebox` 的 `changed.old/new` 一致） | **S1** | **M** | **2** |
| **O-3** | 参数（持久化开关） | `editor_connect_signal` 无 `persist`；返回无 `persisted` | 加 `persist:bool=true` + 响应 `persisted:bool`；**默认值改变既有行为 → 需决策层确认**（§3） | **S1** | **H** | **3** |
| **O-4** | 契约（schema 缺口） | `editor_simulate_input_sequence.events`、`running_game_play_input_recording.events` 都是**无 item schema 的裸 array** | 补 `items`（`type` 的 enum + 各类事件的字段），或在 `description` 里给一个**完整样例** | **S1** | **M** | **4** |
| **O-5** | 契约（少声明被实现的参数） | `running_game_run_test_scenario.steps[].properties` 少了 `pressed`、`strength`（实现 `running_game_test_execution.cpp:141-148` 用，线上**已有多条成功调用**） | 契约补 `pressed:{type:"boolean"}`、`strength:{type:"number"}`；**改契约要经决策层**（`PLAYBOOK §5`：不得自行改契约） | **S1** | **L** | **5** |
| **O-6** | 契约（未记载的语义） | `running_game_get_node_properties` 对**不存在的名字回 `null`**（源码明文声明，契约未写）；`project_get_settings.prefix` **连 description 都没有**，而 `godot_mcp` 与 `godot_mcp/` 给出**不同结果集**（`rb` 105 vs 254，lineno 3 vs 42/54/90/268） | 两处各补一句 `description`（`prefix` 写明「含分隔符的子串前缀，`godot_mcp/` 与 `godot_mcp` 不同」） | **S1** | **M** | **6** |
| **O-7** | 错误消息（候选路径） | 节点找不到的 20 次失败只回 `Node 'X' not found`（带 `data.suggestion` 指向 `editor_get_scene_tree`，lineno 14-26 等） | 在消息/suggestion 里附**最接近的候选路径**（引擎侧可做最近邻/兄弟匹配）；或至少回「当前场景根下的一级子节点名」 | **S1** | **M** | **7** |
| **O-8** | 参数一致性（跨工具） | 171 条契约里「同一个节点」有 **8 种**参数名：`node_path`(51) / `path`(36) / `name`(20) / `parent_path`(9) / `scene_path`(2) / `source_path`(2) / `target_path`(2) / `player_path`(1)；**编辑器端自身**就分裂：用 `path` 的 36 条 vs 用 `node_path` 的 46 条（如 `editor_set_node_property{path}` vs `editor_set_node_script{node_path}`） | ①`description` 里互相指路（「本工具用 `path`，同族的 X 用 `node_path`」）——**零风险**；②真正统一命名（加别名、老名保留）→ 需决策层，且会动契约 sha | **S1** | **M** | **8** |
| **O-9** | 无界列举 | `editor_list_signal_connections{}` 94 862 B / 434 条（约 432 条编辑器内部） | 加 `scope?:string="scene"`（或 `include_editor_internal?:bool=false`）；保留 `signal_name` 精确过滤 | **S2** | **M** | **9** |
| **O-10** | 往返次数（隐式语义没写） | 「只按不松的键状态**跨调用保留**」是 M-5 绕法成立的前提，**任何地方都没写** | 在 `running_game_run_test_scenario` 的 `description` 里补一句；配合 M-5 的采样步后这段绕法就不再需要 | **S1** | **M** | **10** |
| **O-11** | 取证工具（分析器） | ①`analyze_mcp_trace.py` 的 `mergeable.unigrams[].sequence` 被 `list(gram)` 拆成**字符数组**（`["e","d","i",…]`）；②`bigrams/trigrams` 在 `connection==seq` 的工作流下**恒为空**；③`result_bytes` 含 JSON-RPC `id`（`id=1016` 23 362 B vs `id=1` 23 359 B = 差 3 字节） | ①`shapes()` 里 `sequence` 用 `[gram] if isinstance(gram,str) else list(gram)`；②当 `max(calls/connection)==1` 时退化为**按文件顺序**（或按 `ts_ms` 间隔分簇）算 n-gram 并在输出里**声明退化**；③在文档/摘要里说明 `result_bytes` 是**信封长度**，比较前扣掉 id 长度 | **S1** | **M** | **11** |
| **O-12** | 取证工具（追踪自身） | 同一路径追踪无法分辨「新代已开始」 | `Recorder::open()` 成功后立刻写 `{"event":"trace_opened","pid":…,"existing_bytes":…}`（**≈6 行**），让代次切换/被删**可发现** | **S1** | **M** | **12** |
| **O-13** | 语义陷阱（不建议改） | `editor_setup_collision_shape` 在**你给的节点下**挂 `CollisionShape2D`（传 `Car/Collision` → `Car/Collision/CollisionShape2D`），名字容易被读成「为物理体添加形状」 | 只改 `description` 一句（「在你给的节点下挂一个 CollisionShape2D；要挂在物理体上请传物理体路径」）；**不建议**改行为（响应已如实回 `collision_node_path`） | **S2** | **L** | **13** |

---

## 3. 排序与取舍（证据强度 × 影响面）

### 3.1 建议做（按序）

1. **AN-1 `editor_add_resource_to_node_property` 静默成功**（S1×H）→ §4 D-1，**必修**。
2. **AN-3 `editor_connect_signal` 不持久化**（S1×H）→ §4 D-2，**必修**。
3. **C-3 `editor_add_nodes_batch` 支持同批父子**（S1×H）→ 一次失败换来了 20 次级联失败与 4 次拆批。
4. **C-4 四个批量写/读/校验/挂脚本工具**（S1×H）→ 直接砍掉 19.3% 的单点调用量。
5. **M-1 / M-2 建工程 + 编译 C#**（S1×H）→ 这两条是「没有工具能做」的**真缺口**，也是本次唯一真正的工具外回退（另有 CLI 起进程/M-3）。
6. **O-1 / O-2 / O-4 / O-5 / O-6 契约与消息的最小补齐**（S1×M，零/极低成本）。
7. **M-5 采样步**（S1×M）→ 消掉「键状态跨调用保留」这种**未文档化**的绕法。
8. **O-11 / O-12 分析器与追踪的最小修复**（S1×M）→ 下一轮试测的取证质量直接取决于它们。
9. **AN-9 默认端口（9877）**（S1×H）→ **决策项**：这是**已记录的设计**，但它与「绝不占用用户端口」的纪律直接冲突，需要决策者拍板而非实现者自行改。
10. **M-6 InputMap 持久化**（S1×M）→ 优先级低于 M-1/M-2，因为主路径（裸 keycode）已证明可用。

### 3.2 明确**不建议做**（及理由）

| 不建议项 | 理由 |
|---|---|
| **把 `editor_open_scene → editor_get_scene_tree → editor_add_nodes_batch` 合成一个工具**（C-5） | 三步并一会在失败时**无法定位**是哪一步（§A C2 的硬要求）；而且 `editor_add_nodes_batch` **本身**才是问题所在（同批父子），修它比包一层更有价值。只做 C-2 + C-3。 |
| **合并 `editor_list_signal_connections` 与 `editor_analyze_signal_flow`** | 两者语义**故意不同**（前者含全部连接、后者只收 `CONNECT_PERSIST`），**契约两侧的 `description` 都明文写了**，还互相指路。合并会同时毁掉两种能力。**§A AC-6 要求「答案一致」是判据缺陷，不是工具缺陷。** |
| **改 `editor_get_scene_tree` 的 `max_depth` 默认值**（原 OBS-009 建议） | 契约里默认**已经是 `-1`（无限）**；调用方是**显式**传 6/8/12 的。§C 的这条建议基于错误的归因，**撤回**。 |
| **把 `editor_save_scene` 改成「保存并返回文件全文」** | 会把大响应塞进保存路径（场景 `rb` 已达 6 556 B 且会继续长）。C-1 的 `{verify:true → sha256+bytes}` 更小、更可判定。 |
| **为 AN-8 去改 `mcp_trace.cpp` 的打开语义（改成每次截断/轮转）** | 成因已定位为**测试脚本 `Remove-Item`**，模块的追加语义**恰恰是观察者能 tail 文件的前提**（源码注释说明了为什么必须避开 Godot 的 safe-save）。**只加一行 `trace_opened` 记录**，不要动打开模式。 |
| **单端改 `running_game_get_node_properties` 的 `null` 语义**（AN-2） | 源码明文声明它是**有意行为**且已成调用方契约；单端改成硬拒绝会**破坏已有调用方**。必须先决定「两端统一成哪一侧」，属**决策层议题**。 |
| **现在去改 `editor_analyze_screenshot_diff` 的绝对路径支持**（§B N-6 / §A AC-7 反例） | 契约写的是「路径或 base64」，`user://` 与 base64 都能用；绝对 Windows 路径被拒只是**限制**，本次没有任何工作流因此阻塞（`user://` 一次就成，lineno 265 `ok rb=14759 dur=56`）。低价值，**不做**。 |
| **把 `source_path`/`target_path` 全面重命名成 `node_path`**（O-8 的激进版） | 会动契约 sha 与 171 条逐字门，收益只是手感。**只做 description 级指路**。 |
| **为 `editor_setup_collision_shape` 改行为（自动挂到物理体）** | 现行为**诚实**（回 `collision_node_path`），改名/改行为都会破坏既有调用方；只改一句描述。 |

---

## 4. 疑似缺陷（真缺陷，不是可优化项）

> 三条都是**正确性/诚实性**问题（不是手感）。每条给**可直接粘贴的最小复现**、期望/实际、证据 sha256、严重度。
> **所有复现都测自 `f34ee937f`（D86）**。我没有构造新请求（试测环境已收工，且纪律要求不改任何东西），
> 复现来自**已落盘的真实请求/响应 + 追踪原文 + 源码**三者的交集。

### D-1 ★ `editor_add_resource_to_node_property`：对不存在的属性**报成功、什么都没发生**

**严重度：high**（`PLAYBOOK §7.7` 的 A5 家族；同类混淆在 `running_game_set_node_property` 上已修（TASK-014 D-1），
**编辑器写侧这一条漏了**）

**最小复现（可直接粘贴到 9888）**
```json
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"editor_add_resource_to_node_property","arguments":{"node_path":"Car","property":"physics_material_override","resource_type":"PhysicsMaterial","resource_properties":{"friction":0.1,"bounce":0.0}}}}
```
**期望**：`-32001` + `data.suggestion`（像 `editor_set_node_property` 写 `no_such_property_zzq` 那样，lineno 242）。
**实际**：`ok`，`{"node_path":"Car","property":"physics_material_override","resource_type":"PhysicsMaterial"}`（180 B），
而 `editor_get_node_properties{path:"Car",properties:["physics_material_override"]}` **仍回 `-32001`**。

| 证据 | 值 |
|---|---|
| trace | `trace-editor.jsonl` lineno **186**（`seq=186 ok rb=180 dur=0`）、lineno **240**（`ok rb=180`）；读回 lineno **208/241/254**（`-32001 rb=246/246/247`）；正面对照 lineno 238/239（`Track/WallOuter`，`ok rb=192`/`ok rb=254`） |
| 响应 sha256 | `BC27EB125DADB3505099B40D6AFC1581291A501018B64621A9C9F114AC0E61FC`（0061，Car）、`F11D2D1669A47174DBCE23CF4C5065D761DB8A753454A1CCF43B95069FDF43B9`（0005，Car）、`231EB9440F89665AFCD9C891FCDB64F1EEBE92EE4B8001833915CE4F8445B03F`（0003，WallOuter 正面对照） |
| 属性表 | `AC-8-car-property-list.json` 66 项，**无** `physics_material_override`，sha `A1A5CE6C155245E8F44E68F2D93C92D856C39F82E26A722909082D7459B1E5C7` |
| 源码 | `tools/editor_write_scene_editor.cpp:697` `node->set(property, Variant(resource_ref));`（**无** `object_has_property` 检查）+ `:699-703` 无条件回显；引擎侧 `physics_material_override` 只在 `rigid_body_2d.cpp:754` 与 `static_body_2d.cpp:235`，`CharacterBody2D` 确实没有 |
| 对照 | `editor_set_node_property{path:"Car",property:"no_such_property_zzq"}` → `-32001`（lineno 242，**正确**） |

### D-2 ★ `editor_connect_signal` 报 `connected:true`，但连接**不进 `.tscn`**、运行时不存在

**严重度：high**（调用方能造出「看起来连好了、存盘重开就没了」的场景；本次试测**真的**因此得到一台不会计时的车）

**最小复现**
```json
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"editor_connect_signal","arguments":{"source_path":"HUD/StartButton","signal":"pressed","target_path":".","method":"OnStartPressed"}}}
```
→ `ok {"connected":true,"signal":"pressed","source":"HUD/StartButton","target":"."}`（**响应里没有 `persisted`**）
接着 `editor_save_scene{}` → `ok`，然后读盘：`%TEMP%\mcp-racing-test\scenes\main.tscn`
**4 836 B，sha256 `5892209C13782D417D8EF32F794BF94B7AAEBCDE00F40B1E75345EA8A49B7C3C`，`[connection]` 块数 = 0**。
**期望**：连接随场景保存（工具名/语义都指向「连好了」）。
**实际**：重开即消失；运行时 `pressed` 没有监听者，`LapTimer.Timing` 停在 `false`（直到脚本自己 `Connect`）。

| 证据 | 值 |
|---|---|
| trace | `trace-editor.jsonl` lineno **173/174**（`ok rb=167/179 dur=0`）、lineno **203**（`editor_save_scene ok rb=128`）；证据对 `0048/0049-editor_connect_signal.response.json` |
| 源码 | `tools/editor_node_write.cpp:257` `p_source->connect(p_signal, callable);`（**未传 `CONNECT_PERSIST`**）；`scene/resources/packed_scene.cpp:760`（恢复用 `CONNECT_PERSIST`）与 `:1238`（**只序列化带该位的连接**）；`grep CONNECT_PERSIST modules/mcp_server/tools/**` = **0 命中** |
| 运行时后果 | 游戏日志 `%APPDATA%\Godot\app_userdata\mcp-racing-test\logs\godot2026-09-23T23.18.32.log:10-42`（`Attempt to connect nonexistent signal 'speed_changed' …`，脚本侧）；`Main.cs` 自己连按钮后同一套调用才全绿（§B §3③） |
| 对照 | `editor_add_input_action` **老老实实**回 `persisted:false`（lineno 200/201，`0075/0076-…response.json`）——`editor_connect_signal` 连这个诚实字段都没有 |

### D-3 ★ `running_game_get_node_properties` 对**不存在**的属性静默回 `null`，与其同端点的写工具结论相反

**严重度：medium**（不会写坏数据，但会让调用方**以为属性存在**；`PLAYBOOK §7.7` 明确要求区分「拒绝」与「按引擎语义给默认值」）

**最小复现（同一节点、同一端点，两条请求的答案互相矛盾）**
```json
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"running_game_get_node_properties","arguments":{"node_path":"/root/Main/Car","properties":["physics_material_override","collision_layer"]}}}
```
→ `ok`：`{"node_path":"/root/Main/Car","properties":{"collision_layer":1,"physics_material_override":null},"type":"CharacterBody2D"}`
```json
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"running_game_set_node_property","arguments":{"node_path":"/root/Main/Car","property":"physics_material_override","value":1.0}}}
```
→ `-32001 Property 'physics_material_override' on node '/root/Main/Car' not found`
**期望**：两端对「这个名字是不是属性」给出一致答案（要么都拒绝，要么都在契约里说明 get 的 null 语义）。
**实际**：get 说「有，值是 null」，set 说「没有」。

| 证据 | 值 |
|---|---|
| trace | `trace-game.jsonl` lineno **2**（`seq=2 id=90003 ab=91 rb=214 ok`）vs lineno **20/22**（`seq=20 ok rb=191`、`seq=22 -32001 rb=228`） |
| 响应 sha256 | `E863485EA43B5943A80D4CD3DCDA393B092034F82D674FBF8EF8174CD51A8849`（214 B，`game-pmo.res.json`） |
| 源码 | `tools/running_game_observation.cpp:167-168`（注释**明文**：「A name the node does not have at all still answers `null` - that is this tool's documented named-path behaviour and is not changed here」）+ `:194`（无条件 `r_out[name] = serialize_variant(p_node->get(name));`）vs `tools/running_game_node_write.cpp:1158`（写侧 `object_has_property` 检查） |
| 契约 | `running_game_get_node_properties.description` **未**记载这个 null 语义（只说「不传则返回所有属性」） |

> **本节之外：诚实性澄清（不是缺陷）**——`OBS-022` 怀疑的「`editor_add_resource_to_node_property` 报成功后游戏读到旧值 → 是不是写入失败」
> **不成立**：`seq=240/241` 之后到 `seq=246`（`play_scene`）之间**没有任何 `editor_save_scene`**，
> 游戏读到的是**未包含这些写入的磁盘场景**。**不要**把它当 A5 证据（真正的 A5 是 D-1 的读回路径，与游戏无关）。

---

## 5. 结论锚点与自我声明

1. **锚点（D86）**：本文件**全部**结论测自 `feature/mcp-server-module` 的
   **`f34ee937f3d31c49ac42081bb91433c5fc5b36e3`**，引擎自报 `4.8.dev.mono.custom_build.f34ee937f`。
   凡引用 §A/§B/§C 的结论，均已在本文档内**复算**并标注；不一致处逐条纠错（§1、§1.1、§1.2）。
2. **我自己的产物**：本文件；复算脚本与输出在 `%TEMP%\mcp-findings\`（`verify_trace.py`、`recompute.py`、
   `survey.py`、`evidence_chain.py`、`final_checks.py`、`contract*.py`、`dump.py` 及对应 `*.txt/json`）。
3. **未做的事**（诚实声明）：
   - **未修改** `modules/mcp_server/**` 任何实现、测试、契约、脚本（§6 AC-12 复测为空）；
   - **未启动/杀死**任何引擎进程，**未**占用 9888/9889，**未**触碰 9877（只跑了一次 `netstat`：当前无监听）；
   - **未**为了「凑一条 A5/A7」而构造新请求——所有复现都来自**已落盘证据 + 追踪原文 + 源码**；
   - 因纪律禁止，**未**在「9877 空闲」时复现 AN-9 的「会被真的占用」（标**推断**）；§B 的 `E-2`（headless **编辑器**截图）
     与 §A 的可选分支 N/A/T/P **仍未测**（沿用 §B R-2/R-4/R-5）。
4. **本次试测没查成、需要下一轮补的**：
   - `AN-8` 的**因果**仍属强推断（脚本 `Remove-Item` 是唯一能找到的删除者，但没有一步到位的单次实证）；
   - §A §4.1 `A8`（同参连续 N≥3 次的**不确定性**）本会话**没有合格实例**：所有同参重复调用都**逐字一致**
     （`editor_save_scene` 5 次 `rb=128`；`editor_get_scene_tree{max_depth:12}` 3 次 `rb=12308`；
     `tools/list` 两次 **payload 逐字相同**、只差 JSON-RPC `id` 长度）——这是**确定性正面结论**；
   - §B `B-e` 的「`project_validate_script` 对 `.cs` 是否真的编译」需要一个**新探针**（例如同一 `.cs` 里放一个
     **语法**错误，看 `valid` 是否变 `false`），本会话的证据**不足以判定**。

---

## 6. AC-12 复测（模块未被试测改动）

| 检查 | 我这次实测 | 与 §A §0 对照 |
|---|---|---|
| `git status --short modules/mcp_server/tools modules/mcp_server/tests` | **空** | ✅ |
| `docs/tools_list.renamed.json` sha256 | `C844EC8AF9EF00D2E6EC7008C9806B3E2B16757E78794D3CCCA0704EDF844256`（110 770 B） | ✅ 逐字相同 |
| `docs/tool-groups.json` sha256 | `0CFCAC80F0D999FA7DB713AE48F43FEBE96AE52E2C93633257EEED00FFDFBFAC` | ✅ 逐字相同 |
| `git rev-parse HEAD` | `f34ee937f3d31c49ac42081bb91433c5fc5b36e3` | ✅ 未变 |
| 工作树其余未跟踪物 | `.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd` + §A/§B/§C 三份报告与其 `evidence/racing/`（+重灾可见的 `docs/reports/RACING-FINDINGS.md` 本文件） | 与 §A §0 / `PLAYBOOK §5` 一致（**报告不是实现**） |
