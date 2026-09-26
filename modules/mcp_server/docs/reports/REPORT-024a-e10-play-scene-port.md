# REPORT-024a — 顺手性 E-10：`editor_play_scene` 注入 `--mcp-port`

> 任务书：`docs/tasks/TASK-024a-e10-play-scene-port.md`（单点任务，只做 E-10）。
> 通用规范：`docs/tasks/PLAYBOOK-group-port.md`（已完整阅读）。
> 工作树：`feature/mcp-server-module`；实现提交 `485353e8a8` + `76f78f82b9`；**未 push**。
> 验证二进制：`bin\godot.windows.editor.x86_64.console.exe`，`--version` = `4.8.dev.custom_build.76f78f82b`
> （= `git rev-parse --short HEAD` `76f78f82b9` 的前 9 位；`scripts/build_local.cmd -Force`，`tests=yes`）。

**status：完成**（六道门全绿；E-10 专有实测证据 31/31 通过）。

## 1. 提交

| sha | 说明 |
|---|---|
| `485353e8a8` | `TASK-024a E-10: editor_play_scene injects --mcp-port into the game child` —— 契约 override + 重生成 + 生成器版本 1.5.0→1.6.0 + `tools/editor_playback.{h,cpp}` 实现 + doctest |
| `76f78f82b9` | `TASK-024a E-10: live evidence script and comment accuracy` —— 实测脚本 `scripts/mcp024a_e10_play_scene_evidence.ps1` + 注释准确性修正 |
| （本报告） | `docs(reports): REPORT-024a`（文档提交，构建不依赖它，见 §7 注） |

## 2. 逐工具表

本任务**不新增工具**（仍 113/171）。改动只落在既有 `editor_playback` 组的 `editor_play_scene` 上（`editor_stop_scene` 代码未动，只被回归证据覆盖）。

| new_name | 迁移源（仅类别参考） | 引擎依据（第一参考源） | 自然契约（as implemented） | C++ 落点 | 与迁移源差异及理由 |
|---|---|---|---|---|---|
| `editor_play_scene` | `godot_mcp_gdext/src/commands/scene.rs:126-149`（`cmd_play_scene`：无参数，只调 `play_*`） | `EditorRunBar::play_main_scene/play_current_scene/play_custom_scene(..., const Vector<String> &p_play_args)`（`editor/run/editor_run_bar.h:123-125`）→ `_run_scene(path, p_run_args)`（`editor_run_bar.cpp:427/444/446/459`）→ `EditorRun::run(..., p_run_args)`，后者把每个参数**原样**追加到子进程命令行（`editor_run.cpp:157-161`）。`EditorInterface::play_*` **不转发**运行参数（`editor_interface.cpp:815-825`），故不能再用它 | 入参：`mode`（可选，默认 `main`，`main`/`current`/项目场景路径）、**新增** `mcp_port`（可选整数 1..65535）。返回：`playing`、`mode`、(`path`)、**`mcp_port`**、**`mcp_port_source`**∈{`argument`,`auto_free_port`}、**`endpoint`**=`http://127.0.0.1:<port>/mcp`、**`pid`**。错误：越界/类型错 → `-32602`；路径不存在 → `-32001`；指定端口被占/是编辑器自身端口 → `-32000`+`data.suggestion`；非编辑器进程 → `-32000`+suggestion；**子进程没起来 → `-32000`（不报成功）** | `tools/editor_playback.cpp`（`_tool_play_scene`、`MCPTools::is_usable_game_port` / `port_is_bindable` / `pick_free_game_port`、`_editor_mcp_port`）；声明在 `tools/editor_playback.h`；注册块由 `scripts/gen_b2_game_schema.py --group editor_playback --in-place` 从新契约重生成 | ①迁移源没有端口概念，本任务按引擎能力补上（GDR-23 §21 第 4 条「一趟能做的事不要拆成两趟」）；②自定义路径只接受归一后的 `res://`（迁移源用 `file_exists` 放行绝对路径）——沿用既有决定，未改；③`playing:true` 的含义从「调了 play_*」升级为「**读回**确有新子进程」（迁移源/旧实现都是无条件 true） |

### 引擎路径确认（任务书要求「自己确认这条路径在本 fork 下可用」）

- `editor_run_bar.h:123-125` 确有 `p_play_args` 形参；`editor_run_bar.cpp:427/444/446/459` 把它交给 `_run_scene`；`_run_scene`（`editor_run_bar.cpp:255-364`）在 `editor_run.cpp:355-364` 处 `editor_run.run(...)`。
  实测反证更直接：**子进程命令行里真的出现了 `--mcp-port=<端口>`**，且子进程**真的在该端口监听**（§5）。
- 走 `EditorRunBar` 单例而非 `EditorPlugin::run_scene` 钩子是对的：内置模块拿得到 run bar 单例，且 `EditorInterface::play_*` 无法表达运行参数。
- `editor_stop_scene` 仍走 `EditorInterface`（其 `stop_playing_scene()`/`is_playing_scene()` 是 run bar 的一行转发，`editor_interface.cpp:827-833`），行为未变。

### 端口来源与选择逻辑

1. `mcp_port` **给了**：`mcp_port_source = "argument"`。先判范围（1..65535，`0`/负数/越界 → `-32602`），再判可用性：
   - `mcp_port == 编辑器自身端口`（`MCPServer::get_singleton()->get_port()`，**实际绑定端口**而不是配置值）→ `-32000`「is the port this editor's own MCP server is listening on」；
   - 否则 `port_is_bindable(port)`（在 `127.0.0.1` 上以 `TCPServer` 试绑并立刻释放，与 MCP 传输自身绑定同一地址/同一 API）失败 → `-32000`「not free on 127.0.0.1（another process is listening on it）」。
     两个拒绝都带 `data.suggestion`，且**不会启动任何子进程**（实测 `stop_scene` 随后回 `stopped:false`）。
2. `mcp_port` **没给**：`mcp_port_source = "auto_free_port"`。`pick_free_game_port(editor_port, err)`：`TCPServer::listen(0, "127.0.0.1")` 让内核挑，`get_local_port()` 读回，**立刻释放**（端口必须由子进程持有），并用纯函数 `is_usable_game_port(candidate, avoid)` 排除 `0/越界/编辑器自身端口`；8 次都拿不到 → `-32603`（诚实失败，不降级）。
   - Windows 上这个探测是**可信的占用判定**：`NetSocketWinSock::set_reuse_address_enabled()` 在 Windows 上是**故意空实现**（`drivers/windows/net_socket_winsock.cpp:549-554`：「SO_REUSEADDR in this magical world means SO_REUSEPORT」），所以第二次 bind 同一端口会真的 `ERR_ALREADY_IN_USE`。doctest 用「占住→探测说否→释放→探测说是」把这条钉死了。
3. 子进程侧：`--mcp-port=<端口>` 由 `MCPPort::parse`（`mcp_server.cpp:77-91`）读取，`explicit_cmdline=true` 使游戏进程**即使没有** `godot_mcp/enabled_in_game` 也会监听（`MCPPort::should_listen`，REQUIREMENTS C4）——这正是「无需改被测工程」的机制。

### 「不得假装成功」

`EditorRunBar::play_*` 返回 `void`，`_run_scene` 有 4 条静默早退（recovery mode、已有播放器、缺 `project.godot`、自定义目录被拒）。实现**读回**结果而不是假设：

* 调用前记下 `get_current_process()`；调用后要求 `is_playing()`（只有 `EditorRun::run()` 走到 `status = STATUS_PLAY` 才为真，而它只在每个 `OS::create_instance` 返回 OK 时才走到）**且** 子进程 pid 变了；否则 `-32000`。
* 诚实边界（已写进契约描述与代码注释）：它**不**等待子进程完成 bind——子进程是另一个进程，工具不会阻塞编辑器主线程。因此「`playing:true` + pid」= 「命令行参数已注入且新子进程确已创建」，而不是「游戏已经在监听」。§5 的闭环证据（起游戏→连端口→跑游戏侧工具）证明该端口的实际可用性。

## 3. 契约变更（只走 override，未手改契约文件）

* 生成器 `scripts/gen_renamed_contract.py`：`GENERATOR_VERSION` `1.5.0` → **`1.6.0`**；新增 `DESCRIPTION_OVERRIDES["play_scene"]`（**append** 模式，原文「运行场景」逐字保留在句首）与 `SCHEMA_OVERRIDES["play_scene"]`（**replace** 模式 + 理由里逐字引用被移除的 `required` 成员 `[]`）。v1.6 段落已写入脚本 docstring。
* 重生成命令：`python modules/mcp_server/scripts/gen_renamed_contract.py` → 输出 `output sha256 = 13bae3beedc79590f89568ffe6f6682732e12a1d66526c5c7f34a13a4fb887a9`（文件 sha256 `C5120948…`）；`overrides = 11`，其中 `description/play_scene:append`、`inputSchema/play_scene:replace`。
* `git diff` 只动了 `play_scene` 一条的 `description`/`inputSchema` + `_meta.generator_version` + 两条 override 记录（18 insertions / 2 deletions），**没有**任何别的工具被改动——这正是「没有绕过 override」的机器证据。
* C++ 注册块由生成器重生成：`python modules/mcp_server/scripts/gen_b2_game_schema.py --group editor_playback --in-place tools/editor_playback.cpp`（`--in-place` 路径相对 **模块根**，不是仓库根；传错会 `FileNotFoundError`——已在报告里记录，脚本行为未改）。
* **指纹**：`_meta.generator_version = 1.6.0`；`_meta.generated_from_sha256`（旧契约 `8f8051c4…`，冻结值未变）、`_meta.map_sha256 = 2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd`（映射未改）、`_meta.order_normative=false`、`_meta.overrides` 11 条。
* **`TOOL-NAMING.md` 不需要重新渲染**：它由 `docs/scripts/gen_table.py` 从 `tool-rename-map.json` 渲染（不读契约），本次没有改映射，故 `git diff modules/mcp_server/docs/TOOL-NAMING.md` 为空。机器证据：`python modules/mcp_server/docs/scripts/gen_table.py --check-only` **exit 0**（`DETERMINISM render run#1 == run#2 byte-identical (95673 bytes): PASS`；文件 sha256 `CE9BC325…`）。
* 附加一致性：`python modules/mcp_server/docs/scripts/check_rename_map.py` → `RESULT: PASS (all checks green)`，exit 0（171 条、名字唯一、合并/注销集合正确、契约数 == 174-2-1）。

## 4. 红/绿证据（真实输出）

红（只加测试、未改实现，`build_local.cmd -Force` 后 `--headless --test --test-case="*TASK-024a*"`，log sha256 `15EB5713…`）：

```
.\modules/mcp_server/tests/test_mcp_server.h(13511): FATAL ERROR: REQUIRE( properties.has("mcp_port") ) is NOT correct!
  values: REQUIRE( false )
.\modules/mcp_server/tests/test_mcp_server.h(13513): ERROR: CHECK( (String)mcp_port["type"] == "integer" ) is NOT correct!
  values: CHECK( <null> == integer )
.\modules/mcp_server/tests/test_mcp_server.h(13530): ERROR: CHECK( error.code == -32602 ) is NOT correct!
  values: CHECK( -32000 == -32602 )      （×4：0 / 70000 / -1 / 字符串 "9889"）
[doctest] test cases:  1 | 0 passed |  1 failed | 1624 skipped
[doctest] assertions: 18 | 8 passed | 10 failed
[doctest] Status: FAILURE!            （exit 1）
```

绿（最终二进制，log sha256 `64AE8758…`）：

```
[doctest] test cases:  2 |  2 passed | 0 failed | 1624 skipped
[doctest] assertions: 44 | 44 passed | 0 failed
[doctest] Status: SUCCESS!            （exit 0）
```

**红测试真的抓到了实现缺陷**：第一版实现用 `requested_port != 0` 兼作「未给端口」的哨兵，于是显式 `mcp_port: 0` 被静默接受（走自动端口分支）。红阶段用例 `out_of_range_zero_is_-32602` 让它暴露，改为单独判定「参数是否存在」（显式 `null` 仍按缺省处理，与模块其它 `optional_*` 一致）后才变绿。

## 5. 门与证据

### 门① 契约子集逐字（`check_contract_subset.ps1 -Group editor_playback`）—— exit 0，3/3

```
[PASS] editor_9888_contract_subset   editor port=9888 tools=91
       editor_play_scene: name=True description=True inputSchema=True | editor_stop_scene: name=True description=True inputSchema=True
[PASS] game_9889_contract_subset     game port=9889 tools=53
       editor_play_scene: correctly absent on the game endpoint | editor_stop_scene: correctly absent on the game endpoint
[PASS] guard_user_port_9877          pid_before=36392 pid_after=36392
3/3 checks passed        （log sha256 18C005D9…）
```

### 门⑥ 收窄点清单（`python scripts/check_narrowing_points.py`）—— exit 0

```
[gate    ] tools/tool_helpers.cpp:851  G24-THE-GATE  const float narrowed = (float)value;
PASS: every narrowing point of the module is annotated and pinned
（log sha256 E3768A5D…）
```

本次新增代码**没有新增收窄点**（无 `(real_t)`/`(float)`/`Color(`/`Vector2(`… 构造）。注意：`tool_helpers.cpp:851` 的 pin **保持 851 不变**（见 §6 第 4 项）。

### 门③ 模块 doctest（`--headless --test --test-case="[MCPServer]*"`）—— exit 0

```
[doctest] test cases:  197 |  197 passed | 0 failed | 1429 skipped
[doctest] assertions: 7861 | 7861 passed | 0 failed
（基线（REPORT-023）195 例 / 195 passed / 7817 断言 → 本任务 **+2 例 / +44 断言**，passed 只增不减；log sha256 C049F98B…）
```

### 门④ 全引擎回归（`--headless --test`）—— exit 0

```
[doctest] test cases:   1623 | 1623 passed | 0 failed | 3 skipped
[doctest] assertions: 432143 | 432143 passed | 0 failed
（log sha256 022B944A…）
```

### 门⑤ 每批收口（`accept_m1.ps1` 连跑两次）—— 两次 exit 0，PASS 清单一致

```
run1: 22/22 cases passed   （log sha256 DCAE7A94…）
run2: 22/22 cases passed   （log sha256 913A9060…）
run1_pass=22 run2_pass=22 identical=True
implemented tools = 91 (editor endpoint) / 53 (game endpoint); contract = 171
```

### 门② 三类证据 + 跨工具链 + E-10 实测（`scripts/mcp024a_e10_play_scene_evidence.ps1`）—— **31/31 PASS，exit 0**

```
31/31 checks passed; evidence in C:\Users\wyl\AppData\Local\Temp\task024a-e10\evidence
（log sha256 B8471A47…；请求体一律 ConvertTo-Json + curl.exe --data-binary @file，
 响应体一律 curl.exe -s -o <file>，每个响应都有 sha256）
```

**逐工具三类证据（真实请求/响应原文）**

`editor_play_scene`：

| 类 | 请求（要点） | 响应原文 | 证据 sha256 |
|---|---|---|---|
| 成功（指定端口） | `{"mode":"main","mcp_port":19890}` | `{"endpoint":"http://127.0.0.1:19890/mcp","mcp_port":19890,"mcp_port_source":"argument","mode":"main","pid":64148,"playing":true}` | `ED606E9E…` |
| 成功（自动端口） | `{"mode":"main"}` | `{"endpoint":"http://127.0.0.1:57389/mcp","mcp_port":57389,"mcp_port_source":"auto_free_port","mode":"main","pid":9648,"playing":true}` | `D8A7B485…` |
| 缺参/坏参 → `-32602` | `{"mcp_port":"19890"}` | `{"code":-32602,"message":"Parameter 'mcp_port' must be an integer, got String"}` | `93488F44…` |
| 坏值 → `-32602`（0/99999/-1 三条） | `{"mcp_port":0}` 等 | `{"code":-32602,"message":"Parameter 'mcp_port' must be between 1 and 65535, got 0"}`（另两条 got 99999 / got -1） | `22FF4EE7…` / `7CDFFD98…` / `ADB3A4D1…` |
| 底层失败 → `-32001` | `{"mode":"res://scenes/nope.tscn",...}` | `{"code":-32001,"data":{"suggestion":"Use project_get_filesystem_tree to list the .tscn files of the project"},"message":"Scene 'res://scenes/nope.tscn' not found"}` | `C294200E…` |
| 底层失败 → `-32000`（端口被占） | `{"mcp_port":19891}`（本脚本用 `TcpListener` 真实占住 19891） | `{"code":-32000,"data":{"suggestion":"Pass a free mcp_port, or omit mcp_port to let the tool pick a free one for the game child"},"message":"mcp_port 19891 is not free on 127.0.0.1 (another process is listening on it)"}` | `5069A262…` |
| 底层失败 → `-32000`（编辑器自身端口） | `{"mcp_port":9888}` | `{"code":-32000,…,"message":"mcp_port 9888 is the port this editor's own MCP server is listening on"}` | `73FB8208…` |
| 路径越界 → `-32602` | `{"mode":"C:/outside/scene.tscn"}` | `{"code":-32602,"message":"Parameter 'path' must address the project ('res://...'), got 'C:/outside/scene.tscn'"}` | `976BF305…` |

`editor_stop_scene`：

| 类 | 请求 | 响应原文 | 证据 sha256 |
|---|---|---|---|
| 成功（有游戏在跑） | `{}` | `{"message":"Playback stopped","stopped":true}` | `12F75A2C…` |
| 成功（没东西可停，语义上不是失败） | `{}`（两次拒绝之后） | `{"message":"No scene playing","stopped":false}` | `D676DDBC…` |
| 缺参 → `-32602` | **不可构造，已声明**：该工具 `inputSchema.properties = {}`、`required = []`（无参数），没有「缺参」这一类别；传未知多余键按模块通用规则被忽略，不产生参数错误 | — | — |
| 底层失败 | **不可构造，已声明**：它的失败分支是「非编辑器进程 → `-32000`」，而工具只在编辑器端点注册（9889 上 `tools/list` 里根本没有它，见门①），从编辑器端点**无法**在线上触发该分支；其可观测的「状态」维度由 `stopped:true/false` 两条覆盖 | — | — |

**跨工具端到端活证据链（零字符串手术，PLAYBOOK 门②+ GDR-23 §21 第 4 条）**

`editor_open_scene(res://scenes/other.tscn)` → `editor_play_scene({"mode":"res://scenes/other.tscn","mcp_port":19893})` → 立刻对 **19893** 调 `running_game_get_scene_tree` → 把返回的 `tree.path` **原样**喂给 `running_game_get_node_properties`：

```
chain.scene_tree        : {"tree":{"name":"Other","path":"/root/Other","type":"Node2D"}}            sha256 231A83E1…
chain.node_properties   : {"node_path":"/root/Other","type":"Node2D","properties":{...}}            sha256 C63DB302…
调用方字符串处理次数：0（4 步：产出型→消费型 1 次，路径直接透传；无 uid↔res 转换、无 @EditorNode@ 剔除、无格式改写）
```

**E-10 的硬证据：子进程 cmdline 真的含 `--mcp-port`**

```
F:\RustProjects\godot-mcp-pro\code\godot\bin\godot.windows.editor.x86_64.exe
  --path C:/Users/wyl/AppData/Local/Temp/task024a-e10/proj
  --remote-debug tcp://127.0.0.1:6007 --editor-pid 64576
  --scene res://scenes/main.tscn "--mcp-port=19890"          ← 指定端口
  （自动端口那次为 --mcp-port=57389；current 为 19892；路径模式为 19893 + --scene res://scenes/other.tscn）
```

（取自 `Get-CimInstance Win32_Process` 的 `CommandLine`，pid 与工具响应里的 `pid` 同一个；三次 spawn 都核对过。）
改动前该位置只有 `--path/--remote-debug/--editor-pid/--scene`（任务书引述的 REPORT-AUDIT-M4c D-13）。

**「起游戏 → 立刻观察」闭环**：`play_scene` 返回 → 端口 `Wait-ForPort` 通过 → 对 **该端口** 调游戏侧工具：

```
running_game_get_scene_tree.explicit  sha256 494A1092…
  {"tree":{"name":"Main","path":"/root/Main","type":"Node2D","children":[{"name":"Marker","path":"/root/Main/Marker","type":"Node2D"}]}}
running_game_get_scene_tree.auto      同一响应体 sha256（内容一致）
```

**端口选择与冲突处理（任务书 §2.3）**

* 指定 19890 → `mcp_port=19890`、`mcp_port_source=argument`、子进程 cmdline 含它、**真的在 19890 上接受连接**并回答了游戏侧工具。
* 缺省 → `mcp_port=57389`（`auto_free_port`），**≠ 编辑器端口 9888**，**真的可用**（同一条闭环证据）。
* 指定被占端口 19891（脚本用真实 listener 占住，`netstat` 确认占用者就是脚本自身 pid）→ **诚实报错 `-32000` + suggestion**，且**没有启动任何游戏**（随后 `editor_stop_scene` 回 `stopped:false`）。
* 指定编辑器自身端口 9888 → **诚实报错 `-32000`**（专门措辞与建议）。**没有**出现「回退到别的端口」这种静默改口径的行为：要么用你给的，要么明确拒绝。

**响应字段与真实一致性（任务书 §2.4）**：`mcp_port`/`mcp_port_source`/`endpoint`/`pid` 四项每次都核对过——`endpoint` 字符串与 `mcp_port` 一致，`pid` 指向**真实存活**的进程（`Get-Process`）且其 cmdline 含同一端口，`stop_scene` 后该 pid 消失（`stop_scene_kills_child` / `auto_stop_scene_kills_child` / `no_orphan_after_chain` 三条）。

**三种 `mode` 回归（任务书 §3）**：`mode_main_ok` / `mode_current_ok` / `mode_path_ok` 三条全过——每次都给「响应 + 实际 cmdline + 端口真的在监听」三件套；`current` 前先用 `editor_open_scene` 打开 `res://scenes/other.tscn`；路径模式额外核对响应里的 `path` 与 cmdline 里的 `--scene`。

**环境纪律**：全程只读写 9877 的 listener pid（`pid_before=36392 pid_after=36392`，两次都通过）；本任务使用的端口是 9888（编辑器）与 19890/19891/19892/19893 + 一次内核分配的空闲端口；所有脚本只杀自己启动的进程；`--import` 与不需要服务的引擎运行一律加 `--mcp-port=0`，**不尝试**绑定 9877。未 push。

### 关键文件 sha256

| 文件 | sha256 |
|---|---|
| `tools/editor_playback.cpp` | `3C2E687C7868AC1B064EEFDA897FF2A59F9162A4A32D219A1BF5AC204BCE2E3A` |
| `tools/editor_playback.h` | `D5335192DE575EEF4C71EC964991A7C85F3605B69DEE2DB0CE7B5151006CF823` |
| `scripts/gen_renamed_contract.py` | `09AC0B942F145DCF298577BC73F7D739C649B80148B0ADC5932C12DE8F848774` |
| `docs/tools_list.renamed.json` | `C5120948F0D621BBEC90DF430BD902D5BFFF2A230730A44D2A7F938477354FC6`（生成器自报 `output sha256 = 13bae3beedc79590f89568ffe6f6682732e12a1d66526c5c7f34a13a4fb887a9`） |
| `tests/test_mcp_server.h` | `2F76CF7FA510A914A1D9CEB088EFB4D822003259CDCE9474EEEFB8CB48395164` |
| `scripts/mcp024a_e10_play_scene_evidence.ps1` | `BA5A3115525D46241A196DD8AE251F60C38CF77805D598F46F8CB55AC2310DF7` |
| `scripts/check_narrowing_points.py`（**未改**） | `5CEEE0C935E951590A4A318730184EEC0E8ACBE49751479A66D914E20534D4CF` |
| `docs/TOOL-NAMING.md`（**未改**） | `CE9BC325699CAE6CFAEC104D1E3477E91D78A5440F8893366CC030C03C36C975` |

## 6. 半成品补丁的采纳/丢弃说明（逐项）

参考件：`C:\Users\wyl\AppData\Local\Temp\task024-partial.patch`，36186 B，sha256 `9F1AFDEBD621B569AB73612646C3CFE0417F45C0481ADDE0422EB105BD1F153F`（**未验证**，且**不含工具侧代码**）。逐节处置：

| # | 补丁中的位置 | 处置 | 理由 |
|---|---|---|---|
| 1 | `docs/DESIGN-DETAIL.md`：新增 GDR-25 行 + §23（53 行，顺手性判据与日志来源） | **丢弃** | ①那是 TASK-024 **整批**（E-1/E-3/E-6/E-9）的规范文字，不是 E-10 的；②PLAYBOOK §7.2 明确「规范由决策者维护；实现者只写报告」，任务书也要求「不得新建规范/决策文档」；③TASK-024a §1.5 只要求 override + 重生成 + TOOL-NAMING + 指纹。**副作用已处理**：补丁里 `play_scene` 的 override 理由引用了「GDR-25 §23.1 第 4 条」，而该节在现规范里**不存在**（`DESIGN-DETAIL.md` 最后一节是 §22/GDR-24）——我把引用改成只引 **GDR-23 §21 第 4 条**（真实存在），避免悬空引用。 |
| 2 | `docs/tools_list.renamed.json`（重生成结果） | **采纳机制、内容自己重生成** | 契约必须由生成器产出（不得手改）。内容按 §3 重写：补丁的描述写「响应在**游戏真的起来后**给出…」——这是**过度承诺**：工具不等待子进程 boot（子进程 bind 是异进程行为），故改为「在**确认子进程已创建后**给出…，子进程没起来则不报成功」，并补上「越界/被占/编辑器自身端口会被拒绝」。schema 描述文本也改为与我的失败语义一致。 |
| 3 | `scripts/gen_renamed_contract.py`：`GENERATOR_VERSION` 1.5.0→1.6.0 | **采纳** | 契约内容变化必须伴随生成器版本变化（指纹）。v1.6 docstring 段落自己写（补齐机制说明）。 |
| 4 | 同文件：`DESCRIPTION_OVERRIDES["play_scene"]` | **采纳结构、文字重写** | append 模式（原文逐字留首）正确且被生成器的 `startswith(old + " ")` 守卫强制。补丁注释说这是「第八个描述 override」——**计数错误**（现有 8 条，`play_scene` 是第 **9** 条）；我按实际写。 |
| 5 | 同文件：`SCHEMA_OVERRIDES["play_scene"]` | **采纳结构、理由重写** | `mode="replace"` + 理由里逐字引用 `[]` 是 v1.5 守卫的硬要求，补丁做法正确；理由文字改为我自己的（说明「移除的是一个空列表」）。 |
| 6 | `scripts/check_narrowing_points.py`：`tool_helpers.cpp` pin `851 → 1000` | **丢弃** | 本树里该收窄点就在 **851**（门⑥ 用 851 通过，exit 0）；1000 是 TASK-024 的 E-1/E-6 改动把 `tool_helpers.cpp` 撑长后的行号。本任务不改该文件。 |
| 7 | `tests/test_mcp_server.h`：E-1/E-3/E-9/E-6/G-4 的 doctest（数百行） | **丢弃** | 属 TASK-024 的其它 4 项，不在本任务范围；混进来会让「本组门」验证无关行为。 |
| 8 | 同文件：`#include "core/io/tcp_server.h"` | **采纳** | 我的 doctest 需要 `TCPServer`（并额外加了 `../tools/editor_playback.h`）。 |
| 9 | 同文件：`TASK-024 E-10: an ephemeral TCP port can be probed in this process` | **采纳并加强** | 只钉「机制存在」太弱（子代理无法触达 file-private）。我把它替换为**决定性**用例：纯函数 `is_usable_game_port` 的边界表 + `port_is_bindable` 的「占住→否，释放→是」+ 自动端口的范围/可绑定/≠avoid。 |
| 10 | 同文件：`TASK-024 E-10: editor_play_scene validates mcp_port before anything is started` | **采纳（几乎原样）** | 期望值（`-32602` 早于编辑器守卫；`'mcp_port' must be an integer`；`between 1 and 65535`）与我的实现一致；这条红测试**真的抓到了**我第一版的 `mcp_port: 0` 缺陷。 |
| 11 | 补丁中**缺失**：`tools/editor_playback.{h,cpp}` 的工具侧实现 | **必须自己写** | 补丁从未包含它（任务书已说明）。本报告 §2/§5 的全部实现与证据均由我完成。 |

## 7. deviations / blockers / next_step_recommendation

**deviations（与手册/任务书的偏离，逐条显式列出）**

1. **没有改 `docs/DESIGN-DETAIL.md`**（丢弃补丁 §1）：本任务只做 E-10，规范由决策者维护。若决策者希望把补丁里 GDR-25/§23 的**整批**顺手性判据纳入规范，那是 TASK-024 其余 4 项的工作。**当前状态**：`play_scene` 的 override 理由只引真实存在的 GDR-23 §21 第 4 条。
2. **`TOOL-NAMING.md` 未重新渲染**（任务书 §1.5 提到「重渲染」）：它从 `tool-rename-map.json` 渲染而非从契约渲染，映射未改，重渲染是**字节级空操作**。已用 `gen_table.py --check-only`（exit 0，两次渲染 byte-identical）机器证明，而不是只在报告里断言。若决策者要求「无论是否变化都重写一次」，成本为零，但会制造一个无内容的 diff。
3. **对「指定端口」增加了任务书未明写的预检**：指定端口若被占或等于编辑器端口 → `-32000`（任务书 §2.3 允许「诚实报错或明确回退」，我选**明确报错并解释**，不静默回退）。理由：不做预检就会出现「`playing:true` 但端口连不上」——正是本任务第 4 条禁止的假装成功；且能防止把用户的 9877/编辑器端口注入子进程。
4. **`editor_play_scene` 不再走 `EditorInterface`**（改用 `EditorRunBar`）：不是风格偏好，是引擎限制（接口层不转发运行参数）。`editor_stop_scene` 仍走 `EditorInterface`（行为等价的一行转发），以最小化改动面。
5. **`playing:true` 的语义被精确化**（读回 `is_playing()` + pid 变化），不再等同「调过 play_*」。契约描述已相应改写；这是**行为收紧**（原本静默失败会报成功），对合法调用无影响。
6. 报告里记录了一处**无法复现的观察**（PLAYBOOK §7.3 要求的显式撤回）：第一次证据运行（首次 `--import`、未加 `--mcp-port=0`）的 stderr 出现过 `ERROR: Parameter "singleton" is null. at: EditorNode::is_cmdline_mode`，退出码当时无法读取；随后三次 `--import`（含同样的**全新**工程、以及默认端口路径）**均复现不出来**，且退出码稳定为 0。该代码路径与本任务改动无关。**结论：不作为缺陷主张**，仅登记。
7. **`Start-Process -PassThru` 在重定向子进程上读不到 `ExitCode`**（本机 PowerShell 5.1 实测，任何形式都是空）→ 一次性进程（`--import`）改用 `cmd /c` + `$LASTEXITCODE`。这是**证据脚本**的偏离，不是产品代码的。

**blockers**：无。（端口 9877 全程只读观测，未占用/未杀/未重启；无 push。）

**next_step_recommendation**

1. 交给**全新**验收子代理独立验收；重点让它自己复核：(a) 子进程 cmdline 与端口闭环（重跑 `mcp024a_e10_play_scene_evidence.ps1` 即可复现）；(b) 契约只经 override 变更（`git diff` + `_meta.overrides` 逐条核）；(c) 「不假装成功」的两个新增分支（被占端口、编辑器自身端口）以及「子进程没起来则 `-32000`」是否真不可绕过——后者**没有线上证据**（需要 recovery mode 或缺 `project.godot` 的场景才能触发），属**推断边界**，请它明确区分「证据支持」与「推断」。
2. 决策者若采纳「顺手性判据/日志来源」规范文字（补丁 §1），应在 **TASK-024 其余 4 项**的任务书里由决策者写入 `DESIGN-DETAIL.md`；本模块实现者不写规范。
3. 建议 TASK-024 剩余项（E-1/E-3/E-6/E-9）继续**拆分**执行：本项含「契约 override + 重生成 + 引擎新行为 + 实测闭环」就已接近单任务上限（与前一位执行者耗尽上下文的教训一致）。
4. 可选（非本任务）：`editor_play_scene` 的响应里目前不给「注入的原始参数」；若验收希望调用方能直接核验注入文本，可加 `play_args` 字段——本任务**故意未加**（任务书只要求 4 个字段，避免未声明的响应膨胀）。