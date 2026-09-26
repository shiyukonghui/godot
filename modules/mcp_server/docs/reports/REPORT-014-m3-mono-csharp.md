# REPORT-014 — M3：mono 构建 + C# 工程可跑（含 M2 验收的 3 项修复）

> 任务书：`docs/tasks/TASK-014-m3-mono-csharp.md`；通用规范：`docs/tasks/PLAYBOOK-group-port.md`（含 §3 的「门必须先绑定构建」）。
> 执行者：实现子代理（TASK-014）。工作目录 `code\godot`，分支 `feature/mcp-server-module`。

## 0. status 与 commits

**status: done** —— 第一部分的 4 项（D-1/D-2/D-3/R-3）已修并有红/绿与线上证据；mono 构建成功、
glue 与 GodotSharp 均已产出；一个最小 C# 工程 `dotnet build` 通过、真的跑起来，其状态经 9889 的 MCP 工具
被 C++ 模块读到（双向：C++ 也能写进 C# 对象）。五道门全绿，端口/进程纪律收尾干净。

| commit | 说明 |
|---|---|
| `b8da7d7cfe` | D-1/D-2/R-3：属性存在性拒绝、编辑器截图能力码、延迟兜底上限加固（含 2 个新 doctest、PLAYBOOK §6.6 第 7 例） |
| `de87d1c737` | D-3：契约去掉 `required: ["events"]`（`SCHEMA_OVERRIDES` 首个条目 + 生成器 v1.5.0 + 重生成契约 + C++ 字面量） |
| `eb05a50edf` | gate ②/M3 证据脚本 `scripts/mcp014_m3_evidence.ps1` |
| `ce740d96cb` | 证据脚本的三处实测修正（`Engine.get_main_loop()` 取树、C# 成员必须 `[Export]`、证据里记录引擎 `--version`） |
| 本报告自身 | 纯文档提交，**不含任何源码改动**；sha 自指无解，用 `git log --oneline -1 -- modules/mcp_server/docs/reports/REPORT-014-m3-mono-csharp.md` 取 |

本次**未 push**。门①~⑤与两阶段证据都在 `eb05a50edf` 这一源码状态上跑；`ce740d96cb` 只改
`scripts/mcp014_m3_evidence.ps1`（**不参与引擎编译**），报告与前述文档提交同理。

## 1. 逐项 M3 断言表（任务书 §4：本任务不用「逐工具表」）

所有断言都由 `scripts/mcp014_m3_evidence.ps1` 独立可重跑（`-Phase gate2` / `-Phase m3`），
原始输出见 `%TEMP%\mcp014_evidence_{gate2,m3}.log`，每条响应体都落盘在 `%TEMP%\mcp014-evidence\`。

| # | 断言 | 证据（真实输出） | 结论 |
|---|---|---|---|
| M3-1 | mono 构建产出可用的编辑器二进制 | `scons platform=windows target=editor module_mono_enabled=yes -j8` → exit 0，112.8 s（`INFO: Time elapsed: 00:01:43.35`）；产物 `bin\godot.windows.editor.x86_64.mono.exe`（178 121 216 B）+ `.mono.console.exe` | PASS |
| M3-2 | 该二进制的版本串自报 mono，且与 HEAD 同源 | `4.8.dev.mono.custom_build.eb05a50ed`（HEAD = `eb05a50edf`） | PASS |
| M3-3 | mono glue 生成成功 | `--headless --generate-mono-glue modules/mono/glue` → exit 0，2.7 s，末行 `The Godot API sources were successfully generated` | PASS |
| M3-4 | `GodotSharp`/`Godot.NET.Sdk` 构建成功并落到本地 NuGet 源 | `build_assemblies.py --godot-output-dir=bin --godot-platform=windows` → exit 0，80.7 s；`bin\GodotSharp\Api\{Debug,Release}\GodotSharp.dll`；`bin\GodotSharp\Tools\nupkgs\` 4 个包 | PASS |
| M3-5 | **mono 构建下模块照常工作**：编辑器端点 49 / 游戏端点 40 | `tools/list` = 49（9888）与 40（9889），与工具组并集完全一致（m09） | PASS |
| M3-6 | 一个 C# 工程 `dotnet build` 成功 | exit 0；`已成功生成。 0 个警告 0 个错误`；产物 `.godot\mono\temp\bin\Debug\Mcp014Csharp.dll`（9 728 B）（m03/m04） | PASS |
| M3-7 | **C# 代码真的执行了**（不是「文件存在」） | 引擎 stdout：`[MCP014-CS] Main._Ready ran; state=csharp-ready`；C# 方法 `CsharpReport()` → `csharp: ticks=1423 state=csharp-ready`（1433 帧后再次调用为 1572——计数器在跑）（m10/m14/m18） | PASS |
| M3-8 | **跨语言可见性**：从 9889 用 MCP 工具读到 C# 脚本产生的状态 | `running_game_get_node_properties` 两次读 C# 导出属性 `CsharpTicks`：**1428 → 1564**；C# 成员出现在 `get_property_list()` 里（59 条中的 `CsharpTicks`/`CsharpState`），即 C++ 模块读到的属性面（m13/m16） | PASS |
| M3-9 | 反向：C++ 模块写进 C# 对象，C# 代码看得见 | `running_game_set_node_property('CsharpState'='written-from-mcp')` → 回读 `new_value` = `"written-from-mcp"`；C# 方法随即报 `state=written-from-mcp`（m18） | PASS |
| M3-10 | mono 下三项修复照常生效 | `editor_capture_screenshot` → `-32000` + suggestion（m19）；未知属性 → `-32001` + suggestion（m20）；`pending_timeout_ms=0` → 启动日志 `pending_timeout_ms=30000 (configured=0)`（m21）；`play_input_recording` 线上 `required=[]`（m22） | PASS |
| M3-11 | 端口/进程纪律 | 全程 9877 仅被**观察**：`pid_before=36392 pid_after=36392`；收尾 9888/9889 均无 LISTENING；无孤儿进程 | PASS |
| M3-12 | 两个构建同源 | 非 mono `4.8.dev.custom_build.eb05a50ed` / mono `4.8.dev.mono.custom_build.eb05a50ed` = 同一 commit `eb05a50ed` | PASS |

C# 工程源码（由证据脚本生成，逐字见脚本内 `$CsharpScript`/`$CsharpScene`）：

```csharp
public partial class Main : Node2D
{
    [Export] public int CsharpTicks = 0;
    [Export] public string CsharpState = "csharp-ready";
    public override void _Ready() { ...; GD.Print("[MCP014-CS] Main._Ready ran; state=" + CsharpState); }
    public override void _Process(double delta) { CsharpTicks++; ... }
    public string CsharpReport() { return "csharp: ticks=" + CsharpTicks + " state=" + CsharpState; }
}
```

## 2. 第一部分的四项：前后对照

### D-1 `running_game_set_node_property` 对不存在的属性谎报成功 → `-32001`

| | before | after |
|---|---|---|
| 代码 | `tools/running_game_node_write.cpp`（`ca053e5521`）里 `property_type_of`（未知名字恒为 `NIL`）→ `Object::set()` 静默 no-op → 回读也是 null | 写入前先问对象：`_object_has_property()`（值非 NIL，或出现在 `get_property_list()` 里——`property_type_of` 的 NIL **同时**表示「没有这个属性」和「声明类型就是 Variant」，只有属性表能分开） |
| 线上响应 | M2 验收实测 `error=none`，`{"new_value":null,"node_path":"/root/Main","old_value":null,"property":"audit_no_such_property_xyz"}`（`REPORT-AUDIT-M2.md` §6 D-1） | `{"error":{"code":-32001,"data":{"suggestion":"Use running_game_get_node_properties to list the properties this node has"},"message":"Property 'mcp014_no_such_property' on node '/root/Main' not found"}}`（g15；sha256 `da2664e3…`） |
| 真实性控制 | —— | 同一次运行里：真实属性写入仍成功（`position` `{0,0}`→`{321,123}`），并由**另两个工具**独立读回一致（g13）；被拒的那次**确实什么也没发生**（`get("mcp014_no_such_property") == null` → `true`，g17） |
| doctest | 无 | `[MCPServer] a property the node does not have is a -32001 and a real property still writes` |

迁移源更糟：`addons/godot_mcp_rs/mcp_runtime_agent.gd:159-160` 对未知属性无条件回 `set: true`，
故本条**不是与迁移源的行为不一致**，而是「工具真的能用」标准下的诚实性缺口 —— 已按任务书要求写入
手册 §6.6 的**第 7 例**（`docs/tasks/PLAYBOOK-group-port.md`，本次唯一改动的规范类文件，任务书明文要求）。

### D-2 headless 截图用 `-32603` 收尾 → 统一 `-32000` + 建议

| | before（`ca053e5521`） | after |
|---|---|---|
| 代码 | 直接读 `base_control` 的 viewport texture，`image` 为 null/empty 即 `MCPToolError::internal("截图获取失败, 请重试")` | 先判能力的 `MCPTools::game_framebuffer_available()`（游戏侧截图工具用的是**同一个**判定），不支持时 `tool_state(-32000)` + 建议；`image` 为空也只算状态缺失（同样是 `-32000`）；`-32603` 只留给「图像在、PNG 编不出来」这一处真正的内部错误 |
| 线上响应 | M2 验收实测 `{"code":-32603,"message":"Internal error: 截图获取失败, 请重试"}`（`REPORT-AUDIT-M2.md` §6 D-2） | `{"error":{"code":-32000,"data":{"suggestion":"用带 display server 的编辑器进程重跑（去掉 --headless，或换用带渲染驱动的构建）后再次调用"},"message":"编辑器没有可读取的帧缓冲（headless display server 没有纹理存储）"}}`（g02；mono 下同形，m19） |
| 负向控制 | —— | 参数半边未变：`save_path` 越界仍是 `-32602`，且仍在能力判定**之前**（g03） |

**不可构造声明**：D-2 没有 doctest，理由是 doctest 进程不是 editor（`Engine::is_editor_hint()` 为假），
`require_editor_ui()` 会在到达能力分支**之前**就以 `-32000`（"editor writes outside a running editor"）返回；
该分支只能在 headless 编辑器端点用活证据覆盖（本节即该证据）。

### D-3 契约与行为不一致（`events` 是否必填）

裁决（任务书 §1.3：**契约改成与行为一致**）的执行方式：

1. `scripts/gen_renamed_contract.py` 升到 **v1.5.0**，`SCHEMA_OVERRIDES` 取**首个**条目（老机制存在，按
   `DESCRIPTION_OVERRIDES` 的先例使用，理由写进 `_meta.overrides`）：
   `replay_recording` 的 `required` 由 `["events"]` 改为 `[]`（与契约里所有「无需填参数」的工具同形），
   `properties.events` 保留；
2. 同时加一条 `DESCRIPTION_OVERRIDES`（append），把回退规则写进客户端真的会读的那句话：
   「缺省 `events` 时，回放本游戏进程内最近一次 running_game_stop_input_recording 的录制；若本进程没有可用录制则返回 -32602。」；
3. 生成器新增两条**可审计**约束：schema override 必须 `"mode": "replace"`（schema 只能整体替换），
   且 `reason` 必须逐字引用被移除的 `required`（本例 `["events"]`）；另有 `(kind, old_name)` 计数修正
   （此前 `declared_overrides` 是两张表的并集，同一工具不能同时带 description 与 schema override）；
4. 重跑生成器 + 重渲染 `docs/TOOL-NAMING.md`；
5. C++ 字面量由 `scripts/gen_b2_game_schema.py --in-place` 重新发射（第二次运行打印
   `already up to date`）。

| | before（`ca053e5521`） | after |
|---|---|---|
| 契约 | `"required": ["events"]`；描述 = `回放之前录制的输入事件序列` | `"required": []`；描述 = 原文 + 回退规则句 |
| C++ 字面量 | `v3.push_back(String::utf8("events"));` | 无 `push_back`（空 `required`） |
| 线上 `tools/list`（9889） | M2 验收实测 `required=["events"]` | `description` 与契约**逐字相等**、`required=[]`、`properties.events` 仍在（g07；门① 在两端点亦逐字 PASS） |
| 行为（未改，本次只改文本） | 缺省 `events` 时回退到本进程最近一次录制 | 活证据：`create_input_recording` → 游戏内注入一次按键 → `stop_input_recording`（`event_count:1`）→ `play_input_recording` **不带 `events`** → `{"event_count":1,"injected":1,"replayed":true,"speed":8.0}`（g22，`code=0`） |
| 「没有录制则 -32602」 | 实现已有 | doctest 继续钉住该分支：`tests/test_mcp_server.h:6098`（本进程无录制且无 `events` → `-32602` `nothing to replay`）；同一用例的 `:6152` 钉住反向（有录制、缺 `events` → 生成延迟任务、`describe()` 含 `replaying 1 input event(s)`） |

契约 diff 全文只有 3 处内容变化（`git diff` 共 20 行）：该工具的描述、该工具的 `required`、`_meta` 的
`generator_version` 与两条 override 记录。

### R-3 `pending_timeout_ms<=0` 不得关闭兜底

| | before（`ca053e5521`） | after |
|---|---|---|
| 代码 | `pending_timeout_ms = _get_int_setting(..., 30000); if (pending_timeout_ms < 0) pending_timeout_ms = 0;` —— 负值折成 0，0 原样保留 | `MCPPendingTimeout::effective_ms(configured)`：`<= 0` → 默认 30000，正数原样；`!= configured` 时 `WARN_PRINT`，并在启动时打印两值 |
| 为什么 0 是危险的 | 传输层把 0 读作「无期限」，而两个等帧的延迟工具（`running_game_get_node_property_samples` / `running_game_capture_frames`）**不申报自己的期限**（`Task::get_timeout_ms()` 默认 0），这个上限就是它们**唯一**的兜底 | 同上（上限不可被配置关掉） |
| 启动日志 | 无 | `[MCP] pending_timeout_ms=30000 (configured=0) pending_ticks_per_frame=8`（g23；mono 下同形，m21） |
| 活证据 | —— | 项目里配 `pending_timeout_ms=0`，工具自报 **600 s**：`running_game_find_node_when_available{timeout:600}` → **30.0 s** 后 `{"code":-32000,"data":{"timeout_ms":30000,...},"message":"Deferred call timed out after 30000 ms: waiting for node 'Mcp014NeverAppears'"}`（g25） |
| doctest | 无 | `[MCPServer] a non-positive pending_timeout_ms cannot switch the deferred fallback off`（单测 `effective_ms` 并把后果测到 `MCPJsonRpc::dispatch` 的 `timeout_ms` 上） |

## 3. 红 / 绿证据（TDD）

**红**（`%TEMP%\mcp014_red_gate3.log`，实现尚未修、测试已写）：

```
.\modules/mcp_server/tests/test_mcp_server.h(7067):
TEST CASE:  [MCPServer] a property the node does not have is a -32001 and a real property still writes
.\modules/mcp_server/tests/test_mcp_server.h(7082): ERROR: CHECK( refused.get_type() == Variant::NIL ) is NOT correct!
  values: CHECK( 27 == 0 )
.\modules/mcp_server/tests/test_mcp_server.h(7083): ERROR: CHECK( error.code == -32001 ) is NOT correct!
  values: CHECK( 0 == -32001 )
.\modules/mcp_server/tests/test_mcp_server.h(7084): ERROR: CHECK( error.message.contains("mcp014_no_such_property") ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(7085): FATAL ERROR: REQUIRE( error.data.get_type() == Variant::DICTIONARY ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(7136): FATAL ERROR: REQUIRE( nil_typed_property_exists ) is NOT correct!
===============================================================================
.\modules/mcp_server/tests/test_mcp_server.h(7177):
TEST CASE:  [MCPServer] a non-positive pending_timeout_ms cannot switch the deferred fallback off
.\modules/mcp_server/tests/test_mcp_server.h(7188): ERROR: CHECK( MCPPendingTimeout::effective_ms(0) == MCPPendingTimeout::DEFAULT_MS ) is NOT correct!
  values: CHECK( 0 == 30000 )
.\modules/mcp_server/tests/test_mcp_server.h(7189): ERROR: ... effective_ms(-1) ...  values: CHECK( 0 == 30000 )
.\modules/mcp_server/tests/test_mcp_server.h(7190): ERROR: ... effective_ms(-60000) ...  values: CHECK( 0 == 30000 )
.\modules/mcp_server/tests/test_mcp_server.h(7204): ERROR: CHECK( zero_configured.timeout_ms == MCPPendingTimeout::DEFAULT_MS ) is NOT correct!
  values: CHECK( 0 == 30000 )
[doctest] test cases:  124 |  122 passed | 2 failed | 1429 skipped
[doctest] assertions: 3650 | 3640 passed | 10 failed
[doctest] Status: FAILURE!        (exit 1)
```

红阶段的实现是「先把 `write_node_property` 按旧行为抽出来、`effective_ms` 先原样返回」，所以红是**运行期断言
失败**而不是编译失败，红绿之间只差真正的行为改动。红阶段还顺带量到一个事实：
`Object::set_meta(name, Variant())` 会**删除**该 meta（`core/object/object.cpp:1097-1109`），因此
「声明类型为 `Variant::NIL` 的属性」在 doctest 里**构造不出来** → 该子例被换成可构造的等价子例（见 §7 偏离 3）。

**绿**（最终二进制 `4.8.dev.custom_build.eb05a50ed`，`%TEMP%\mcp014_gate3_final.log`）：

```
[doctest] test cases:  124 |  124 passed | 0 failed | 1429 skipped
[doctest] assertions: 3653 | 3653 passed | 0 failed
[doctest] Status: SUCCESS!        (exit 0)
Cannot get path of node as it is not in a scene tree.  出现次数 = 0
```

（基线 = REPORT-013 的 `122 / 3618`；本批只增不减。`get_path` 引擎报错计数为 0，见 §7 偏离 4。）

## 4. 五道门的真实输出与退出码

**门① 契约子集逐字**（`scripts\check_contract_subset.ps1 -Group running_game_input`，两次跑，其中一次在绑定 HEAD 的重建二进制上）：

```
editor set  : 49 tool(s)
game set    : 40 tool(s)
[PASS] editor_9888_contract_subset   editor port=9888 tools=49 ... running_game_play_input_recording: correctly absent on the editor endpoint
[PASS] game_9889_contract_subset     game port=9889 tools=40 ... running_game_play_input_recording: name=True description=True inputSchema=True
[PASS] guard_user_port_9877          pid_before=36392 pid_after=36392
3/3 checks passed     (exit 0)
```

**门② 三类证据 + 跨工具活证据链**（`scripts\mcp014_m3_evidence.ps1`）：

- `-Phase gate2`（非 mono，18/18 PASS，exit 0；首条即把二进制版本记进证据：`g00 engine --version = '4.8.dev.custom_build.eb05a50ed'`）
  覆盖 D-1/D-2/D-3/R-3 各一组真实请求/响应（§2 已逐条引用），以及两组端点计数；
- `-Phase m3`（mono，20/20 PASS，exit 0）覆盖 §1 的 M3-4..M3-11。

**三类证据的可构造性**（本任务的门②对象是「被修的四项」而不是某个工具组，故按项列）：
- 成功类：g10（真实写入 `position`，并被两个工具独立读回）、g22（缺省 `events` 回放成功）、
  m03/m04/m14/m16/m18（C# 侧：构建、执行、跨语言读、跨语言写）；
- 参数拒绝类：g03（`save_path` 越界 → `-32602`，且发生在能力判定之前）；**缺参**类由 doctest 承担并已存在：
  `running_game_set_node_property` 的 `Missing required parameter: node_path` / `: property` /
  `'value'`（`tests/test_mcp_server.h:6353-6371`），`running_game_play_input_recording` 的
  `:6098`（无录制且无 `events` → `-32602`；`:6099-6101` 覆盖 `events` 类型/空数组/元素类型错）；
- 底层/状态失败类：g15（属性不存在 → `-32001`）、g02（能力不足 → `-32000`）、g25（延迟超时 → `-32000`）；
- **不可构造类的声明**：D-2 的能力分支在 doctest 进程不可达（§2 D-2）。

**门③ 模块 doctest**：`124 | 124 passed | 0 failed | 1429 skipped`，`3653 | 3653 passed | 0 failed`，
`Status: SUCCESS!`，exit 0。（基线 122/3618）

**门④ 全引擎回归**：`1550 | 1550 passed | 0 failed | 3 skipped`，`427935 | 427935 passed | 0 failed`，
`Status: SUCCESS!`，exit 0。（基线 1548/427900；+2 用例 / +35 断言，全部来自本批新增测试）

**门⑤ 收口门**（`scripts\accept_m1.ps1` **连跑两次**，均在绑定 HEAD 的二进制上）：

```
run1: 22/22 cases passed   (exit 0)
run2: 22/22 cases passed   (exit 0)
两次 PASS 清单逐行相同 = True（22 行）
```

**门必须先绑定构建（PLAYBOOK §3 / R-1）的执行记录**：实现提交后重建了非 mono 二进制，使其
`--version` 自报 `4.8.dev.custom_build.eb05a50ed` == `git rev-parse --short HEAD`（`eb05a50edf`）的前 9 位；
**本报告引用的门①~⑤与 gate2 证据全部来自重绑后的这一次运行**。mono 二进制的 `--version` 同样是
`…mono.custom_build.eb05a50ed`。

## 5. mono 构建全流程：命令与输出

全部原始输出（未裁剪、未抑制）在 `%TEMP%` 下：`mcp014_mono_build.log`、`mcp014_mono_glue.log`、
`mcp014_mono_assemblies.log`。

```text
① 环境
   dotnet --version = 10.0.300-preview.0.26177.108
   dotnet --list-sdks = 9.0.100, 9.0.300, 10.0.300-preview.0.26177.108
   dotnet --list-runtimes 含 Microsoft.NETCore.App 8.0.11 / 8.0.25   （net8.0 目标可满足）
   curl https://api.nuget.org/v3/index.json  ->  http_code=000（本机**无公网**，离线必须自带包源）

② 引擎（mono 编辑器目标）  耗时 112.8 s   exit 0
   D:\Anaconda\Scripts\scons.exe platform=windows target=editor module_mono_enabled=yes -j8
   ... Linking Program bin\godot.windows.editor.x86_64.mono.exe ...
   scons: done building targets.
   INFO: Time elapsed: 00:01:43.35
   （scons 自报 WARNING: ANGLE 渲染驱动依赖未安装 —— 与本任务无关，非 mono 构建同样如此）

③ glue   耗时 2.7 s   exit 0
   bin\godot.windows.editor.x86_64.mono.console.exe --headless --generate-mono-glue modules/mono/glue
   The Godot API sources were successfully generated
   ERROR: [MCP] SceneTree never became available; MCP server disabled.   ← 模块自己在无 SceneTree 进程里的既有日志，正常

④ GodotSharp / GodotTools / Godot.NET.Sdk   耗时 80.7 s   exit 0
   python modules\mono\build_scripts\build_assemblies.py --godot-output-dir=bin --godot-platform=windows
   Copying assembly to ...\bin\GodotSharp\Api\{Debug,Release}\...
   已成功创建包 ... GodotSharp.4.8.0-dev.nupkg / GodotSharpEditor.4.8.0-dev.nupkg /
                   Godot.SourceGenerators.4.8.0-dev.nupkg / Godot.NET.Sdk.4.8.0-dev.nupkg
```

**组合说明（任务书 §2.4）**：mono 构建**不带** `tests=yes`（doctest 由非 mono 构建承担），
两个构建的模块源码**同一 commit**：`4.8.dev.custom_build.eb05a50ed` 与 `4.8.dev.mono.custom_build.eb05a50ed`。
`module_mono_enabled=yes` 下 scons 用的是**不同文件名**（`.mono.exe` / `.mono.console.exe`），
所以两个二进制**互不覆盖**——`bin\` 里同时留着两种，后续批次两条轴都可直接用。

## 6. 构建产物与最终 bin 状态

| 文件 | 字节 | sha256 | 说明 |
|---|---|---|---|
| `bin\godot.windows.editor.x86_64.exe` | 191 555 072 | `243dd5fd64b5e2a2dceb0d4c3da3a696f2bc7018cb6943840d8649591fb87b78` | **非 mono（`tests=yes`）编辑器**：门①③④⑤ 与 gate2 证据用的就是它，`--version` = `4.8.dev.custom_build.eb05a50ed` |
| `bin\godot.windows.editor.x86_64.console.exe` | 300 544 | `9aeff8a05b0f474163f61fca681baccbe13fc178e04870e7a636b75839a0d4e2` | 同上（console 包装） |
| `bin\godot.windows.editor.x86_64.mono.exe` | 178 121 216 | `548a7202f3ee49a46562ef9ed54ea222a5586047fd9607fffbfcd57ce62a5eb0` | **mono 构建**：M3 证据用的就是它，`--version` = `4.8.dev.mono.custom_build.eb05a50ed` |
| `bin\godot.windows.editor.x86_64.mono.console.exe` | 300 544 | `d0ebd904fe01bf7095b265dab8ac8c71d09ed65bf0221a958f553585ca0d80d7` | 同上（console 包装） |

**最终留下的二进制是「两种都在」，且默认名 = 非 mono（tests）那一份**（后续批次跑门③④⑤不需要改路径；
需要 C# 时用 `.mono.console.exe`）。`bin\` 不受版本控制（`.gitignore [Bb]in/`），故这些产物不进提交。
另在 `%TEMP%\mcp014-bin-nonmono\` 保留了一份 13:17 版的非 mono 二进制副本作为回滚点。
`bin\GodotSharp\**`（Api/{Debug,Release} + Tools + nupkgs）是本流程的产物，供 C# 轴复用。

## 7. C# 相关版本事实（供 hof-rs `hoh doctor` 预检）

| 事实 | 值 | 来源 |
|---|---|---|
| .NET SDK（实际使用者） | `10.0.300-preview.0.26177.108`；`modules/mono/global.json` 要求 `8.0.0` + `rollForward: latestMajor` | `dotnet --info` |
| 目标框架 | `net8.0`（Godot 4.8 mono 的 glue 与 `GodotPlugins.runtimeconfig.json` 都是 net8.0） | `modules/mono/build_scripts/build_assemblies.py:228` |
| 运行时前提 | `Microsoft.NETCore.App 8.0.x` 必须存在（本机 8.0.11/8.0.25） | `dotnet --list-runtimes` |
| Godot mono 版本串 | `4.8.dev.mono.custom_build.eb05a50ed` | `--version` |
| Godot .NET 包版本（Godot.NET.Sdk / Godot.SourceGenerators / GodotSharp / GodotSharpEditor） | **`4.8.0-dev`** | `modules/mono/SdkPackageVersions.props` |
| GodotSharp API 目录 | `<引擎目录>\GodotSharp\Api\{Debug,Release}\`（`target=editor` → `Debug`，`godotsharp_dirs.cpp:56-58`） | 实测 |
| 工程程序集落点 | `<工程>\.godot\mono\temp\bin\Debug\<AssemblyName>.dll`（SDK 的 `Sdk.props` 把 `OutputPath` 改到这里；`[dotnet] project/assembly_name` 必须与 `<AssemblyName>` 一致） | 实测 |
| 离线包源 | `<引擎目录>\GodotSharp\Tools\nupkgs`（Godot 自己的构建把 4 个 nupkg 复制进去；用户工程 `NuGet.config` `<clear/>` + 只指向它即可离线构建） | 实测，见 §8 |
| 需要显式步骤 | 该离线源**没有** `Godot.NET.Sdk` 之外的第三方包；`Godot.SourceGenerators` 的构建依赖（Roslyn）来自本机 NuGet 缓存，首次构建需缓存已就绪 | `mcp014_mono_assemblies.log` |

## 8. C# 工程的直接证据（M3 的核心）

`%TEMP%\mcp014-scratch\m3-csharp-proj\`（脚本重建）：`project.godot`（`[dotnet] project/assembly_name="Mcp014Csharp"`、
`[godot_mcp] enabled_in_game=true`、`[mcp_server] pending_timeout_ms=0`）、`Mcp014Csharp.csproj`
（`Sdk="Godot.NET.Sdk/4.8.0-dev"`，版本串由脚本从 `SdkPackageVersions.props` **读出**而不是硬编码）、
`NuGet.config`（`<clear/>` + `bin\GodotSharp\Tools\nupkgs`）、`Main.cs`、`scenes\main.tscn`。

```text
$ dotnet build -c Debug          (cwd = 工程目录)
  正在确定要还原的项目…
  已还原 ...\Mcp014Csharp.csproj (用时 314 毫秒)。
  Mcp014Csharp -> ...\.godot\mono\temp\bin\Debug\Mcp014Csharp.dll
已成功生成。
    0 个警告
    0 个错误
已用时间 00:00:03.66            exit 0
```

运行与跨语言读数（9889；响应体逐条落盘，sha256 见 §4 的 gate2/m3 日志）：

```text
# C# 自己打印的（引擎 stdout）
[MCP014-CS] Main._Ready ran; state=csharp-ready

# 用 MCP 工具在 9889 上调到 C# 方法（GDScript 由 C++ 模块编译执行）
tools/call running_game_execute_gdscript {"code":"var tree := Engine.get_main_loop() as SceneTree\nreturn tree.current_scene.call(\"CsharpReport\")"}
-> {"result":"csharp: ticks=1423 state=csharp-ready","result_type":"String"}

# 用 MCP 属性工具读 C# 导出的状态（间隔约 0.9 s，两次）
running_game_get_node_properties {"node_path":"Main","properties":["CsharpTicks"]}
-> {"node_path":"/root/Main","properties":{"CsharpTicks":1428},"type":"Node2D"}
-> ...第二次 {"CsharpTicks":1564}            ← C# 代码在两次读数之间继续跑

# 反向：C++ 模块写进 C# 对象，C# 自己确认
running_game_set_node_property {"node_path":"Main","property":"CsharpState","value":"written-from-mcp"}
-> {"new_value":"written-from-mcp","node_path":"/root/Main","old_value":"csharp-ready","property":"CsharpState"}
--> CsharpReport() = "csharp: ticks=1572 state=written-from-mcp"
```

**C# 执行与否的判据不是「文件存在」**：`ticks` 只由 `_Process` 递增（1423 → 1428 → 1564 → 1572），
`CsharpReport()` 返回的字符串由 C# 拼装；`[MCP014-CS]` 行由 C# 自己 `GD.Print`。

## 9. 指纹（本批改动涉及契约/生成器/脚本/规范）

| 文件 | 字节 | sha256 |
|---|---|---|
| `docs/tools_list.renamed.json`（**已改**） | 100 674 | `56095079c499477004f70c86def350be6517cb76d3b695c7ba5ed02bffd46cbd` |
| `docs/tool-rename-map.json`（未改） | 70 917 | `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd` |
| `docs/TOOL-NAMING.md`（重渲染，**逐字节未变**） | 98 720 | `ce9bc325699cae6cfaec104d1e3477e91d78a5440f8893366cc030c03c36c975` |
| `docs/tool-groups.json`（未改） | 5 682 | `0cfcac80f0d999fa7db713ae48f43febe96ae52e2c93633257eeed00ffdfbfac` |
| `docs/tool-groups-b2.json`（未改） | 11 623 | `14eba00016c00bff914bb39aff9cfb5f01e375a43fa2ff5038d69bdedfc8b75d` |
| `scripts/gen_renamed_contract.py`（**已改**，v1.5.0） | 31 347 | `4ca8ac2d4616aa95e5e7fb7327886e6c8f49daf022bac80cde63dcc75b9cf654` |
| `scripts/gen_b2_game_schema.py`（未改，仅重跑） | 12 384 | `cc00f5275dc1a57876d562a5abf4aa0fe18d2110f2e2d0a58c232a693d6ac088` |
| `scripts/mcp014_m3_evidence.ps1`（新增） | 46 969 | `83a13db5c42d877c0a68659289602860a9d5a1b40af4cf7544f27b96b165df2d` |
| `docs/tasks/PLAYBOOK-group-port.md`（**已改**：§6.6 第 7 例） | 12 171 | `27e16f5976e96f39cb2e5d13be95189170ea0f539fa4b8e99ad732148f3067b2` |

`docs/TOOL-NAMING.md` 逐字节未变是可预期的：它由 `docs/scripts/gen_table.py` 从 `tool-rename-map.json`
渲染，而映射本次未动（D-3 只动契约的 `required`/描述，映射的 `reason` 按 PLAYBOOK §6.5 不改写）。
两次生成器运行的自检均通过（`self-checks = OK (lint 171/171, unique 171/171)`；
`TOOL-NAMING.md` 渲染 `DETERMINISM PASS`）。

## 10. deviations（与手册/任务书的偏离，逐条显式）

1. **没有为「修复前」重建一份旧二进制去抓线上红线**。理由：M2 独立验收已经逐条实测并写在仓内
   （`REPORT-AUDIT-M2.md` §6 D-1 的成功形状、D-2 的 `-32603`），加上 `ca053e5521` 的源码与**本次
   真实的 doctest 红阶段**，before 侧的证据链完整且**来自独立第三方**；为此再跑一次全引擎构建的收益
   低于风险（且会让 `bin/obj` 在两套 flag 间反复重建）。before/after 的对照逐条见 §2。
2. **红阶段日志早于测试文本的最后一处编辑**：红运行里包含一个后来判定「不可构造」的子例
   （`REQUIRE(nil_typed_property_exists)`），最终测试把它换成了可构造的等价子例。因此红日志的行号
   对应旧文本，但红阶段失败的两组**核心断言**（未知属性→`-32001`、`effective_ms(0)==30000`）与最终
   测试逐字相同。
3. **一条声明的覆盖缺口**：「声明类型为 `Variant::NIL` 的属性仍应可写」这一子例在 doctest 进程
   **构造不出来**（`set_meta(name, Variant())` 会删除 meta —— 红阶段实测；脚本实例需要 doctest
   没有的 `ClassDB`/脚本语言），因此实现里「以属性表为准」的规则由代码注释论证、由两条可构造的
   子例（未知属性必须拒、当前值为 null 的属性必须能写）夹住。若后续进程能造出该状态，应补一条。
4. **`write_node_property` 对「不在树里的节点」不再触发引擎报错**：结果里的 `node_path` 现在先问
   `is_inside_tree()`（不在树里返回空串，与 `String(get_path())` 的返回值相同，只是不再打
   `ERR_FAIL_COND_V_MSG`）。**在树里时取值完全不变**，运行中的游戏节点永远在树里；这处只在 doctest
   的裸 `Node2D` 上可观察（门③日志里 `Cannot get path of node` 出现 0 次）。
5. **改了 `docs/tasks/PLAYBOOK-group-port.md`**（§6.6 第 7 例）。任务书 §1.1 明文要求「记入手册 §6.6
   的第 7 例」；它是本批唯一改动的规范类文件，且**没有新建任何规范文档**（REQUIREMENTS/DESIGN 均未创建）。
   其余「不得改契约/映射/生成器」的约束中，**契约与生成器是被任务书 §1.3 明确要求修改的**（D-3），
   映射一个字节未动。
6. **mono 构建不带 `tests=yes`**：任务书 §2.4 允许；doctest 由非 mono 构建承担，两个构建同 commit
   （版本串可核）。因此「mono 下跑 doctest」这条**没有被测**（也未声称）。
7. **写到了 `modules/mcp_server/**` 之外**——全部是构建产物，非源码：`modules/mono/SdkPackageVersions.props`、
   `modules/mono/glue/GodotSharp/GodotSharp/Generated/**`、`modules/mono/**/{bin,obj}`、`bin/GodotSharp/**`、
   `bin/obj/**`。前者两个都在 `.gitignore` 里（`modules/mono/.gitignore`、`glue/GodotSharp/.gitignore`）；
   `git status --short` 除既有的 4 个未跟踪物外**没有任何多余条目**。引擎**源码**零改动。
8. **过程事故（自曝）**：本批中途我曾同时跑了两个 scons（第一个后台作业被 kill 时，其 scons 子进程并未
   停止），两者并发重建了 `modules/modules_tests.gen.h` 这一生成头，于是在若干**与本次改动无关**的文件
   （`mcp_deferred.cpp`、`input_recorder.cpp`、`editor_input_read.cpp` 等）上刷出一片假编译错误。
   发现后我确认没有并发构建、单进程重建即全部消失；期间未改任何源码。教训：后台构建要么真等它结束，
   要么确认子进程已死再开第二个——`job_kill` 只停 shell 包装不保证停 scons。
9. **gate2 证据的二进制绑定**：第一次 gate2 运行（17/17）用的是提交**之前**构建的二进制（`--version`
   自报 `ca053e552`，即三个提交前的 HEAD）。提交完成后我重建了非 mono 二进制使其 `--version` == HEAD，
   并**重跑了门①③④⑤与 gate2 证据**；本报告引用的全部是重绑后的运行（gate2 18/18）。
10. **证据脚本自身的两处真实教训（已写进脚本注释与提交信息）**：
    (a) `running_game_execute_gdscript` 把代码编译到 `extends RefCounted` 的实例上，那里**没有** `get_node()`，
    第一版脚本因此实测到两个 `does not compile: Parse error`，改为经 `Engine.get_main_loop()` 取树；
    (b) C# 的 **public 字段不是 Godot 属性**，只有 `[Export]` 成员才进属性表，第一版 C# 工程因此
    被测出「属性表里没有 CsharpTicks/CsharpState」，加 `[Export]` 后 m13/m16/m18 全绿。

## 11. blockers

无。任务书 §1~§3 的每一项都有可复现证据；没有遇到需要用户介入的环境阻塞。

## 12. next_step_recommendation

1. **B3 可以开工**：`running_game_set_node_property` 已是「先问存在性再写」的形态，node-write 家族其余
   工具照同一模式即可；本批顺带证明的 `[Export]` 事实（C# 侧只有导出成员在属性面上）应写进 B3 的
   任务书注意事项，否则 B3 在 C# 工程上取属性时会重踩。
2. **`hoh doctor` 的预检项**（hof-rs 侧）建议至少覆盖：`dotnet --list-runtimes` 里有 `Microsoft.NETCore.App 8.x`、
   引擎目录存在 `GodotSharp/Api/{Debug,Release}`、`GodotSharp/Tools/nupkgs` 里有 `Godot.NET.Sdk.<版本>`、
   以及 `dotnet build` 能否离线解析到该包源（本机公网不可达，这一点必须当成常态而不是异常）。
3. **验收建议关注的两点**：(a) 门③/门④ 的增量是否确为 2 用例 / 35 断言；(b) D-3 的契约 diff 是否
   只有该工具的 `description`/`required` 与 `_meta`（`git diff de87d1c737^ de87d1c737`）。
4. **流程性建议**：把本次的事故 8（并发 scons 会污染 `modules/modules_tests.gen.h`）与 R-1 并列写进
   PLAYBOOK §3——它与「陈旧构建」是同一类风险（门跑在了不该跑的产物上），只是成因不同。

## 13. 环境事实与端口纪律

| 事实 | 值 |
|---|---|
| 用户正在用的编辑器 | `D:\Program Files\Godot_v4.7.1-stable_mono_win64\...\Godot_v4.7.1-stable_mono_win64.exe`，PID **36392**，全程监听 9877 |
| 9877 是否被触碰 | 否。每次运行前后都断言 `pid_before == pid_after == 36392`（门①、gate2、m3 三处都有该断言） |
| 测试端口 | 9888（编辑器）/ 9889（游戏） |
| 收尾状态 | 9888/9889 均无 LISTENING；本机仅剩 1 个 godot 进程（用户的 36392）；无孤儿进程 |
| 证据落点 | `%TEMP%\mcp014-evidence\`（每请求一个 `.request.json` + `.response.json`，日志里逐条打印字节数与 sha256）、`%TEMP%\mcp014-logs\`、`%TEMP%\mcp014-scratch\` |
| 证据采集纪律 | 请求体一律 `ConvertTo-Json` 写文件 + `curl.exe --data-binary @file`；响应体一律 `curl.exe -s -o <file>` 后从磁盘算 sha256；未使用 `Out-File`/管道承载响应体 |
| 网络 | 公网不可达（nuget.org `http 000`）；本流程全程离线，未安装任何依赖 |
