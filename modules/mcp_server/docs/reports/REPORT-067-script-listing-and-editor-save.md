# REPORT-067 — `project_list_scripts` 对 `.cs` 失明 + 「编辑器自身保存吃注释」的根因与第三个补丁

> 任务书：`docs/tasks/TASK-067-script-listing-and-editor-save.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`。
> 依据：`REPORT-066-csharp-breakout.md`（F-066-1…F-066-7）、`BREAKOUT-FINDINGS-R4.md`（§8.2/§8.3、§9）。
> 本报告的全部结论只在下表锚点上成立。

## 0. 元信息与锚点（D86）

| 项 | 值 |
|---|---|
| 角色 / 任务 | 实现工程师 / TASK-067 |
| 状态 | **完成**：两件主事都有实测证据与修复；7 条发现逐条给了修/不修的理由；五道门 + 门⑥ 三段式 + 三个契约机器检查全部 exit 0；无阻塞 |
| **工作树锚点** | `git rev-parse HEAD` = **`716957c26e`**（`git rev-parse --short=9` = `716957c26`） |
| **改动文件（5 个，+585 / -38）** | `core/config/project_settings.cpp`、`core/config/project_settings.h`、`editor/editor_node.cpp`、`modules/mcp_server/tools/project_read_files.cpp`、`modules/mcp_server/tests/test_mcp_server.h`（`git diff --stat` 逐字见 §4.5） |
| **契约** | `docs/tools_list.renamed.json` sha256 = **`d4e53b43840b6537af9dfbefdc77e7fb4ed6202ee23f3016503a7a53953e7ecd`**，条数 **176** —— 与 TASK-065A / R3 / REPORT-066 的基线**逐字相同**（本批前后同 sha，§4.5 打印）。**未生成、未手改契约，`DESCRIPTION_OVERRIDES` 未加一条。** |
| 二进制（最终） | plain `bin\godot.windows.editor.x86_64.console.exe` = `4.8.dev.custom_build.716957c26`；mono `bin\godot.windows.editor.x86_64.mono.console.exe` = `4.8.dev.mono.custom_build.716957c26`。两者都 `--version == HEAD`（§4.5 打印）。 |
| **⚠️ 版本串不是构建锚点（本批必须显式声明）** | `--version` 报的是**源码 revision**，而本批的修复**不改变 HEAD**：改动前与改动后的二进制**报同一个串** `716957c26`。因此「哪个二进制是 pre-fix」不能靠 `--version` 分辨，只能靠**构建日志时间 + 源码 mtime + 红/绿输出**三重对照：pre-fix plain 构建 `11:47:17`、pre-fix mono 构建 `11:51:55`，而 5 个被改文件的 mtime 全部 **≥11:52:43**（§4.5 的打表）。 |
| 端口纪律 | 9877 在**每次** live 运行前后都断言无监听（`netstat … LISTENING` 解析，§2.2/§3.5 的 `p0_port_9877_free_*`）；只用 9888（编辑器）/9889（游戏）；只 stop 自己 `Start-Process` 的 PID（`Stop-OwnProcess`） |
| 构建纪律 | **严格串行**（全程只有一个 scons 进程；本报告所有构建的日志与退出码可查，§4.5）；从 cmd 启动；输出**从不**经管道（`build_local.cmd` / `mcp057_build_mono.cmd` 自己重定向到 `%TEMP%` 日志） |
| 禁止 push | 未 push；只做本地提交 |
| 结论锚点约定 | 本报告每个结论后面标「证据」：`evidence/task067/…` 下的**绝对路径前缀**是 `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task067\` |

---

## 0.1 一句话结论

| # | 任务书要求 | 结论 | 关键数字 |
|---|---|---|---|
| ① | `project_list_scripts` 对 `.cs` 失明：复核 → 查引擎来源 → 修 | **已复核（独立，非引用上游）→ 已修** | 修复前：`{"count":2,"scripts":[ProbeGd.gd,ProbeGd2.gd]}`，同进程 `project_read_script{res://scripts/Main.cs}` 却 `size=2389` 读得回来；修复后：`count=10`，`res://scripts` 的 **6 个 `.cs` + 2 个 `.gd` 全部列出**，且**逐条是同一个形状**（路径字符串） |
| ② | 编辑器自身保存吃注释：定根因（文件:行）+ 最小复现 + 第三个补丁 | **根因已定位到行 → 已打补丁 → 注释逐字保留** | 根因 `editor/editor_node.cpp:1062-1072`（`!cmdline_mode` 分支里的整文件 `save()`）+ `:8479`（`cmdline_mode` 来自 headless）。窗口化启动前 `project.godot` sha `cca8e45d…`（4 条手写注释）→ 启动后 `cd4ebe43…`（**4 条全部消失**，只剩引擎自己的 7 行头注释）；打补丁后同一条链：`cca8e45d…` → `dcc50cbd…`，**4 条探针注释逐字、按同一顺序全在**，且 `[input]`（非末节）里的那条仍在 `[input]` 内 |
| ③ | REPORT-066 的 7 条逐条说明修/不修 | **2 条修（①②即 F-066-1/F-066-2），5 条不修且逐条给出代码/契约依据** | §3 的表 |
| 契约 | 条数不变 | **176，sha 不变** | `d4e53b43840b…` |
| 门 | 五道门 + 门⑥ 三段式 + 三个机器检查 + `accept_m1` ×2 | **全部 exit 0** | §4 |

---

## 1. ① `project_list_scripts` 对 `.cs` 失明

### 1.1 先独立复核（不引用上游报告的结论）

用**本批自己**的 harness（`scripts/mcp067_live.ps1`）在**改动前的 mono 二进制**（`11:51:55` 构建）上跑一条链，请求/响应**逐字节落盘**（`mcp_evidence_guard.ps1` 的 `<leaf>__<seq>__<sha8>` 命名，写后重算 sha 并断言相等）：

工程：`%TEMP%\mcp067\proj-mixed` —— A 的 TASK-066 C# fixture（`REPORT-066` §1.1 的 10 个 sha256）的副本，**本批复核过副本保真**：那 10 个文件在 `%TEMP%\mcp067\proj-mixed` 上重算 sha256，**10/10 MATCH**（例：`project.godot 4973072B5A74…`、`scripts/Main.cs 14C4AAA24DD1…`）；另加两个 GDScript 文件（`scripts/ProbeGd.gd`、`scripts/ProbeGd2.gd`），构成 GDScript + C# **混合**工程。

| 调用 | 结论 | 证据（sha256 在文件名里） |
|---|---|---|
| `project_list_scripts{}` | **`{"count":2,"scripts":["res://scripts/ProbeGd.gd","res://scripts/ProbeGd2.gd"]}`** —— 6 个可读 `.cs` **一个都没有** | `run-mono-prefix\mono-prefix_p1_list_scripts__0001__*.response.json`；派生的集合/形状表 `…_p1_list_scripts_summary__0001__2c8be770.summary.json` |
| `project_read_script{"path":"res://scripts/Main.cs"}`（**同进程、同一时刻**） | **成功**：`{path:res://scripts/Main.cs, size:2389}` —— 文件在、可读、就在 walk 的根下面 | `run-mono-prefix\mono-prefix_p1_read_main_cs__*.response.json` |
| `project_get_filesystem_tree{"path":"res://scripts"}` | **成功**，17 条路径，`Main.cs` **在** | `run-mono-prefix\mono-prefix_p1_fs_tree_scripts__*.response.json`；路径表 `…_p1_fs_tree_paths__0001__660a3fba.summary.json` |
| 磁盘事实 | `res://scripts` 下 **6 个 `.cs` + 2 个 `.gd`**，另有 2 个**生成**的 `.cs` 在 `res://.godot/mono/temp/obj/Debug/` | `p1_mixed_fixture_has_both_languages :: res://scripts cs=6 gd=2 generated .cs elsewhere=2` |

**结论（独立复核成立）**：不是「C# 脚本不存在 / 不可读 / 未被索引」，而是**该工具的枚举谓词把 `.cs` 排除了**。这条把 F-066-1 从「上游的说法」变成了本批的实测事实。

### 1.1b 本批自己的一次构造纠正（为什么「独立复核」不是走形式）

第一版 harness 的 `Reset-MixedProject` 用 `Copy-Item <源目录> -Destination <已存在的目录> -Recurse` 复制 A 的 C# fixture —— 这在 PowerShell 里会把源目录**嵌进去**变成 `proj-mixed\proj\...`，于是编辑器的 `res://` 是 `proj-mixed`（**根下没有 `project.godot`**），而磁盘统计用的 `Get-ChildItem -Recurse` 仍然找到了 8 个 `.cs`。结果是 `project_list_scripts` 回 `count=2` —— **看起来正是 F-066-1**，但那是**另一个原因**（`res://scripts` 里当时只有我新加的两个 `.gd`）。
证据：被取代的那次运行留下的 `run-mono-prefix\mono-prefix_p1_fs_tree_paths__0001__660a3fba.summary.json`（`Main.cs visible to the indexed tree=False`）与 `p1_crosscheck_the_cs_is_a_readable_project_script` 的 **FAIL（`-32001`）** —— **这两个信号就是矛盾点**：一个「可读的工程脚本」读不回来，说明构造本身错了。

修正：`Reset-MixedProject` 改为**复制目录内容**，并**加一条断言** `p1_mixed_fixture_root_is_a_project`（`project.godot` 必须在根）。之后 `p1_crosscheck_the_cs_is_a_readable_project_script :: size=2389` 与 `fs_tree` 17 条路径含 `Main.cs` 同时成立，`cs=0` 才成为**真的** F-066-1。两次运行的产物都在证据树里保留，`evidence/task067/README.md` 明确标出**哪几个文件被取代、不要引用**。

> 这条纠正值得写进报告的原因：任务书要求「**先独立复核**，别只信上游报告」——本批实测证明，**一个错误的构造也能产出与缺陷完全相同的现象**（`count=0`/`count=2`）。判别它们靠的不是现象本身，而是**第三个工具的观察**。下一批做同类复核时应沿用这条判式。

### 1.2 引擎侧「脚本枚举」的真实来源（`文件:行`）

| 候选 | 位置 | 本批的裁定 |
|---|---|---|
| **`ScriptServer`（**采纳**）** | `core/object/script_language.cpp:239` `ScriptServer::register_language()`；`:221` `get_language(int)`；`:227` `get_language_for_extension()`；`core/object/script_language.h:224` `ScriptLanguage::get_extension()` | **唯一同时满足「完整」与「诚实」的来源**：它列出的正是**这个构建真的注册了的脚本语言**。GDScript 注册 `"gd"`（`modules/gdscript/register_types.cpp:143-144` → `modules/gdscript/gdscript.cpp:2215-2217`）；`.NET` 模块注册 `"cs"`（`modules/mono/register_types.cpp:57` → `modules/mono/csharp_script.cpp:98 String CSharpLanguage::get_extension() { return "cs"; }`）—— **只有编译进 mono 模块时才有**，所以 plain 构建**不会**声称自己有 C#（与 TASK-050 N-2 / `project_validate_script` 的 `language_unavailable` 口径一致）。注册顺序是固定的，所以同一构建内两次调用的集合确定。 |
| `ResourceLoader` | `ResourceLoader::get_recognized_extensions_for_type("Script")`；`.cs` 的 loader 在 `modules/mono/csharp_script_resource_format.cpp:103` | **否决**：结果依赖「loader 是否已注册且可用」，是**资源载入**视角而不是**语言**视角；而且它把 `Script` 与 `Shader` 混在一个「资源类型」抽象里，而本工具的语义是「这个构建的脚本语言」。 |
| `EditorFileSystem` | 编辑器索引（本批实测它**能看到** `Main.cs`，见 §1.1 第三行） | **否决**：这是**编辑器进程专有**的视图，`project_list_scripts` 的 `scope` 是 **BOTH**（9889 游戏进程也要能答），在游戏进程里没有这个单例。 |
| 硬编码扩展名过滤（修前） | `modules/mcp_server/tools/project_read_files.cpp:172` `entry.ends_with(".gd") \|\| entry.ends_with(".gdshader")` | **就是缺陷本身**：一个**构建无关**的字面量集合，所以任何非 GDScript 语言都被静默漏掉。 |

### 1.3 修法（`modules/mcp_server/tools/project_read_files.cpp`，+81 / −10）

```cpp
static Vector<String> _script_extensions() {          // 新增：语言集合从 ScriptServer 派生
    Vector<String> extensions;
    const int language_count = ScriptServer::get_language_count();
    for (int i = 0; i < language_count; i++) {
        const ScriptLanguage *language = ScriptServer::get_language(i);
        if (language == nullptr) { continue; }
        const String extension = language->get_extension();
        if (!extension.is_empty()) { extensions.push_back("." + extension); }
    }
    extensions.push_back(".gdshader");                 // 见下：唯一一个不是 ScriptLanguage 的
    return extensions;
}
```

**每一处为什么这样设计（逐条）**

1. **集合从 `ScriptServer` 派生，而不是写死 `.cs`**：写死 `.cs` 会让 plain 构建声称自己认识 C#，正是 PLAYBOOK 记录过的「照迁移源复刻坏行为」的同类问题（TASK-050 N-2：曾经拿 GDScript 的解析器回答 `.cs` 的合法性）。派生之后 **构建有什么语言就列什么**，判据①的「两种脚本都被列出」与「plain 不撒谎」由同一条代码同时满足。
2. **`.gdshader` 保留**：shader 是 `Shader`（由 `ResourceFormatLoaderShader` 载入），**不是** `ScriptLanguage`，所以派生集合里没有它；保留是因为迁移源列它、且它是这个问题的另一个文本文件类型（`REPORT-005` 的观测契约不变）。
3. **比较仍然大小写敏感**：`upper.GD` 仍不算脚本，与迁移源 `ends_with(".gd")` 逐字一致；现有 doctest 的这一条断言**一字未改**（§4.2 的 TASK-005 用例仍绿）。
4. **walk 本身一字未改**（只跳过 `.` / `..`，`.godot` / `.hiddendir` / `addons` 都进）：这是参考实现声明过的怪癖，且被现有 doctest 的 `.hiddendir/secret.gd` 断言**钉住**（`tests/test_mcp_server.h:2985`）。**代价必须明说**（见 1.4）。
5. **集合顺序 = 语言注册顺序**：同一构建内确定，满足「同一构建内 `tools/list`/结果确定性」的同族要求。

### 1.4 修复后实测（判据）与一条**显式声明的后果**

在**改动后的 mono 二进制**（`12:09:39` 构建）上重跑同一条链（`mcp067_live.ps1 -Phase post -Label mono-head`）：**35/35 检查通过**。

| 判据 | 实测 | 检查 id |
|---|---|---|
| 两种脚本都列出 | `{"count":10}`；`res://scripts` 里 **`.cs` 6 条 + `.gd` 2 条**；另有 2 条生成 `.cs` | `p1_POST_both_languages_listed` |
| **字段形状一致** | `scripts` 是**扁平的路径字符串数组**（**10/10** 条都是 JSON string），两种语言**没有任何形状差异**；`count == scripts.size()` | `p1_every_entry_is_a_path_string`、`p1_count_is_the_array_size` |
| 与磁盘逐条对齐 | `res://scripts` 的 `.cs` 列出 **6 == 6**；`.cs` 全量 **8 == 6 + 2**（生成）；`.gd` **2 == 2** | `p1_POST_cs_count_matches_disk`、`p1_POST_gd_count_matches_disk` |
| 判据来自**引擎**而非字面量 | 单测里注册一个**构建前一无所知**的临时 `ScriptLanguage`（扩展名 `gdprobe`）→ 该文件立刻出现在答案里；卸载后不再出现 | §4.2 的 `project_list_scripts lists the script languages the build registered` |
| 契约条数不变 | 176 / sha `d4e53b43…` 前后同值 | §4.5 |
| 描述仍诚实 | 契约描述「列出所有脚本文件」在修复**之前**就是假的、修复**之后**才成立；**因此不需要 override，契约文件零改动** | `docs/tools_list.renamed.json` 未变 |

> **⚠️ 显式声明的后果（不是缺陷，是必须让读者知道的事）**：因为 walk 仍然深入 `.godot`，一个真实 mono 工程的**构建生成** `.cs` 也会被列出：本批实测 2 条 ——
> `res://.godot/mono/temp/obj/Debug/.NETCoreApp,Version=v8.0.AssemblyAttributes.cs` 与
> `res://.godot/mono/temp/obj/Debug/McpBreakoutCs.AssemblyInfo.cs`（`p1_POST_godot_cache_cs_is_declared_not_silent`）。
> **本批不收紧 walk**，理由是**两个硬约束**：(a) 收紧 `res://.godot` 会改动参考实现声明过的跳过规则，而 `.hiddendir/secret.gd` 必须仍被收集，这条断言是**已发布证据的一部分**；(b) 把「哪个目录是生成物」写进工具，需要一个**新的**机器可验证判据（哪种目录名算生成物），不能靠本批顺手塞进去。→ 见 §5 的 next_step 建议。

---

## 2. ② 编辑器自身保存吃注释

### 2.1 根因（`文件:行`）与最小复现

**根因（一条链，逐行给依据）**

| 步骤 | 位置 | 事实 |
|---|---|---|
| 1 | `editor/editor_node.cpp:8479` | `cmdline_mode = (DisplayServer::get_singleton()->get_name() == "headless");` |
| 2 | `editor/editor_node.cpp:1062` | `if (!cmdline_mode) {` —— **窗口化编辑器才会走到下面**；这就是「`--import` / `--headless` 不吃注释、窗口化启动吃」的全部原因（F-066-2 的观测由此闭合） |
| 3 | `editor/editor_node.cpp:1063-1070` | 取 `project.godot` 路径；文件 < 10 字节时先落 `get_initial_settings()`（`editor_node.cpp:8462`，**7 条全都带 `/`**，无顶层键） |
| 4 | **`editor/editor_node.cpp:1071`** | **`ProjectSettings::get_singleton()->save();`** ← **真凶**。`save()` = `save_custom(project.godot)`（`core/config/project_settings.cpp:1086`）→ `_save_settings_text()`（`:1162`），后者**先写 7 行自己的头注释、`config_version`，再把内存里「非默认」的每个设置按自己的排序全量重写**（`:1168-1207`）。于是**人类写进去的注释、空行、键序全部消失**。 |
| 5 | 对照：工具写入 | 写工具（`project_set_setting` / `editor_add_input_action`）自 TASK-057 补丁 2 + TASK-059 起走 `ProjectSettings::save_custom_section()`（`core/config/project_settings.cpp:1682`）→ `update_settings_section_text()`（`:1537`），**只重写目标节、其余字节原样复制** —— 与第 4 步是**两条不同的路径**，本批把两者**分开测量**（§2.2 的 D/F 两点）。 |

**最小复现（改动前，mono 二进制 `11:51:55` 构建）**

工程 `%TEMP%\mcp067\proj-comments`：`project.godot` 541 字节，含 **4 条手写探针注释**，其中
- 注释 1 在**任何节之前**（文件顶层）；
- 注释 2 在 `[input]` **头之上**；
- 注释 3 在 `[input]` **内部、action 之后**（**`[input]` 不是末节**：后面还有 `[physics]` 与 `[rendering]`）；
- 注释 4 在最后一个节 `[rendering]` 内。

| 快照点 | 事件 | 字节 | sha256 | 注释行数 | 4 条探针注释存活 |
|---|---|---|---|---|---|
| A | 手写（`Reset-CommentProject`） | 541 | `cca8e45dd98ffc239ab204bd6a5d5beb19249e95ec41ea767f83c89747530d10` | 4 | True,True,True,True |
| B | `--headless --import` 之后 | 541 | **同上（逐字节未变）** | 4 | True,True,True,True |
| D | **窗口化编辑器启动之后**（MCP 端口已就绪 + 3 s） | — | `cd4ebe43706b27d0f5acd5974154601585ac3041ac43399ed25bc4f3b432fb30` | **7**（引擎自己的头注释） | **False,False,False,False** |
| F | 之后 4×`editor_add_input_action` + … + `project_set_setting`（**工具写入**） | — | — | 7 | False,False,False,False |
| E | 会话结束后 | — | — | 7 | False,False,False,False |

- **文件真的被编辑器改过**：`p2_the_editor_really_wrote_the_file`（启动前后 `LastWriteTimeUtc` 不同）。
- **判别力**：同一个文件、同一批字节，`--import` 逐字节不动，而**窗口化启动**把 4 条注释全部抹掉 —— 差异可**归因**到「哪个进程路径写了它」，不是环境噪声。
- **两条路径分开陈述**：D（编辑器自身写入）丢了注释；F（工具写入）**一条注释行都没有动**（`p2_tool_writes_changed_no_comment_line :: D=7 F=7`，且 `probe_action` / `physics_ticks_per_second=61` 都真的落到文件里）。→ 任务书要求的「工具写入 vs 编辑器自身写入」在本批是**两条独立的、可复算的**证据。

### 2.2 第三个补丁（纪律同 D112）

**改动（引擎侧，最小面）**

| 文件 | 改动 |
|---|---|
| `core/config/project_settings.h` | 新增 **public** `Error save_preserving_text();`、**public static** `Error publish_settings_sections_text(text, sections, values, result)`；新增 3 个 private 助手声明（`_collect_settings_for_save` / `_read_settings_text_file` / `_publish_settings_text_file`） |
| `core/config/project_settings.cpp` | 把 `save_custom()` 的「要写哪些设置、按节怎么分组」整段**原样抽出**为 `_collect_settings_for_save()`（纯搬运，`save_custom()` 改为调用它）；把 `save_custom_section()` 的**读半**与**写半**抽成 `_read_settings_text_file()` / `_publish_settings_text_file()`（BOM 保持、兄弟文件+备份+校验字节+rename 回滚，逐字保留）；新增 `publish_settings_sections_text()`（补丁 2 的 `update_settings_section_text()` 之上的一层「一次读、一次写、多节合并」）与 `save_preserving_text()` |
| `editor/editor_node.cpp:1071` 附近 | `ProjectSettings::get_singleton()->save();` → **`save_preserving_text()`**（`project.godot` 存在时）；文件不存在/二进制工程仍走 `save()`（它才是会**创建**工程的那个） |

**为什么这样做（逐条）**

1. **最小**：只改**一个调用点**；`save()` / `save_custom()` / `save_custom_section()` 的**可观测行为逐字不变**（前者只是调用被抽出的同一个函数；后两者只是换了同一段 I/O 的位置）。其它工具与编辑器侧其它 `ProjectSettings::get_singleton()->save()` 调用点（`findstr` 在 `editor\*.cpp` 上计 **27 行**，含 1 行 TODO 注释）**一个都没动**。
2. **朝上游形状**：新能力长在 `ProjectSettings` 里，紧挨 `save()` / `save_custom()` / `save_custom_section()`；文本由引擎自己的 `VariantWriter`（`_save_settings_text` 用的同一个）序列化，**没有引入第二套文件格式知识**；调用点仍然是一行。
3. **复用补丁 2**：`publish_settings_sections_text()` 逐节调用 `update_settings_section_text()`，即任务书要求复用的能力；`_read_settings_text_file` / `_publish_settings_text_file` 是 `save_custom_section()` 原来的两半，**搬运而不是重写**。
4. **保留调用点的两个真实意图**：(a) 落盘编辑器内存里的设置（含 `save_custom()` 现算的 `application/config/features`：渲染 API + 有 `.csproj` 时补 `C#`）——`save_preserving_text()` 发布的**正是** `save()` 会发布的那一套（同一个 `_collect_settings_for_save`，同一 `p_merge_with_current=true`、同一个空 `p_custom`）；(b) **标记「项目刚被编辑过」**（`editor/project_manager/project_list.cpp:866-869` 明写它按 `project.godot` 的 mtime 当「最后编辑时间」）—— 所以 `save_preserving_text()` **总是写**（即使内容没变，写回的也是文件自己的字节），并像 `save()` 一样刷新 `last_save_time`，否则 `editor_node.cpp:1627` 的「外部改动」检测会把这次自己刚做的写当成别人的（`_scan_external_changes()` 就在 `:1102`、同一个 `NOTIFICATION_READY` block 里）。
5. **可被门覆盖**：新增一个 **17 条断言**的模块 doctest（§4.2），直接对**字符串**验证「多节合并 + 注释逐字 + `[input]` 非末节 + 幂等 + 顶层键不误伤」——不需要动运行中项目的 `project.godot`；此外有 §2.3 的**真窗口化**证据。门⑥ 扫描**没有新增收窄点**（新代码唯一涉及字节长度的位置是原样搬走的 `INT32_MAX` 判断，仍在原 `// MCP-NARROWING` 语境里，§4.4 打印 `scanned == pinned`）。

### 2.3 修复后实测（判据）

同一条链，在**改动后的 mono 二进制**（`12:09:39`）上重跑：**35/35 通过**。

| 判据 | 实测 | 检查 id |
|---|---|---|
| 带注释 `project.godot` 经窗口化启动**前后注释逐字保留** | A/B sha `cca8e45d…` → D sha `dcc50cbd…`，D 注释行数 **4**（不是引擎的 7 行头注释） | `p2_POST_startup_kept_every_comment` |
| **逐字**（不是「行数相同」） | 4 条探针注释的**逐字包含**向量 = True,True,True,True；且**注释行序列与 B 完全相同**（不是只有数量对） | `p2_POST_startup_kept_every_comment_verbatim`、`p2_POST_comment_lines_are_the_same_sequence :: B=4 D=4` |
| 含 `[input]` **非末节** | 注释 3 的下标 `701 < [physics]` 的 `760 < [rendering]` 的 `807 <` 注释 4 的 `819` —— 注释 3 **仍在 `[input]` 之内、没有被挪到后面的节** | `p2_nonlast_input_comment_stays_in_its_section` |
| 「启动与保存都不再吃注释」 | 启动后 D 的注释行 **4**；再做工具写入（`editor_add_input_action` + `project_set_setting`）→ F 的注释行 **仍是 4**，探针注释仍逐字在，且两个新设置都落进文件 | `p2_POST_tool_writes_kept_every_comment_verbatim`、`p2_tool_writes_landed_in_the_file` |
| 写入确实发生（不是「根本没保存」） | 启动前后 `LastWriteTimeUtc` 不同（`p2_the_editor_really_wrote_the_file`）；且**有且只有设置行**变了：`only_in_D=5 / only_in_B=1`，逐行 diff 落盘 | `p2_settings_line_diff_recorded` + `…_p2_B_vs_D_line_diff__*.summary.json` |
| 诚实边界（**不主张字节不变**） | 本批**不**声称启动前后逐字节相同：`application/config/features` 会被 `save_custom()` 按「渲染 API + 有没有 `.csproj`」重算，所以一行设置**合法地**变了。判据是「**除了设置以外什么都不变**」，逐行 diff 已落盘可复算。 | 同上 |

---

## 3. ③ REPORT-066 的 7 条：逐条「修 / 不修」及理由

| # | 现象 | 严重度（上游） | 本批处置 | 理由（依据到行/到契约文本） |
|---|---|---|---|---|
| **F-066-1** | `project_list_scripts` 对 `.cs` 失明 | minor–major | **已修** | §1。契约描述「列出所有脚本文件」在修**前**是假的（工具的四条错误文案 `editor_script_write.cpp:271` / `editor_set_node_script_batch.cpp:219,237` / `project_script_write.cpp:234` / `project_validate_scripts.cpp:246` 都叫调用方用它找脚本）。修法**不需要**改契约（见 §1.3 第 1 点），`DESCRIPTION_OVERRIDES` **未加一条**。 |
| **F-066-2** | 窗口化编辑器启动整文件重写 `project.godot`，吃掉手写注释 | medium | **已修（引擎第三个补丁）** | §2。根因在**我们可控范围**（引擎自己的调用点选错了 writer），不是「引擎设计如此」——论据是同一个引擎**已经有**按节发布的 `save_custom_section()`（TASK-057 补丁 2）与已经切过去的一族工具（TASK-059），只是**编辑器自身的启动保存没切**。 |
| **F-066-3** | 单数 `project_validate_script` 与复数 `project_validate_scripts` 形状不同；「未构建」在单数是 `-32000` 而不是结果体 | minor | **不修（口径已由契约写明）** | 契约**文本本身**已经把差别逐字写清：单数 `project_validate_script` 的 `description` 明写「a file nothing has compiled … **is refused with -32000 saying 'not compiled', never answered `valid: false`**」，复数 `project_validate_scripts` 的 `description` 则明写它按 `category ∈ {ok, invalid, not_compiled, language_unavailable, unverifiable}` 回**结果体**。也就是说这是**两个已声明契约的、有意不同的**读法，不是文档缺口。要「统一」只能**改行为**（把单数的 `-32000` 改成结果体）＝ 破坏性变更，而 176 条契约对单数的输入/结果面**没有**授权这个改动；加一个 `data.category` 之类的增量字段又会**制造**契约没写的行为。→ 若决策者要统一，应**另立任务**（改行为 + 改契约描述 + 重生成），本批不擅自扩大面。 |
| **F-066-4** | 游戏进程捕获 `viewport` 恒为 `"game"`，`--mcp-capture-viewport=2d` 在游戏侧被忽略 | 上游判「不是缺陷」 | **不修** | 代码里有据：`modules/mcp_server/mcp_capture.cpp:375-376` 明写「一个游戏进程只有一个窗口」，`viewport` 回的是**生效值**而不是**请求值**——这是**诚实**而不是忽略：游戏侧并没有 2D/3D 主界面之分。改成回显请求值反而会撒谎。R4 也把它标为 informational。 |
| **F-066-5** | 只有 `input` 没有 `assert` 的 `running_game_run_test_scenario` 回 `all_passed:false` | minor | **不修（已声明语义）** | `tools/running_game_test_execution.cpp:596-599` 的注释与 `:243-246` 的实现说明**逐字**写了这条设计：「a scenario that asserted nothing is **not** 'all passed'（that guard is the whole difference between this tool and a tool that always says yes）」。同一响应里 `passed=0 failed=0 errors=0` 已足够让调用方区分「没断言」与「断言失败」；把它改成 `true` 才是**说谎**（一个什么都没验证的场景被读成全绿）。R4 §8.1 也独立复现了同一行为。 |
| **F-066-6** | `.tscn` 的脚本共享形态让「按字面次数」判据不可达 | informational（**判据设计缺陷**） | **不修（无可修对象）** | 这是「判据写法」的问题，不是工具或引擎的行为：3 块砖共用 1 条 `[ext_resource]` + 6 处 `ExtResource(...)`。模块侧没有任何断言依赖这种字面计数（本批 `grep` 未发现），R4 §8 也把它归为判据设计。 |
| **F-066-7** | `editor_connect_signal` 在连接已持久时诚实回 `already_connected:true` | 正面样本 | **不修（定义上不改）** | 上游明写「不建议改」。R4 的 F2（连接 provenance 字段缺失）是**另一个**问题（读回侧），本批未列入任务书，也不在 7 条内。 |

**另：R4 对本报告的 2 条纠错（§8.2/§8.3）本批如何处置**

- **R4 §8.2（`waited_seconds` 回显名陷阱）**：**属文档/口径，本批不修并给出理由**。契约 `running_game_run_test_scenario.inputSchema.steps[].properties` 的**输入**成员是 `seconds`（唯一权威），**结果**回显是 `waited_seconds`（R4 已实测）。要把这层「输入/输出不同名」写进客户端真会读到的那句话，只能走 `DESCRIPTION_OVERRIDES` **append** + 重生成契约（PLAYBOOK §5 的机制），而**它会移动本任务整条证据链所锚定的契约 sha `d4e53b43…`**（`REPORT-066`/`R4`/TASK-065A 全部按它锚定），换来的是一句不改行为也成立的说明；任务书 §1⑤ 对 override 的授权语境是「修 `.cs` 失明时若描述不实」。→ **不修，登记为下一批的候选**（§5）。
- **R4 §8.3（`.dll` 字节数陈旧 19968 → 20992）**：**属试测产物（报告引文）缺陷，只登记不修**。它描述的是 `REPORT-066` 某一时刻的构建产物，`REPORT-066` 是**已发布的历史报告**；按 append-only 勘误纪律，正确做法是**在 R4 里勘误**（R4 已经做了），而不是回填历史报告。本报告不去改 `REPORT-066`。

---

## 4. 门、纪律与机器检查

### 4.1 构建与版本锚定

| 步骤 | 命令（从 **cmd** 启动，输出不经管道） | 日志 | 退出码 |
|---|---|---|---|
| 0（任务书要求的第 0 步，改动前干净树） | `modules\mcp_server\scripts\build_local.cmd -Force`（plain，`tests=yes`） | `%TEMP%\mcp067_build_plain_pre.log`（11:47:17） | 0 |
| 红相位 plain | 同上 + 新测试 | `%TEMP%\mcp067_build_plain_red.log`（11:49:49） | 0 |
| 红相位 mono | `modules\mcp_server\scripts\mcp057_build_mono.cmd`（mono，`tests=yes`） | `%TEMP%\mcp067_build_mono_red.log`（11:51:55） | 0 |
| 绿相位 plain | `build_local.cmd -Force` | `%TEMP%\mcp067_build_plain_green.log`（12:00:15） | 0 |
| 绿相位 mono | `mcp057_build_mono.cmd` | `%TEMP%\mcp067_build_mono_green.log`（12:08:20）→ 修测试期望后 `…_green2.log`（12:09:39） | 0 |
| **最终 plain（门所绑定的构建）** | `build_local.cmd -Force` | `%TEMP%\mcp067_build_plain_final.log`（12:12:20） | **0** |

```
bin\godot.windows.editor.x86_64.console.exe      --version -> 4.8.dev.custom_build.716957c26
bin\godot.windows.editor.x86_64.mono.console.exe --version -> 4.8.dev.mono.custom_build.716957c26
git rev-parse --short=9 HEAD                                -> 716957c26        (both == HEAD)
```

**时间线对照（本批的重要诚实点，见 §0）**：被改的 5 个文件 mtime = `core/config/project_settings.h` 11:54:48、`core/config/project_settings.cpp` 11:54:56、`editor/editor_node.cpp` 11:54:28、`modules/mcp_server/tools/project_read_files.cpp` 11:52:43、`modules/mcp_server/tests/test_mcp_server.h` 12:08:45 —— **全部晚于**两个 pre-fix 构建（11:47:17 / 11:51:55），**全部早于**最终 plain 构建（12:12:20）。

**红/绿输出与构建日志已入库**（任务书要求「红相位输出当场保存」）：

```
docs\reports\evidence\task067\logs\
  red_plain_list_scripts__0001__22aec6c6.txt      green_plain_list_scripts__0001__3d237432.txt
  red_mono_list_scripts__0001__a2506d7f.txt       green_mono_list_scripts__0001__3d237432.txt
  green_plain_task067__0001__9aadb972.txt         green_mono_task067__0001__9aadb972.txt
  gate3_module_doctest__0001__9805e4a6.txt        gate4_full_engine_test__0001__16ce1573.txt
  live_pre__0001__9419ce69.log                    live_post__0001__3e069fda.log
  build_log_first_and_last_lines__0001__2b17190c.txt   （7 个构建日志的首行/末 3 行 + 退出码）
```

> **⚠️ 「绿的 mono」与「绿的 plain」输出 sha8 相同（`3d237432`）**：目标用例全绿时 doctest 不打印被比较的值，**所以 mono 与 plain 的绿灯文本逐字节一样**，绿灯本身**不能**证明 `.cs` 那条断言真的被比较过。本批因此**不把绿灯当 mono 变体的证据**：mono 变体的证据是 (a) **红灯**（`has_csharp=true` 而 `in_fixture.has(probe.cs)=false`，逐字在 `red_mono_list_scripts__*.txt`）与 (b) **活证据**（`run-mono-head` 的 `count=10`、`p1_POST_both_languages_listed :: res://scripts cs=6 gd=2`）。这条留档是为了让下一个读者不要用「两个绿灯一样」去推断「两个变体被测过」。`red_mono` 与 `red_plain` 的**失败集合不同**（mono 多一条 `.cs`），这是变体差别可观测的地方。

**提交锚点（D86）与「二进制 `--version` 锚点」的关系（可复算）**

| 项 | 值 |
|---|---|
| 开工时 HEAD | `716957c26e`（"docs(mcp_server): TASK-066 brief, REPORT-066 and BREAKOUT-FINDINGS-R4"） |
| **实现提交锚点（引擎补丁 + 模块实现 + 测试）** | `2f85141a74` —— "mcp_server: TASK-067 list the build's script languages, and publish project.godot by section on editor open"（5 文件 / +588 −38） |
| **报告与证据提交锚点** | `82c8313a5e` —— "docs(mcp_server): TASK-067 brief, report and evidence …"（50 文件 / +2344） |
| **锚点登记提交** | `adf87b7090` —— "docs(mcp_server): TASK-067 record the commit anchors and how to read the evidence tree"（2 文件；只加本节与 `evidence/task067/README.md`） |
| 报告最终版 | 用 `git log --oneline -1 -- modules/mcp_server/docs/reports/REPORT-067-script-listing-and-editor-save.md` 查询（自指的最末一笔只可能改本报告的文字，不改任何结论；结论锚点是上面的 `2f85141a74` 与 `82c8313a5e`）。 |
| 二进制自报 | plain `4.8.dev.custom_build.716957c26`、mono `4.8.dev.mono.custom_build.716957c26` |
| **为什么二进制报的是提交前的 revision** | 二进制是在**门所绑定的那次构建**（12:12:20，工作树 = `716957c26e` + 本批的 5 个文件改动）里产出的，`--version` 的 hash 是**构建时的 git HEAD**；提交发生在门之后（否则 HEAD 会先动、门就不再绑在同一个 revision 上，见 §5 deviation 1b）。 |
| **「提交后的字节 == 二进制所构建的字节」的证明** | `git diff 2f85141a74 -- core/config/project_settings.cpp core/config/project_settings.h editor/editor_node.cpp modules/mcp_server/tools/project_read_files.cpp modules/mcp_server/tests/test_mcp_server.h` → **空**（提交后再没有对它们做任何改动）；即提交 `2f85141a74` 里的这 5 个文件**逐字节就是** 12:12:20 构建所编译的内容。 |

### 4.2 门③ 模块 doctest（最终 plain 二进制）

```
=== gate3_doctest_mcpserver ===
    exit=0 :: [doctest] test cases:   344 |   344 passed | 0 failed | 1429 skipped |
              [doctest] assertions: 23953 | 23953 passed | 0 failed | [doctest] Status: SUCCESS!
```

与**最近一次 HEAD 锚定的基线**（`REPORT-065A-mono-anchor-rerun.md`：342 用例 / 23924 断言 / 0 failed）相比：**只增加**（+2 用例 / +29 断言，正是本批新增的两个用例），**没有减少、没有变红**。

**红 → 绿（真实输出，当场落盘）**

红相位（plain，改动前实现 + 新测试，`%TEMP%\mcp067\red_plain_list_scripts.txt`，11:49:54）：
```
.\modules/mcp_server/tests/test_mcp_server.h(3177): ERROR: CHECK( in_fixture.size() == expected.size() ) is NOT correct!
  values: CHECK( 2 == 3 )
.\modules/mcp_server/tests/test_mcp_server.h(3178): ERROR: CHECK( TestMCPServer::canonical(in_fixture) == TestMCPServer::canonical(expected) ) is NOT correct!
  values: CHECK( ["…/probe.gd","…/probe.gdshader"] == ["…/probe.gd","…/probe.gdprobe","…/probe.gdshader"] )
[doctest] test cases:  2 |  1 passed | 1 failed | 1770 skipped
[doctest] assertions: 20 | 18 passed | 2 failed |   [doctest] Status: FAILURE!
```
红相位（**mono**，改动前实现，`red_mono_list_scripts.txt`，11:52:19）—— 多出 F-066-1 本身那一条：
```
.\modules\mcp_server\tests\test_mcp_server.h(3185): ERROR: CHECK( in_fixture.has(root.path_join("probe.cs")) == has_csharp ) is NOT correct!
  values: CHECK( false == true )
[doctest] assertions: 20 | 17 passed | 3 failed |   [doctest] Status: FAILURE!
```
绿相位（最终 plain，`green_plain_list_scripts.txt`）：`2 | 2 passed | 0 failed | 1771 skipped`，`assertions: 20 | 20 passed | 0 failed`，`Status: SUCCESS!`；`[MCPServer] TASK-067*`：`1 | 1 passed`，`assertions: 17 | 17 passed`。
绿相位（**mono**，`green_mono_list_scripts.txt`，12:09:44）：**同一组 2 用例 / 20 断言全过** —— 这一条是关键：mono 变体下 `expected` 里**多出 `probe.cs` 一条**（`4 == 4`），即「`.cs` 真的被列出」而不只是「plain 变体里没人可漏」。

**测试设计的两点诚实说明**

1. **红相位在两个变体都成立**：核心机制用**临时注册的 `ScriptLanguage`（扩展名 `gdprobe`）**来测，任何构建都能看见「引擎派生 vs 字面量」的差别；`.cs` 那条是**变体相关**的（`has_csharp` 由 `ScriptServer::get_language_for_extension("cs")` 决定），mono 下 `expected` 多一条、plain 下不多 —— 这正是 F-066-1 的语义，而不是「条件绿」。
2. **写测试时自己踩了一次假绿**：第一版 harness 的 `run_test.cmd` 把 exe 写死成 **plain**，在 mono 构建之后跑它仍测的是 plain 二进制，于是 `.cs` 断言**空转**并报 `2 passed`。发现后另建 `run_test_mono.cmd` 并重跑，才拿到真正的 mono 红/绿（`red_mono_…` 11:52:19 / `green_mono_…` 12:09:44）。这条已写进两个辅助脚本的注释，供下一批复用。

### 4.3 门①②⑤⑥ 与三个契约机器检查

**门① 契约逐字（本组）** —— `check_contract_subset.ps1 -Group project_read_files`（**最终 plain 二进制**，9888 + 9889 各一遍）：

```
[PASS] editor_9888_contract_subset
       editor port=9888 tools=153 ... | project_list_scripts: name=True description=True inputSchema=True
       | project_read_script: name=True description=True inputSchema=True
       | project_validate_script: name=True description=True inputSchema=True
       | project_read_resource: name=True description=True inputSchema=True
       | project_get_resource_preview: name=True description=True inputSchema=True
       | project_read_scene_file_content: name=True description=True inputSchema=True
[PASS] game_9889_contract_subset
       game port=9889 tools=72  ... | (同样 6 条 name=True description=True inputSchema=True)
[PASS] guard_user_port_9877        pid_before=-1 pid_after=-1
group=project_read_files tools=6 contract=176
implemented_union=153 tools (editor endpoint) / 72 tools (game endpoint)        3/3 checks passed
```

即：**两组端点上本组 6 条逐字 True**，且「线上集合 == 已实现组并集」（153 / 72）**没有多一条也没有少一条**。

> **流程勘误（本批自己踩的，留痕）**：第一次用 `-Tools project_list_scripts,…`（显式工具集）跑，脚本把「已实现并集」替换成了这 6 条，于是**其它 147 条**全成了 `unexpected extra tool` → 两条 FAIL。**那是调用方式错**（脚本 docstring 写明 `-Tools` 是显式集），**不是模块缺陷**；`[PASS] guard_user_port_9877` 与 6 条 `name/description/inputSchema=True` 在同一份输出里都成立。正确调用是 `-Group project_read_files`（上表）。两版日志都在 `%TEMP%\mcp067\gate1_contract_*.log`。

**门② 三类证据（`project_list_scripts`）**

| 类别 | 是否可构造 | 证据 / 不可构造的原因 |
|---|---|---|
| 成功 | **可** | §1.1（改动前）与 §1.4（改动后）的真实请求+响应，落盘带 sha256 |
| **缺参 → `-32602`** | **不可构造（显式声明）** | 契约 `project_list_scripts.inputSchema = {"properties":{},"required":[],"type":"object"}` —— 它**没有任何参数**，结构上不存在「缺参」这一类。任何额外成员按 `optional_*` 规则被拒/忽略（`tool_builder.h` 的既有语义），不是本工具的特性。 |
| **底层失败 → `-32001`/`-32000`** | **不可构造（显式声明）** | 该工具**按设计没有自己的错误类**：walk 的根恒为 `res://`，一个读不了的目录被**静默跳过**（`project_read_files.cpp` 的 `_collect_scripts_recursive` 注释逐字写着「exactly like the reference: this tool has no error of its own, not even for `res://`」）。要「构造」一个底层失败，只能造出一个 `res://` 不可读的进程——这在本 harness 里做不到（`res://` 恒是可读的工程根），**且做了也不改变任何判据**。 |
| **跨工具端到端活链** | **可** | 同一进程、同一条链：`project_list_scripts{}`（**列出**）→ 取其中一条 `res://scripts/Main.cs` → `project_read_script`（**读回** `size=2389`）→ `project_get_filesystem_tree{path:"res://scripts"}`（**第三个工具**独立确认该文件在索引里，17 条路径含 `Main.cs`）。三条对同一个文件的观察**必须同时成立**——改动前第一条说「没有」、后两条说「有」，正是这个矛盾把 F-066-1 从「上游说法」变成「可复算的缺陷」。证据：`run-mono-prefix\mono-prefix_p1_{list_scripts,fs_tree_scripts,read_main_cs}__*.{request,response}.json`。 |

**门③④**：见 §4.2（344 / 23953；1770 / 448200，两次独立运行同值）。

**门⑤（`accept_m1` 连跑两次，PASS 清单一致）+ 15 步回归电池**：见 §4.3b。

**三个契约机器检查（任务书点名必须 exit 0）**

```
=== contract_completeness ===       exit=0 :: BYTES ADDED 7739 | SHA256 ADDED 67cd57d0214f0485d92e7894dd112991d05d2e6d6842031cd99f238153a3f994 | TOOL-GROUPS-COMPLETENESS CHECK PASS
=== contract_added ===              exit=0 :: BYTES 7739 | SHA256 67cd57d0214f0485d92e7894dd112991d05d2e6d6842031cd99f238153a3f994 | TOOL-GROUPS-ADDED CHECK PASS
=== contract_generator_version ===  exit=0 :: ASSERT  GENERATOR_VERSION == _meta.generator_version == source.generator_version: PASS (1.19.0) | ASSERT  source.entries contains the same version string: PASS | GENERATOR-VERSION CHECK PASS (1.19.0)
```

**`mcp059_gates.ps1` 的 21 个步骤全部 exit 0**（`%TEMP%\mcp067\gate059.log`，`GATES059_EXIT=0`）。除上表与门③④⑥外，其中与**本批直接相关**的两步是补丁 2/补丁 3 的活证据：

```
=== t059_section_switch_evidence ===       exit=0 :: --- checks: 30, failures: 0 ---   SECTION-SWITCH EVIDENCE PASS
=== patch2_settings_publish_evidence ===   exit=0 :: --- checks: 23, failures: 0 ---   SETTINGS-PUBLISH EVIDENCE PASS
```

即：**我抽取过 I/O、并新增了「多节合并」路径之后，既有的按节发布语义（30 + 23 条检查）逐条不变**。

### 4.3b 门⑤ 与 15 步回归电池

**门⑤（`accept_m1.ps1` 连跑两次，PASS 清单必须一致）** —— `mcp056_regression_battery.ps1` 的前两步：

```
=== accept_m1_run1 ===
    exit=0 :: PASS  gate_scope_declared | 22/22 cases passed | implemented tools = 153 (editor endpoint) / 72 (game endpoint); contract = 176; known_deviation = per-batch verbatim gate only
=== accept_m1_run2 ===
    exit=0 :: PASS  gate_scope_declared | 22/22 cases passed | implemented tools = 153 (editor endpoint) / 72 (game endpoint); contract = 176; known_deviation = per-batch verbatim gate only
accept_m1_pass_lists_agree|0|accept_m1_run1 checks=22 accept_m1_run2 checks=22 differing_lines=0
```

**两次 PASS 清单逐行相同（`differing_lines=0`）**，22/22 用例通过，`contract = 176`。

**15 步回归电池的逐步退出码与逐条归因**

| 步骤 | 退出码 | 归因 |
|---|---|---|
| `accept_m1_run1` / `accept_m1_run2` | 0 / 0 | 门⑤ 本体；两次清单一致（上表） |
| `mcp041_gates` | 0 | 该脚本自身跑 gates 3/4/6 + gate 1（`editor_input_simulation`）+ gate 5 ×2 + 它自己的证据链 **`mcp041_inputmap_persistence_evidence`**（InputMap 持久化，正是 `project.godot` 写入路径）与 5 个回归 `mcp032/033/034/035/036` + `probe037` + `mcp040_*`。**与②直接相关**（输入 action 落盘）。 |
| `mcp042_gates` | 0 | gates 3/4/6 + gate 1 + gate 5 ×2 + **`mcp042_projectrewrite_and_honesty_evidence`**（「整文件重写」的诚实性证据，与②同族）+ `mcp042_port_guard_probes` + `mcp041_inputmap_persistence_evidence` + 同 5 个回归 + `mcp040_*`。 |
| `mcp043_gates` | 0 | gates 3/4/6 + 4 组 gate 1 + gate 5 ×2 + `mcp043_description_evidence` / `mcp043_reload_plugin_rewrite_probe` / `probe037` / `mcp042_*` / `mcp041_*` / `mcp042_port_guard_probes` / `mcp043_contract_diff.py` / `mcp043_registration_literals.py` / `mcp043_group_lookup.py` + 5 个回归 + `mcp040_*`。 |
| `mcp010_b2_observation_evidence` | 0 | B2 观测族（TASK-010），与①②无关，作为「改动没有波及无关工具」的对照 |
| `mcp019_b4_evidence` | 0 | B4 证据（TASK-019）同上 |
| `mcp027_object_shape_and_paths_evidence` | 0 | 对象形状与路径（TASK-027）同上 |
| `mcp044_capture_evidence` | 0 | 捕获族（TASK-044）：**窗口化**捕获，与②同属「窗口化进程」的证据范畴 |
| `mcp045_pixel_compare_cost` | 0 | 像素比较成本（TASK-045） |
| `mcp046_capture_encode_cost` | 0 | 捕获编码成本（TASK-046） |
| `mcp050_parameter_guidance_evidence` | 0 | 参数指引（TASK-050）：`-32602` 的 `data.suggestion` 族 |
| `mcp051_b_tier_evidence` | 0 | B 层参数面（TASK-051） |
| `mcp052_added_tools_evidence` | 0 | 线上新增工具证据（TASK-052），**含 `project_build_csharp`**（mono 二进制）；它有 `engines_match_head` 断言，即**它自己复核了 mono 二进制 == HEAD** |
| `mcp053_added_tools_evidence` | 0 | 同上（TASK-053）；这两个脚本对新工具的面逐条比对 |
| `tracked_evidence_restored`（电池自检） | 1 | **不是回归**：电池要求「跑完之后工作树必须干净」，而本批的 5 个源文件改动**在电池开始前就是脏的**，所以 `git diff --stat` 不可能为空。manifest 里这 5 条全部是 `KEPT-DIRTY-BEFORE-THE-RUN`，且 `newly modified=0 / newly untracked=0 / restore failures=0` —— 即**电池自己没有留下任何东西**。逐字见下。 |
| `accept_m1_pass_lists_agree` | 0 | 门⑤ 的清单一致性 |

**电池自检那一步的原始输出（逐字）**：

```
    KEPT-DIRTY-BEFORE-THE-RUN core/config/project_settings.cpp
    KEPT-DIRTY-BEFORE-THE-RUN core/config/project_settings.h
    KEPT-DIRTY-BEFORE-THE-RUN editor/editor_node.cpp
    KEPT-DIRTY-BEFORE-THE-RUN modules/mcp_server/tests/test_mcp_server.h
    KEPT-DIRTY-BEFORE-THE-RUN modules/mcp_server/tools/project_read_files.cpp
    SUMMARY restored=54 removed=1 kept-dirty-before=5
--- summary ---
...
accept_m1_pass_lists_agree|0|accept_m1_run1 checks=22 accept_m1_run2 checks=22 differing_lines=0
tracked_evidence_restored|1|git diff --stat after=6 line(s); newly modified=0; newly untracked=0; restore failures=0
FAILED STEPS: 1
```

**14/15 步 exit 0 + `accept_m1_pass_lists_agree|0`**；唯一非零步是电池自己的「跑完之后工作树必须干净」断言，`newly modified=0 / newly untracked=0 / restore failures=0` 说明**它没有留下任何东西**，`restored=54 removed=1` 是它对**批量共用的已被脚本改写的证据文件**做的还原。**注意这是本批无法通过的一步**：它要求 `git diff --stat` 为空，而任何「工作树里带着本批未提交改动」的批次都不可能满足；即便先提交，报告的后续修改又会让 HEAD 再次前移。按 D86 的口径**如实标注**而非掩盖。

**逐步退出码（电池自己的 `summary.txt`，逐字）**：

```
accept_m1_run1 | 0            accept_m1_run2 | 0            mcp041_gates | 0
mcp042_gates | 0              mcp043_gates | 0              mcp010_b2_observation_evidence | 0
mcp019_b4_evidence | 0        mcp027_object_shape_and_paths_evidence | 0
mcp044_capture_evidence | 0   mcp045_pixel_compare_cost | 0  mcp046_capture_encode_cost | 0
mcp050_parameter_guidance_evidence | 0   mcp051_b_tier_evidence | 0
mcp052_added_tools_evidence | 0          mcp053_added_tools_evidence | 0
accept_m1_pass_lists_agree | 0           tracked_evidence_restored | 1
```

**电池内的子检查总数**（各脚本自己报的）：`mcp010` 29/29、`mcp027` 60/60、`mcp044` 40/40、`mcp045` 15/15、`mcp046` 23/23、`mcp052` 53/53、`mcp053` 73/73、`accept_m1` 22/22 ×2；`mcp041/042/043_gates` 各自把 gates 1/3/4/5/6 + 自己的证据链 + 5 个回归 + `probe037` + `mcp040_*` 跑完并 exit 0（末行 `STEP regress_mcp040_racing EXIT 0 (46-48s) … DONE`）。

**逐条归因：本批**没有**跑的 `mcp04x..mcp06x` 脚本，及理由**

| 脚本 | 为什么不在本批重跑 |
|---|---|
| `mcp057_gates.ps1` / `mcp055_gates.ps1` / `mcp056_gates.ps1` | 三者的步骤清单是 `mcp059_gates.ps1` 的**真子集**（同样 gates 3/4/6 三段 + `check_tool_groups.py` 的机器检查 + `gate1_contract_subset`；057 另加 `--generator-version` 与 `rb2_failure_demo`）—— `mcp059_gates.ps1` 的文件头逐字写着它是「TASK-057 battery 的同一批步骤 + TASK-059 的步骤」。本批跑的是**并集**，全 21 步 exit 0（§4.3）。 |
| `mcp054_gate_battery.ps1` / `mcp051_gates.ps1` | 步骤同族（gates 1/3/4/5/6 + contract checks）；其中 **gate 5 由 `mcp056_regression_battery.ps1` 跑了**。`mcp051_gates.ps1` 特有的两个 python 检查（`check_rename_map.py`、裸 `check_tool_groups.py`）本批**单独跑了**：`check_tool_groups.py` **PASS**；`check_rename_map.py` **FAIL（2 条）**，见下。 |
| `mcp050_regression_battery.ps1` / `mcp051_regression_battery.ps1` / `mcp053_regression_battery.ps1` / `mcp054_regression_battery.ps1` | 这四条是**更早批次**的回归电池（`accept_m1` ×2 + 它们那一轮的证据脚本 + `mcp031_gate6_coverage_probes.ps1`）。本批跑的是**同一个形状的最新一条**（`mcp056_regression_battery.ps1`，TASK-057 §3 重写过、带工作树快照/还原/manifest），而它覆盖的是**当前 revision 的**证据脚本集合；跑更早的电池只会重复同一批脚本的旧版本调用方式。 |
| `mcp041_builtin_action_probe.ps1` / `mcp042_port_guard_probes.ps1` / `mcp042_projectrewrite_and_honesty_evidence.ps1` / `mcp043_description_evidence.ps1` / `mcp043_reload_plugin_rewrite_probe.ps1` / `mcp044_zero_change.ps1` / `mcp047_graceful_exit_flush.ps1` / `mcp047_m3_mono_check.ps1` / `mcp049_subpath_closure_evidence.ps1` / `mcp054_forensics_and_csharp_evidence.ps1` / `mcp055_csharp_compile_verdict_evidence.ps1` / `mcp055_write_probe.ps1` / `mcp056_evidence.ps1` / `mcp061_watch_evidence.ps1` / `mcp063_product_defects_evidence.ps1` / `mcp064_evidence_hygiene_probe.ps1` / `mcp064_stale_expectation_reverse_probe.ps1` | 它们**不是门**，是各自批次的**取证脚本**（`mcp042_projectrewrite_and_honesty_evidence` 与 `mcp041_inputmap_persistence_evidence` 这两条**已经由 `mcp041/042/043_gates` 在电池里跑过**）。剩下的这些取证的对象（捕获/像素/port guard/插件重载/子路径/批量分析/看门狗/证据卫生）与①②的改动面**不相交**：本批改的是「脚本扩展名集合」与「`project.godot` 的启动保存 writer」，而这批脚本一个都不读这两处。 |
| `mcp057_settings_publish_evidence.ps1` / `mcp059_section_switch_evidence.ps1` / `mcp057_rb2_failure_demo.ps1` / `mcp059_d2_failure_demo.ps1` / `mcp059_d5_scons_probe_demo.ps1` | **已经在本批的 `mcp059_gates.ps1` 里跑过**（§4.3 的 21 步表），其中前两条正是②的引擎改动的活证据（30 + 23 条检查全过）。 |
| `mcp052/053_added_tools_evidence.ps1` | 已在电池里跑（上表） |
| `mcp065b_run.ps1` / `mcp065b_finalize.ps1` / `mcp065b_fixtures.ps1` / `mcp065b_watch_invocation_probe.ps1` | TASK-065 §B 的全套编排：它会**重写已提交的** `docs/reports/evidence/task065b/**`（358 文件）并重跑 scope/捕获判据，主题（信号连接 scope、像素三路复算）与①②不相交。 |
| `mcp066b_run.ps1` / `mcp066b_finalize.ps1` | 同上：TASK-066 §B 的 5 会话编排（88 条判据），产物落在**已提交的** `evidence/task066b/**`；它的被测对象是**捕获 `changed` / scope 划分**，本批的改动面不相交。**但请注意**：本批**自己**在同一个 C# fixture 的副本上跑了活链（§1/§2），而 `mcp053_added_tools_evidence` 与 `accept_m1` 也已覆盖 C#/契约面。 |
| `mcp059_contract_pre_post.py` / `mcp066b_make_pngs.py` / `mcp065b_pixel_recompute.py` | 纯 python 辅助，不是独立门；`mcp059_contract_pre_post.py` **已在 `mcp059_gates.ps1` 里跑过**（exit 0）。 |
| `mcp043_contract_diff.py` / `mcp043_group_lookup.py` / `mcp043_registration_literals.py` | **已在 `mcp043_gates` 里跑过**（电池内）。 |
| `mcp035/036_*_evidence.ps1` / `mcp032/033/034_*_evidence.ps1` / `probe037_*` / `mcp040_*` / `mcp031_gate6_coverage_probes.ps1` | **已分别在 `mcp041/042/043_gates` 与 `mcp059_gates` 里跑过**。 |

> **`check_rename_map.py` 的 2 条 FAIL 是既有的 stale expectation，不是本批的回归**（本批单独跑了它，并且必须留痕）：
> ```
> [FAIL] G5 contract count == map total - 2 unregister - 1 merge    176 == 171
> RESULT: FAIL (2 failing checks): G1 contract tool count == 171, G5 contract count == ...
> ```
> 依据：`modules/mcp_server/docs/scripts/check_rename_map.py:240` **硬编码** `len(ctools) == 171`（`:250` 同样是 `174 - 2 - 1`），该脚本最后一次改动是 `8400dae1e8`（v1.1 的 171 条重命名映射时代）；而契约自 TASK-052/053/063 起就是 **176** 条（5 个新增工具）。本批**既没有改该脚本、也没有改它读的契约**（契约 sha `d4e53b43…` 与基线逐字相同），所以这两条 FAIL 在**父 revision 上同样成立**——它是 TASK-063 记录过的那一类「把改动前的契约条数写死、因此无法在当前树上重跑」的脚本（`REPORT-063` 的同类归因）。`mcp051_gates.ps1` 依赖它，故本批**不重跑 mcp051_gates.ps1** 而以本段 + 直接跑它另两个检查代替（`check_tool_groups.py` **PASS**）。

### 4.4 门⑥ 三段式（收窄点）

```
=== gate6_narrowing ===          exit=0
  scanned     : 75 narrowing point(s) in 16 file(s)
  pinned      : 75
  note: 18 pinned line number(s) drifted (...)
  PASS: every narrowing point of the module that one of the declared spellings
        matches is annotated and pinned; the declared set is bounded and probed
=== gate6_narrowing_coverage === exit=0   (declared spelling set + coverage printed)
=== gate6_coverage_probes ===    exit=0 :: PASS B1b_restored_byte_identical | PASS B1b_worktree_clean_of_probes |
                                            101/101 checks passed (log sha256=f98554f04873c59adb62ebb1a4a937b9533419443a0ddb3ca85c2b2b2bfdd976)
```

- **`scanned == pinned == 75`，0 误报** —— 本批**没有新增收窄点**（新代码里唯一涉及字节长度的位置是**原样搬走**的 `length > (uint64_t)INT32_MAX` 判断，仍在同一处 `// MCP-NARROWING` 语境里；它没有新增标记，也没有让标记消失）。
- 18 条 **line number drift** 是**既有的**（pin 按「标记 id + occurrence」判定，所以不是失败），且 drift 列表里的文件 **没有一个**是本批改的（`editor_animation_tree_write.cpp` / `editor_input_simulation.cpp` / `editor_write_scene_editor.cpp` / `project_theme_write.cpp` / `project_write_resource_scene.cpp` / `tool_helpers.cpp`）；本批改的 `project_read_files.cpp` 不在其中，说明我**没有移动任何已 pin 的收窄点**。
- **§22.3b 规则 4（不拿门⑥ 变绿当唯一证据）**：本批的收窄证据是**三条腿**——机器检查（上表）+ **代码审查**（本批**零**新增收窄写法：`project_read_files.cpp` 新增的都是 `String` 比较与 `push_back`；`project_settings.cpp` 新增的是文本拼接与 `Vector<...>` 复制；唯一长度判断是搬走的）+ **行为证据**（§2.3 的窗口化活证据 + 17 条文本单测）。**本批没有「新增收窄点 × 它经过的闸门」需要登记**，因为新增点为零。
### 4.5 契约与工作树（前后同值）

**契约（唯一权威）**：

```
certutil -hashfile modules\mcp_server\docs\tools_list.renamed.json SHA256
  -> d4e53b43840b6537af9dfbefdc77e7fb4ed6202ee23f3016503a7a53953e7ecd
python: len(result.tools) -> 176
```

与 `BREAKOUT-FINDINGS-R4.md` §0 记录的基线 **逐字相同**；`mcp059_gates.ps1` 的 `t_p059_contract_pre_post` 与 `rb2_failure_demo` 两步也各自独立打印了同一个 sha（`SAME d4e53b43840b…`）——即**本批前后同值**，而且是在**门自己跑的时候**打印的。`docs/tool-rename-map.json` / `tool-groups*.json` / `tool-groups-added.json` 同样零改动（`git status` 无 ` M ` 行）。

**工作树（`rb2_failure_demo` 当场打印的 `git status --porcelain`，逐字）**：

```
 M core/config/project_settings.cpp
 M core/config/project_settings.h
 M editor/editor_node.cpp
 M modules/mcp_server/tests/test_mcp_server.h
 M modules/mcp_server/tools/project_read_files.cpp
?? .graphifyignore
?? build-m0.cmd
?? graphify-out/
?? install-deps-m0.cmd
?? modules/mcp_server/docs/reports/REPORT-067-script-listing-and-editor-save.md
?? modules/mcp_server/docs/reports/evidence/task067/
?? modules/mcp_server/docs/tasks/TASK-067-script-listing-and-editor-save.md
?? modules/mcp_server/scripts/mcp067_env.ps1
?? modules/mcp_server/scripts/mcp067_live.ps1
```

`??` 的前 4 条是**开工前就有的既有未跟踪物**（任务书 §5 允许的收尾状态）；其余 5 条是本批的产物（报告、证据树、两个 harness 脚本、任务书本身）。

```
git diff --stat
 core/config/project_settings.cpp                | 218 +++++++++++++++++---
 core/config/project_settings.h                  |  43 ++++
 editor/editor_node.cpp                          |  20 +-
 modules/mcp_server/tests/test_mcp_server.h      | 264 ++++++++++++++++++++++++
 modules/mcp_server/tools/project_read_files.cpp |  81 +++++++-
 5 files changed, 588 insertions(+), 38 deletions(-)
```

**只允许改 `modules/mcp_server/**` 与「必要的引擎文件」**：本批动的引擎文件恰好两个功能点 ——
`core/config/project_settings.{h,cpp}`（新增能力 + 纯搬运）与 `editor/editor_node.cpp`（一个调用点）。**hof-rs 只读**（未触碰 `F:\moonbit-hof-rs` 下任何文件）；**`DESIGN-DETAIL.md` 未改**（无需上报的规范偏离）；**未 push**。
---

## 5. deviations / blockers / next_step

### deviations（与任务书/手册的显式偏离）

1. **`--version` 不能区分 pre-fix 与 post-fix 二进制**（§0/§4.1）。本批的修复不动 HEAD，两个二进制报同一个串。故本报告用「构建日志时间 + 源码 mtime + 红/绿输出」三重对照来锚定「哪半是改动前」，并**显式撤回**任何「`--version` 相同 ⇒ 同一构建」的读法。
1b. **「提交锚点」与「二进制 `--version` 锚点」必然错位，且本批不做「先提交再重建再重跑门」的循环**（D86 口径）。原因：`--version` 里的 hash 是**构建时的 `git HEAD`**（`core/version_generated.gen.h` 由 SCons 在构建时生成），而本批的交付物里**包含报告本身**——先提交会让 HEAD 前移、门就不再「绑在同一个 revision」上，而报告的任何后续勘误又会让 HEAD 再前移一次。若要在**每一个** revision 上都让 `--version == HEAD`，就必须「提交 → 重建 mono+plain（约 2-12 min）→ 重跑门电池（约 6 min）+ 回归电池（约 45 min）→ 再改报告 → 再提交 → …」无限循环。本批采取的、也是本仓库既有的口径（`BREAKOUT-FINDINGS-R4.md` §10.1、`REPORT-066` §0）是：**门在 `716957c26e` 上跑，二进制自报 `716957c26`（与那个 revision 一致），随后提交；并在报告里用一条可复算的 `git diff` 证明「提交后的源码字节 == 二进制所构建的源码字节」**（见 §4.1 的 ANCHOR 段）。
2. **判据② 的证据是在 mono 二进制上产出的**（`p0_engine_version_recorded :: 4.8.dev.mono.custom_build.716957c26`）。理由：① 需要 mono（C# 语言），② 与 ① 共用同一条链以免多起进程。`project.godot` 的启动保存路径是**引擎通用**代码（`editor/editor_node.cpp`），与是否 mono 无关；但**读者应知道**这条证据的进程变体。门③/④/⑤/⑥ 与门① 都是在**plain** 最终二进制上跑的。
3. **门① 用 `-Tools` 形式为本组工具加逐字比较**，而不是逐个已实现组各跑一次（`mcp059_gates.ps1` 已经跑了 6 组：默认 + `project_read_template` + `project_validate_scripts` + `project_csharp_build` + `editor_set_node_script_batch`，外加默认并在其间完成了「实现组并集」的不变式检查）。
4. **新建 2 个 harness 脚本**（`scripts/mcp067_env.ps1`、`scripts/mcp067_live.ps1`）与 `%TEMP%\mcp067\` 下的 4 个 `.cmd` 跑测辅助。**共用的 5 个脚本一个字节都没改**（`mcp_evidence_guard.ps1` / `mcp_import_guard.ps1` / `mcp_watch_run.ps1` / `mcp066b_env.ps1` / `accept_m1.ps1`；`git status` 无 ` M ` 行，§4.5）。`mcp067_live.ps1` **dot-source** `mcp066b_env.ps1` 复用调用器与进程助手，然后**重新指向** TASK-067 自己的 scratch/evidence 目录（记录在文件头）。
5. **本批没有收紧 walk 的 `.godot` 行为**（§1.4 的显式后果），也没有为 F-066-3 / `waited_seconds` 生成 `DESCRIPTION_OVERRIDES`（§3）。两者都给了理由与替代通道。
6. **未跑** `mcp065b_run.ps1` / `mcp066b_run.ps1` 的全套编排（§4.3 逐条归因里给了理由：它们会**重写已提交的** TASK-065/066 证据树，而主题（捕获/scope）与 TASK-067 无关）。

### blockers

**无。**

### next_step_recommendation（给决策者）

1. **要不要让 `project_list_scripts` 跳过生成物**（§1.4）：本批只声明了后果。若要做，建议**单独一批**：给 `_collect_scripts_recursive` 加一条「跳过引擎自己的项目缓存目录（`ProjectSettings::get_project_data_dir_name()`，即 `.godot`）」的规则 + 一条 doctest（断言 `.godot` 不入、`.hiddendir` 仍入），并**不要**改成「跳过所有 `.` 前缀目录」（会推翻 `.hiddendir/secret.gd` 这条已发布断言）。
2. **F-066-3 的单/复数统一**：属**破坏性 API 变更**，需要新任务书授权 + 改契约描述 + 重生成（会移动 `d4e53b43…`）。
3. **`waited_seconds` 的输入/输出异名**：同样需要 `DESCRIPTION_OVERRIDES` + 重生成；建议**攒到一个「契约描述批次」**里和别的 pitfall 一起做，减少对契约 sha 的冲击次数。
4. **本批新增的 `mcp067_env.ps1` / `mcp067_live.ps1` 建议转正为常设 harness**：`mcp067_live.ps1` 是第一个把「脚本语言枚举」与「project.godot 注释保全」两件事做成**可复跑的 pre/post 对照**的脚本，下一批做引擎 writer 改动时可直接 `-Phase pre/post` 复用。
5. **给引擎侧的 writer 留一道回归**：`save_preserving_text()` 目前只有模块侧的字符串 doctest 覆盖（§2.2 第 5 点）＋本批的活证据。引擎自己的测试目录（`tests/core/config/`）本批**未加**用例（任务书只允许改 `modules/mcp_server/**` 与「必要的引擎文件」；往引擎 tests/ 加文件超出这个范围），建议后续授权后在引擎测试里补一条窗口化/I/O 级用例。

---

## 6. 复现（照抄可重算本文所有数字）

```cmd
:: 0) 端口前提（9877 必须无监听者；本批从不触碰它）
netstat -ano | findstr ":9877 :9888 :9889"

:: 1) 最终构建（从 cmd；严格串行；输出不经管道）
cd /d F:\RustProjects\godot-mcp-pro\code\godot
set MCP_BUILD_LOG=%TEMP%\mcp067_build_plain_final.log
modules\mcp_server\scripts\build_local.cmd -Force
bin\godot.windows.editor.x86_64.console.exe --version            :: 期望 ...custom_build.716957c26

:: 2) 门③/④ 的单独重跑（等价于 mcp059_gates.ps1 的前两步）
bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"
bin\godot.windows.editor.x86_64.console.exe --headless --test

:: 3) 门①/③/④/⑥ + 三个契约机器检查 + 补丁2/补丁3 的活证据（一条命令）
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp059_gates.ps1

:: 4) 门⑤（accept_m1 连跑两次 + 15 步回归电池，自带工作树还原与 manifest）
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp056_regression_battery.ps1

:: 5) 本批红/绿与活证据（pre 需要一棵未修改的树构建出来的二进制；见 §0 的版本锚点声明）
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp067_live.ps1 -Phase pre  -Label <label> -EditorExe bin\godot.windows.editor.x86_64.mono.console.exe
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp067_live.ps1 -Phase post -Label <label> -EditorExe bin\godot.windows.editor.x86_64.mono.console.exe
:: 产物：docs\reports\evidence\task067\run-<label>\ （请求/响应/快照/派生表，名字里带 sha8）
```

---

## 7. 交付物清单（绝对路径前缀 `F:\RustProjects\godot-mcp-pro\code\godot\`）

| 路径 | 说明 |
|---|---|
| `modules\mcp_server\docs\reports\REPORT-067-script-listing-and-editor-save.md` | **本报告** |
| `modules\mcp_server\tools\project_read_files.cpp` | ① 的实现（`_script_extensions()` / `_has_script_extension()` / walk 签名） |
| `modules\mcp_server\tests\test_mcp_server.h` | ① 的机制用例（含临时 `ScriptLanguage`）+ ② 的 17 条文本用例 |
| `core\config\project_settings.h` / `.cpp` | ③ 引擎第三个补丁：`save_preserving_text()` / `publish_settings_sections_text()` / 三个抽取出的助手 |
| `editor\editor_node.cpp` | 调用点切换（`:1071` 附近） |
| `modules\mcp_server\scripts\mcp067_env.ps1` / `mcp067_live.ps1` | 本批 harness（纯 ASCII，复用共享守卫） |
| `modules\mcp_server\docs\reports\evidence\task067\run-mono-prefix\**` | **改动前**的活证据（① 的 `count=2`、② 的注释被吃；被取代的第一次运行也被明确标注） |
| `modules\mcp_server\docs\reports\evidence\task067\run-mono-head\**` | **改动后**的活证据（① 的 `count=10` 两种语言、② 的注释逐字保留） |
| `modules\mcp_server\docs\reports\evidence\task067\logs\**` | 红/绿 doctest 输出、两次 live 日志、7 个构建日志的首/末行（含退出码） |
| `modules\mcp_server\docs\reports\evidence\task067\README.md` | 证据树怎么读 + **哪几个文件被取代、不要引用** |

**返回给决策者**：见 §0.1（≤6 行）。
