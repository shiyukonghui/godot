# TASK-009 — B1 收官：最后一组 `running_game_read_scene` + 助手去重批次 + 本地构建脚本

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-009-b1-closure-running-game-read-scene.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。
> 本任务很小，**不要扩范围**。

## 1. 最后一组：`running_game_read_scene`（1 个 `scope=game` 工具）

- 成员：**`running_game_find_nearby_nodes`**（旧 `find_nearby_nodes`，`channel=running_game`，`scope=game`，`mutating=false`）
- 这是 B1 里**唯一的 `scope=game`** 工具，因此**首次**让「**game-only 必须缺席于编辑器端点**」这一方向有真实对象：
  1. **9889（游戏进程）**：该工具必须出现，且与契约 `name`/`description`/`inputSchema` **逐字相等**；
     并用 `curl.exe --data-binary @file` 给出**成功 / 缺参 / 底层失败**三类真实证据（不可构造的类要声明）。
  2. **9888（编辑器进程）**：该工具**必须缺席**；且从编辑器进程调用它必须得到 `-32601` 且**不执行**（给真实响应）。
  3. 报告里给出两个端点 `tools/list` 的**工具名清单对比**。
- 语义参照：`godot_mcp_gdext/src/commands/`（找到它的实现文件并写出可观察契约）；
  注意它在**游戏进程内**运行，节点树来自**运行中的场景**（不是编辑场景）。
- `docs/tool-groups.json` 的 `implemented` 置 `true`，并在报告里给出「**B1 = 41/41 全部落地**」的机器校验输出
  （`docs/scripts/check_tool_groups.py` 或等价自写检查 + 每个 `implemented=true` 组的工具计数）。

## 2. 助手去重批次（与 §1 同批做，先做）

TASK-008 记录了两处**跨组重复**（因组间不得互改文件而复制）：
1. `_require_editor_ui`：`editor_write_scene_editor.cpp` 与 `editor_read_scene_inspector.cpp` 各一份；
2. **属性值强制转换**（property-value coercion）：`editor_write_scene_editor.cpp` 里是
   `project_write_resource_scene.cpp` 的**局部子集**（后者的完整版是该组文件私有）。

做法（与 TASK-005 / TASK-008 的两次先例一致）：
- 把这两者上提到共享助手（`tools/tool_helpers.*`，或与现有助手风格一致的新共享头）；
- 让相关组改用共享实现、删除本地副本；
- **必须证明行为等价**：同一请求序列在重构前后的**响应逐字节相同**（对照提交 = 重构前的那一刻）；
- 断言「同一函数只有一个定义」（贴 `grep`/`rg` 结果）。

## 3. 本地构建脚本（消除一个环境陷阱）

TASK-008 记录：仓库根的 `build-m0.cmd`（未跟踪的本地脚本）**没有 `tests=yes`**，
导致后续批次容易在**无测试的二进制**上跑门（会看不到 doctest）。
→ 在模块内提交一个**受跟踪**的构建脚本 `modules/mcp_server/scripts/build_local.cmd`
（或等价 `.ps1`），内容为**已验证可用**的构建命令（`platform=windows target=editor module_mono_enabled=no tests=yes -j8`），
并在脚本头部注释说明：**门③/门④需要 `tests=yes`**；以及**修改 `tests/test_mcp_server.h` 后必须删除过期 obj 才会重新编译测试 TU**。

## 4. 门

按 `PLAYBOOK-group-port.md` §3 五道门（门①用 `-Group running_game_read_scene`，**逐端点 scope 语义**），
外加：§1 的双端点清单对比与缺席/拒绝对证据、§2 的等价性证明、§3 的脚本可运行证据（贴一次真实构建输出）。

## 5. 报告

按手册 §4，写到 `docs/reports/REPORT-009-b1-closure-running-game-read-scene.md`；
另加：「B1 收官计数（41/41）」与「game-only 缺席方向的首个端到端证据」两节。
**返回值：≤15 行总结 + 报告路径。**