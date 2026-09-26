# TASK-016 — ACCEPTANCE（阶段五工件，决策者维护）

## 1. 结论

**verdict = pass**（独立验收子代理给出，1 条 minor 缺陷、3 条已披露风险，无 blocker / major）。

- 实现交接 HEAD：`c851020f35`，`--version` = `4.8.dev.custom_build.c851020f3`（与 HEAD 一致）。
- 实现提交：`805899b4e5`(U1 上提) → `ca9627f638`(等价性证明) → `4e023604e4`(U2 read 6) →
  `6788201ca7`(U3 instantiate 4) → `c1f2b82ace`(证据脚本+注册顺序) → `c9760a7f88`(GridMap doctest 加固) → `c851020f35`(报告)。
- 验收子代理**不是**实现者，未继承任何结论；A1–A11 逐条由它自己复现（A2 的 before 半程为推断，见 §4）。

## 2. 逐条标准与证据（验收子代理自测，非抄报告）

| id | 判定 | 它自己的证据（摘要） |
|---|---|---|
| A1 | pass | 自己 grep：`find_node` / `edited_scene_root` 各只剩 `tool_helpers.cpp:367` / `:375` 一处定义 + 头文件两处声明；`static Node *_find_node` 与 `static Node *_edited_scene_root` 为 **0**（重构前分别 2 / 3 处）；`_relative_path` 仍 `editor_node_write.cpp:81` 单处未动 |
| A2 | pass（before 半程 inferred） | 通读脚本确认写死 `$PreCommit='c26516becc'`、有 checkout+重建+`--version` 断言、失败非零退出；**自己重算**残留 20/20 before/after 响应 sha256 逐字节相同；引擎启动 banner `editor-before.out.log` = `c26516bec` vs `editor-after.out.log` = `805899b4e`；`git reflog` 独立显示 checkout 往返 |
| A3 | pass | 自己重跑门①两组：各 `3/3 checks passed`、exit 0、10 条 `name/description/inputSchema` 全 True |
| A4 | pass | 自己解析：9888 = 69 个名字且 10 个各出现 1 次；9889 = 40 个且 10 个全缺席；自己逐个调 9889 → 10 条全 `-32601 Method not found` 且无 `result` |
| A5 | pass | 自己造 BOM-free scratch（`--import` exit 0）采三类证据；7 个 `required` 工具 `{}` → `-32602`，3 个 `required:[]` 工具合法成功（报告「不可构造」声明诚实）；底层失败一律 `-32001`+suggestion；空结果 `count:0` 为成功 |
| A6 | pass | 自己跑一条**非报告里**的写读链：add_node → set_node_property(`{7,9}`) → get_node_properties 读回 `{7.0,9.0}` → set_node_groups → get_node_groups → find_nodes_in_group → connect_signal → get_node_signals(ready.connections) → list_signal_connections 命中 → disconnect → count 11 且 Chain/ready 归零 |
| A7 | pass | 自己重跑：门③ `139/139 passed, 0 failed, 5185/5185`；门④**在仓库根** `1565/1565 passed, 0 failed, 429467/429467`（并确认自己没重复实现者的 cwd 假红） |
| A8 | pass | 自己连跑 `accept_m1.ps1` 两次 exit 0，自己抽 `[PASS]` 集 `diff` 为空 → `PASS-SET-IDENTICAL` |
| A9 | pass | `git diff` 显示 manifest **恰好 2 行** `implemented: false → true`，其余零改动 |
| A10 | pass | 自己重算：`tools_list.renamed.json` 171 条、B3 已实现 20、76+10=86、171−86=85；门⑤ 自己也打印 `86 / 171` |
| A11 | pass | 自己重算报告 §9 的 12 个文件 sha256 **全部逐一相符** |

## 3. 未通过项

无 blocker / major。唯一缺陷：

| id | 严重度 | 内容 | 处置决定 |
|---|---|---|---|
| D1 | minor | 被列举规则隐藏、但**点名要求**的属性（如 `"script"`）的拒答串语法破损：`Property 'script' on node 'Probe' is not readable by name not found` —— `MCPToolError::not_found()` 会在已含 `is not readable by name` 的短语后再追加 `" not found"`。**行为正确**（`-32001` + `data.suggestion`），只是可见字符串难看。报告 §5.6 已原文披露。 | **接受并延后**：不为此重开阶段四。理由：①纯文案、无行为后果；②已披露；③重开一轮「全新实现者+全新验收者+五道门」的代价与收益不成比例。列为下一批（TASK-017）的实现者顺手修项，写入 `DECISIONS.md` D-T016-4 |

## 4. 遗留风险（验收子代理原样保留）

| id | 风险 | 状态 |
|---|---|---|
| R1 | `c9760a7f88` 把 `editor_add_gridmap` 的 doctest 接收者从 `GridMap` 改成裸 `Node`（全量 doctest 进程里 `GridMap` SIGSEGV，二分证明：仅排除该用例即 1564/1564 全绿）。**doctest 层的真 `GridMap` 接收者覆盖有意消失**，crash 未根因定位（`modules/gridmap` 不在本任务范围）。工具侧真路径由线上证据覆盖，验收子代理已自行复现（`mesh_library_set:true, type:GridMap`），但它承认 SIGSEGV 本身为 inferred（复现需改只读测试） |
| R2 | `editor_get_node_signals` 用统一的 `MCPTools::find_node` 解析 `node_path`（精确相对路径 + 根名前缀重试），迁移源用的是 GDScript 的递归按名查找（`root.find_node(path,true,false)`）。裸叶子名（非根、非直接子节点）现在回 `-32001`。**由 DESIGN-DETAIL §2 指定、报告 deviation 3 已披露**，对从 Rust addon 迁移的调用方是真实语义差异。验收子代理线上复现：`Deep/Grand` 成功、`Grand` → `-32001` |
| R3 | 报告 §9 记的二进制 sha256（`700c02a1…`, 300544 B）**不是**交接时磁盘上二进制的哈希（当前 `56f2c46c…`）：门跑在 `c851020f35` 报告提交之前的重建上，之后为让 `--version` 等于 HEAD 又原样重建一次。报告 §10.16 已预测并说明。**审计者应校验 `--version` == HEAD，而不是比对二进制字节** |

## 5. 验收子代理明确声明的「未能复现项」（不得当作证据）

1. **A2 的 before 半程没有自己重建重跑**（成本 + 会扰动工作树）。它用五路旁证（脚本通读、20/20 sha256 自算、引擎 banner、reflog、上提体与 PRE 五份副本逐字对照）支撑，并明确标注 before 端 provenance 是**推断**。这是本报告最应被后续读者注意的一处保留。
2. **红阶段的构建没有自己复现**（需临时回退两处纠正）。它改为验证：两处纠正确实存在于代码、两条点名 doctest 存在、自己跑出的门③绿数与红/绿产物完全一致、迁移源里确实存在两处缺陷（`node.rs:249-261` 静默过滤、`scene_3d.rs:273-280` `if let Some(lib)` + 无条件 `created:true`）。
3. **线上构造「无对象 Callable」**以验证 `target == ""` —— 该行为由 `tests/test_mcp_server.h:8163-8180` 的 doctest 覆盖（在它自己的门③ 运行中执行），**线上部分为推断**。

## 6. 纪律核对（验收子代理自测结果）

- `git diff c26516becc..c851020f35 --stat` **只**触及 `modules/mcp_server/**`（16 个文件）。
- `git branch -vv` 无 upstream；`git log --branches --not --remotes` 列出全部 7 个提交 → **未 push**。
- `git status --short` 只剩四个既有未跟踪物 + 决策者的 `modules/mcp_server/docs/spec/`。
- 9877 全程 PID `36392` 不变；验收期间只绑定过 9888/9889。
- 契约 / 映射 / 生成器零改动（`docs/tools_list.*`、`tool-rename-map.json`、`docs/scripts/*` 均不在 diff 内）。
- 跨进程确定性（PLAYBOOK §6.4）独立验证：9888 同进程两次 + 进程重启后一次，`tools/list` sha256 = `bed98680b709b7d0` / 19123 B，有序名字列表一致。

## 7. 决策者给用户的话

1. 本批交付：**助手上提（含逐字节等价证明）+ 2 组 10 个工具**，五道门在绑定二进制上全绿，独立验收 pass。
2. **已实现 86 / 171，剩余 85**（B3 剩 20、B4 剩 7、B5 剩 58）。
3. 一个 minor 文案缺陷（D1）与三条已披露风险（R1/R2/R3）随本报告交接，未隐藏。
4. **仓库内不存在 `DECISIONS.md`**（PLAYBOOK 反复引用它、并引用了 D43/D59/D62 等条目，但本工作区内找不到该文件）。
   我按「发现缺失就在报告里报缺陷、不另起规范」的纪律：**没有**新建仓库级决策日志，
   本任务的决策记录写在本目录 `DECISIONS.md`（`.spec` 层级，决策者工件，不污染模块规范）。建议决策者补建权威决策日志并回填。
