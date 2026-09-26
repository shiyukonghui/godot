# REPORT-AUDIT-RACING-BACKLOG — 独立确认「试测改进清单」（6 缺失工具 + 4 建议合并 + 3 不建议 + 13 可优化 + `project.godot` 拼接）

> **角色**：独立验证方（TASK-AUDIT-RACING-BACKLOG 的执行者），**未参与** TASK-039 试测与任何实现。
> **本报告不采信** `RACING-FINDINGS.md` 与任何 `REPORT-*` 的结论：清单里的每一条都按**我自己跑出的证据**重判，
> 凡引用他人结论处一律标其**提交锚点**并在本锚点**复测**（D86），不一致处逐条纠错（§5.6、§3.1、§4.4、§8 N-5）。
> **本任务只确认，不修改任何东西**：仓库内**只**新增本报告一个文件（§0.3 自证）。

---

## 0. 锚点、方法与纪律自证

### 0.1 提交锚点（D86）

| 项 | 值 | 来源 |
|---|---|---|
| 仓库 / 分支 | `F:\RustProjects\godot-mcp-pro\code\godot` / `feature/mcp-server-module` | `git rev-parse --abbrev-ref HEAD`【实测】 |
| **本报告全部结论测自 HEAD** | `5ee2c596a8446c486f9a3462c67b3aba2f84fae1`（短 `5ee2c596a`，`docs(mcp_server): REPORT-049 …`） | `git rev-parse HEAD`【实测】 |
| 引擎自报 | `4.8.dev.custom_build.5ee2c596a` | `bin\godot.windows.editor.x86_64.console.exe --version`【实测，== 短 HEAD】 |
| 构建命令 | `modules\mcp_server\scripts\build_local.cmd -Force`（从 `cmd` 启动，`tests=yes`，`module_mono_enabled=no`）→ **exit 0** | `%TEMP%\mcp_server_build_local.log`【实测】 |
| **被审计清单的原锚点**（对照用） | `f34ee937f3d31c49ac42081bb91433c5fc5b36e3`（`RACING-FINDINGS` §0.1 自报） | `git show f34ee937f:…tools_list.renamed.json`【实测，sha `C844EC8A…` 与其自报一致】 |
| 契约（HEAD） | `modules/mcp_server/docs/tools_list.renamed.json` **118 032 B / sha256 `443F1DF2E9A3C5B0A2AD1C4CE532A4CFB6F33D22D0401A02448A0CA0BEDE914F`**，**171 条** | 【实测】 |
| 两锚点的工具名集合 | **逐字相同**（171/171，`set(cur) == set(old)` = True） | 【实测】`survey2.py` |
| 线上 `tools/list`（编辑器端点） | 45 186 B / sha256 `23f3bd6b9f4ddaa42858cd4804d7bd389e19d5f5af36d42d1a850eafef00a810`，148 条 | 【实测】与 `REPORT-043 §6` 的 `L10` 逐字相同 |

### 0.2 两个锚点之间的时间线（为什么很多条目「已经不是那样了」）

`f34ee937f`（试测锚点）之后到 HEAD 之间，试测清单的**大部分条目已被后续批次修过**：

```
8e35a95b94  TASK-040  fix the three racing defects (D-1 property gate, D-2 CONNECT_PERSIST+persisted, D-3 named-read consistency)
36c485834e  TASK-041  M-6: persist editor_add_input_action into project.godot's [input] and read it back from disk
d5b98df19a  TASK-042  editor_add_input_action answers action_state and project_entry
3b7a3c19b1  TASK-042 §3-4  project.godot rewrite measured byte by byte + the [input] splice spike (REPORT-042 §3)
10dfe36a69  TASK-042      the 9877 preconditions, the rewrite attribution and the O-6 honesty fields
47b5008bac  TASK-043  the five tools that rewrite project.godot now say so in their description
3193981897  TASK-049  the resource property bag takes the engine's own property names
```

本报告因此对**每条**都分别回答：①现象在本锚点**是否仍然存在**；②**是否已被现有 171 个工具覆盖**；③影响面；④代价与契约面。

### 0.3 纪律自证

| 纪律 | 实测 |
|---|---|
| 只读（不改仓库任何文件） | 开工与收工两次 `git status --porcelain` **逐行相同**（只有开工前就存在的 5 个未跟踪项：`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`、本任务书）；`git diff --stat` 为空；**无任何 git 写操作**；`git rev-parse HEAD` 未变【实测】 |
| 本报告的写入物 | **只** `modules/mcp_server/docs/reports/REPORT-AUDIT-RACING-BACKLOG.md`（新文件） |
| 临时文件 | 全部在 `%TEMP%\audit-racing-backlog\`（224 个文件，`evidence-manifest.txt` 逐文件给字节数与 sha256） |
| 端口纪律 | 全程**只观测** 9877：每次运行的检查里 `owner before == after == -1`（无监听）；编辑器 9888、游戏 9889、一次性引导探针 9891（我校验并**只杀我自己**拉起的进程，见 §0.4） |
| 证据 | 响应体一律 `curl.exe -s -o <file>` 落盘 + `SHA256`；请求体 `ConvertTo-Json -Compress` 写为无 BOM UTF-8 |
| `.ps1` 纯 ASCII | 5 个脚本逐个字节校验：非 ASCII 字节数 = **0** |
| scons | 不并发、不抑制；`build_local.cmd -Force` 的输出全量在 `%TEMP%\mcp_server_build_local.log` |
| **未能满足的环境限制（须记录）** | 本锚点的构建是 **`module_mono_enabled=no`**，`bin\godot.windows.editor.x86_64.mono.console.exe --version` = `4.8.dev.mono.custom_build.019c4b019`（**≠ HEAD**）→ 任何 **C# 编译语义**都无法在本锚点实测（§3.2 M-2 标注为「部分确认」）。 |

### 0.4 一处必须交代的自身事故（诚实优先）

第一次「无 `project.godot`」探针用 `Start-Process` 拿到了 `.console.exe` 的句柄，**实际进程是它生出的
`.exe` 子进程**，所以 `Stop-Process` 只杀了启动器，子进程继续监听 9891（pid 74548）。
我在下一步先**按命令行确认那是我的进程**（`--path …\audit-racing-backlog\noproject --mcp-port=9891`），
查询完它之后才杀掉并复核 9891 释放。此后的脚本一律改为**按命令行前缀杀自己 temp 树里的进程**。
全程**没有**触碰 9877，也没有动任何非本审计启动的进程。

---

## 1. 总表（可据以排期）

> 判定口径：**confirmed** = 我自己复现了现象；**partially** = 现象部分成立/能力已被现有工具覆盖一部分；
> **not confirmed** = 在本锚点**不成立**（已修、或本来就被别的工具覆盖、或清单的归因是伪影）。
> 阻塞度：**阻塞** / **显著摩擦** / **便利**。「改契约」= 是否改变 171 条契约面。

### 1.1 §2.2 缺失工具（6 条）

| 编号 | 名称 | 判定 | 阻塞度 | 是否改契约 | 证据位置 | 建议批次 |
|---|---|---|---|---|---|---|
| M-1 | 从零创建工程（`project.godot`/`.csproj`/`NuGet.config`） | **partially** | 便利（C# 脚手架为显著摩擦） | 新增才改（171→172）；若只补描述=override | §3.1；`ev-noproj/*`、`ev-last/Y01-Y02` | 描述批次（S）；C# 脚手架并入 M-2 批次（L） |
| M-2 | 编译 C# 程序集 | **confirmed** | 显著摩擦（对 C# 工程近乎阻塞） | **是**（新工具 171→172） | §3.2；契约 171 条 `(build\|compile)` = 0 命中 | 单独立项（L） |
| M-3 | 让工具起的游戏 `--headless` / 加子进程参数 | **confirmed** | 显著摩擦 | **是**（`editor_play_scene` 加参数） | §3.3；`editor_playback.cpp:319-332` + 子进程命令行 | 与 M-5 同批（M） |
| M-4 | 给工具起的游戏指定追踪文件 | **not confirmed**（已被 `project_set_setting` 覆盖） | 便利（残余=文档缺口） | 只补描述=override | §3.4；契约 0 处提及 `trace` | **不做新工具**；描述批次（S） |
| M-5 | 一次调用里「边注入输入边连续采样」 | **confirmed** | 显著摩擦 | **是**（新步类型/新工具） | §3.5；`running_game_test_execution.cpp:893-895` + `G06/G07` | 与 M-3 同批（M） |
| M-6 | InputMap action 持久化 | **not confirmed**（TASK-041 已实现） | 便利（残余=只能一个键盘键） | 只补描述/或扩 schema | §3.6；`editor_input_simulation.cpp:560-668` + `A15/A16/G08` | 描述批次（S）；`events[]` 属新参数（M） |

### 1.2 §2.3 可合并（4 条）与不建议（3 条）

| 编号 | 名称 | 判定 | 阻塞度 | 是否改契约 | 证据位置 | 建议批次 |
|---|---|---|---|---|---|---|
| C-1 | `editor_save_scene{verify}` | **partially**（共现无法在仓库内复测；能力已被覆盖） | 便利 | **是**（加参数） | §4.1；`A03`/`A05` | 不做 / 或与 C-2 同批（S） |
| C-2 | `editor_open_scene{include_tree}` | **partially**（同上；且 `open_scene` 是隐式前置） | 便利 | **是**（加参数） | §4.2；`A04` | 不做（价值 90% 由 C-3 覆盖） |
| C-3 | `editor_add_nodes_batch` 同批父子 | **confirmed** | **显著摩擦**（失败→全批回滚→级联失败） | **是**（加参数，默认保持现语义） | §4.3；`editor_node_batch_write.cpp:251-258` + `A06/A07/A08/A09` | **批次 B（M）** |
| C-4 | 四个批量工具（写/读/校验/挂脚本） | **partially**（①已存在但语义不同；②游戏侧已有、编辑器侧无；③④确实缺） | 显著摩擦 | 新增=**是**（171→172+）；①=只补描述 | §4.4；契约两锚点均有 `editor_set_node_property_batch` + `A10/A11/A12` | ③④批次 C（M）；①②描述批次（S） |
| C-5 | 把 `open_scene→get_scene_tree→add_nodes_batch` 并成一个工具 | **同意不建议** | — | — | §4.5 | 不做 |
| C-6 | `editor_stop_scene` 的连续尾调用 | **同意不建议**（频次在本锚点**不可复测**：仓库无该 trace） | — | — | §4.6 | 不做 |
| C-7 | 合并 `editor_list_signal_connections` + `editor_analyze_signal_flow` | **同意不建议**（契约两侧明文写差异，实测差异真实） | — | — | §4.7 | 不做 |

### 1.3 §2.4 可优化（13 条）

| 编号 | 名称 | 判定 | 阻塞度 | 是否改契约 | 证据位置 | 建议批次 |
|---|---|---|---|---|---|---|
| O-1 | `Missing required parameter` 不带 `data.suggestion` | **confirmed** | 显著摩擦（横切 171 条） | 只改错误 data（契约不动） | §5.1；`tool_builder.cpp:207-232` vs `tool_registry.cpp:371-377`；`A01/A02/G02` | **批次 A（S）** |
| O-2 | `editor_add_resource_to_node_property` 无 `old_value/new_value` | **confirmed**（影响已被 TASK-040 降低） | 便利 | **是**（返回形状） | §5.2；`editor_write_scene_editor.cpp:710-714`；`A13` | 批次 B（S） |
| O-3 | `editor_connect_signal` 加 `persist` 参数 | **not confirmed**（TASK-040 已修行为并回 `persisted`） | — | — | §5.3；`editor_node_write.cpp:282-288`、`:903-909` | **不做** |
| O-4 | 两个 `events` 是裸 array（无 `items`） | **confirmed** | 显著摩擦（一次失败即换路） | **是**（schema） | §5.4；`X11 -32602 "events[0].type"` | 批次 A（S） |
| O-5 | `steps[].pressed`/`strength` 实现读了、契约没写 | **confirmed** | 便利 | **是**（schema） | §5.5；`running_game_test_execution.cpp:141-148`；`G03` | 批次 A（S） |
| O-6 | `prefix` 无 description；`get_node_properties` 的 null 语义 | **partially**（prefix 描述缺=confirmed；「斜杠改变结果集」=**证伪**；null 语义=**已修**） | 便利 | 只补描述=override | §5.6；`project_read_template.cpp:141-180`；`X01-X04`；`G01` | 批次 A（S） |
| O-7 | 节点找不到时不带候选路径 | **confirmed** | 便利（已有指向 `editor_get_scene_tree` 的 suggestion） | 只改消息（契约不动） | §5.7；`X05/X06` | 批次 A（S） |
| O-8 | 「同一个节点」有 8 种参数名，编辑器端自身分裂 | **confirmed** | 便利 | 描述级=override；真改名=**是** | §5.8；契约普查 | 描述批次（S）；不改名 |
| O-9 | `editor_list_signal_connections` 无界列举 | **confirmed** | 显著摩擦 | **是**（加 `scope`） | §5.9；`A14`（60/60 条编辑器内部，12 659 B） | **批次 B（M）** |
| O-10 | 「按下的键跨调用保留」无人记载 | **confirmed** | 显著摩擦 | 只补描述=override | §5.10；`G03→G04` | 批次 A（S） |
| O-11 | `analyze_mcp_trace.py` 三处取证缺陷 | **confirmed** | 便利（只影响下一轮取证质量） | 否（脚本） | §5.11；`analyze_mcp_trace.py:208-224`；`analysis-game.json` | 批次 D（S） |
| O-12 | 追踪无法分辨「新代已开始」 | **confirmed** | 便利（取证质量） | 否（追踪格式） | §5.12；全模块 `trace_opened` grep = 0；我的 trace 有 **3 处 `seq=1`** | 批次 D（S） |
| O-13 | `editor_setup_collision_shape` 的名字被误读 | **confirmed**（描述级；行为不改） | 便利 | 只补描述=override | §5.13；`X07-X10`（重复调用会嵌套堆叠） | 批次 A（S） |

### 1.4 专项（`REPORT-042 §3.4` 拼接 / `REPORT-043` 整文件重写）

| 编号 | 名称 | 判定 | 阻塞度 | 是否改契约 | 证据位置 | 建议批次 |
|---|---|---|---|---|---|---|
| P-1 | 引擎写出口=整文件重写、手写注释丢失 | **confirmed**（逐字节复测，4/4 注释丢失） | 显著摩擦（数据丢失） | 描述已由 TASK-043 覆盖 | §6.1；`splice-results.jsonl` | 已闭环 |
| P-2 | 「只拼接 `[input]` 条目」的可行性 | **confirmed 可行**（真游戏进程读到、注释保留、幂等） | — | 否（内部实现） | §6.2 | 仅在「保留注释」成为硬需求时立项（L） |
| P-3 | 拼接方案的风险清单 | **confirmed 有真实风险**（我构造出「`[input]` 非末节 → 键落错节、游戏读不到」的可复现反例） | — | — | §6.3 | 与 P-2 同批 |
| P-4 | 五条「整文件重写」描述已写进契约 | **confirmed**（逐字比对） | — | 契约描述层已改（override 23 条） | §6.4；契约 sha `443F1DF2…` | 已闭环 |

### 1.5 计数（精确口径，供排期核对）

**清单 26 条** = §2.2 六条 + §2.3 四条合并与三条不建议 + §2.4 十三条：

| 判定 | 条数 | 逐条 |
|---|---|---|
| **confirmed** | **15** | M-2、M-3、M-5；C-3；O-1、O-2、O-4、O-5、O-7、O-8、O-9、O-10、O-11、O-12、O-13 |
| **partially** | **5** | M-1、C-1、C-2、C-4、O-6 |
| **not confirmed** | **3** | M-4（已被 `project_set_setting` 覆盖）、M-6（TASK-041 已实现）、O-3（TASK-040 已修） |
| **同意「不建议做」（维持现状）** | **3** | C-5、C-6、C-7 |
| 小计 | **26** | 15 + 5 + 3 + 3 = 26 ✔ |

**专项四点**（`REPORT-042 §3.4` 与 `REPORT-043`）：P-1 整文件重写+注释丢失、P-2 拼接可行、P-3 拼接风险、P-4 五条描述已诚实化
→ **全部 confirmed（4 条）**。

| 总计（30 个判定点） | 条数 |
|---|---|
| **confirmed** | **19**（15 + 4） |
| **partially** | **5** |
| **not confirmed** | **3** |
| **同意不建议（无需动作）** | **3** |

> 一句话摘要：**19 条确认成立、5 条部分成立、3 条在本锚点不成立（已修/已被覆盖）、3 条维持现状；
> 其中清单原样可排期的动作项，最该先做的是 O-1、C-3、O-9。**

---

## 2. 方法（每条都走同一套四问）

1. **真的存在吗**：契约（HEAD 的 `tools_list.renamed.json`）+ 源码（`file:line`）+ **我自己的最小复现**（可粘贴请求 → `curl.exe -s -o` 落盘 → sha256）。
2. **是否已被现有工具覆盖**（最重要）：先对 **171 个工具名**做正则普查，再对可疑者**真调**；若已有工具或其组合能做，给确切调用并判 `not confirmed`。
3. **影响面**：对「用工具做真实游戏」的阻塞程度。
4. **实施代价与契约面**：新增工具 = 171→172+；合并 = 条目减少；纯行为/描述修正 = override 层（`_meta.generator_version` 1.11.0、23 条 override）。

命令行口径（所有探针共用）：

```
F:\RustProjects\godot-mcp-pro\code\godot\bin\godot.windows.editor.x86_64.console.exe --headless -e --path <scratch> --mcp-port=9888
curl.exe -s -o <resp.json> -H "Content-Type: application/json" --data-binary @<req.json> http://127.0.0.1:9888/mcp
```

---

## 3. §2.2 缺失工具 —— 逐条明细

### 3.1 M-1 「从零创建一个 Godot 工程」 → **partially**（大部分能力**已被现有工具覆盖**）

**①真的存在吗？** **一半不成立。**

清单的理由是「契约里 `project_create_project` 未注册（**鸡生蛋：没有工程连不上端点**）」。
我的复现把这个前提直接推翻：

| 步骤 | 我的复现 | 结果 |
|---|---|---|
| 1. 空目录（无 `project.godot`）起引擎 | `godot.…console.exe --headless -e --path %TEMP%\audit-racing-backlog\noproject --mcp-port=9891` | **端点起来了**：`GET /mcp` → `{"is_editor":false,"tools":69,"listening":true,...}`（`ev-noproj/status.json`）；`tools/list` = **69 条、0 条 `editor_*`、46 条 `project_*`、23 条 `running_game_*`**（`ev-noproj/tools_list.res.json` 24 559 B，sha `1B0D4751…`）。**角色是 game**（没有工程数据 → 不是编辑器）。 |
| 2. 用**已有工具**写第一份 `project.godot` | `project_set_setting{"key":"application/config/name","value":"bootstrap_probe"}` | `{"created":false,"existed_before":true,"key":"application/config/name","saved":true,"value":"bootstrap_probe"}`；**磁盘上真的出现了 `project.godot`（346 B，sha `0AD6307B…`）**。 |
| 3. 用**已有工具**建场景/脚本 | `project_create_scene_file{"path":"res://scenes/main.tscn"}` → `{"created":true,…}`；`project_create_script{"path":"res://bootstrap.cs","content":"x"}` → `{"bytes":1,"created":true,…}` | 文件都在磁盘上（`scenes/main.tscn`、`bootstrap.cs`）。 |
| 4. 以编辑器身份重启同一目录 | `<engine> --headless -e --path %TEMP%\audit-racing-backlog\noproject --mcp-port=9888` | `{"is_editor":true,"tools":148,"listening":true,"port":9888}`；`tools/list` sha `23f3bd6b…`（与编辑器端点逐字相同）；`project_get_info` → `{"project_name":"bootstrap_probe",...}` | 

→ **「没有工程就连不上端点」是错的**：端点在无工程时以 **game 角色**存在，且 `project_set_setting` / `project_create_scene_file` / `project_create_script` 足以完成引导。

**②是否已被现有工具覆盖？** **绝大部分是。** 确切调用序列（我实测跑通）：

```
1) <engine> --headless --path <空目录> --mcp-port=<port>          # 起 game 角色端点（69 工具）
2) project_set_setting {"key":"application/config/name","value":"<名字>"}   # 写出第一份 project.godot
3) project_create_scene_file {"path":"res://scenes/main.tscn"}
4) project_create_script     {"path":"res://main.gd","content":"extends Node2D\n"}
5) 关掉，再以 --headless -e --path <同一目录> --mcp-port=9888 重启   # 见到 148 条编辑器工具
```

**仍然缺的一小块（这是 M-1 唯一站得住的部分）**：
`project_create_script{path:"res://mcp_probe.csproj"}` →
`-32602 Parameter 'path' must name a script file (.gd or .cs), got 'res://mcp_probe.csproj'`（`project_script_write.cpp:122`），
`res://NuGet.config` 同样被拒。→ **`.csproj`/`NuGet.config` 这两份文件目前没有任何工具能生成**（`ev-last/Y01-Y02`）。
对 C# 工程（正是试测场景）这一块仍需手写。

**③影响面**：引导本身=**便利**（有绕法，且绕法只是「先起 game 角色」）；C# 工程脚手架=**显著摩擦**（每次新建 C# 工程都要手写两个文件）。

**④代价与契约面**：不需要新工具也能做（因此「缺失工具」判定为 partially）；若要更好用，两条路：
(a) **零契约成本**：把上述 5 步引导写进 `project_set_setting` / `project_create_scene_file` 的 `description`（override 层）；
(b) **新工具** `project_create_project{path, name?, dotnet?, …}`（171→172），内部就是上面 5 步的封装 + `.csproj`/`NuGet.config`
（后者需要新增「写工程文件」能力，见 §5.2 同一批）。**批次规模 S（描述）/ M（封装）**。

### 3.2 M-2 「编译 C# 程序集」 → **confirmed（真缺口）**

**①真的存在吗？** **成立（能力缺口），但「是否有别的路径」只证到一半。**

* 契约普查：171 条工具名里 `(build|compile)` **0 命中**（`survey_contract.py`）；没有任何工具能触达 `dotnet`/MSBuild。
* 唯一的近似工具是我本轮**实测**的 `project_validate_script`，它的机制是
  `ScriptLanguage *language = ScriptServer::get_language_for_extension(ext); … script->set_source_code(source); script->reload();`
  （`project_read_files.cpp:299-320`）——即**只对单个脚本调 `reload()`**，不写 `.csproj`、不产出程序集、不报 warnings。
* **诚实标注**：本锚点的构建是 `module_mono_enabled=no`，`--version` 无 `.mono.`；`bin\godot.windows.editor.x86_64.mono.console.exe`
  是 `4.8.dev.mono.custom_build.019c4b019`（**≠ HEAD**，用它就违反 D86）。所以
  **「`CSharpScript::reload()` 到底会不会真的编译出 assembly」我无法在本锚点证明**——清单里 B-b 留下的问题在本报告里仍然是「未证」。

**②是否已被现有工具覆盖？** **否。** 没有工具、也没有工具组合能编译 C#（`project_validate_script` 只验单文件语法；`editor_reload_plugin` 是 GDExtension 插件重载）。

**③影响面**：**显著摩擦（对 C# 工程近乎阻塞）**：`[Export]`/`[Signal]` 只有在程序集建好后才能被编辑器看到，而这一步目前必须在工具外跑 `dotnet build`。

**④代价与契约面**：**新增工具 ⇒ 契约 171→172**。`project_build_csharp{configuration?="Debug", target?}` → `{ok, assembly_path, sha256, warnings[], errors[], duration_ms}`。
实现要点（给下一批的输入）：进程内跑 MSBuild/`dotnet build` 是**跨进程**动作（`OS::execute`/`create_process`），必须解决
超时、并发调用（两个 build 同时写 `obj/`）、错误输出捕获、以及「编辑器是否需要 rescan/reload assembly」。
**批次规模 L**（新工具 + 过程执行 + 门 + 契约 + 证据）。

### 3.3 M-3 「让工具起的游戏 `--headless` / 给子进程加命令行参数」 → **confirmed**

**①真的存在吗？** 成立，三份独立证据：

* 契约：`editor_play_scene.inputSchema` = `{mode, mcp_port}` —— **没有** `headless`/`extra_args`（契约 sha `443F1DF2…`）。
* 源码：`editor_playback.cpp:319-332`
  ```cpp
  Vector<String> play_args;
  play_args.push_back("--mcp-port=" + itos(game_port));   // 只注入端口
  … run_bar->play_main_scene(false, play_args);            // 引擎本来收的是数组
  ```
* **我的最小复现**：`editor_play_scene{mode:"main"}` → `pid=65272`，其命令行（`Get-CimInstance Win32_Process`）是
  `…x86_64.exe --path C:/Users/wyl/AppData/Local/Temp/audit-racing-backlog/proj --remote-debug tcp://127.0.0.1:6007 --editor-pid 62124 --scene res://scenes/main.tscn "--mcp-port=9889"`
  —— 除了引擎自己加的 `--remote-debug/--editor-pid/--scene` 与工具注入的 `--mcp-port=9889`，**没有任何调用方可控参数**（`p_editor.out.txt`）。

**②是否已被现有工具覆盖？** **否**（`editor_play_scene` 不收这类参数；`os_deploy_to_android_device` 自己组 `--headless` 但那是 Android 导出，不是「起被观测的游戏」）。

**③影响面**：**显著摩擦**：`--headless` 是 CI/无显示器环境的常规需求；试测里必须绕过工具自启进程（`b7_headless_mode.ps1`）。

**④代价与契约面**：**`editor_play_scene` 加可选参数 = 改契约（条目数不变，但 `inputSchema` 变）**。建议
`{mode?, mcp_port?, headless?:bool=false, extra_args?:string[]=[]}`，响应回 `args_injected[]`；`headless` 落地为 `--headless`（或
`--display-driver headless`，需按引擎实际接受的形式实测）。**批次规模 M**（与 M-5 同批）。

### 3.4 M-4 「给工具起的游戏指定追踪文件」 → **not confirmed（已被现有工具覆盖）**

**①真的存在吗？** **不成立（作为「缺失工具」）。** 现有工具链已经能做到，我实测跑通：

```
project_set_setting {"key":"godot_mcp/trace_file","value":"C:\\…\\audit-racing-backlog\\ev-editor\\trace-game.jsonl"}  → ok
editor_play_scene   {"mode":"main","mcp_port":9889}                                                                  → ok（子进程起来）
→ 子进程按工程设置启用追踪：文件存在且被写入；随后 8 条 tools/call 全部落进该文件（3 102 B）
```

源码侧同样明确：`mcp_server.cpp:500-522`（`godot_mcp/trace_file` / 点号别名 `godot_mcp.trace_file`，命令行 > 工程设置 > 关闭），
子进程读**自己的**工程设置，所以由工具起的游戏同样生效。

**②是否已被现有工具覆盖？** **是。** 确切调用：`project_set_setting{key:"godot_mcp/trace_file", value:"<绝对路径>"}`（比 `--mcp-trace` 更容易从工具面完成）。

**残余（这一半是真的）**：契约里 **`trace` 一词出现 0 次**（`findstr /i trace tools_list.renamed.json` → 0 行）；
该设置键只写在 `docs/DESIGN-DETAIL.md:854` 与 `REPORT-038`，**调用方从工具面看不到**。
→ 所以「必须知道一个没被契约提到的设置键」这条**隐式依赖 I-4 成立**，但它属于**文档缺口（可优化）**，不是缺失工具。

**③影响面**：便利。
**④代价与契约面**：只补描述（override 层，`editor_play_scene` 的 `description` 里写「要追踪就 `project_set_setting{godot_mcp/trace_file}`」）。**批次 S**。

### 3.5 M-5 「一次调用里『边注入输入边连续采样』」 → **confirmed**

**①真的存在吗？** 成立：

* 契约 `running_game_run_test_scenario.steps[].properties.type` 的 `enum` = `["input","wait","assert"]`（契约 sha `443F1DF2…`）。
* 源码同样只有三种：`running_game_test_execution.cpp:311/315/340`（解析）、`:427/432`、`:893-895`（枚举字面量 `input/wait/assert`）。
* **我的最小复现**：`running_game_run_test_scenario{steps:[{type:"sample",node_path:"/root/Main/Car",properties:["position"],frame_count:3}]}`
  → 拒绝（`G06`，146 B）；而分开两次调用 `run_test_scenario{…input…}`（`G03` ok）→ `running_game_get_node_property_samples{…}`（`G07` ok，384 B）就能做到。

**②是否已被现有工具覆盖？** **否**（组合能做，但需要 2 次调用，且依赖 §5.10 那条**没写**的「键状态跨调用保留」语义）。

**③影响面**：**显著摩擦**（试测里必须用「先按不松、再单独采样、最后松」三步绕）。

**④代价与契约面**：**是**（新步类型或新工具）。风险点：单响应会变大（试测用例 3 属性×180 帧 = 23 020 B），需要
`max_samples` 或分页/截断策略；deferred 通道（跨帧）本身已存在，采样步必须走 deferred。**批次 M**。

### 3.6 M-6 「把 InputMap action 持久化进 `project.godot`」 → **not confirmed（TASK-041 已实现）**

**①真的存在吗？** **不成立。** 这是本审计里**最典型的「已在别处修过」**：

* 源码：`editor_input_simulation.cpp:647-667` 注释明写 *"TASK-041 section 2 (M-6) … the tool now also publishes the action's real
  state … and then **reads the file back off disk**"*，实现是 `MCPTools::persist_input_action(map, trimmed, persist_reason, &publish)`
  （`tool_helpers.cpp:842-862`，经 `publish_project_settings_to()` → `save_custom()`）。
* **我的最小复现**：`editor_add_input_action{"action":"audit_action","key":"J"}` 的响应键为
  `action, action_state, created, event_count, key, persisted, persisted_reason, project_entry, target`（`persisted:true`）；
  `project.godot` 从 328 B 变 871 B 且**含 `audit_action`**；第二次同参调用**字节不变**；
  **游戏进程**里 `InputMap.has_action("audit_action") == true`（`A15/A16/G08`）。

**②是否已被现有工具覆盖？** 它就是现有工具（无需新增）。

**残余（两处真的仍在，但都是「能力边界」而非「缺失工具」）**：

1. **一次调用只能绑一个键盘键**：schema `{action, key}`（契约），实现 `_make_key_event(keycode,true,false,false,false)`
   （`editor_input_simulation.cpp:605-608`）→ 不能加鼠标键/手柄轴/同一动作多键。
2. **`project_set_setting` 无法表达这类值**：`input/<action>` 的值是含 `Object(InputEventKey,…)` 的 `Array`，
   而 `project_set_setting` 的类型白名单（`project_setting_write.cpp:110-138`）**没有 Object 类型** → 调用方无法自己拼。

**③影响面**：便利（主路径可用）。
**④代价与契约面**：若要做残余 1，`editor_add_input_action` 加 `events?:[{type:"key"|"mouse_button"|"joypad_button"|…}]`（改 schema，条目数不变）。**批次 M（可选）**。

---

## 4. §2.3 合并建议 —— 逐条明细（含**合并后签名草案**与**不合并的理由**）

### 4.1 C-1 `editor_save_scene{verify}` → **partially**

* **现象**：`editor_save_scene` 的 schema 只有 `{path}`；实测响应 125 B 只有 `{"saved":true,"path":…}`，**没有** `sha256`/`bytes`/`verify`（`A03`）。
* **是否已被覆盖**：**是** ——「保存后自证落盘」用现有一对工具就能做：`editor_save_scene{}` + `project_read_scene_file_content{"path":"res://scenes/main.tscn"}`
  （我实测两者都 ok，`A03`/`A05`）。**合并降低的是往返次数，不是能力**。
* **共现频次**：清单说 5 次；**我在本锚点无法独立复测**（该 trace 不在仓库里，仓库证据只有 `CALL-LOG.jsonl` 与 130 个响应体；
  且 `CALL-LOG.jsonl` 记录的 `seq=43→44` 等配对属于**他人产物**，按纪律不采信）。→ 判 partially 而非 confirmed。
* **合并后签名草案**：`editor_save_scene{path?:string, verify?:bool=false}` → 原响应 + `{sha256:string, bytes:int}`（`sha256` 必须与读文件工具同口径）。
* **不合并的理由也写出来**：`project_read_scene_file_content` 还必须保留（读任意 `.tscn` + 给全文）；
  且「保存」与「读回」是两件事，合并后若只想保存就要多付一次文件读取/哈希的成本。
* **③影响面**：便利（L）。**④代价**：加参数=**改契约 schema**；**批次 S**，价值不高，**建议不做或与 C-2 同批**。

### 4.2 C-2 `editor_open_scene{include_tree}` → **partially**

* **现象**：`editor_open_scene` schema 只有 `{path}`；实测响应 126 B 只有 `{"opened":true,"path":…}`（`A04`）。
* **是否已被覆盖**：**是**（`editor_get_scene_tree` 就是下一个调用，且路径已经现成）。
* **注意**：`open_scene` 是**隐式前置**（不开场景，编辑器节点工具一律 `-32000 No scene is currently open`，我实测 `M1b`）——
  所以「open→tree」的共现是**必然**的，不代表调用方需要合并。
* **合并后签名草案**：`editor_open_scene{path, include_tree?:bool=false, max_depth?:int=-1}` → 原响应 + `{tree?}`。
* **不合并的理由**：响应会从 ~126 B 涨到最多 13 412 B（清单自己引的 `lineno 270`）；`include_tree=false` 时行为逐字不变，收益≈0。
* **③便利 / ④改契约 schema / 批次 S，建议不做。**

### 4.3 C-3 `editor_add_nodes_batch` 支持同批父子 → **confirmed（建议做）**

* **现象（源码级）**：`editor_node_batch_write.cpp:251-258`
  ```cpp
  // The parent is resolved before the node is constructed, so a refused
  // element does not even allocate an orphan.
  Node *parent = find_node(p_root, parent_path);
  if (parent == nullptr) { … _transaction_fail(…) }
  ```
  父路径按**请求开始前的树**解析，且失败即**整批回滚**（`:100-146` 的逆序 `memdelete`）。
* **我的最小复现**：`editor_add_nodes_batch{nodes:[{type:"Node2D",name:"P1"},{type:"Node2D",parent_path:"P1",name:"C1"}]}`
  → `-32001`，消息含 `nodes[1]: parent 'P1'`；随后 `editor_get_scene_tree` **没有任何 `P1`**（回滚干净，`A06/A07`）。
* **绕法**：分两次调用（先建父、再建子）都 ok（`A08/A09`）→ 每深一层多一次往返；试测里导致 3 次失败 + 20 次级联失败。
* ****是否已被现有工具覆盖**：否**（`editor_add_node` 是单节点版，组合 = 分多次 `add_nodes_batch`，正是被抱怨的绕法）。
* **合并后签名草案**：`editor_add_nodes_batch{nodes:[…], resolve_within_batch?:bool=true}`
  —— 语义：同一批内按数组顺序**边建边注册**父节点；`false` 时**逐字保持现语义**；失败仍保持「第 i 项 + 全或无」的定位（`data.batch.{status,errors,rolled_back,on_error}` 已存在）。
* **不合并/不生效的理由**：无（这是**同一工具的 4 次调用本可以是 1 次**，不是把两个工具并成一个）。
* **③显著摩擦 / ④改 schema（加参数，条目数不变） / 批次 B，S–M（源码循环内一次 `find_node` 顺序调整 + doctest + 线上证据）。**

### 4.4 C-4 四个批量工具 → **partially（①已存在但语义不同；②半覆盖；③④确实缺）**

清单列了四件：①`editor_set_node_property_batch{updates:[…]}`、②`editor_get_node_properties_batch`、③`project_validate_scripts`、④`editor_set_node_script_batch`。

| 子项 | 判定 | 证据 |
|---|---|---|
| ① 任意 updates 批量写 | **partially** | **工具已存在**（`editor_set_node_property_batch`，**在试测锚点 `f34ee937f` 的契约里就有**，我 `git show` 出来对照过），但它的语义是**同类型节点 + 一个属性 + 一个值**：`{node_type, property, value}`。实测：`{node_type:"CharacterBody2D",property:"collision_layer",value:2}` → ok（`A10`）；而 `{updates:[{path,property,value}]}` → **被拒**（`A11`）。→ 「57 次单点写」中**同类型同属性**那部分其实早就能一次做完，是**没被试用者发现**；但**跨类型/跨属性的任意批量仍缺**。 |
| ② 编辑器侧批量读 | **partially** | 游戏侧 `running_game_get_node_properties_batch` 存在（契约，且 `REPORT-040` 有 per-item 语义）；**编辑器侧无**：`editor_get_node_properties_batch` → 未注册（`A12`）。 |
| ③ `project_validate_scripts`（复数） | **confirmed 缺** | 契约 171 条只有 `project_validate_script`（单文件）。 |
| ④ `editor_set_node_script_batch` | **confirmed 缺** | 契约无此工具。 |

* **合并后签名草案**：
  * ②`editor_get_node_properties_batch{paths:[string], properties?:[string]}` → `{results:[{path,properties}|{path,error}]}`（per-item，不许一项失败丢全部）；
  * ③`project_validate_scripts{paths:[string]}` → `{results:[{path,valid,message}]}`；
  * ④`editor_set_node_script_batch{assignments:[{node_path,script_path}]}` → `{applied:[…],failed:[{index,…}]}`；
  * ①若要补任意批量：`editor_set_node_property_batch` **不能改语义**（会破既有调用方），应新增 `editor_set_node_property_updates{updates:[{path,property,value}]}`（171→172）。
* **不合并的理由**：①的既有形态（按类型刷同一属性）是**另一个真实需求**（批量给同类节点设层/碰撞位），
  不能被 `updates[]` 取代 → 两者并存，而不是替换。
* **③显著摩擦 / ④新增=改契约面（171→172+） / 批次 C（M）。**

### 4.5 C-5 三步并一 → **同意不建议**

`editor_open_scene → editor_get_scene_tree → editor_add_nodes_batch` 三步并一后，失败时**无法定位**是哪一步；
而且这三步里真正的问题是 `add_nodes_batch` 本身（C-3）。同意清单结论：只做 C-3（+可选 C-2）。

### 4.6 C-6 `editor_stop_scene` 连续尾调用 → **同意不建议（频次不可复测）**

4 次连续同参尾调用是**调用方脚本**的收尾习惯（无参幂等调用），不是工具面缺陷；
「`stop_scene` 也单独出现」使它不满足「必然成对」的判据。**本锚点无法复测频次**（trace 不在仓库），
但结论不依赖频次：**无参幂等调用不需要合并**。

### 4.7 C-7 合并两个信号工具 → **同意不建议**

契约两侧**明文写了差异**，我逐字核对（契约 sha `443F1DF2…`）：

* `editor_list_signal_connections`：*"收全部连接（不过滤非持久连接）、`node_path` 与 `signal_name` 均按**子串**匹配"*；
* `editor_analyze_signal_flow`：*"只收集**持久连接**（CONNECT_PERSIST，值为 2；注意 Godot 4 中 flags & 1 是 CONNECT_DEFERRED，不是持久连接）、`node_path` **精确**匹配、无 `signal_name` 过滤"*。

两者的答案**必然不同**且都已被文档化 → 合并会同时毁掉两种能力。**同意不合并。**
（§A AC-6 要求「三个工具答案一致」是**判据缺陷**，不是工具缺陷——我在契约层面独立确认。）

---

## 5. §2.4 可优化 —— 逐条明细

### 5.1 O-1 缺必填参数时没有 `data.suggestion` → **confirmed**

* **证据**：`tool_builder.cpp:207-232`（`require_string`/`require_int` 的缺失分支只给 `"Missing required parameter: " + p_key`）
  vs `tool_registry.cpp:359-377`（未知参数侧给 `Accepted parameters of <tool>: …`，`:373`）。
* **我的最小复现**：
  * `editor_set_node_property{property:"visible",value:true}` → 93 B，`{"code":-32602,"message":"Missing required parameter: path"}`，**无 `data.suggestion`**（`A01`）；
  * 同工具加一个未声明参数 `zzq_unknown` → 223 B，**带** `data.suggestion="Accepted parameters of editor_set_node_property: path, property, value"`（`A02`）；
  * 游戏端点：`running_game_get_autoload_node{}` → 93 B，无 suggestion（`G02`）。
* **是否已被覆盖**：不是能力问题，是**错误消息质量**问题（且横切 171 条工具）。
* **③显著摩擦**（一次失败后调用方要么猜、要么先 `tools/list`）。
* **④代价**：**零契约成本**（契约不动；`error.data` 是行为面）。实现上**不必改 ~30 个 handler**：
  `MCPToolRegistry::call_tool`（`tool_registry.cpp:380-388`）与 `call_deferred_tool` 两个入口已经拿到 `def`，
  可在 handler 返回 `-32602` 且 `error.data` 为空时**统一补**同一条 suggestion。**批次 A（S）**。

### 5.2 O-2 `editor_add_resource_to_node_property` 无 `old_value/new_value` → **confirmed（影响已被降低）**

* **证据**：`editor_write_scene_editor.cpp:710-714` 只写 `node_path`/`property`/`resource_type`；实测响应 166 B 无 `old_value`/`new_value`（`A13`）。
* **重要更正**：**TASK-040 已把「报成功但什么都没发生」这条缺陷修掉**（`assign_resource_to_property()`，
  `tool_helpers.cpp:2370-2391`，内部先 `object_has_property()` 再写；`editor_write_scene_editor.cpp:697-708` 的注释逐字说明它来自哪个缺陷）。
  所以 O-2 现在只剩「**写进去了，但写成了什么值**不可判定」这一半（例如 `resource_properties` 被 `coerce_to_property_type` 收敛后的实际值）。
* **是否已被覆盖**：部分——可以先写再 `editor_get_node_properties` 读回（2 次调用）。
* **③便利 / ④改返回形状（schema 之外，但契约 `_meta` 认为返回形状属描述面；实现上不动 inputSchema） / 批次 B（S）。**

### 5.3 O-3 `editor_connect_signal` 加 `persist` 参数 → **not confirmed（TASK-040 已修）**

* 源码：`editor_node_write.cpp:282-288`
  ```cpp
  // so the connection is remade with `CONNECT_PERSIST`: …
  if (p_source->connect(p_signal, callable, Object::CONNECT_PERSIST) != OK) { … }
  ```
  响应 `:903-909` 增加诚实字段 `result["persisted"] = persisted;`（注释逐字指向「试测的 `[connection]` 计数是 0」）。
* 清单建议的 **`persist:bool=true` 开关已无必要**（默认就该持久化；给开关反而多一条「可以不持久化」的歧义）。
* **③— / ④— / 不做。**

### 5.4 O-4 两个 `events` 是裸 array（无 item schema） → **confirmed**

* 契约：`editor_simulate_input_sequence.events` = `{"type":"array"}`（无 `items`）；`running_game_play_input_recording.events` 同样。
* **我的最小复现**：`editor_simulate_input_sequence{events:[{keycode:"W",pressed:true}]}`
  → 103 B `{"code":-32602,"message":"Missing required parameter: events[0].type"}`，**无 suggestion**（`X11`）；
  加上 `"type":"key"` 后成功（`X12`，199 B）。→ 调用方只能靠试错知道 `type` 的取值集合。
* **③显著摩擦 / ④改 schema（`items` 声明 enum 与各字段）= 契约面变（描述层之外的 inputSchema 变） / 批次 A（S）。**
  建议同时给 `description` 一个**完整可粘贴样例**（与 `items` 双保险）。

### 5.5 O-5 `steps[].pressed`/`strength` 实现读了、契约没写 → **confirmed**

* 实现：`running_game_test_execution.cpp:141-148`（`optional_bool(p_step,"pressed",true,…)`、`optional_float(p_step,"strength",1.0,…)`）；
  契约 `steps[].properties` 的九个键里**没有**它们（`443F1DF2…`）。
* **我的最小复现**：`running_game_run_test_scenario{steps:[{type:"input",keycode:"W",pressed:true}]}` → ok（`G03`）。
* **③便利（L）/ ④改 schema（补两个键） / 批次 A（S）。** 归因提示：`_reject_unknown_arguments` 只查顶层，嵌套成员不受闸门约束（`tool_registry.cpp:331-354`）——这一点也值得在契约里写明。

### 5.6 O-6（两项） → **partially**

**(a) `project_get_settings.prefix` 连 `description` 都没有 → confirmed（描述缺口）**，且我把它真正该写的语义测清楚了：

| 调用 | 结果 |
|---|---|
| `{"prefix":"godot_mcp"}` | `{"count":1,"settings":{"godot_mcp/trace_file":"…"}}`（234 B） |
| `{"prefix":"godot_mcp/"}` | **逐字相同**（234 B，sha 相同） |
| `{"prefix":"godot_mcp/tr"}` | **逐字相同**（234 B） |
| `{"prefix":"od_mcp"}` | `{"count":0,"settings":{}}`（102 B） |

源码 `project_read_template.cpp:141-180`（`:168` `name.begins_with(prefix)` 过滤 `settings->get_property_list()`）与实测一致。

> **★纠错（D86 复测）**：清单 `OBS-018④/O-6` 说「`prefix` **尾随斜杠**改变结果集（`godot_mcp` → 105 B vs `godot_mcp/` → 254 B）且无文档」。
> 我的复测表明：**语义是 `begins_with`，斜杠不改变结果集**；那 105→254 的差异是**状态变化**（`seq=3` 发生在
> `project_set_setting{godot_mcp/trace_file}`（`seq=39`）**之前**，当时 `godot_mcp*` 一个键都还没有）。
> → **「斜杠敏感」不成立**；真正该写进描述的是「**是前缀匹配、不是子串匹配**」。

**(b) `running_game_get_node_properties` 对不存在的名字回 `null` → not confirmed（已修）**：
`running_game_observation.cpp:153-181` 现在先用 `object_has_property()` 判存在，缺失即 `-32001`（注释逐字写 *"TASK-040 D-3 …so the two sides can no longer answer 'there is no such property' and 'its value is null' for the same name"*）。
**我的最小复现**：`running_game_get_node_properties{node_path:"/root/Main/Car",properties:["collision_layer","physics_material_override"]}`
→ `-32001`（302 B，`G01`），与同端点的写工具结论一致。→ **清单 D-3 / O-6 的 null 语义已不存在**。

* **④** (a) 只补描述=override；(b) 无需改动（若要，也可在描述里补一句「缺失名字会 `-32001`」）。**批次 A（S）**。

### 5.7 O-7 节点找不到时不带候选路径 → **confirmed**

* 源码 `editor_write_scene_editor.cpp:669-673`（`not_found(vformat("Node '%s'", node_path), "Use editor_get_scene_tree to list the nodes of the edited scene")`）。
* **我的最小复现**：`editor_set_node_property{path:"Carr",…}` → `{"-32001","Node 'Carr' not found"}` + 上面那条 suggestion（170 B，`X05`）；
  `path:"Car/NoSuchChild"` → 同样只有一句（181 B，`X06`）。**没有**候选路径/兄弟节点名。
* **③便利**（`data.suggestion` 已能让调用方自纠，试测里正是它让调用方 3 分钟内自纠）。
* **④改消息（契约不动） / 批次 A（S）。** 有了 §5.1 的横切改造后，这条是纯增强（附最近邻候选）。

### 5.8 O-8 参数名不统一 → **confirmed（计数与清单一致）**

我的独立普查（契约 `443F1DF2…`）：`node_path` **51**、`path` **36**、`name` **20**、`parent_path` **9**、`scene_path` **2**、`source_path` **2**、`target_path` **2**、`player_path` **1**；**没有任何工具同时用 `path` 和 `node_path`**。
编辑器端自身分裂：`editor_*` 102 条里 `node_path` **46** / `path` **8** / `name` **16** / `parent_path` **9**。

* **③便利（L）** —— 试测里这确实制造了「同一个东西要试两个名字」的摩擦，但每次都靠 §5.1 的 suggestion 自纠。
* **④**：清单的两条建议里，**「description 里互相指路」= override 层（零风险）**；**真正统一命名（加别名）会动 `inputSchema` 与 171 条逐字门** → **不建议**。**批次 A（S，只做指路）。**

### 5.9 O-9 `editor_list_signal_connections` 无界列举 → **confirmed**

* 契约：`editor_list_signal_connections` 的 schema 只有 `{node_path?, signal_name?}`（子串过滤），描述明写「收**全部**连接（不过滤非持久连接）」。
* **我的最小复现（一个 5 节点的小场景）**：`{}` → 响应 **12 659 B**、`count=60`；**60/60 条的 `method` 都是编辑器内部方法**
  （`ScriptEditor::_queue_update_list`、`SceneTreeEditor::_node_script_changed`、`Viewport::canvas_parent_mark_dirty` …），
  即「用户自己一条连接都没连，答案里全是编辑器的」。
  （试测场景更大 → 434 条 / 94 862 B，同一个机理。）
* **注意过滤维度**：这些内部连接的 `source` 是**场景节点路径**（`.`、`Car`、`Button`…），所以按 `source` 过滤没用；
  真正能区分的是 `method`（含 `::`）或 `target`（编辑器 UI 路径）→ **设计 `scope` 时必须以 method/target 为依据**。
* **③显著摩擦 / ④加 `scope?:"scene"|"all"`（默认 `scene`）或 `include_editor_internal?:bool=false`，保留 `signal_name` 精确过滤=改 schema / 批次 B（M）。**

### 5.10 O-10 「按下的键跨调用保留」无人记载 → **confirmed**

* 契约 `running_game_run_test_scenario.description` 只有一句「运行测试场景并执行一系列测试步骤」。
* **我的最小复现**：调用 1 `steps:[{type:"input",keycode:"W",pressed:true}]` → ok（`G03`，253 B）；
  **随后另一次调用** `running_game_execute_gdscript{code:"return Input.is_key_pressed(KEY_W)"}` → `{"result":true,"result_type":"bool"}`（`G04`，115 B）；
  再调 `pressed:false` 才松开（`G05`）。
* **③显著摩擦**（这条未文档化的语义正是 M-5 绕法成立的前提，也是「忘了松键」会污染后续断言的陷阱）。
* **④只补描述=override / 批次 A（S）。**

### 5.11 O-11 取证脚本三处缺陷 → **confirmed**

* 源码 `analyze_mcp_trace.py:208-224`：`shapes(counter,size)` 对 unigram 也走 `list(gram)` → **字符串被拆成字符数组**。
* **我自己的复现**：用我在 `project.godot` 里打开追踪后产生的 trace（28 条 `tools/call`，**3 个不同 editor 进程代次**）
  跑该脚本：`analysis-game.json` 的 `unigrams[0]` = `{"sequence":["r","u","n","n","i","n","g","_",…],"length":1,"count":3}`
  （字符数组）；`bigrams=[]`、`trigrams=[]`——**尽管同一次会话里 `running_game_run_test_scenario` 被连调 3 次**。
  原因与清单一致：`mergeable()` 按 `connection` 分桶（`:196-198`），而 `connection` 在正常 HTTP 工作流里**每次请求都是新值**
  （我的 trace 里 connection = 2..9，逐条不同）→ 每个桶只有 1 条，n-gram **结构性恒空**。
* **③便利（只影响下一轮取证质量，不影响工具本身）/ ④脚本，不动契约 / 批次 D（S）。**
  修法（我建议的顺序）：①`sequence` 用 `[gram] if isinstance(gram,str) else list(gram)`；②当每桶只有 1 条时**声明退化**并按文件顺序/`ts_ms` 间隔分簇；
  ③在摘要里说明 `result_bytes` 是**含 JSON-RPC `id` 的信封长度**。

### 5.12 O-12 追踪无法分辨「新代已开始」 → **confirmed**

* `grep -r "trace_opened" modules/mcp_server/**` → **0 命中**（实现里根本没有这一行；只有报告里提到）。
* **我的复现（副作用证据）**：同一个 `trace-game.jsonl` 被我 3 次启动的编辑器进程**连续追加**，
  文件里出现 **3 个 `seq==1`**（28 行、9 990 B），却**没有任何**「新代开始/pid/既有字节数」的记录；文件也不含 `initialize`
  （因为我没发 `initialize`），所以除了 `seq==1` 之外没有别的代次线索。
* **正面结论**：`mcp_trace.cpp` 是**纯追加**（清单对 OBS-005「模块 O_TRUNC」的纠正是**对的**，我在本锚点再次确认）。
* **③便利（取证质量）/ ④追踪格式 + ≈6 行代码，不动契约、不动打开语义 / 批次 D（S）。**

### 5.13 O-13 `editor_setup_collision_shape` 语义陷阱 → **confirmed（只改描述）**

* 契约描述：「为物理体添加碰撞形状」；源码注释 `editor_node_setup.h:102`「Adds a `CollisionShape2D`/`CollisionShape3D` **under `p_node_path`**」。
* **我的最小复现**：
  * `{node_path:"Car"}` → `{"collision_node_path":"Car/CollisionShape2D",…}`（260 B，`X07`），树里 `Car/CollisionShape2D`；
  * **再对形状节点本身调一次** `{node_path:"Car/CollisionShape2D"}` → `{"collision_node_path":"Car/CollisionShape2D/CollisionShape2D",…}`（`X09`），树里出现**嵌套的形状**（`X10`）。
* **③便利 / ④只补一句描述（override 层，不改行为、不改名）/ 批次 A（S）。**
  附带证据：响应**已经**如实回 `collision_node_path`，所以「诚实」这一半清单说对了；我额外发现**重复调用会嵌套堆叠**，
  可以作为描述里「要挂在物理体上请传物理体路径；不要在形状节点上重复调用」的实证。

---

## 6. 专项：`project.godot` 拼接发布 与 整文件重写实测（`REPORT-042 §3.4`、`REPORT-043`）

> 这一节**全部是我自己复测**的（样本是**本 fork 自带**的带注释工程 `modules/gdscript/tests/scripts/project.godot`，
> 407 B / sha256 `d26d99504f66f29f62bb72b5045fd15eacbdaefc5ea9ae512660e9089e0c98ca`——与其报告的样本 sha 一致，
> 我**只读**它、把副本写进 `%TEMP%\audit-racing-backlog\splice\`）。

### 6.1 P-1 整文件重写 + 注释丢失（**confirmed**）

`editor_add_input_action{"action":"audit_spliced","key":"J"}`（在副本工程上）：

| 事实 | 我的实测值 |
|---|---|
| 重写前后 | **407 B → 860 B**（sha `d26d9950…c98ca` → `de76a0e9…ae1011`） |
| 手写注释 | **4/4 行全部丢失**（`comments lost 4/4`，丢的就是那 4 行 `;`） |
| 其余内容 | 原文件里「不再逐字存在」的**恰好是那 4 行注释**（`original_non_empty_lines_no_longer_present = 4`，内容就是那 4 行） |
| 既有 `[input]` 多行块 | `test_input_action={ "deadzone": 0.2, "events": [] }` **逐字节保留** |
| 引擎固定头 | 新第一行 = `; Engine configuration file.` |
| 引擎新增 | `config/features=PackedStringArray("4.8")`（原文件没有） |
| 幂等 | 第二次同参调用 **sha 不变**（`S02`，`action_state=pre_existing_unchanged`、`project_entry=unchanged`） |

→ **REPORT-042 §3.2 的结论在我的锚点逐条成立**（字节数 860 vs 其 869 的差异来自引擎版本/序列化细节，不影响任何结论）。

### 6.2 P-2 拼接方案可行（**confirmed 可行**）

做法（复刻其 spike）：从引擎刚写完的文件里取出**它自己序列化**的那一条（21 行 / **377 字符**，
`audit_spliced={ "deadzone": 0.2, "events": [Object(InputEventKey,…)] }`），**追加**到**原始 407 字节**之后（原文件 `[input]` 是末节）：

| 检查 | 我的实测 |
|---|---|
| 原始 407 B 是否为拼接结果的**精确前缀** | **是**（逐字节比较） |
| 注释 | **4 行全部保留** |
| 拼接结果 | 785 B / sha `259dd744…916660`；重复拼接**字节相同**（纯函数） |
| `--import` 之后 | 文件 sha **不变**（`--import` 不重写工程文件） |
| **真游戏进程能读到吗** | 起了真实 game 进程（`is_editor:false`、69 工具），`running_game_execute_gdscript`：`InputMap.has_action("audit_spliced") = true`、`action_get_events(...).size() = 1`、且**既有的 `test_input_action` 仍在** |
| 游戏运行是否改动文件 | **sha 不变**（只读） |

→ **「只改 `[input]` 段的局部发布」在引擎之外确实可行**，方案的行为规格可照 REPORT-042 §3.4 采纳。

### 6.3 P-3 风险清单（逐条，**每条都有实证或源码依据**）

| # | 风险 | 我的实证/依据 | 严重度 |
|---|---|---|---|
| R1 | **`[input]` 不是最后一个节 → 追加的键落进别的节** | **我构造了反例并实测**：把原文件尾部加上 `[rendering]` 段后，同一段文本追加到文件末尾（=落进 `[rendering]`），真游戏进程读 `InputMap.has_action("audit_spliced")` = **false**，而旧动作仍 true（`S06/S07`）。→ 朴素「追加到文件尾」**会静默失败**。 | **高** |
| R2 | **重复键 / 已存在同名动作** | 若文件里已有 `audit_spliced=`，追加会产生重复键；`ConfigFile` 对重复键的行为需实测（本轮未测），且幂等性判定必须显式做「键是否已存在」 | 高 |
| R3 | **`[input.<feature>]` 这类 feature override 段** | 引擎的 `save_props` 支持 `input/<action>.<feature>`（我在 `project_get_settings` 的默认列表里看到 `input/ui_close_dialog.macos` 等 `.macos` 变体）→ 拼接器必须识别而不误判 | 中 |
| R4 | **BOM / CRLF / 行尾** | 我只在 LF、无 BOM 的样本上测过；拼接是**字节级**操作，CRLF 文件追加 LF 行会把风格撕裂（引擎仍能读，但「逐字节保留」的承诺变复杂） | 中 |
| R5 | **转义与多行格式** | 引擎序列化用的是 `VariantWriter::write_to_string(value, vstr, true)`（多行、`Object(...)`、属性名经 `property_name_encode()`）；手写/换行的任何差异都可能让引擎解析出不同对象 | 中 |
| R6 | **并发写** | 模块的写出口是「临时兄弟文件 + rename」（`tool_helpers.cpp:558-566`）；拼接器若直接改原文件，就与 `project_set_setting`/`editor_add_input_action` 的原子写**产生两种并发语义**，必须串行化或加锁 | 中 |
| R7 | **与 `project_set_setting` 行为不一致** | 后者仍是**整文件**重写。同一工程上两个工具「一个保注释、一个不保」会让调用方无法预测 | 中 |
| R8 | **引擎版本/格式漂移** | 拼接依赖引擎当前的多行序列化文本；升级引擎后格式可能变（我的样本 377 字符 vs REPORT-042 的 386 字符就是**锚点间的格式差异**） | 中 |
| R9 | **无法安全处理时必须拒绝** | 需要明确的兜底：检测到 R1/R2/R3/R4 任一 → **拒绝并回落整文件**或直接报错，**不猜** | 高（设计要求） |

### 6.4 P-4 五条描述已诚实化（**confirmed**）

契约里这 5 条 `description` **都以同一句英文收尾**（我逐字比对 `443F1DF2…`）：
`project_set_setting`、`project_add_autoload`、`project_remove_autoload`、`editor_add_input_action`、`editor_reload_plugin`
——句尾都是 *"…it rewrites the entire project.godot with the engine's own whole-file writer (the engine has no partial-publish API), so every hand-written comment in that file is lost…"*。
`_meta.generator_version = 1.11.0`、`_meta.overrides = 23`（与 REPORT-043 §3.2 一致）。
另外我独立复查了写出口普查：`tools/**` 里只有 4 个文件触达 E1/E2/E3 三条链
（`project_setting_write.cpp:218`、`project_autoload_write.cpp:150/181`、`editor_input_simulation.cpp:665`、`editor_write_scene_editor.cpp:396-397`）
→ 「受影响工具恰好 5 个」成立。**REPORT-043 的结论在契约与源码两侧都复核通过。**

**关于整文件重写的处置建议**：现状（描述已诚实 + 注释会被丢）对**多数用户**可接受；
只有「保留注释」被确认为硬需求时才值得做拼接器（L 批），且**必须**把 R1–R9 写进行为规格与 doctest。

---

## 7. 建议排期

### 7.1 最该先做的 3 条

1. **O-1（缺必填参数补 `data.suggestion`）** —— 横切 171 条工具、**零契约成本**、实现集中在两个入口
   （`tool_registry.cpp:380` 的 `call_tool` 与 `call_deferred_tool`），是本清单里**性价比最高**的一条。证据：`A01/A02/G02`。
2. **C-3（`editor_add_nodes_batch` 同批父子）** —— 唯一在「真实建场景」路径上**必然踩到**的行为级摩擦（失败→全批回滚→级联失败），
   改动小（同一个循环里顺序建父）、语义可保持向后兼容（默认 `resolve_within_batch=false` 或显式参数）。证据：`editor_node_batch_write.cpp:251-258` + `A06/A07/A08/A09`。
3. **O-9（`editor_list_signal_connections` 加 `scope`）** —— 实测 5 节点小场景就有 60/60 条编辑器内部连接、12.6 KB；
   真实场景 94 KB。加一个默认值安全的参数即可，且能顺手把 `description` 写清「`source` 过滤不掉内部连接」。证据：`A14`。

> 第 4 位（**最大真缺口**）：**M-2 `project_build_csharp`**。它是唯一「没有工具能做、也没有组合能做」的能力，
> 但需要跨进程执行 + 超时/并发/输出捕获，属**独立 L 批**，不宜塞进小批次。

### 7.2 批次划分（按契约面与风险分组）

| 批次 | 内容 | 契约面 | 规模 |
|---|---|---|---|
| **A（描述与错误消息）** | O-1、O-4、O-5、O-6(a)（`prefix`）、O-7、O-10、O-13、O-8（只做指路）、M-1(a)、M-4（补 `trace_file` 指路）、C-4①②（写清既有批量工具的语义边界） | 描述 override（`_meta.overrides` +若干）；O-1/O-7 只动 `error.data`；O-4/O-5 动 `inputSchema` | S |
| **B（参数/返回形状）** | C-3（`resolve_within_batch`）、O-9（`scope`）、O-2（`old_value/new_value`） | `inputSchema` + 返回形状；条目数不变 | M |
| **C（新工具/新能力）** | M-2（`project_build_csharp`）、M-1(b)（`.csproj`/`NuGet.config` 脚手架）、M-3（`headless`/`extra_args`）、M-5（采样步）、C-4③④（`project_validate_scripts`、`editor_set_node_script_batch`、可选 `…_updates`） | **171 → 172+** | L |
| **D（取证工具，不改工具面）** | O-11（分析器三处）、O-12（`trace_opened` 一行） | 无（脚本 + 追踪格式） | S |

**建议顺序**：A → B → D → C（C 里先 M-3/M-5 这一对，再 M-2；M-2 与 C# 脚手架同批做最自然）。

### 7.3 明确**不建议做**

| 不建议 | 理由（我的判定） |
|---|---|
| **O-3 给 `editor_connect_signal` 加 `persist` 参数** | 行为已在 TASK-040 修好并回 `persisted`；加开关反而引入「可以不持久化」的歧义（§5.3） |
| **C-5 三步并一** | 失败无法定位；真正的问题在 C-3（§4.5） |
| **C-6 合并 `editor_stop_scene`** | 无参幂等调用，频次不可复测也不影响结论（§4.6） |
| **C-7 合并两个信号工具** | 两者语义**故意不同**且契约两侧都写了；合并会毁掉两种能力（§4.7） |
| **O-8 的激进版（把 `path`/`source_path`/`target_path` 全面改名为 `node_path`）** | 会动 `inputSchema` 与 171 条逐字门，收益只是手感；只做描述指路（§5.8） |
| **C-2（`open_scene` 合并树）** | 收益≈0，响应可从 126 B 涨到 13 KB；`open_scene` 与 `get_scene_tree` 本来就必须依次调用（§4.2） |
| **现在做 `project.godot` 拼接器** | 已被证实**可行**，但 R1–R9 未解决（尤其 R1 我复现了静默失败）；只有「保留注释」成为硬需求时才立项（§6.3） |
| **改 `editor_get_scene_tree.max_depth` 的默认值**（原 OBS-009 建议） | 契约默认**已经是 `-1`（无限）**，是调用方显式传了 6/8/12；该建议基于错误归因，**撤回**（我逐字核对契约） |
| **按清单原样做 M-4 / M-6 两个新工具** | M-4 已被 `project_set_setting` 覆盖；M-6 已在 TASK-041 实现（§3.4/§3.6） |

---

## 8. 我发现的、清单里没有的新问题

| # | 新发现 | 证据 | 建议 |
|---|---|---|---|
| **N-1** | **无工程目录下引擎是「game 角色」而不是编辑器**（`is_editor:false`、69 工具、**0 条 `editor_*`**），而 `project_set_setting` 会**创建** `project.godot`。→ 这是一条**没有任何工具文档描述过的引导路径**（M-1 的「鸡生蛋」假设正是被它推翻）。 | `ev-noproj/status.json`、`tools_list.res.json`（sha `1B0D4751…`）、`N03` 之后磁盘上出现 346 B 的 `project.godot`（sha `0AD6307B…`） | 写进 `project_set_setting`/`project_create_scene_file` 的描述（批次 A）；或封装成 `project_create_project`（批次 C） |
| **N-2** | **非 Mono 构建下 `project_validate_script` 对合法 `.cs` 报 `valid:false / ERR_PARSE_ERROR`**：`get_language_for_extension("cs")` 返回 null 时**回退到 GDScript**（`project_read_files.cpp:302-305`），于是「用 GDScript 解析 C#」的结论被当成「编译失败」报出来（我实测：合法 C# 文件 → `{"error_text":"ERR_PARSE_ERROR","valid":false}`）。 | `ev-last/Y03`（创建 109 B 的合法 `.cs`）→ `ev-last/Y04`（`valid:false`，sha `a25cf0b9…`） | 当扩展名对应的语言**未初始化**时，返回 `valid:null` + 明确说明「本构建没有该语言」，而不是借另一门语言的解析结论（低优先，但属**诚实性**问题） |
| **N-3** | **`project_create_script` 拒绝 `.gd`/`.cs` 之外的路径**（`-32602 Parameter 'path' must name a script file (.gd or .cs)`）→ 没有任何工具能写 `.csproj`/`NuGet.config`/`.cfg` 这类工程文本文件。这是 M-1 残余的**最具体边界**。 | `project_script_write.cpp:122`；`ev-last/Y01`、`Y02` | 若要支持 C# 工程脚手架，需要一个「写工程文本文件」的受限能力（白名单扩展名 + 大小上限），并入 M-2 批次 |
| **N-4** | **`editor_setup_collision_shape` 不具备幂等性**：对已存在的 `CollisionShape2D` 再调用会创建 `Car/CollisionShape2D/CollisionShape2D`（嵌套堆叠）。清单只提「名字容易被误读」，没提这个行为面。 | `X07→X09→X10`（树的 JSON 里出现嵌套形状） | 在描述里写清（批次 A）；若要做行为层，需先决策「已存在时改写还是新增」 |
| **N-5** | **O-6 的「`prefix` 尾随斜杠改变结果集」是测量伪影**：105 B（`seq=3`，**设置还不存在**）vs 254 B（`seq=42` 之后）。真实语义是 `begins_with`，斜杠与部分段都不改变结果集。 | 我的 `X01`≡`X02`≡`X04`（234 B 逐字相同）、`X03`（`od_mcp`→count 0）；源码 `project_read_template.cpp:168` | 描述里写「前缀匹配（不是子串）；`godot_mcp` 与 `godot_mcp/` 等价」 |
| **N-6** | **证据保全风险（方法论）**：本审计 224 个证据文件全在 `%TEMP%\audit-racing-backlog\`（有 `evidence-manifest.txt` 逐文件 sha256），`%TEMP%` 会被清理；而清单的 trace 原文（`trace-editor.jsonl` / `trace-game.jsonl`）在仓库里**根本不存在**——这正是我无法独立复测 C-1/C-2/C-6 频次的原因，也印证了 `RACING-FINDINGS §0.3` 的告诫。 | 仓库 `docs/reports/evidence/racing/` 只有 `CALL-LOG.jsonl` + 130 个响应体；`glob **/*trace*` 无命中 | 下一批把关键证据**当场复制进仓库**（本轮按任务书「只写报告」未复制） |
| **N-7** | **`data.suggestion` 的覆盖面本身有第二层缺口**：`running_game_get_node_properties` 缺失**必填**参数时无 suggestion（`G02`），但**未知参数**时有（`tool_registry.cpp:373`）；同理 `editor_simulate_input_sequence` 的 `events[0].type` 缺失也无 suggestion（`X11`）。→ 与 O-1 同根，但值得用「**所有 `-32602` 都附 accepted-parameters**」的一条规则一次性解决（含嵌套路径 `events[0].type` 的定位信息）。 | `A01`、`G02`、`X11` vs `A02` | 并入 O-1 的实现（批次 A） |

---

## 9. 判定口径与限制（诚实声明）

1. **锚点差异**：清单测自 `f34ee937f`，本报告测自 `5ee2c596a`。**工具名集合逐字相同（171）**，但 `f34ee937f`→HEAD 之间
   有 TASK-040/041/042/043/049 等批次，因此**清单里相当一部分条目已经不再成立**（这本身是最重要的确认结论）。
2. **未能实测的部分**：
   * **C# 编译语义**（M-2 / 旧 B-b）：本锚点构建 `module_mono_enabled=no`，mono 二进制停在 `019c4b019`（≠HEAD）→ 只证到
     「没有工具能跑 MSBuild」「`project_validate_script` 只对单文件调 `set_source_code()+reload()`」「非 Mono 构建会回退到 GDScript 解析」，
     **没有**证明 `CSharpScript::reload()` 是否真的产出程序集。
   * **C-1 / C-2 / C-6 的共现频次**：原始 trace 不在仓库，且按纪律不采信他人报告 → 我只判其**能力是否被覆盖**（是），频次判「不可独立复测」。
   * **拼接的 CRLF/BOM/重复键/feature override 段**（R2/R3/R4）：只做了 R1 的**可复现反例**，其余按源码与默认设置列表推断，标为风险而非实测。
3. **线上证据全在 `%TEMP%`**（224 文件 / `evidence-manifest.txt` 有逐文件 sha256）：端口 9888/9889 + 一次性 9891（仅我校验并清理自己的进程）；
   **9877 全程无监听、未被绑定**（每次运行的 `owner before == after == -1`）。
4. **本报告未修改任何实现、测试、契约、脚本或其它报告**；仓库唯一新增物是本文件。
