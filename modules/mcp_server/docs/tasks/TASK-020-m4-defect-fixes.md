# TASK-020 — 修复 M4 验收的 3 个缺陷（静默错值残留 + 断言字段）并补两项未验证项

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含；**注意 §3 关于
> 「静默错值的两个层级」「门配置必须用 `build_local.cmd`」的新条款**），再读本文件。
> 报告写到 `docs/reports/REPORT-020-m4-defect-fixes.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 来源

**M4 独立验收判 `fail`**（详见 `docs/reports/REPORT-AUDIT-M4.md`），3 个缺陷必须修：
两处「**静默写错值并报成功**」的残留面（D-1/D-2，均为 high）与一处字段集不一致（D-3，medium）。
其余六类（全量对等 / 安全与事务 / 延迟通道 / 工程门 / 端口纪律 / fix-first 现状）已 pass。

## 1. D-1（high）：**复合属性的分量**绕过静默错值闸门

- 现象：给 `position`（`Vector2`）传 `{"x":"abc"}`、`{"x":"NaN"}`、`{"x":null}`、`{"x":{"z":9}}`、`{"x":[1,2]}`
  → **`code=0`（成功）**，读回 `position.x` 均为 **`0.0`**。
- 根因（验收方已定位）：`tools/tool_helpers.cpp:599-607` 的 `property_value_from_json` 在 **DICTIONARY 分支递归时传 `Variant::NIL`**，
  分量因此**不过** `coerce_to_property_type` 的 `Variant::can_convert` 门；而门只作用于 **dict→Vector2 整体**
  （该整体转换在引擎里是**允许**的），所以整值级闸门拦不住分量级。
- 修法：**递归时携带目标分量类型**（`Vector2.x/y = FLOAT`、`Vector3.x/y/z = FLOAT`、
  `Color.r/g/b/a = FLOAT`、`Vector2i/3i` 分量为 INT 等），使**每个分量**也走同一道判定；
  不合规一律 **`-32602`**，且**批量路径必须在任何写入之前**拒绝（保持 TASK-017 的全成功/回滚）。
- 注意：`DICTIONARY→VECTOR2` 在引擎转换关系里是允许的，**不能**靠收紧整体关系解决——必须做分量级。

## 2. D-2（high）：`STRING→FLOAT/INT` 放行无法解析的字符串

- 现象：`rotation="abc"` → **`code=0`**，读回 `0.0`；`"NaN"` 同样 `code=0`。
- 根因：`tool_helpers.cpp:683` 的 `!Variant::can_convert` 门在 `STRING→FLOAT` 上为**真**，
  而 `:698` 的 `type_convert("abc", FLOAT)` 返回 `0.0`。该缺口**同时使 FLOAT 分支的 NaN/Inf 守卫对字符串失效**。
- 修法：对 `STRING→FLOAT/INT` 增加**可解析性 + 有限性**判定，不可解析/非有限 → **`-32602`**；
  **保留 `Color` 的 `#rrggbb` 既有特例**。
- 这是**对已验收工具的行为变更**：报告必须**显式列出受影响工具**（至少
  `editor_set_node_property`、`editor_set_node_property_batch`、`editor_add_nodes_batch`、
  `running_game_set_node_property`、`editor_add_resource_to_node_property`、`project_create_resource`、
  `project_edit_resource`，以你实测的调用面为准）。

## 3. **证据形态硬要求**（D67 漏掉该类的原因）

这两类缺陷的自检**必须**给出**能区分「拒绝」与「按引擎语义写默认值」**的证据：
1. **错误码**（`-32602`）；
2. **前后场景 `.tscn` / 磁盘 sha256 相同**；
3. **旧值仍为旧值**（用**另一个**读工具读回，且明确断言「未被改动」）。
> **仅**比较「读回值 vs 请求值」**不足以**判定——因为「引擎按语义写入默认值」也会让读回值 ≠ 请求值，
> 却仍然是**静默成功**。
并且**每个反例**都要同时覆盖：**整数/浮点/字符串/复合/数组/dictionary/null** 六类与**批量路径**。

## 4. D-3（medium）：两个独立断言工具失败时不带 `reason`

`running_game_assert_node_state` / `running_game_assert_screen_text` 的**独立**失败返回只有
`actual`/`expected`（后者还带 `visible_elements[]`），而**场景运行器内**同一断言**有 `reason`**。
→ 复用同一条 `reason` 文案生成路径（或把 verdict 构造下沉为共享 helper），使**两个入口字段集一致**。
补 doctest 断言「两个入口的失败字段集相同」。

## 5. 顺带修正文档措辞

`docs/DESIGN-DETAIL.md` §17.3 的端点期望公式措辞与实况的**对称 scope 规则**不相容
（实况与门脚本都按对称规则；§17.3 文字需同步）。**只改措辞，不改规则。**

## 6. 补两项验收方未能完成的验证（它们已准备好素材）

1. **`project_set_node_property_across_scenes` 的多场景全或无事务**：用「**一个好文件 + 一个坏文件**」
   （坏文件用截断的 `.tscn`，验收方已备 `scenes/broken.tscn`）把事务**跑透**，给出
   ①坏文件在后 → 好文件**未被改动**（sha256 相同）、②错误里带 `data.scenes.errors` 与「Nothing was written」形态、
   ③两个都好 → 都写入成功。
2. **`editor_analyze_screenshot_diff`**：构造一对**真实 PNG**（引擎自己编码生成），
   验证 `identical`/`changed_pixels`/`diff_percentage`/`threshold` 越界 `-32602` 与「相同图 → identical=true」。

## 7. 门

按 `PLAYBOOK-group-port.md` §3 五道门（第 0 步：**用 `scripts/build_local.cmd`（`tests=yes`）重建**并校验
`--version` == `git rev-parse --short HEAD`；**不要**用仓库根的 `build-m0.cmd`），
外加：§1/§2/§3 的反例矩阵与证据形态、§4 的字段集一致性、§5 的文档 diff、§6 的两项补验。
**并且**：重跑 M4 验收用过的对抗性反例（D-1/D-2 的五种分量值与字符串值、批量事务段）以证明闭合。

## 8. 报告

按手册 §4，写到 `docs/reports/REPORT-020-m4-defect-fixes.md`；另加：
「D-1/D-2/D-3 的前后对照与**证据形态**说明」「受影响工具清单」「两项补验结果」「文档措辞修正 diff」。
**返回值：≤15 行总结 + 报告路径。**