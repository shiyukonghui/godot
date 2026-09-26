# TASK-063 — 修第 2 轮抓到的 4 条产品缺陷（端点静默失能 / 参数面 / 批量写不同值 / parse 行列）

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件；证据原文 `docs/reports/BREAKOUT-FINDINGS.md`（**以 `docs/reports/evidence/task060/**` 为准**）。
> 报告 `docs/reports/REPORT-063-round2-product-defects.md`。返回决策者：**≤8 行总结 + 报告路径**。

## 1. **(a) major：游戏端点 `bind` 失败却静默失能**

实测：`bind failed on 127.0.0.1:9889 (error=22)` → `get_port()=0`（**MCP server 被禁用**），
**唯一日志痕迹**是那一行；**响应侧无任何迹象**，调用方会以为端点只是"不响应"。
**要求**：
1. **先给最小复现 + 根因**（`文件:行` 依据）：`error=22`（EINVAL）由什么造成？
   查 `NetSocketWinSock` 的 bind 路径、端口解析、`--mcp-port` 与 `editor_play_scene` 的端口注入（E-10）、
   以及**游戏进程是否与编辑器抢用同一端口**；给出「什么条件必然导致失败」的判定。
2. **必须可见**：启动时 **ERROR 级日志**（明确写：请求的端口 / 失败原因 / **MCP 端点已禁用**），
   并在**进程不会退出的前提**下把该状态**记录下来**（例如 `get_port()==0` 时提供可查询状态）。
   **不得**静默继续、**不得**伪造可用性。
3. **修根因**（若可修）：使 E-10 注入的端口在游戏进程里**真的能绑上**；若根因是"端口被占"，
   则**报错必须点名占用者/建议换端口**，并且**不得**静默退化为禁用。
4. **证据**：①复现（含失败日志原文）；②修复后**同一场景绑上**（游戏端点可用 + `tools/list` 69/72 条）；
   ③冲突场景（故意先占端口）→ **明确 ERROR + 状态可查**，而非静默。

## 2. **(b) 参数面不一致**：`path` vs `node_path` / `node_paths`

实测：`editor_set_node_property`/`editor_get_node_properties` 用 **`path`**（单数、**场景根相对**），
`editor_set_node_script_batch` 用 **`node_paths`**（复数）；三者都**拒绝** `/root/...` 与裸名，但**描述未声明**、`-32001` **不指路**
（第 1 轮 DEV-LOG 那条「缺陷」实为**误报**，根因在此）。
**要求**：**保留现有参数名**（改名会破坏既有证据与调用方），改为：
①走 `DESCRIPTION_OVERRIDES` **声明路径基准**（"relative to the edited scene root; `/root/...` is not accepted"）与单/复数差别；
②让**拒绝消息**指路（`-32001`/`-32602` 的 `data.suggestion` 明说**该用哪个参数名、什么形状**）；
③给「`/root/Main/Car` → 明确指路」与「正确写法成功」两条线上证据；④**契约条数不变**。

## 3. **(c) `editor_set_node_property_batch` 只能写同一个值** → **新增工具** `editor_set_node_property_updates`

实测：`{node_type, property, value}` 是**类型作用域**（给同类节点写同值）；按路径列表写**不同值**的能力**不存在**
（试 `updates` → `-32602`）；真实开发里几何只能 **20 次单点写**。
**要求（走 `ADDED_TOOLS`，契约 175 → 176）**：
- 名 `editor_set_node_property_updates`（`editor` + `set` + `node_property_updates`；作用域 `editor`，`mutating=true`）。
- **描述（英文，逐字）**：`Set a different value on each of many nodes in the edited scene in one call, and answer per entry whether the value landed.`
- **`inputSchema`**：`updates`（array，必填，≥1；元素 `{path:string(必填), property:string(必填), value:any(必填)}`）、
  `stop_on_error`（boolean，默认 `false`）。
- **行为**：逐条**读回核实**（`changed`/`old_value`/`new_value`）；`stop_on_error:false` 时**逐条**给结果（部分成功要**明示**），
  `true` 时**首错即停 + 已改的回滚或明示不可回滚**（二选一，说明理由）；越界/未知属性/值不合法 → 该条明确错误码 + `data.suggestion`；
  **不得**把它做成绕过 §20/§22 收窄闸门的后门（**必须**过同一道 `ValueSlot` 闸门）。
- **证据**：一次调用给 4 个不同节点写**4 个不同值**（含一个越界值 → 该条被拒、其余成功）+ **读回**证明；两工具口径对比（类型作用域 vs 路径作用域）。

## 4. **(d) `editor_execute_gdscript` 的 parse 错误不带行列**

实测：26 次调用、7 对失败→成功，错误只有 `Parse error`。
**要求**：**先查引擎源码**能否拿到行/列（`GDScript`/`ScriptLanguage` 的错误记录、`Parser` 的 error_line/error_column）→
能拿就补进 `error_text`/`data`；拿不到就**如实声明边界**并给「能定位到什么程度」的实测对照。

## 5. 门与纪律

第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；五道门 + 门⑥ 三段式 +
`--check-completeness`/`--added`/`--generator-version`（新增工具 → **176**）；`accept_m1` ×2（清单一致）；
回归 `mcp041/042/043` + `mcp010/019/027` + `mcp044/045/046` + `mcp050…062` 脚本，**逐条归因**；
**构建严格串行**；**绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push；`.ps1` 纯 ASCII；**红相位输出当场保存**；结论按 D86 标锚点。
**所有产物写绝对路径**（`F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\...`）—— D119 的教训。