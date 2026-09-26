# REPORT-AUDIT-075 — TASK-076 §B：第 5 轮修复的**独立验收**

> **验收者身份**：全新会话的独立验收子代理，**未参与任何实现**，**未采信任何 `REPORT-*` 或决策者摘要**。
> 本文每一条结论都附**我自己跑出的**证据；凡引用实现方产物，只作为"被检验对象"，不作为论据。
> **D86 锚点**：本报告的结论绑定在
> `anchor = b13f3197b`（`ANCHOR_EQUAL`，`HEAD = b13f3197b5`，`diff_count=0`）
> 与二进制 `4.8.dev.custom_build.b13f3197b`（由我在验收开始时用 `scripts/build_local.cmd -Force` 从 cmd 重建，
> `exit=0`，`--version` 自报 hash 前缀 == `git rev-parse --short HEAD`）。
> **工作目录**：`F:\RustProjects\godot-mcp-pro\code\godot`（分支 `feature/mcp-server-module`）。

---

## 0. 判定摘要（分类：围栏 / 诚实性 / D2 / D9 撤回 / 分析器 / A 改动 / 工程门）

| 类别 | 判定 | 一句话理由 |
|---|---|---|
| **围栏**（`project_read_text_file` 的 `res://` 约束） | **FAIL** | 句法型越界（`..`/绝对路径/`user://`/UNC/百分号/大小写/目录/非 UTF-8/`max_bytes` 边界）**全部拦住**；但**符号链接与 junction 能读到物理上位于 `res://` 之外的文件**（最小复现 + sha256 见 §1，两个端点都一样） |
| **诚实性**（`parsed:false`） | **PASS** | 12 条带载荷的返回路径（成功 10 / 裁剪 1 / 边界内 1）**每条**都带 `"parsed":false` 与 `note`；错误路径不带载荷、也不带 `parsed`，**没有任何分支泄露"我懂它"** |
| **D2 拒绝语义** | **FAIL（不完整）** | 根类型不兼容：拒绝 + `readable:false` + 盘上零写入 + 合法绑定 `attached:true,readable:true` + **不是类型名硬编码**（用引擎自己的 `get_instance_base_type()`/`is_class()`）——**这四点是真修好了**；但**编译不过的脚本仍被报成 `attached:true, readable:true`**，而引擎在载入场景时**丢弃**它（§3）——正是 D2 要关掉的那一类 |
| **D9 撤回** | **PASS（撤回成立）** | 我从**权威逐调用记录**独立复算：**9889 = 2**（不是 14），9888 = 28，合计 30。三条互不相关的记录一致；「14」= **两个端口 `-32001` 的总数**（12 编辑器 + 2 游戏）。与 TASK-075 的撤回**完全一致**，无分歧 |
| **分析器** | **PASS（机制）/ 带缺陷（边界）** | `--self-test` 在我自造的两处变异下**都变红**；同一份冻结追踪上**修复前后差异类别真的出现**（前：`probed args none`；后：6 条）。**但 6 条里 4 条是契约 `inputSchema` 里确有拼写正确的参数**，属误报（§5，缺陷 D-B3） |
| **A 改动** | **PASS** | 两处**只改了描述**（结构化证明：契约 177 条里恰好 3 条变，且**只有 `description` 键**；C++ 与 doctest 的 diff 只有描述字面量）；派生**未放松断言**（我自写的反向探针：新表达式真、旧字面量假、变异后假） |
| **工程门** | **PASS** | 重建 `exit=0`、`--version == HEAD`、`ANCHOR_EQUAL`；六道静态门 + 门③ + 门④ 全绿（§7） |

**总判定：`fail`** —— 阻塞缺陷 1 条（围栏，按任务书 §B.1 明文判据），D2 类缺陷 1 条，分析器边界缺陷 1 条（非阻塞）。

---

## 1. 围栏：`project_read_text_file` 的 `res://` 约束（对抗测试）

### 1.1 我的做法（不复用实现方脚本）

自建 scratch 工程 `C:\Users\wyl\AppData\Local\Temp\task076_auditB\proj`（手写 `project.godot` / `scenes\main.tscn` /
6 个 `.gd`），**并在工程目录里放入三种指向工程外部的链接对象**：

| 链接对象 | 建法 | 指向 |
|---|---|---|
| `proj\link`（junction） | `mklink /J link ..\outside` | `...\task076_auditB\outside`（`proj` 的**兄弟目录**） |
| `proj\dlink`（目录符号链接） | `mklink /D dlink ..\outside` | 同上 |
| `proj\sym_secret.txt`（文件符号链接） | `mklink sym_secret.txt ..\outside\secret.txt` | 工程外文件 |
| `proj\hard_secret.txt`（硬链接） | `mklink /H hard_secret.txt ..\outside\secret.txt` | 同卷同一 MFT 记录（**不算越界**，仅作对照） |

工程外文件内容为 `OUTSIDE_SECRET_TASK076_AUDITB_9f3c1d`，
`sha256 = a41903ea7079f0d807a676757fe199951a0310acd98c794a838e1f2696aaf4f1`（39 B）。

请求全部由 `curl.exe -s -o <file> --data-binary @<file>` 发出（不经 PowerShell 管道），
响应体落盘后我再解析；探针集合 40 条（`F01..F40`）+ 12 条 `max_bytes`/目录/缺文件/非 UTF-8，
编辑器 9888 与游戏 9889 **两个端点都打**。

### 1.2 结果：句法型越界全部拦住

| 探针 | 输入 | 结果 |
|---|---|---|
| `..` | `res://../secret.txt` | `-32602` must not walk upwards with `..` |
| `..` 反斜杠 | `res://..\secret.txt` | `-32602` 同上 |
| 嵌套 `..` | `res://a/../../secret.txt` | `-32602` 同上 |
| `....//` | `res://....//secret.txt` | `-32602` 同上 |
| `res:/..` | `res:/../secret.txt` | `-32602` must address the project |
| `res:/..\` | `res:/..\secret.txt` | `-32602` must address the project |
| `./../` | `res://./../secret.txt` | `-32602` 同上（`..` 先于折叠被拒） |
| 混合分隔符 | `res://a/..\..\secret.txt` | `-32602` |
| 百分号 `%2e%2e` | `res://%2e%2e/secret.txt` | `-32001`（**未解码**，落到不存在的字面名） |
| `%2e%2e%2f` / `..%2f` / `%5c..%5c` / `%2e/../` | 四种 | `-32001` 或 `-32602`，**均未越界** |
| 大小写 | `RES://...`、`Res://...` | `-32602` must address the project（大小写**敏感**：是**假否定**，不构成越界） |
| `user://` | `user://secret.txt`、`user://../secret.txt` | `-32602` |
| 绝对路径 | `C:/Windows/win.ini`、`C:\Windows\win.ini` | `-32602` |
| UNC | `\\?\C:\Windows\win.ini`、`\\localhost\C$\Windows\win.ini` | `-32602` |
| 盘符相对/绝对 | `F:secret.txt`、`F:\Windows\win.ini` | `-32602` |
| 伪装在 res 内 | `res://\\?\C:\Windows\win.ini`、`res://localhost/C$/...`、`res://CON` | `-32001`（未越界） |
| NUL | `res://\0/../secret.txt` | `-32602` |
| 目录 | `res://scenes` / `res://scenes/` / `res://link` | `-32602` names the directory / must name a file |
| 缺文件 | `res://nope.txt` | `-32001` + `data.suggestion` |
| 非 UTF-8 | `res://bin.dat`（`FF FE 41 00 42`） | `-32000` + `data.suggestion` |
| `max_bytes` | `0` / `-1` / `1.5` / `"abc"` / `"16"` | `-32602`（正整数 / integer 类型） |
| `max_bytes` 超上限 | `16777217` | `-32602` must not exceed 16777216 |
| `max_bytes` 边界 | `16777216` | 成功（上限**允许**） |
| `max_bytes` 裁剪 | `1` | `parsed:false` + `text_omitted:true` + `size`/`sha256` 仍描述**整文件** |

→ **这一半是真的做到了**，而且 `..` 的判据在**折叠之前**（`normalize_project_path`，`tools/tool_builder.cpp:309-315`），
所以不存在"折叠把被拒路径变成可接受路径"的经典漏洞。

### 1.3 ★ 阻塞缺陷 D-B1：符号链接 / junction 读到 `res://` 之外

**最小复现（编辑器 9888；游戏 9889 逐字同结果）**

```
mklink /J  C:\...\task076_auditB\proj\link            C:\...\task076_auditB\outside
tools/call project_read_text_file { "path": "res://link/secret.txt" }
```

**响应（逐字节落盘）**

```json
{"note":"The bytes are answered as they are: ...","parsed":false,
 "path":"res://link/secret.txt","sha256":"a41903ea7079f0d807a676757fe199951a0310acd98c794a838e1f2696aaf4f1",
 "size":39,"text":"OUTSIDE_SECRET_TASK076_AUDITB_9f3c1d \r\n","text_omitted":false}
```

**证据 sha256**

| 探针 | 输入 | 响应体 sha256 | 结论 |
|---|---|---|---|
| `F22_junction_dir` | `res://link/secret.txt` | `8a60ea9d4cf0f2e80ebbe8dbe9f47b3d30afd1a67f3a45c02f6dde327fecf123` | **读出工程外内容** |
| `F24_file_symlink` | `res://sym_secret.txt` | `d10fc839b3d2de20b1856dad340838f00b525cb8247fdb300266088aaf948c41` | **读出工程外内容** |
| `F25_dir_symlink` | `res://dlink/secret.txt` | `53fede204a693f923498af0c6fdcca9c97bcfd2b015cdec2cfb85f6ed3fad4d0` | **读出工程外内容** |
| `G04_junction`（**游戏端点 9889**） | `res://link/secret.txt` | `8a60ea9d4cf0f2e80ebbe8dbe9f47b30...`（**与 F22 逐字节相同**） | 两个端点同缺陷 |
| `F26_hardlink` | `res://hard_secret.txt` | `cac76b55feb85438...` | 同卷硬链接（**不算越界**，仅对照） |

决定性比对：响应里的 `sha256` 与**操作系统**对 `...\outside\secret.txt` 算出的
`a41903ea7079f0d807a676757fe199951a0310acd98c794a838e1f2696aaf4f1` **逐字相等**。

**范围（我另外做的界定探针 `b_live3.ps1`）**：这不是新工具独有的洞——
`project_get_filesystem_tree{path:"res://link"}` 把工程外文件列成 `res://link/secret.txt`；
`project_read_script{path:"res://sym_secret.txt"}` 也把同一份工程外内容原样回传。
即**本模块的 `res://` 围栏从不解析链接对象**，新读工具继承了它。

**判据**：任务书 §B.1 原文——「**任何一条能读到 `res://` 之外的内容 → 阻塞缺陷**（给最小复现 + sha256）」。
按此判据成立，记为**阻塞缺陷**。严重度的一体两面：
①要构造它，需要在工程目录里存在一个链接对象，而**工具面本身造不出链接**（`project_write_text_file` 只能写文件）；
②但 `editor_execute_gdscript` 已经能在编辑器里执行任意 GDScript，所以对"已有代码执行能力"的调用方这不是新增能力。
**这两点不改变判据的字面成立**，但应影响修复的优先级与修法（解析后比较工程根 vs. 直接在描述里如实声明）。

---

## 2. `parsed:false` 的诚实性

我对**每一条带载荷的返回路径**逐个解析响应体：

| 路径 | 响应体 sha256（节选） | `parsed` | `note` |
|---|---|---|---|
| 成功（19 B 文本文件） | `f7ad024990e4…` | `false` | 有 |
| 成功（`.tscn` 373 B） | `74a15863efa0…` | `false` | 有 |
| 成功（`.tscn` 1610 B） | `40d87adef05b…` | `false` | 有 |
| **裁剪**（`max_bytes=1`） | `c0111f6c9cf3…` | **`false`** | 有（含 `reason`/`text_omitted:true`） |
| 边界内（`max_bytes=16777216`） | `f7ad024990e4…` | `false` | 有 |
| 链接对象 3 条 + 硬链接 1 条 | 见 §1.3 | `false` | 有 |
| 游戏端点 2 条 | `f7ad024990e4…` / `8a60ea9d4cf0…` | `false` | 有 |

**没有**任何分支给出"这是 JSON / 这是场景 / 这是合法配置"之类的判断；
唯一一处与内容有关的陈述是非 UTF-8 拒绝里的 "its bytes are not valid UTF-8 text"，
那是**编码**判断（工具承诺返回文本），不是**格式**解释，我判定可接受。

错误路径（`-32602` / `-32001` / `-32000`）**不带 `parsed` 字段**——因为它们**不带载荷**，无内容可被误读。
我据实记录这一事实：若未来要求"每条 **error** 也带 `parsed:false`"，则当前实现不满足；按"不泄露我懂它"的实质标准，**满足**。

**判定：PASS。**

---

## 3. D2：拒绝语义与 `readable`

### 3.1 四点要求逐条核对（全部用响应体 + 磁盘 sha）

| 要求 | 探针 | 结果 | 证据 |
|---|---|---|---|
| ①不兼容绑定**必须拒绝**且**盘上什么都没写** | `D201` 单数 `{Body(CharacterBody2D), incompat.gd extends Area2D}`；`D220` 批量 `{["Body","Sprite"], incompat.gd}` | `-32000` + `data.suggestion` + `data.batch.errors[0].readable=false`；`attached: []` | `D201.response.json` sha `88cfecc9672d…`；`D220.response.json` sha `6979cff9d47272ff0460e7746af4da7c83bc5b05ce41a61bc1286042d785e840` |
| ①（盘上零写入） | 拒绝前后 `Get-FileHash scenes\main.tscn` | `b063c98251f5…` → `b063c98251f5…`（单数）；`59e7a478ce13…` → `59e7a478ce13…`（批量） | **逐字节相同** |
| ②合法绑定**必须成功且 `readable:true`** | `D221` `{["Sprite"], broad.gd}`；`D222` `{["Sub","Sprite"], broad.gd}`；`D224`；`D227` | 全部 `"attached":true,"readable":true` | `D221.response.json` sha `45df5bc4af7052202f1a193119bdf03ec1b2d28515d8e41fe52bf322561806ca` |
| ④批量与单数语义**一致** | 同一配对分别走单数 / 批量 | `Body+broad.gd`：两者都成功；`Sprite+narrow.gd`：两者都 `-32000`（批量响应 sha `d61cb5da0c37…` 两次相同） | `D223` / `D231` |
| 附带：全批回滚 | `D231` `{["Sprite","Body"], narrow.gd}` → 拒绝后保存并读回 `.tscn` | `D233_read_tscn` 中 **不存在** `narrow.gd` | 磁盘侧证明"整批什么都没留下" |

### 3.2 ★ 防假修复（③）：不是类型名硬编码

我**自己构造**了四组"看起来兼容 / 看起来不兼容"的用例，专门打"是不是靠类型名字符串硬编码"：

| 探针 | 组合 | 期望（引擎语义） | 实测 |
|---|---|---|---|
| `D205` | 节点 `CharacterBody2D` + `broad.gd extends Node2D` | `Node2D` 是 `CharacterBody2D` 的**基类** → 兼容 | **成功** `attached:true` |
| `D207` | 节点 `Node2D` + `narrow.gd extends CharacterBody2D` | `CharacterBody2D` 不是 `Node2D` 的类 → 拒绝 | **`-32000`** |
| `D208` | 节点 `CharacterBody2D` + `chain.gd extends "res://scripts/broad.gd"`（**脚本继承脚本**，原生基类 `Node2D`） | 原生基类 `Node2D` 是类 → 兼容 | **成功** `attached:true` |
| `D209`/`D210` | `refcounted.gd extends RefCounted` → `Node2D` / `CharacterBody2D` | 不是 Node → 拒绝 | **`-32000`** |
| `D211` | 节点 `Area2D` + `incompat.gd extends Area2D` | 精确匹配 → 兼容 | **成功** |

**结论：判据来自引擎自身**（`script_readable_on()`：`p_script->get_instance_base_type()` + `p_node->is_class(base)`，
`tools/editor_set_node_script_batch.cpp:180-192`），对**基类方向**、**脚本继承链**、**非 Node 基类**都给出正确结论，
**不是**类型名白名单硬编码。③通过。

### 3.3 ★ 缺陷 D-B2：编译不过的脚本被报成 `attached:true, readable:true`，而引擎会丢弃它

我自造的 `scripts\broken.gd`：

```gdscript
extends Node2D
func broken(:
```

| 探针 | 请求 | 响应 |
|---|---|---|
| `D212`（单数） | `{node_path:"Sprite", script_path:"res://scripts/broken.gd"}` | `{"attached":true,"node_path":"Sprite","previous_script_path":"res://scripts/broad.gd","script_path":"res://scripts/broken.gd"}`（sha `17d8df0ff2a8…`） |
| `D226` / `H14`（批量） | `{node_paths:["Sprite"] / ["Sub"], broken.gd}` | `{"attached":[{"attached":true,"readable":true,...}],"count":1,"errors":[],"status":"ok"}`（`H14.response.json` sha `609c6d820321012eb4bd3058cdb2aa694c9a55f71d2580ef1177d98281fd7364`） |
| `H15` | 保存场景 | `{"saved":true}` —— **`broken.gd` 被真的写进 `main.tscn`** |
| `H01`（**游戏进程载入同一场景**） | `running_game_get_scene_tree` | `/root/Main/Sprite` **没有任何 `script` 字段**（形如 `{"name":"Sprite","path":"/root/Main/Sprite","type":"Node2D"}`）；同一响应里 `Body→broad.gd`、`Area→incompat.gd` 都在 → **引擎只丢弃了 `broken.gd`** |
| 游戏进程 stderr | —— | `SCRIPT ERROR: Parse Error: Expected parameter name.` / `at: GDScript::reload (res://scripts/broken.gd:2)` / `ERROR: Failed to load script "res://scripts/broken.gd" with error "Parse error".` |
| `H10`（**编辑器自己的权威判定**） | `project_validate_script{res://scripts/broken.gd}` | `{"valid":false,"error_text":"ERR_PARSE_ERROR","message":"Compilation failed..."}`（sha `c2f52f47c38aabc74b87b7a5432dc149a575b8994b99baf8bf350889370d380a`）；同一进程里 `broad.gd`/`chain.gd` = `valid:true` |

**为什么这是缺陷而不是"另一类"**：D2 的立项目的写在实现自己的注释里——
「the answer must not report `attached: true` for an attachment the engine will drop when the scene is loaded」
（`editor_set_node_script_batch.cpp:332-338`）。`broken.gd` **正是**被引擎在载入时丢弃的附件，
而工具报了 `attached:true` 且 `readable:true`。`readable` 声称"测过"，但它只测了
"原生基类型是不是节点的类"，**没测脚本能不能编译**——于是同一类谎报换了个入口复活。
（`apply_node_script()` 里 `ResourceLoader::load()` 对语法错误的 `.gd` **不返回 null**，所以装载检查也没拦住。）

**严重度**：D2 类（S1/S2 之间）。它不会写坏磁盘（`.tscn` 写的是对的），但会把"挂上了"这一**结论**错报给调用方，
且调用方无法从响应里看出差别；对照工具 `project_validate_script` 在本进程里就能给出 `valid:false`。

**建议修法（不在本次验收范围内，供决策者下发）**：`script_readable_on()` 之外，
在写入前的预检里对 GDScript 加一次 `Script::is_valid()`/`can_instantiate()` 或
`GDScript::get_instance_base_type()` 为空时的显式拒绝；并且**拒绝时的错误码/建议**要与
现有的 `-32000 + data.suggestion` 形状保持一致（指向 `project_validate_script`）。

---

## 4. D9 与那次「撤回」：到底是 2 还是 14？

**我不采信任何报告，直接从冻结的权威记录复算。**

### 4.1 三条互不相关的记录，结论一致

| 记录 | 复算方式 | 9888（编辑器） | 9889（游戏） | 合计 |
|---|---|---|---|---|
| `docs/reports/evidence/task074/CALLS.jsonl`（**权威逐调用记录**，232 行，sha `56d95094d8184072a031f1f0fb39c380f7b6c44c4a785bab473c0d75f9c3c13c`） | 我自己写 `b_d9.py`：`result` 字段首词 == `error` 才算非 ok | **28**（`-32602`×9、`-32001`×12、`-32000`×4、`-32601`×3） | **2**（全 `-32001` / `running_game_get_node_properties`） | **30** |
| `docs/reports/evidence/task074/raw/**`（232 个目录，每个一份 `response.json`） | 我按 `CALLS.jsonl` 的 `response_file` **1:1 关联**（`b_d9_link.py`）：232 行全部关联成功、**0 mismatch** | **28** | **2** | **30** |
| `docs/reports/evidence/task074/traces/*.jsonl` | 我逐行解析 `method == tools/call && !ok` | **28** | **2**（`trace-game3` seq2、`trace-game4` seq1；`game`/`game2` 各 0） | **30** |

**★ 决定性一点：`PLATFORMER-FINDINGS` 用来支持「游戏侧 14」的那份自己的证据文件
`docs/reports/evidence/task074/aggregate/c_calls2.stdout.txt`（sha `decae247efa4d68044717e20f59781afb7986cce8a274cb87a317160041a4870`）第 6 行逐字写着：**

```
port 9889 calls 34 ok 32 non-ok 2
```

**即「14」在它自己引用的产物里就查无实据。**

### 4.2 「14」是从哪来的（我复核的算术）

`CALLS.jsonl` 全表的 `-32001` 计数 = **14**（编辑 12 + 游戏 2）。
第 5 轮汇总（`PLATFORMER-FINDINGS.md:42` 自报 `-32001 = 14`，:44 自报编辑器 28）把**两个端口**的 `-32001` 总数
当成了**游戏侧**的非 ok 数——与它自己同一张表的「非 ok 30」自相矛盾（28 + 14 ≠ 30）。

### 4.3 与 TASK-075 撤回结论的比对

TASK-075 的撤回（`9889 = 2`，编辑 28 / 游戏 2 / 合计 30，`raw/**` = 30 MATCH）与我的独立复算**逐字一致**。
**无分歧，无需报告新的反例**；反而要指出：**第 5 轮汇总的 D9 是错的，TASK-075 的撤回是对的。**

**判定：PASS。「14」不成立，正确口径是 9888=28 / 9889=2 / 合计 30。**

---

## 5. 分析器（`scripts/analyze_mcp_trace.py`）

### 5.1 `--self-test` 在**我自造的变异**下真的变红

| 变异 | 我做的改动 | `--self-test` 结果 |
|---|---|---|
| 基线 | 原样 | `exit 0`；`SELF-TEST PASS (... atlas_x, atlas_y, bogus, path, property; counted 2 unreadable and 0 truncated argument list(s))` |
| **变异 1**：恢复 D11 缺陷 | 把 `call_args()` 改回 `isinstance(args, dict)` 那一支（其余保留） | **`exit 1`**，3 条 FAIL：`atlas_x`/`atlas_y` 未报 + `unreadable` 期望 2 得 5 |
| **变异 2**：去掉"从未被接受"的对照 | 把 `if count < probe_min or succeeded_keys.get(key, 0) > 0:` 改成 `if count < probe_min:` | **`exit 1`**，FAIL：`'node_path' is accepted by a successful call and must never be reported as probed` |

→ 自测不是空跑：两个方向的退化都会红。**PASS。**

### 5.2 同一份冻结追踪上，"修复前后"的差异类别真的出现

同一份 `docs/reports/evidence/task074/traces/trace-editor.jsonl`（sha `4c9ec2ac81cb2091…`），
`BEFORE` = `git show bf9518c2b3:modules/mcp_server/scripts/analyze_mcp_trace.py`，`AFTER` = 当前树：

| | `probed args` |
|---|---|
| BEFORE | `none`（且 `probed_argument_names: []`） |
| AFTER | `source_id (x4)`、`atlas_x (x2)`、`atlas_y (x2)`、`resource_properties (x2)`、`resource_type (x2)`、`atlas_coords (x2)` |

→ 漏报类别**真的出现**。**PASS。**

### 5.3 ★ 缺陷 D-B3（边界）：会把"拼写正确、但因别的原因失败"的参数名误报为"缺参数"

**据实判定：会，而且在这份冻结追踪上 6 条里有 4 条是误报。**

分析器的判据（`missing_tools()`）：某个参数名在**失败的**调用里出现 ≥ `probe_min` 次，
且在**任何工具的成功调用**里**从未出现** → 报为 `probed argument name`。
它的自述语义（模块 docstring「argument names that were probed repeatedly and never accepted」，
以及源码注释「the schema the caller expected is not the schema the tool has」）指向"工具没有这个参数"。

我把 AFTER 报出的每个名字回到**契约的 `inputSchema`** 里核对，并调出携带该名字的真实失败调用：

| 名字 | 失败次数 | 在契约 `inputSchema` 里？ | 真实失败原因 |
|---|---|---|---|
| `atlas_x` / `atlas_y` | 2 / 2 | **否** | `-32602` Unknown parameters atlas_y, atlas_x（**真阳性**） |
| `resource_properties` | 2 | **是**（`editor_add_resource_to_node_property` 的声明参数） | seq66 `-32602` Unknown resource **type**: Vector2；seq90 `-32602` Parameter **'resource_properties' cannot be written to a Vector2i property**（**误报**） |
| `resource_type` | 2 | **是**（同上） | seq66 失败原因是**取值的枚举**不认识 `Vector2`，不是名字不存在（**误报**） |
| `source_id` | 4 | **是**（`editor_set_tilemap_cell` / `_cells_in_rect` 的**必填**参数） | seq53/54 失败于 `atlas_x/atlas_y`；seq91/99 失败于 `-32000` 无 TileSet（**误报**） |
| `atlas_coords` | 2 | **是**（同上） | seq91/99 同上的 TileSet 缺口（**误报**） |

**判据**：修复**确实让信号出现**（5.2），但该信号**没有与"名字是否在该工具的 schema 里"挂钩**，
因此"拼写正确、因别的原因失败"的调用会被读成"缺参数"。据任务书 §B.5③ 要求**据实判定**：**会误报**。
严重度：中（诊断工具，会把人引向错误的排查方向；不会造成数据损失）。

---

## 6. 对 A 的复核（两处改动是否真的只是描述 / 派生）

### 6.1 结构化证明："只改了描述"

`git show e8c2ed5993` 是本轮 A 的全部源码改动。我不看 diff 的样子，而是**把前后两份契约解析成 JSON 后逐条比对**（`b_contract_diff.py`）：

```
sha256 before: 6f654b64f87f60a5b0296e5a7a6b50f3b1a0af98c9ce8770ffe9f964172afbd6
sha256 after : a5c59853c1e5a4913d600c663c8e972f058f7144869ec20337ab41b7a7bb17ea
names before/after: 177 177 same set: True
  CHANGED editor_get_scene_tree ['description']
  CHANGED editor_set_tilemap_cell ['description']
  CHANGED editor_set_tilemap_cells_in_rect ['description']
entries changed: 3
changes that are NOT description-only: []
```

→ **177 条一个没增删，恰好 3 条变更，且变更的键只有 `description`**；`_meta.count = 177`、`added_count = 6`、`map_sha256` 未动。

C++ 侧（`git show e8c2ed5993 -- tools/... tests/test_mcp_server.h`）：`editor_read_scene_inspector.cpp` 与
`editor_tilemap_write.cpp` 的 diff **各只有 `ToolBuilder builder("名", String::utf8(R"desc(...)desc"))` 那一行**，
`builder.schema(...)` 行是未改动的上下文；`tests/test_mcp_server.h` 只有 3 行 `expect_description(...)` 的字面量；
`tool-groups-added.json` 只有 `generator_version` 1.21.0 → 1.22.0 与其说明文字。

`scripts/gen_renamed_contract.py` 的净代码改动 = 版本字符串 + 3 条 append-only `DESCRIPTION_OVERRIDES` 记录
+ 两个共享句子常量（我逐段核对了运行时求值行为，新增部分只构造描述字符串）。

**判定：两处确实只改了描述。PASS。**

### 6.2 派生是否**未放松断言**（我自写的反向探针）

`git show` 显示 `scripts/mcp071_gate2_live_evidence.ps1` 只动了三处：G208 的表达式、G208 的标签去掉 `_176_`、
以及最后的 PASS 文案改用 `-f $contractNames.Count`。**行为断言本身有没有被削弱**由我自己复算（`b_a_reverse.ps1`）：

```
contract file: 177 names
202: Check 'G208_live_union_equals_the_contract_entries' `
203:     (($union.Count -eq $contractNames.Count) -and ($missingFromLive.Count -eq 0) -and ($extraInLive.Count -eq 0)) `

[real union]      new expression  $union.Count -eq $contractNames.Count : True  (expect True)
[real union]      old literal     $union.Count -eq 176                 : False (expect False - it is stale)
[mutated union]   new expression                                       : False (expect False - not a tautology)
[mutated union 2] full G208 condition                                  : False (missing=1 extra=0)

missingFromLive.Count -eq 0                          present=True
extraInLive.Count -eq 0                              present=True
Where-Object { -not $union.ContainsKey($_) }         present=True
Where-Object { -not $contractNames.ContainsKey($_) } present=True
```

→ 派生表达式**非空转**（变异后为假），**两个集合逐名比较一个都没删**，旧的 176 字面量确实已经为假（陈旧）。
文件里残留的 `176` 只出现在第 6 行与第 193 行的**注释**里（我逐行 grep 过），不在可执行断言中。

`python modules\mcp_server\scripts\check_hardcoded_counts.py` → `exit 0`，
`BUCKET UNCLASSIFIED = 0`（157 条 occurrences 全部归类）。

**判定：未放松，PASS。**

---

## 7. 工程门（我自己跑的）

| 门 | 命令 | 结果 |
|---|---|---|
| 第 0 步：重建 | `cmd /c modules\mcp_server\scripts\build_local.cmd -Force`（**从 cmd 启动**，tests=yes，不抑制输出） | **`exit 0`**；`--version` = `4.8.dev.custom_build.b13f3197b` == `git rev-parse --short HEAD` = `b13f3197b` |
| 锚点（D86） | `check_engine_anchor.ps1 -VersionText 4.8.dev.custom_build.b13f3197b` | **`VERDICT=ANCHOR_EQUAL` `RESULT PASS`**（`anchor=b13f3197b head=b13f3197b diff_count=0`） |
| 门⑥ 收窄点 | `check_narrowing_points.py` | `exit 0`；`scanned 75 / pinned 75`（18 条行号漂移按设计不算失败） |
| 门⑥ coverage | `check_narrowing_points.py --coverage` | `exit 0`（17 种已声明拼写，边界如实声明） |
| 退出码传播 | `check_exit_propagation.py` | `exit 0`（`EXIT-CODE PROPAGATION CHECK PASS`） |
| 同义反复 | `check_tautologies.py` | `exit 0`（`TAUTOLOGY CHECK PASS`） |
| 硬编码计数 | `check_hardcoded_counts.py` | `exit 0`，`UNCLASSIFIED = 0` |
| 门③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **`exit 0`；`test cases: 348 \| 348 passed \| 0 failed \| 1429 skipped`；`assertions: 24223 \| 24223 passed \| 0 failed`** |
| 门④ 全引擎回归 | `--headless --test` | **`exit 0`；`test cases: 1774 \| 1774 passed \| 0 failed \| 3 skipped`；`assertions: 448470 \| 448470 passed \| 0 failed`** |
| 线上工具数 | `tools/list`（我实测） | 编辑器 **154**、游戏 **73**，两端**都**含 `project_read_text_file`（与任务书给的口径一致） |

门③/④ 输出里大量的 `ERROR:` / `SCRIPT ERROR: Parse Error:` 是模块**自己的负路径 fixture** 打印的
（`mcp_server_test_fixture*` 下的故意坏文件），与 `failed` 计数无关——这一次 `0 failed`。

---

## 8. 收尾纪律

| 项 | 结果 |
|---|---|
| **未改仓库文件** | 全部实验在 `%TEMP%\task076_auditB\` 内进行（scratch 工程、链接对象、变异副本、响应体）；**我没有编辑任何一个既有仓库文件**。新产物只有本报告与本轮的 `docs/reports/evidence/task076/auditB/**`（证据，见下），与既有报告/证据目录的惯例一致，已提交（**未 push**） |
| `git status --short` | 仅剩既有未跟踪物：`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd` |
| **9877 未碰** | 开工前 listener 集合 `[]`、收工后 `[]`（`unchanged=True`）；**我从未向 9877 发过一个字节** |
| 9888 / 9889 已释放 | 收工 `netstat`：两个端口**无 LISTENING**（只剩客户端 `TIME_WAIT`） |
| 构建严格串行 | 全程只有一次 `build_local.cmd`；后段无任何 scons |
| `.ps1` 纯 ASCII | 我写的三个 `.ps1` 全部 `non-ascii: 0`（`b_ascii.py` 校验）；`b_live2.ps1` 末行写日志时因我自己的 `$out`/`$Out` 变量遮蔽（PowerShell 大小写不敏感）抛了 `DirectoryNotFoundException`，**探针结果不受影响**，控制台原文已存档为 `logs\b_live2_console.txt` |

---

## 9. 缺陷与未确认

### 9.1 缺陷

| ID | 类别 | 严重度 | 一句话 | 最小复现 / 证据 |
|---|---|---|---|---|
| **D-B1** | 围栏 | **阻塞** | 符号链接 / junction 能读到 `res://` 之外：`mklink /J proj\link <外部目录>` → `project_read_text_file{"path":"res://link/secret.txt"}` 返回工程外文件全部字节，`sha256` 与 OS 对工程外文件的哈希逐字相等；编辑器与游戏两个端点行为相同；该洞是模块级的（`project_read_script`、`project_get_filesystem_tree` 同样穿透） | `F22` sha `8a60ea9d4cf0f2e80ebbe8dbe9f47b3d30afd1a67f3a45c02f6dde327fecf123`；`F24` `d10fc839b3d2de20…`；`F25` `53fede204a693f923…`；`G04` = `F22` 逐字节同；工程外文件 `a41903ea7079f0d807a676757fe199951a0310acd98c794a838e1f2696aaf4f1` |
| **D-B2** | D2 | 高 | 编译不过的脚本被报成 `attached:true, readable:true`，被写进 `.tscn`，而引擎载入场景时**丢弃**它：`broken.gd`（`func broken(:`）→ 批量响应 `readable:true`（sha `609c6d820321012eb4bd3058cdb2aa694c9a55f71d2580ef1177d98281fd7364`）；同一场景在游戏进程里 `Sprite` **没有 `script` 字段**（`H01` sha `791cb88c1b13899781b1cb467e5f02fbe234ffff1ef87a3c4191bc139aa13e2b`），stderr 有 `GDScript::reload (res://scripts/broken.gd:2)` Parse Error；编辑器自己的 `project_validate_script` 同进程答 `valid:false / ERR_PARSE_ERROR`（sha `c2f52f47c38aabc74b87b7a5432dc149a575b8994b99baf8bf350889370d380a`） | 见左 |
| **D-B3** | 分析器 | 中 | `probed_argument_names` 不与"该名字是否在该工具的 `inputSchema` 里"挂钩：冻结追踪上 6 条里 4 条（`source_id`、`resource_properties`、`resource_type`、`atlas_coords`）是**契约里确有、拼写正确**的参数，只是失败于别的原因（无 TileSet / 取值枚举不认识 / 类型不可写），却被读成"缺参数" | `b_probed_fp.txt`；契约 `editor_add_resource_to_node_property` properties = `[node_path, property, resource_properties, resource_type]`；`editor_set_tilemap_cell` properties = `[atlas_coords, node_path, source_id, x, y]` |

### 9.2 未确认 / 需决策者裁定

1. **D-B1 的适用范围是否算"越界"**：链接对象必须在工程目录内**预先存在**，而工具面本身造不出链接；
   同时 `editor_execute_gdscript` 已能执行任意 GDScript（因此对能执行代码的调用方，这不是新增能力）。
   我的判定按任务书 §B.1 的**明文字面判据**（能读到 `res://` 之外 → 阻塞）。**是否需要把"链接穿透"降级为已声明边界**，
   请决策者裁定；若要修，修法有两条互斥路线（解析后比较工程根 vs. 在描述里如实声明），这属于设计决策。
2. **D-B2 是否属本轮范围**：根类型不兼容（TASK-075 的 D2 原文）**确实已修好**；
   编译失败属同一后果（引擎丢弃）但不同成因。TASK-075 的任务书没有点明它，
   但它正好落在实现自己写下的承诺里（`attached:true` 不得用于引擎会丢弃的附件），我按此判为缺陷。
3. **门③/④ 的 passed 基线**：我只核对了 `0 failed` 与 `exit 0`，**没有**与上一轮报告的 passed 数逐一对比
   （那需要采信实现方的历史数字）。若回归口径要求"passed 只允许增加"，请给出可信基线。
4. **9877 的"未碰"**：整场验收期间 9877 上**没有任何 listener**；我未发送任何请求。
   因此"未占用/未杀/未重启"由"端口空集前后一致 + 我未发请求"证明，而不是由 PID 比对证明。
5. **修复后必须重跑**：D-B1 / D-B2 任一被修复后，本报告的全部结论**作废**，需要新的锚点与新的独立验收会话。

---

## 10. 证据索引（**绝对路径**）

根目录：`F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task076\auditB\`

| 文件 | 内容 |
|---|---|
| `MANIFEST-sha256.txt` | 本目录全部文件 + 关键外部输入的 sha256；**逐字复算入口**（哈希取自**工作副本的当前字节**；仓库开了 `core.autocrlf`，`.txt` 类证据在将来检出时行尾可能被归一为 LF，届时 sha 会变——要精确复验请用 `git show ef3b545591:<path>` 或现场重跑 `scripts\` 下的脚本） |
| `scripts\b_d9.py` / `b_d9.txt` | D9 独立复算（`CALLS.jsonl` 按端口） |
| `scripts\b_d9_cross.py` / `b_d9_cross.txt` | 三条记录交叉核对（`CALLS.jsonl` / `raw/**` / traces） |
| `scripts\b_d9_link.py` / `b_d9_link.txt` | `CALLS.jsonl` ↔ `raw/**` 的 1:1 关联（232/232，0 mismatch） |
| `scripts\b_analyzer.py` / `b_analyzer.txt` | 分析器：自测基线、两处变异、冻结追踪 before/after |
| `scripts\b_probed_fp.py` / `b_probed_fp.txt` | 分析器误报取证（名字 × 契约 schema × 真实失败原因） |
| `scripts\b_contract_diff.py` / `b_contract_diff.txt` | A 的契约结构化比对（只改 description） |
| `scripts\b_a_reverse.ps1` / `b_a_reverse.txt` | A 的派生非空转反向探针（我自写） |
| `scripts\b_live.ps1` | 主对抗实验（40 条围栏探针 + D2 全矩阵 + 读工具全边界，两个端点） |
| `scripts\b_live2.ps1` / `logs\b_live2_console.txt` | `broken.gd` 的决定性复核（游戏载入丢弃 + 编辑器 `valid:false`） |
| `scripts\b_live3.ps1` | 链接穿透的范围界定（文件系统树 / `project_read_script` 同样穿透） |
| `scripts\b_schemas.py`、`b_contract.py`、`b_ascii.py` | 契约 schema 提取、ASCII 校验 |
| `logs\b_live.log` | 主实验的**全部** 100+ 请求/响应摘要（探针 × 响应 sha × 首段） |
| `responses\*.json` | 决定性请求/响应**原始字节**（62 个文件） |

关键原始响应体（绝对路径，均在 `...\auditB\responses\`）：
`F22_junction_dir.response.json`、`F24_file_symlink.response.json`、`F25_dir_symlink.response.json`、
`G04_junction.response.json`、`H01_game_scene_tree.response.json`、`H10_validate_broken.response.json`、
`H14_batch_broken_on_sub.response.json`、`D214_read_tscn.response.json`、
`D220_batch_incompatible.response.json`、`D221_batch_legal.response.json`、
`D231_batch_partial_rollback.response.json`、`E01_tools_list.response.json`、`G01_tools_list.response.json`。

Scratch 工程与链接对象（工程外，验收后保留，含建法）：
`C:\Users\wyl\AppData\Local\Temp\task076_auditB\proj`（含 `link` / `dlink` / `sym_secret.txt` / `hard_secret.txt`）、
`C:\Users\wyl\AppData\Local\Temp\task076_auditB\outside\secret.txt`。

---

**总判定：`fail`** —— 阻塞缺陷 **D-B1**（围栏：链接穿透），高 **D-B2**（D2：编译失败仍报 `readable:true`），
中 **D-B3**（分析器：拼写正确的参数被误报为缺参数）。
**通过的部分**：`parsed:false` 诚实性、D9 撤回（9889 = **2**，不是 14）、分析器的修复机制本身、
A 的两处描述改动与派生、以及全部工程门。