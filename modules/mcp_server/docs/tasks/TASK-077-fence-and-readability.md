# TASK-077 — 修独立验收的 **D-B1（围栏被链接穿透，阻塞）** / **D-B2（编译不过仍报 readable）** / **D-B3（分析器误报）**

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件。
> 来源：`REPORT-AUDIT-075.md`（**verdict=fail**；D-B1 阻塞 / D-B2 高 / D-B3 中 + 4 条 unconfirmed）。报告（**绝对路径**）
> `...\reports\REPORT-077-fence-and-readability.md`。契约 **177**（条数不变；若仅改描述则同批一次移动 sha）。

## 1. **D-B1（阻塞）**：`res://` 围栏被**链接**穿透 —— **模块级**

实测：工程内放 junction/目录符号链接/文件符号链接指向工程外 → `project_read_text_file{path:"res://link/secret.txt"}`
**返回工程外文件的全部字节**（响应 sha `8a60ea9d…` == OS 哈希 `a41903ea…`），**9889 同样**；
**`project_read_script`、`project_get_filesystem_tree` 一样穿透**（**一处修好覆盖三个**）。
**裁决**：**按缺陷修**——**不是因为「提权」**（调用方本就能执行任意 GDScript），而是因为
**工具描述承诺了 `res://` 约束却返回工程外字节**，属「**声明与行为不一致**」同一族。
**要求**：
1. **先复现**（junction + 目录符号链接 + 文件符号链接三种，给响应 sha 与 OS 哈希相等）。
2. **修**：写入/读取前**解析真实路径**（处理 `..`、链接、junction、盘符与 UNC），**校验落在工程根之内**；
   越界 → **明确错误码 + `data.suggestion`**；**三个工具口径一致**。
3. **若引擎 API 无法可靠判定** → **在描述里如实声明**（并给「为什么做不到」依据），**但必须**同时满足：
   ①声明覆盖三个工具；②给出**可被调用方自行校验**的返回字段（例如 `resolved_path`）——**不得**保持沉默的穿透。
4. **对抗证据**：把验收方那三条（F24/F25 与 OS 哈希对照）**自己重跑**，修后**必须全部被拒**；
   并给**合法路径对照**（工程内普通文件仍可读）。
5. **反例**：构造一个**合法**的 `res://` 相对路径（含合法 `..` 归一但仍在根内）→ **必须成功**（防过度拒绝）。

## 2. **D-B2（高）**：`readable` 必须意味着「**引擎真的能载入/编译**」

实测：`broken.gd`（`func broken(:`）被批量报 **`attached:true` + `readable:true`** 并写进 `.tscn`，
而引擎载入场景时**丢弃**（游戏侧 `Sprite` 无 `script` 字段；stderr `GDScript::reload(...:2) Parse Error`），
**同进程 `project_validate_script` 已答 `valid:false/ERR_PARSE_ERROR`**。
**要求**：`readable` 的判据升级为**真的可加载/可编译**：GDScript 走解析检查（与 `project_validate_script` **同源**）、
C# 走 `invalid`/`not_compiled` 口径；**不满足则拒绝并回滚**（错误码 + 建议），**合法脚本仍 `readable:true`**。
**必须**：单数与批量口径一致；**合法对照**（防过度拒绝）；**红相位当场保存**。

## 3. **D-B3（中）**：分析器误报「缺参数」

实测：`probed_argument_names` 不与「名字是否在该工具 `inputSchema` 里」挂钩 → 6 条里 **4 条**
（`source_id`/`resource_properties`/`resource_type`/`atlas_coords`）是**契约确有且拼写正确**、只因**无 TileSet / 枚举不认识 Vector2 / 类型不可写**而失败的。
**要求**：**与契约 `inputSchema` 交叉核对**，**分两桶报告**（**契约外参数** vs **拼写正确但别的原因失败**），
命名不得暗示因果；并**加自测**（合成用例：真契约外名 → 桶 A；契约内名 → 桶 B）。

## 4. 门与纪律

第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；五道门 + 门⑥ 三段式 +
`--check-completeness/--added/--generator-version`（**177 = 171+6**）+ `accept_m1` ×2（清单一致）+
`check_exit_propagation.py` + `check_tautologies.py` + `check_hardcoded_counts.py` + `check_engine_anchor.ps1`；
回归相关脚本**逐条归因**；**构建严格串行**；**绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push；`.ps1` 纯 ASCII；
**红相位输出当场保存**；结论按 D86 标锚点；产物**绝对路径**。