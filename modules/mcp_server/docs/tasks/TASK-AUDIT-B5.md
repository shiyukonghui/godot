# TASK-AUDIT-B5 — 独立验收：B5 全部 58 工具 + **契约 171/171 收口**（M5 引擎侧）

> 你是**独立验收方**，未参与任何实现；**不得采信**任何 `REPORT-*`（含实现报告）与决策者结论。
> 只依据规范、代码与你**自己可复现**的证据。
> 报告写到 `docs/reports/REPORT-AUDIT-B5.md`；返回值**只允许**是「≤15 行总结 + 报告路径 + verdict」。

## 0. 基准与开工

1. 权威依据：`docs/tools_list.renamed.json`（171 条）、`docs/tool-rename-map.json`、
   `docs/tool-groups{,-b2,-b3,-b4,-b5}.json`、`docs/DESIGN-DETAIL.md`（**§17–§23 / GDR-16..GDR-25**）、
   `docs/tasks/PLAYBOOK-group-port.md`（**门①–门⑥**、§6、§7）、`F:\moonbit-hof-rs\DECISIONS.md`（D45–D89）。
2. 开工第一步：`scripts/build_local.cmd -Force`（`tests=yes`，**从 cmd 启动**）重建 +
   校验 `--version` == `git rev-parse --short HEAD`。
3. 历史验收原文仅供了解历史：`REPORT-AUDIT-M4{,b,c,d,e}.md`。

## 1. 必须核实（逐项给结论 + **你自己跑出的证据**）

### A. **全量对等 171/171**（核心）
1. **自己解析** `tools/list` 的 `name` 字段（**禁止** `-match`/文本包含），核实**并集 == 契约 171**（missing=0/extra=0）；
2. 逐条与契约 `name`/`description`/`inputSchema` **逐字相等**（两端点各自可见的那部分）；
3. 按映射 `scope` 推导两端点期望集合，与实况双向差集为空；跨端点调用 **`-32601` 且不执行**；
4. 机器校验：`check_tool_groups.py --check-completeness` 与 `--batch B1|B2|B3|B4|B5` 全部 exit 0
   （**171 = 66 + 105，两两不相交**）。

### B. 契约纪律（**override 必须可核对**）
5. `_meta.overrides` 条数与你从生成器源码读出的**声明数一致**（应为 **18**）；
6. **自己**用生成器把契约重生成到临时文件，与跟踪文件**逐字节比对**（证明**无手改**）；
7. 结构化 diff：清空 override 表后重生成基线 → 差异**只**应是那些 override 影响的字段 + `_meta.overrides`。

### C. 诚实性：**7 个 `fix_implementation_first` + 2 个 `unregister`**
8. **7 个 fix-first 的现状**：早期 4 个（`editor_remove_output_log`、`editor_disconnect_signal`、
   `editor_set_auto_dismiss_dialogs`、`editor_get_test_report`）+ B5 的 3 个
   （`editor_set_tilemap_cell`、`editor_set_tilemap_cells_in_rect`、`editor_bake_navigation_mesh`）——
   **自己构造证据**证明它们**真的做到了**，尤其：
   - `editor_set_tilemap_cell`：迁移源的单参 `set_cell` 是**擦除**形状 → 现在写**真的落进去**且**读族能读回**；
   - `editor_set_tilemap_cells_in_rect`：批量**故意坏的中间元素** → **全成功或全回滚**；
   - `editor_bake_navigation_mesh`：**另一工具**证明烘焙**真的产出**（多边形数变化），且**无导航数据时诚实拒绝**；
9. **2 个 `unregister_until_implemented`** 仍**未注册**；
10. **不得有假成功**：抽查 ≥10 个 B5 工具的不存在目标（未知 tile 源/未知 shader 参数/未知主题项/不存在预设/无 SDK 等）
    → 必须**明确错误** + 可读建议。

### D. 顺手性（GDR-23/25）
11. **零字符串手术链**：自己跑 ≥2 条（含主题链与导航/移动链），**逐步**确认调用方字符串处理为 0
    （直接读脚本源码区间核对，不要只看报告）；
12. `§23.4` 读回↔写回双向闭合抽样 ≥8 项（含 packed 与对象）；`§23.5` `OBJECT` 三形态；
13. **`running_game_move_player_to_target`**：自己从游戏端点发起，**用另一个工具跨帧观察位置**——
    必须**真的在移动**（多个互异位置），**不得**是瞬移；终点与工具自报一致；
14. `editor_theme_*` 的写必须**回读核实**（引擎归一化/夹取 → `ignored` 语义）。

### E. 门⑥ 三段式（**对抗**）
15. 自己跑 `check_narrowing_points.py` + `--coverage` + `mcp031_gate6_coverage_probes.ps1`；
16. **自己插**一个未标注收窄点（用 **TASK-033 之后已覆盖的拼写**，如 `(real_t)`、`static_cast<float>`、
    `Color{…}`）→ 必须 **exit 1**；只加空行/位移 → **不假红**；**逐字节还原**并证明 `git status` 干净；
17. 核实覆盖集合与未覆盖边界**都被打印**（§22.3b 规则 6）。

### F. 工程门与端口
18. 六道门自己跑（门①按 ≥4 组、门②抽 ≥4 组证据脚本、门③④、门⑤ `accept_m1.ps1` ×2 且 PASS 清单一致、门⑥ 三段）；
19. **9877 全程 PID 36392**、测试只用 9888/9889（另开端口收尾释放）、**无孤儿**、
   **不得** git 写操作、**不得**修改被跟踪文件。

### G. **能力缺失 vs 真实成功**（Android/export）
20. 核实 `os_list_android_devices` / `os_deploy_to_android_device` / `project_get_android_preset_info`
    **没有**伪造成功或回显假数据；「能力缺失」的证据（本机无 SDK/adb/设备）**真实**；
    并与 `project_get_export_info` / `project_list_export_presets` 的**真实成功**分支**分开**陈述。

## 2. 硬性约束

不得修改任何文件（临时实验须**逐字节还原并留证**）；临时文件 `%TEMP%\audit-b5\`；不得安装依赖；
证据 `curl.exe -s -o` + sha256、请求体 `ConvertTo-Json`；不抑制 scons 输出；不并发跑 scons；
**`.ps1` 一律纯 ASCII**；**D86**：引用任何报告的结论必须标明其提交锚点并**复测**。

## 3. 报告

`verdict`（分类：171/171 对等 / 契约纪律 / fix-first 与诚实性 / 顺手性 / 门⑥ / 工程门 / 端口 / 能力缺失声明）、
逐项结论与**你自己跑出的证据**、`defects`、`unconfirmed`、`risks`、`next_step_recommendation`。
**返回值：≤15 行 + 报告路径 + verdict。**