# TASK-AUDIT-M4d — 第四次独立验收：M4 里程碑（B3+B4 = 47 工具）+ **顺手性条款（GDR-23/25）** 的一并复核

> 你是**独立验收方**，未参与任何实现；**不得采信** `docs/reports/REPORT-*.md` 与决策者的结论。
> 只依据规范、代码与你**自己可复现**的证据。
> 报告写到 `docs/reports/REPORT-AUDIT-M4d.md`；返回值**只允许**是「≤15 行总结 + 报告路径 + verdict」。

## 0. 基准与开工

1. 权威依据：`docs/tool-rename-map.json`、`docs/tools_list.renamed.json`（171 条）、
   `docs/tool-groups{,-b2,-b3,-b4,-b5}.json`、`docs/DESIGN-DETAIL.md`（**§17–§23 / GDR-16..GDR-25**）、
   `docs/tasks/PLAYBOOK-group-port.md`（**门①–门⑥**、§6 已知偏差、§7 纪律）、
   `F:\moonbit-hof-rs\DECISIONS.md`（D45/D59/D61/D63/D66..D83）。
2. **开工第一步**：`modules/mcp_server/scripts/build_local.cmd -Force`（`tests=yes`）重建，
   并校验 `--version` 的 hash 前缀 == `git rev-parse --short HEAD`。**不得**在陈旧二进制上验收。
3. 本里程碑 = **B3+B4 = 47 个工具**（已实现总数 113/171）；**顺手性条款**（GDR-23/25）是本轮的新验收面。

## 1. 必核（逐项给结论 + **你自己跑出的证据**）

### A. 全量对等与 scope（沿用既有判据）
1. **自己解析** `tools/list` 的 `name` 字段（**明令禁止** `-match`/文本包含 —— 描述会互相按名引用，曾造成假 PASS），
   与 B1..B4 的 `implemented=true` 组并集比对；逐条与契约 `name`/`description`/`inputSchema` **逐字相等**；
2. 按映射 `scope` 推导两端点期望集合并与实况比对；跨端点调用 **`-32601` 且不执行**；
3. **override 纪律**：契约里应有 **13 条 override**（`_meta.overrides`）；**自己**用结构化 diff 证明
   除这些 override 与指纹字段外，**没有别的契约改动**（尤其不能有手改）。

### B. 「静默写错值」这一类（**已出现 5 种形态**）——自己重造反例
对**每一种形态**都要自己构造并给出**四条证据形态**（①`-32602`；②拒绝响应**无值回显**；
③**显式保存后文件字节扫描**无 `inf`/`nan`/`Color(inf`；④**另一读工具**读到旧值未变），并给合法值对照：
- ①**整值级**：`position: 1e20`；②**分量级**：`position:{"x":"abc"|"NaN"|null|{}|[]}`；
- ③**标量级**：`rotation: 1e300` / `3.5e38` / `1e-300`；④**专用 setter 路径**：
  `editor_set_viewport_3d_camera.position`、`editor_setup_world_environment.bg_color`（**并确认保存文件里没有 `inf`**）；
- ⑤**构建配置**：确认 `FLOAT32` 与 `REAL_T` 已分离（源码级 + 单元级；**本机无法端到端验双精度**，评审其风险登记是否诚实）。
**自己再找同族新面**（5 条写路径 × 你想到的所有值类：整数/浮点/字符串/布尔/复合/数组/packed/dictionary/null）。

### C. **门⑥（收窄点清单）必须真的能挡住**
1. 自己跑 `scripts/check_narrowing_points.py`（应 exit 0）；
2. **自己打破它**：插入一个**未标注**的收窄点（如 `const real_t x = (real_t)1.0e300;` 或 `Color(` 构造）
   → 必须 **exit 1**；**再用「只加空行/移动代码」**证明**不假红**（exit 0）；
3. 核实它的索引方式**确实是标记身份**（`文件 + 标记 id + 出现序`），**不是行号**（这是 REPORT-023 声称与实现不符、后被修的项）；
4. 核实「陈旧条目」（删掉某个标记）仍 **exit 1**。做完**必须还原**并证明 `git status` 干净。

### D. 顺手性（GDR-23/25）——**自己重跑零字符串手术链**
1. **E-10**：`editor_play_scene` 必须把 `--mcp-port` 注入子进程（**自己抓子进程 cmdline**），
   并从**响应给出的端口**真的跑一个游戏侧工具；端口被占 / 等于编辑器端口 → 诚实错误（**不启动游戏**）。
2. **E-1/G-2**：`project_get_scene_dependencies` 的 `type` 是**真实类型**、`path` **可直接喂回**；
3. **E-3/§23.4**：读回形状 ↔ 写回形状**双向闭合**（自己抽 ≥10 项做「读→原样写回→再读」三层等价）；
   含 **§23.5** 的 `OBJECT`（未设置读回 **`null`**；`{}` 写回 `-32602`；`null` 写回后读回 `null`）；
4. **E-9**：`project_read_resource` 给出属性值 + 限量/截断；**E-6/G-4**：日志工具的 `source` 与**归属进程**正确、
   不可用时**诚实空**（不得 `-32603`）、同族形状一致；
5. **E-2/E-8**：编辑器节点路径**相对编辑场景根**、**跨两个独立进程启动逐字相同**、错误消息无 `@EditorNode@`；
6. **G-1**：子属性路径 `position:y` 写入成功且**另一个工具读回**；两条负例（不存在子段 `-32001` / 不可 index `-32602`）；
7. **G-3**：`clear` 缺省**纯读**（两次读取响应体 sha256 相同、桥接文件仍在）、显式 `clear:true` 才清、
   且**线上** `tools/list` 的 `default` 与实现一致。
8. **自己挑 ≥2 条链**（跨 ≥4 工具）重跑，并**逐步检查调用方字符串处理次数**（目标 0；
   直接读脚本源码区间确认没有 `Split/Replace/Substring/Trim` 之类）。

### E. 延迟通道 / 事务 / 安全（沿用既有判据）
deferred 超时与断连、批量「故意坏的中间元素」零半成品、跨场景「好文件+坏文件」全或无、
路径逃逸（写侧 × 读侧：绝对路径 / `..` / 盘符 / UNC / 符号链接 / 前缀碰撞）、参数滥用（缺参/类型错/越界/`NaN`）。

### F. 工程门与端口纪律
六道门自己跑（门①按 ≥3 组、门③④、门⑤ `accept_m1.ps1` **×2** 且 PASS 清单一致、门⑥）；
**9877 全程属用户（PID 36392）**、测试只用 9888/9889（本任务可能产生其它空闲端口，收尾必须释放）、
**无孤儿进程**（含 `editor_play_scene` 拉起的游戏子进程）、**不得** git 写操作、**不得**修改被跟踪文件。

## 2. 硬性约束

不得修改任何文件（临时实验须**还原并留证**）；临时文件放 `%TEMP%\audit-m4d\`；不得安装依赖；
证据用 `curl.exe -s -o <file>` + sha256、请求体用 `ConvertTo-Json`（**禁止** `Out-File`/管道承载响应体、
**禁止**字符串拼接 JSON）；**不要抑制 scons 输出**；**不要并发跑两个 scons**；
`.ps1` 脚本**一律纯 ASCII**（本机 PowerShell 5.1 会按 ANSI 读无 BOM 脚本，中文常量会被破坏）。

## 3. 报告

`verdict`（分类：全量对等 / 静默错值五形态 / 门⑥ / 顺手性八项 / 延迟与事务与安全 / 工程门 / 端口纪律）、
逐项结论与**你自己跑出的证据**、`defects`（severity/claim/evidence/location/recommendation）、
`unconfirmed`、`risks`、`next_step_recommendation`。
**返回值：≤15 行 + 报告路径 + verdict。**