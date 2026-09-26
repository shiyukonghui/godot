# REQUIREMENTS — TASK-005（框架清理 + 组 `project_read_files` 移植）

工件属阶段一（需求分析）。执行依据：`docs/tasks/PLAYBOOK-group-port.md`（通用规范）+ `docs/tasks/TASK-005-project-read-files.md`（本组任务书）。
本文件不重复手册内容，只固化本任务的目标、边界与验收标准（决策者已确认）。

## 1. 目标（Goal）

1. **第一部分 · 框架清理**：把 TASK-004 在 `tools/project_read_analysis.cpp` 内重复实现的 4 个内部链接助手
   上提为 `tools/` 下的共享公共助手，并让 `project_read_analysis.cpp` 与 `project_read_template.cpp`
   改用共享版本、删除各自本地副本。**硬要求：重构前后任何可观察行为逐字节不变。**
2. **第二部分 · 组移植**：移植只读组 `project_read_files` 的 6 个工具
   （`project_list_scripts` `project_read_script` `project_validate_script` `project_read_resource`
   `project_get_resource_preview` `project_read_scene_file_content`），经 `MCPTools::ToolBuilder` 注册，
   TDD 先红后绿，跑满五道门。

## 2. 非目标（Non-goals）

- 不实现 B1 其它组（`editor_*`、写操作组等），不注册任何未实现工具（GDR-7）。
- 不修改契约/映射/生成器：`docs/tools_list.renamed.json`、`docs/tool-rename-map.json`、
  `docs/scripts/gen_*`、`scripts/gen_renamed_contract.py` **一个字节都不动**。
- 不改 `godot_mcp_gdext`、不改整个 `F:\moonbit-hof-rs`、不改引擎其它目录。
- 不改 `tools/project_read_template.cpp` / `project_read_analysis.cpp` 的**工具语义**（只允许删除被上提的助手并改调用点）。
- 不 push；不安装依赖；不访问 100.105.152.101:18080。

## 3. 硬约束

| 约束 | 内容 |
|---|---|
| 改动面 | 只允许 `code\godot\modules\mcp_server\**` |
| 端口纪律 | **绝不占用 9877**（用户 Godot 4.7.1-mono，PID 36392）；测试只用 9888（编辑器）/9889（游戏）；scratch 在 `%TEMP%` |
| 证据采集 | 一律 `curl.exe --data-binary @file`（JSON 走命令行参数会丢引号 → `-32700`） |
| 契约权威 | 每个工具的 `description` / `inputSchema` **逐字**取自 `docs/tools_list.renamed.json`，不得自行改写 |
| 注册路径 | 只能经 `MCPTools::ToolBuilder::register_into()`（`register_tool` 私有） |
| 只读性 | 本组 6 个工具**不得写任何项目文件**（含 `.uid`、`*.import`、`.godot/` 缓存） |
| 构建 | `D:\Anaconda\Scripts\scons.exe platform=windows target=editor tests=yes module_mono_enabled=no -j8`（pwsh/cmd，勿用 Git Bash） |
| 诚实性 | 不得伪造输出；红/绿两阶段真实输出都要入报告；之后由全新子代理独立验收 |

## 4. 边界（Boundary）

- **助手去重的边界**：只上提 4 个（`_split_lines`、`_serialize_variant`、`_join_path`、扩展名递归遍历）。
  它们的**行为逐字保留**，包括 `_collect_files_by_extension` 里「跳过一切 `.` 开头项」「`addons` 仅在
  `include_addons` 为真时下钻」「扩展名比较 `to_lower()`」这三条。
  若发现 `project_read_template.cpp` 的对应实现与 `project_read_analysis.cpp` 的**语义不逐字一致**，
  则**不得强行合并**：保留各自实现并在报告 `deviations` 显式登记差异。
- **`project_read_files` 的边界**：`channel=project`、`mutating=false`、`scope=both`、`required` 逐字按契约
  （`project_list_scripts` 无必填参数，其余 5 个必填 `path`；`project_get_resource_preview` 另有可选 `max_size` 默认 256）。
- **迁移源是语义参照，不是逐字复刻对象**：迁移源自身缺陷按 PLAYBOOK §6 处理（以「工具真的能用」为准并显式记录）。

## 5. 验收标准（Acceptance Criteria，可机器核对）

| id | 标准 |
|---|---|
| AC-1 | `git grep`/`rg` 证明 4 个助手在 `tools/` 下**各只有一处定义**（共享头），两组成员文件内不再有本地定义 |
| AC-2 | 重构前后对已实现两组各 3 个工具的同一组请求，响应体**逐字节相同**（长度 + 逐字节比较 + sha256） |
| AC-3 | 本组 6 个工具在 **9888 与 9889** 上的 `name`/`description`/`inputSchema` 与契约**逐字 True** |
| AC-4 | live `tools/list` 恰好等于 `tool-groups.json` 中所有 `implemented=true` 组的并集（本组落地后为 **19** 个），无多余、无缺失 |
| AC-5 | 每个新工具都有 doctest 覆盖：成功路径、缺参 → `-32602`、底层失败 → `-32001`（带 `data.suggestion`）、以及该工具特有边界 |
| AC-6 | TDD 红阶段真实输出（失败原因是「功能不存在」，不是编译/断言写法错）与绿阶段真实输出都入报告 |
| AC-7 | 模块 doctest `[MCPServer]*` 全绿，例/断言数**只增不减**（基线 65 例 / 607 断言） |
| AC-8 | 全引擎 `--headless --test` **0 failed**（基线 1491 例 / 424888 断言，passed 只允许因新增测试增加） |
| AC-9 | `scripts\accept_m1.ps1` 连跑两次 `EXIT=0`，两次 PASS 清单一致（其硬编码工具数须同步到 19） |
| AC-10 | 只读不变式：依次调用 6 个工具后 fixture 文件列表逐字节不变 |
| AC-11 | `docs/tool-groups.json` 的 `project_read_files.implemented` 置 `true`；`docs/scripts/check_tool_groups.py` 自跑 PASS |
| AC-12 | 报告 `docs/reports/REPORT-005-project-read-files.md` 按 PLAYBOOK §4 格式，含「重构等价性证据」一节 |
| AC-13 | 端口纪律：门① 与门⑤ 各自打印 `pid_before=36392 pid_after=36392` |

## 6. 假设（Assumptions）

1. 用户正在使用的编辑器固定占 9877（PID 36392）且本任务全程不得干扰——按任务书给定的事实处理。
2. 契约 `docs/tools_list.renamed.json`（171 条）与组清单 `docs/tool-groups.json` 是**唯一事实源**，无需修正。
3. `docs/tools_list.renamed.json` 的 `_meta.order_normative=false`：注册顺序**不是**门，但同一次构建内必须确定性。
4. `Main::test_setup()` 不调用 `ScriptServer::init_languages()`，故 doctest 进程**不加载脚本语言**；
   依赖脚本语言的正例由门② 真实工程证据承载（TASK-005 §2 特别注意 3）。

## 7. 复盘：未明说但默认成立的假设 / 缺失信息 / 常见错误

| 类别 | 内容 | 处置（已确认） |
|---|---|---|
| 默认假设 | 门⑤ `accept_m1.ps1` 把「工具总数」**硬编码**为 13（`case1`/`case12`/`case20` 断言 `tools`），并在 `$ToolNames` 里硬编码 13 个名字。组落地后不更新它，门⑤ **必然 FAIL** | 本任务显式授权把 `$ToolNames` 扩到 19、硬编码 13 → 19；这是 TASK-004 §7.1 的既定先例，处理方式相同，入报告 deviations |
| 默认假设 | 门① `check_contract_subset.ps1` 的「无多余工具」是**并集语义**（已由 TASK-004 §7.3 修正），新组落地**无需**再改门脚本 | 只改 `tool-groups.json` 的 `implemented` |
| 默认假设 | doctest 进程里 `Marshalls::get_singleton()` 可能未初始化 | base64 编码**不得**经 `Marshalls::get_singleton()`；直接用 `CryptoCore::b64_encode_str`（引擎内静态函数），并以 doctest 绿 + 门② 真实响应佐证 |
| 缺失信息（设计阶段解决） | `_serialize_variant` 只在 `project_read_resource` 的「变体保真」上有用，但**迁移源的 `read_resource` 并不返回属性**（`{path,type,loaded}`），契约描述是「读取资源文件」 | 采取**迁移源的窄语义**（`{path,type,loaded}`），差异显式登记；`_serialize_variant` 仍上提为共享助手（供后续组使用），不做多余属性序列化（避免发明未声明行为） |
| 缺失信息（实现阶段 spike） | `project_validate_script` 走 `GDScript` 编译校验在**不加载脚本语言的 doctest 进程**里是否可用（也可能 SIGSEGV） | 实现者**先 spike 实测**：可用则以真实编译结果为 `valid`；不可用则退化为诚实的启发式检查，且**不得**声称「语法正确」，并在报告 deviations 登记 |
| 常见错误 | 把「`--test` 里跳过脚本相关断言」写成假通过 | 明确禁止：要么真实断言，要么把正例交给门② 真实证据 |
| 常见错误 | 为让门好看而注册未实现工具 | 禁止（GDR-7）；门① 的并集语义会直接抓住 |
| 常见错误 | `Image::resize()` 传入 `max_size<=0` → 引擎 `ERR_FAIL` 或除零 | `max_size` 必须校验：`<=0` → `-32602`（与 `require_int`/`optional_int` 一致的显式错误语义） |

## 8. 待确认问题的最终结论

1. **共享助手的落点**：`tools/tool_builder.h` **只**放「构建与注册 + 参数校验 + 结果封装 + 路径/IO 助手」这一职责集；
   4 个通用文本/路径/变体助手放到**新共享头 `tools/tool_helpers.{h,cpp}`**（`namespace MCPTools`），
   由两组成员文件与新组共同 include。理由：`tool_builder.h` 已 153 行且职责是「工具定义构建」，
   把通用文本工具塞进去会让它对每个组都变成不必要的编译依赖；独立一对 `.h/.cpp` 与仓库既有
   `tools/<topic>.{h,cpp}` 风格一致，`SCsub` 的 `tools/*.cpp` glob 自动纳入构建。
2. **`accept_m1.ps1` 是否可改**：可改（TASK-004 先例 + 门⑤是收口门，硬编码不更新则必然 FAIL），改动仅限
   工具名清单与计数常量，**不得**放松任何断言强度。
3. **`docs/tool-groups.json` 是否可改**：可改且必须改（`implemented` 置 `true`），报告 deviations 登记。
4. **新组注册顺序**：按 `docs/tool-groups.json` 的 `tools` 数组顺序（`project_list_scripts` 起），
   在 `tools/registration.cpp` 的 `register_all_tools()` 末尾追加 include + 一行调用。