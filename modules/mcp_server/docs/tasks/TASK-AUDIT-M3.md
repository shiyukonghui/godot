# TASK-AUDIT-M3 — 独立验收：mono 构建 + C# 工程可跑 + M2 三项修复

> 你是**独立验收方**，未参与实现，**不得采信** `docs/reports/REPORT-014-m3-mono-csharp.md` 与决策者的结论。
> 只依据规范、代码与你**自己可复现**的证据。
> 报告写到 `docs/reports/REPORT-AUDIT-M3.md`；返回值**只允许**是「≤12 行总结 + 报告路径 + verdict」。

## 1. 验收对象与声称

- mono 构建：`module_mono_enabled=yes` → `bin\godot.windows.editor.x86_64.mono.exe`；
  glue 生成 + `build_assemblies.py` → `bin\GodotSharp\**` 与 4 个 `4.8.0-dev` nupkg；
  版本串 `4.8.dev.mono.custom_build.eb05a50ed`（与非 mono `4.8.dev.custom_build.eb05a50ed` **同一 commit**）。
- 模块共存：mono 下编辑器端点 9888 = **49**、游戏端点 9889 = **40**。
- C# 工程：`%TEMP%\mcp014-scratch\m3-csharp-proj`，离线 `dotnet build` 0 警告 0 错误；
  运行后 `execute_gdscript` 调 C# 方法得 `csharp: ticks=… state=csharp-ready`；
  `[Export] CsharpTicks` 经 `get_node_properties` 两次读到 **1428 → 1564**；
  C++ 写入 `CsharpState` 后 C# 读回 `state=written-from-mcp`。
- M2 三项修复 + R-3：D-1 未知属性 → `-32001`+建议；D-2 headless 截图 → `-32000`+建议；
  D-3 契约 `required` 由 `["events"]` → `[]`（并重生成指纹 + 同步 C++ 字面量）；
  R-3 `pending_timeout_ms<=0` → 落回 30000（实测工具自报 600 s 时 30.0 s 后 `-32000` + `data.timeout_ms=30000`）。
- 门（声称）：doctest 124/124·3653、全引擎 1550/1550·427935 断言 0 failed、门① 3/3、
  `accept_m1.ps1` 22/22 ×2（PASS 清单逐字节相同），且**全部在 `--version == git rev-parse HEAD` 的重建二进制上**。

## 2. 必核（自己跑）

1. **契约 D-3 正确性**：自己比对 D-3 前后的契约差异——**只**应有该工具的 `description` 与 `required`（以及 `_meta` 指纹）变化；
   自己验证 `required` 确实为空、描述里含**回退规则**（缺省 = 回放本进程最近一次 `stop_input_recording`；无录制 → `-32602`）；
   自己核实**线上 `tools/list` 与契约仍逐字相等**（门① 自己跑，两端点）。
2. **D-1**：自己调 `running_game_set_node_property` 写一个**不存在的属性** → 必须 `-32001`+`data.suggestion`；
   再写一个**真实属性** → 成功，并用**另一个工具**独立读回确认（不得只看自己的回读）。
   另核实：**C# 工程的 `public` 字段确实不是 Godot 属性**（只有 `[Export]` 在属性面里）——这是宣称的引擎事实，值得独立确认。
3. **D-2**：headless 下 `editor_capture_screenshot` → `-32000`+建议（不是 `-32603`）；参数错仍是 `-32602`。
4. **R-3**：把 `mcp_server/pending_timeout_ms` 配成 `0`（scratch 工程）→ 启动日志必须报**配置值与生效值**，
   且一个自报 600 s 的工具必须在 **~30 s** 后以 `-32000` + `data.timeout_ms=30000` 收尾（真实计时）。
5. **mono 与 C#**：自己跑一次 **C# 工程**（离线，`nuget.org` 在本机不可达属**正常**，不得因此判失败），
   自己从 **9889** 用 MCP 工具读到该 C# 脚本的状态；自己确认 **`dotnet build` 的退出码与「0 错误」**。
   若你选择**重建 mono**（耗时长），可跳过重建但必须**核对版本串与 HEAD 一致**并在报告里说明取舍。
6. **工程门**：doctest、全引擎、`accept_m1.ps1` ×2（自己跑；注意 PLAYBOOK §3 的「门必须先绑定构建」——
   先校验 `--version` 的 hash 前缀 == `git rev-parse --short HEAD`，不一致就先重建）。
7. **端口与收尾**：**9877 全程 PID 36392 未被触碰**；9888/9889 无 LISTENING；无孤儿进程（含 C# 游戏进程）。
8. **对抗性**：尝试让 C# 游戏进程与模块产生冲突（例如在 C# 脚本里创建同名节点/触发异常），
   确认模块**不崩溃**且错误可观测；并抽查一个 B1/B2 工具在 mono 下的行为与非 mono 一致（抽样 ≥3 个，含 1 个 deferred 工具）。

## 3. 约束

不得修改任何文件（临时改测试须还原并留证）；临时文件放 `%TEMP%\audit-m3\`；不得 git 写操作；不得安装依赖；
**绝不占用/杀/重启 9877**；证据用 `curl.exe -s -o <file>` + sha256、请求体用 `ConvertTo-Json`；
**不要抑制 scons/dotnet 输出**；**不要并发跑两个 scons**（曾造成生成头竞态与假编译错误）。

## 4. 报告

`verdict`（分类：mono 构建 / C# 可跑 / 模块共存 / 三项修复 / 工程门 / 端口纪律）、逐项结论与**你自己跑出的证据**、
`defects`（severity/claim/evidence/location/recommendation）、`unconfirmed`、`risks`、`next_step_recommendation`。
**返回值：≤12 行 + 报告路径 + verdict。**