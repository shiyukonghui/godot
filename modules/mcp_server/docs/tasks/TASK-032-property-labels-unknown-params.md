# TASK-032 — D3（分组标签混入属性 + 大小写冲突）· D4（未知参数名静默忽略）· D6（游戏侧路径描述）· `mcp018` 历史不变式收口

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-032-property-labels-unknown-params.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 四项（来自 M4d 第四次独立验收 + TASK-030 的上报）

### D3（medium，**优先级最高**）：`editor_get_node_properties` 把**检查器分组/类别标签**当属性输出

**实测**：不带 `properties` 时响应里出现 **12 个不存在的 null 属性**
（`Node`/`Node2D`/`Material`/`Transform`/`Visibility`/`Ordering`/`Texture`/`Process`/`Thread Group`/
`Auto Translate`/`Editor Description`/`Physics Interpolation`/`CanvasItem`），
且 **`Material` 与真实属性 `material` 大小写冲突** → 本机 PowerShell 直接报
`contains the duplicated keys 'Material' and 'material'`，**整包无法解析**
（大小写不敏感字典实现的客户端同样受影响；R3：容易被误判为偶发坏响应）。

**位置**：`tools/editor_node_read.cpp:192-205`（只跳过 `_` 前缀与 `script`，**未按 `PROPERTY_USAGE_GROUP`/`CATEGORY` 过滤**）。

**要求**：
1. **过滤**分组/类别条目（按引擎语义：`PROPERTY_USAGE_GROUP` / `PROPERTY_USAGE_CATEGORY` /
   无 `STORAGE` 且无 `EDITOR` 的纯标签项，**以引擎源码为准**）；
2. **不得有大小写冲突**：即使引擎同时给出 `Material`（标签）与 `material`（属性），输出里也**只能有一个**；
   并明确**输出键的规则**（引擎原始拼写；若同一键大小写变体冲突 → 报告里说明取舍）；
3. **回归**：同一节点在**修复前后**属性集合的对照；
   **用大小写不敏感的解析器**（例如 PowerShell `ConvertFrom-Json`）验证**能解析**（这是本缺陷的直接判据）；
4. **`running_game_get_node_properties` 同族一起查**（若同样问题一并修，并在报告说明）。

### D4（minor）：未知/多余参数名被静默忽略

`project_get_settings` 的契约参数是 `prefix`，用 `filter` 调用 → `code:0` 且返回 **981 条**设置
（既**不拒绝**也**不过滤**）→ 「拼错的参数名得到像样的错答案」。
对比 `project_set_setting` 用 `name` 时诚实回 `-32602 Missing required parameter: key`。

**要求**：**未知参数名一律 `-32602`**，消息**点名**未知参数（并给出建议：`data.suggestion` 里列出该工具接受的参数名）。
**影响面**：这是**行为收紧**，可能影响既有证据脚本（它们若传过多余参数会开始失败）→
**必须重跑全部证据脚本并列出受影响的**；若某个脚本因此失败，说明它之前依赖了被忽略的参数（**报告里说明**）。

### D6（minor）：游戏侧路径形态与描述不一致

`running_game_get_scene_tree` 返回 `path="/root/Main/Actor"`，而同族 `running_game_get_node_properties`
的描述写「`node_path`（相对于场景根节点）」；实测**两种写法都能喂回**。

**要求**：走 **`DESCRIPTION_OVERRIDES`**（append）**声明实际返回形态**并写明**两种写法都接受**；
**重生成契约 + 更新全部指纹**；门① 逐字通过。**不得手改契约文件**。

### `mcp018` 历史不变式收口

`scripts/mcp018_*.ps1` 里断言 `derivation_new_union_is_old_plus_exactly_ten`（`old=96 new=113`），
随工具数增长**必然失效**（TASK-030 如实上报未自改）。
→ 改为**相对当时清单**的判据（例如「基线字面量 == 那批 manifest 的派生集」），或**显式标记为已被后续批次超越**，
使它**不再持续红**；**不得**为了让脚本变绿而放宽真正的不变式（`B1/B2 路径输出 sha 不变` 之类必须保留）。

## 1. 门

- 第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD。
- 五道门 + **门⑥**。
- **重跑**：`TASK-028/029/030` 的证据脚本 + `mcp018`；并**新增**一条「大小写不敏感解析器能解析整包」的断言（D3 的直接判据）。

## 2. 报告

按手册 §4（含「引擎依据」列），写到 `docs/reports/REPORT-032-property-labels-unknown-params.md`；另加：
「D3 前后属性集合对照 + 大小写冲突消除证据」「D4 受影响的既有脚本清单」「D6 的 override 记录与线上实测」
「`mcp018` 判据改写前后」。**返回值：≤15 行总结 + 报告路径。**