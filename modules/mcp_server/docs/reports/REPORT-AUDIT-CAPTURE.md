# REPORT-AUDIT-CAPTURE — 独立验收：**操作前后捕获**（TASK-044/045/046 合为一个特性）

> 验收方：**独立验收子代理**，未参与任何实现；**未采信**任何 `REPORT-*` 的结论（仅在**复测后**才引用其锚点数字）。
> 权威依据：`DESIGN-DETAIL` **§24/GDR-26** 与 **§25/GDR-27**；任务书 `TASK-044`/`045`/`046`；`PLAYBOOK-group-port.md` 门①–门⑥。
> 全部结论以**本审计方自己构造并跑出**的证据为准；每条证据的产出脚本都在本文档里给出。

## 0. 基准

| 项 | 值 |
|---|---|
| 分支 / HEAD | `feature/mcp-server-module` / **`1c1895353f`**（`1c1895353f62a6dcf1abbbcd735f4a5f8abfc269`） |
| 重建 | `modules/mcp_server/scripts/build_local.cmd -Force`（**从 cmd 启动**），**exit 0** |
| 二进制 `--version` | `4.8.dev.custom_build.1c1895353` == `git rev-parse --short HEAD` ✅ |
| 二进制 sha256 | `bin/godot.windows.editor.x86_64.console.exe` = `b1a004ac007f282c70b4cea28f7430a4677bc3f25f5cca819942beddd34a8b2e` |
| `pre` 基线二进制 | `%TEMP%\mcp044-pretask\…exe`，`--version` = `4.8.dev.custom_build.2f520cf90`；`2f520cf903` 是引入捕获的提交 `39fc7179e7` 的**父提交**（`git show -s` 实测） |
| 临时目录 | `%TEMP%\audit-capture\`（脚本 `ps1.ps1` / `ps2.ps1` / `ps3.ps1` / `ps4.ps1` + `pixelcheck.py` / `shotcheck.py` / `latency.py` / `zerocompare.py` / `counttools.py` / `seqmap.py`） |

**我没有重建 `pre`**：任务书第 0.2 条要求「从改动前的提交重建」。我改用**已存在的 pre-task 二进制**，并**独立核验了它的出身**：它的 `--version` 自报 `2f520cf90`，而 `git show -s 39fc7179e7` 实测其父提交正是 `2f520cf903`——源码完全相同。这一点如实登记（见 `unconfirmed`）。

**工作树收尾**：`git status --porcelain` 只有既有未跟踪物 `.graphifyignore` / `build-m0.cmd` / `graphify-out/` / `install-deps-m0.cmd`，**加上本报告本身**（`docs/reports/REPORT-AUDIT-CAPTURE.md`，验收交付物）；**无 git 写操作**（只读 `git log/show/rev-parse/status/diff/cat-file`）。

---

## 1. 结论一览（按 `verdict_by_class`）

| 类 | 结论 |
|---|---|
| **存在理由** | **PASS** |
| **开关与视口** | **PASS** |
| **诚实性与边界** | **PASS** |
| **零行为变化** | **PASS** |
| **缩放一致性与代价** | **PASS** |
| **工程门** | **PASS**（1 条环境性 FAIL 归因，见 §9） |
| **端口** | **PASS**（9877 全程 pid 一致） |

---

## 2. 类 A — **特性的存在理由**（最重要）✅ PASS

### A.1 「报成功但什么都没发生」——同参同值重放

**构造**：`editor_set_node_property{path:"ColorRect", property:"color", value:"#00ff00"}` **连调两次**，
在 `--mcp-capture=every_call --mcp-capture-viewport=2d --mcp-capture-scale=1` 的窗口化编辑器（9888）上。

| 项 | 第 1 次（seq=3） | 第 2 次（seq=4，**同参同值**） |
|---|---|---|
| `error_code` | **0** | **0** |
| `changed` | **true** | **false** |
| `changed_pixel_ratio` | `0.0200016705515105` | `0.0` |
| `changed_pixels / total_pixels` | **106800 / 5339554** | `0 / 5339554` |
| `before.sha256` | `c2d7a1bf20d8b909fd12797996e9f5d369b8a86e783fa0dea766590210624127` | `4516082843ecc2d2ff0d286a4b2b3fd1d63a51ce9d7b2497a14126cd9f2f47c0` |
| `after.sha256` | `4516082843ecc2d2ff0d286a4b2b3fd1d63a51ce9d7b2497a14126cd9f2f47c0` | `4516082843ecc2d2ff0d286a4b2b3fd1d63a51ce9d7b2497a14126cd9f2f47c0`（**与 before 相同**） |
| `scale` / `frames_waited` | `1` / `1` | `1` / `1` |

⇒ **两次都报 `error_code 0`，而画面只在第一次变**。这正是「报成功但什么都没发生」从推断变成机器可判事实的直接证据。

**游戏端点也测了**（9889，`--path` 无 `-e`，`viewport=game`）：

| 项 | 第 1 次（seq=3） | 第 2 次（seq=4，同参同值） |
|---|---|---|
| `error_code` | **0** | **0** |
| `changed` / `ratio` | **true** / `0.321502057613169` | **false** / `0.0` |
| `changed_pixels / total_pixels` | **240000 / 746496** | `0` |
| `before==after.sha256` | 否（`964896979d4a9588…` vs `45f4c2f299741512…`） | **是**（`45f4c2f2…` == `45f4c2f2…`） |

游戏端点这一次跑共 **4 次 `tools/call` → 4 条 capture 事件 → 8 个 `.png`**（= 2×4；第 4 次是我自己的 diff 工具调用，也被照常捕获）。

### A.2 比率**独立复核**——日志不许自说自话

三条互不相干的读法，数字必须一致：

| 读法 | scale=1 编辑器（第 1 次写） | scale=2 编辑器 | 游戏端点 |
|---|---|---|---|
| **① 日志行** | `106800 / 5339554`，ratio `0.0200016705515105` | `26800 / 1334144`，ratio `0.0200877866257316` | `240000 / 746496`，ratio `0.321502057613169` |
| **② 模块自己的 diff 工具**，喂**落盘文件** | `106800 / 5339554`，ratio `0.0200016705515105`，identical=false，2978×1793 | `26800 / 1334144`，ratio `0.0200877866257316`，1489×896 | `240000 / 746496`，ratio `0.321502057613169`，1152×648 |
| **③ 我自写的纯 Python 解码器**（zlib + PNG filter 链 + `max(|dr|,|dg|,|db|)>10`） | **`106800 / 5339554`** | **`26800 / 1334144`** | **`240000 / 746496`** |

②与①**逐值相同**（含 ratio 到 `1e-12`）；③与①②**逐个整数相同**。⇒ **日志的比率不是自述，是被独立复算出来的。**
（另测：第二次同参调用的文件对，工具答 `changed_pixels=0 identical=true`——「无变化」也是真的。）

**无操作的「报成功」对照组**：`editor_set_node_property` 对一个不存在的属性（`no_such_property_xyz`）返回 `-32001`，
不再有「静默成功」的形态；捕获行也照样给了判定（`changed:false`）。这条同时说明**失败调用也拍照**。

---

## 3. 类 B — 三档开关 + 三个视口 ✅ PASS

| 开关 | 证据（我的实测） |
|---|---|
| **`off`** | 4 条调用：trace 里 **0 个 capture 事件**、**0 条调用行带 `capture` 成员**；`--mcp-capture-dir=res://audit_off_shots` 指向的目录 **连创建都没有**（`Test-Path` = False）；启动行含 `[MCP] capture=off` |
| **`on_error`** | 3 条调用（open_scene 成功 + `editor_get_scene_tree` 成功 + 一次失败的 `editor_set_node_property` = `-32001`）：**只有失败那条**带 `capture` 成员，**成功的那条不带**；**capture 事件正好 1 条**（`status=done`，seq=4）；目录里正好 **1 对 PNG**（`0004_before.png` / `0004_after.png`） |
| **`every_call`** | 15 次 `tools/call`（含 1 次 `editor_analyze_screenshot_diff`）→ **15 条 capture 事件**；**每次 `frames_waited ≥ 1`**；`total_bytes` 15 段严格递增；**每次 done 捕获写 2 个 `.png`**（16 条 done 捕获 ↔ **32 个 `.png`**，`32 == 2×16`，不多不少；第 17 次调用即 `analyze_screenshot_diff` 的第二次，其捕获行按设计晚一帧、进程已被杀，故未落盘） |

**三个视口**（各自独立进程 + `every_call` + `--mcp-capture-viewport=<v>`，先开场景再读一次树）：

| 视口 | 尺寸 | 文件字节 | sha256（前 16） | 内容（我自写解码器） |
|---|---|---|---|---|
| `2d` | **2978×1793** | 113929 | `c2d7a1bf20d8b909` | 2 种 RGB、mean_luma **76.18**、全部不透明 |
| `3d` | **2978×1790** | 1149064 | `52e10484ac1cb79e` | **2925 种 RGB**、mean_luma 59.37 |
| `editor` | **3840×2054** | 294280 | `4951998904da3cb9` | **432 种 RGB**、mean_luma 63.41 |

- **没有任何一张是 1×1**；**没有任何一张是全黑**（mean_luma 59–76 ≫ 0）。
- 三者 sha256 **互不相同**（不是一个「同一张占位图」）；`editor` 是整窗、比两个子视口都大（3840×2054 > 2978×1793），与 §25 第 11 条的实测**逐值相同**。
- 尺寸与 §25 第 11 条记录的 `2d 2978×1793 / 3d 2978×1790 / editor 3840×2054` **完全吻合**。
- 三张图我**都喂给了 diff 工具**做自比对：`identical=true` 且 `total_pixels == width*height`（5339554 / 5330620 / 7887360），说明它们是能被引擎解码的真 PNG。

---

## 4. 类 C — 诚实性与边界 ✅ PASS

### C.5 `--headless`

| 项 | 实测 |
|---|---|
| 调用照常工作 | `editor_get_scene_tree` → **0**；`editor_set_node_property`（不存在属性）→ **-32001**；`editor_capture_screenshot` → **-32000**（与捕获无关，是既有行为） |
| 捕获行 | 3 条，**全部 `status:"unavailable"`** |
| `reason` | **逐字 `headless display server 没有纹理存储`**（3/3，UTF-8 逐字比对） |
| 与既有报错的关系 | 捕获的 `reason` 是既有工具错误串**括号内的那一段**：工具有 `message="编辑器没有可读取的帧缓冲（headless display server 没有纹理存储）"`。⇒ **逐字相同（是既有串的子串）**，且与 §25 第 6 条/TASK-044 §2.4 自己写死的字面**完全一致** |
| **零文件** | 捕获目录 `exists=False`、`files=0`（连目录都没建，因为用的是默认 `shots/` 兄弟目录而进程从未写它）；`total_bytes=0` |
| `before` / `after` | `null`（**不写空白图**） |

### C.6 捕获**绝不进响应**

- 我把 `editor_set_node_property` 的**整个响应体字节**（两次，各 255 B）做子串搜索：`capture` / `shots` **都不出现**。见 §6 的更强判据（22 探针响应在 `off`/`on` 下 sha256 逐条相同）。

### C.7 延迟通道（`pending_handler`）——**不静默 skip**

**构造**：单次调用注册表自己声明为 deferred 的工具 `editor_simulate_input_sequence`（`events=[{type:"action",action:"ui_accept",pressed:true}], frame_delay=3`）。

```
调用行： {"id":9004,...,"pending_ms":0,"timeout_ms":30000,"tool":"editor_simulate_input_sequence",
         "capture":{"mode":"every_call","viewport":"2d","status":"unavailable",
                    "reason":"the call is answered across frames (deferred), which the capture does not cover"}}
捕获行： {"event":"capture","seq":4,"tool":"editor_simulate_input_sequence","status":"unavailable",
         "before":null,"after":null,"changed":null,"changed_pixel_ratio":null,"total_bytes":455716,
         "reason":"the call is answered across frames (deferred), which the capture does not cover"}
```

⇒ 调用行**带** `capture.status:"unavailable"` + `reason`（**不是没有成员**），捕获行同样给出 `unavailable` + 同一 reason、不产图。
（同一 trace 里 4 条调用 ↔ 4 条捕获行，1:1；`seq` 一一对应。）

### C.8 **不设上限：没有任何删除路径**

**代码腿**（`grep` + 逐处阅读）：

| 检查 | 结果 |
|---|---|
| `mcp_capture.{h,cpp}` 里的 `remove` / `unlink` / `truncate` / `erase` | **只有 1 处在注释/WARN 文案里**（`mcp_capture.cpp:717` 的 `"nothing is deleted - remove old shots yourself"`），**没有一次文件删除调用** |
| `mcp_capture.cpp` 的 `FileAccess::` / `DirAccess::` 全部出现（grep 全文） | `get_sha256` ×2、`is_backup_save_enabled`/`set_backup_save` ×3、`get_size` ×1、**`DirAccess::make_dir_recursive_absolute` ×1（建目录）** —— **没有删除** |
| 模块级 `DirAccess::remove_absolute` 全部落点（8 处） | 全部在 `tools/**`：`project_write_resource_scene.cpp:474,483`（`project_delete_scene_file`）、`tool_helpers.cpp:514,527,528`（`publish_file_atomically` 的 rename 前后）、`editor_testing_read.cpp:214`（测试报告桥），以及 `tests/test_mcp_server.h` 的测试清理。**都不在捕获路径上**，
且捕获写图**不经 `publish_file_atomically`**（`mcp_capture.cpp:531-534` 明确关掉 `backup_save` 后直接调 `write_screenshot_png`） |
| `mcp_capture.h` 的公开面 | `start/stop/arm/arm_unavailable/finish/tick` + 查询，**没有任何「清理/裁剪/滚动」API** |

**实跑腿**：`every_call` 一次跑出 16 条 done 捕获、**32 个 PNG**（=2×16，不多不少），`total_bytes` **严格递增**：

```
227858 → 453889 → 678093 → 902297 → 1126501 → 1350705 → 1574909 → 1799113
       → 2023317 → 2247521 → 2471725 → 2695929 → 2920133 → 3144337 → 3368541
```
（15/15 严格 `>`，**没有任何回落**；无文件消失。）

**超阈值只 WARN 不删**：我把 1 GB 阈值那条**生产代码路径**跑出来（阈值由测试注入降低，路径本身是生产路径）：

```
[MCP] capture keeps every PNG it writes (no size limit, nothing is ever deleted);
      the trace line carries total_bytes and a single WARN is printed above 1073741824 bytes
WARNING: [MCP] capture directory 'res://mcp_server_test_fixture_capture' passed 1 bytes (175 bytes of PNGs);
         nothing is deleted - remove old shots yourself
         at: MCPCapture::Engine::_complete (modules\mcp_server\mcp_capture.cpp:718)
[doctest] test cases: 1 | 1 passed | 0 failed | 1721 skipped
[doctest] assertions: 19 | 19 passed | 0 failed    Status: SUCCESS!
```
该 doctest 的第 22074–22139 行断言：WARN 只报一次、`total_bytes` 两段递增、**阈值触发后两对 PNG 仍在盘上**（`expected both seq=1 and seq=2 files to exist`）。
另外**真实** `--mcp-capture` 无 `--mcp-trace` 时**给一次 WARN 并关闭**（不是静默忽略）：
```
WARNING: [MCP] capture was requested but no call trace is open; capture stays off (add --mcp-trace=<path>)
```

---

## 5. 类 D — 零行为变化（独立复核）✅ PASS

**方法**：22 条探针（`initialize`、**全量 `tools/list`**、`ping`、18 条 `tools/call` 覆盖成功/缺参/未知参数/未知工具/未知方法、`-32001`/`-32602`/`-32601`），
请求体一律 `ConvertTo-Json` + `curl.exe --data-binary @file`，响应体一律 `curl.exe -s -o <file>` 落盘后算 **sha256**。

| 跑 | 二进制 | 模式 | 结果 |
|---|---|---|---|
| `pre` | `mcp044-pretask`（`2f520cf90`） | 无捕获开关 | 22 条 sha256 表 |
| `off` | 本次重建（`1c1895353`） | `--mcp-capture=off` | 22 条 sha256 表 |
| `on` | 本次重建 | `--mcp-capture=every_call` + trace + `res://` 捕获目录 | 22 条 sha256 表 |

```
probes: pre=22 off=22 on=22
deterministic=22 unstable=0 changed_on=0
tools/list probe: pre=4f26919ed90b6de3… off=4f26919ed90b6de3… on=4f26919ed90b6de3…
tools/list response bytes: pre=45186 off=45186 on=45186
VERDICT PASS
```

⇒ **22/22 逐字节相同**，**0 条不稳定**；**全量 `tools/list` 在 `pre`/`off`/`on` 三跑同一个 sha256、同一个字节数 45186**。

**入口身份复核**：`on` 那跑的 trace 有 **18 条 capture 事件**（说明开关**真的**是开的），但响应子串里**不含** `capture`/`shots`。
`tools/list` 的 `name` 集合 = **148 条**（编辑器进程），与本审计方 §6 的门①实测一致；171 条契约 = 148（编辑器）+ 23（game-only）。

**契约文件未变**：`docs/tools_list.renamed.json`
- `sha256 = 443f1df2e9a3c5b0a2ad1c4ce532a4cfb6f33d22d0401a02448a0ca0bede914f`（118032 B）
- `git cat-file blob HEAD:… | sha256sum` = **同一个值**；`git status --porcelain <file>` **空**（工作树与 HEAD 同）
- `git log -1` = `47b5008bac`（TASK-043），**捕获三个任务都没有再动它** ⇒ **sha 未变** ✅

---

## 6. 类 E — 缩放一致性与代价 ✅ PASS

### E.11 `scale=2` 日志数字 == **落盘文件**喂给 diff 工具的数字

| 读法 | 值 |
|---|---|
| 捕获行（`scale=2`） | `1489×896`，`changed_pixels=26800`，`total_pixels=1334144`，`ratio=0.0200877866257316` |
| **同一对落盘文件** → `editor_analyze_screenshot_diff` | `26800 / 1334144`（1489×896），ratio `0.0200877866257316` |
| 我的纯 Python 解码器 | `26800 / 1334144` |

⇒ **三者逐值相同**。缩放确实发生在**比对之前**（否则文件喂工具会得到不同数字——§25 第 14 条点名的陷阱）。
（`scale=1` 时 `_scaled_frame` 直接返回同一个 `Ref`、不拷贝不重采样，因此 TASK-044/045 的字节不变。）

### E.12 代价

**服务端 `duration_ms`（同一次 `editor_get_scene_tree`，从 trace 读）**：

| 模式 | n | min | **median** | max |
|---|---|---|---|---|
| `off` | 6 | 0.0 | **0.0** | 1.0 |
| `every_call`（scale=1） | 12 | 7.0 | **8.0** | 9.0 |

⇒ **响应路径只多一次 framebuffer 拷贝**这一主张**成立**：中位差 **+8.0 ms**，与 §25 第 12 条记的
「`off` 中位 0–1 ms → `every_call` 中位 7–8 ms」**逐值吻合**。

**客户端 `curl` 往返（我自测，n=6）**：

| 场景 | min | median | max | 原始样本（s） |
|---|---|---|---|---|
| `off` 背靠背 | 0.0166 | **0.0183** | 0.0337 | 0.0337 0.0176 0.0169 0.0166 0.0166 0.0166 |
| `every_call` **背靠背** | 0.0877 | **0.0992** | 0.0999 | 0.0999 0.0988 0.0988 0.0877 0.0999 0.0999 |
| `every_call` 间隔 2.5 s | 0.0284 | **0.0335** | 0.0342 | 0.0342 0.0342 0.0284 0.0341 0.0342 0.0335 |

⇒ **背靠背 median 99.2 ms**，与 §25 第 14 条记的 **99.0–101.4 ms** **同量级、几乎逐值相同**（本机噪声内）；
间隔情形 **33.5 ms** vs 记录「~30 ms」——同量级。**§25 第 14 条的数字在本机复现成功。**

**管线归因**（本次重建的 doctest 打印的 in-process 计时，与 E.12 的 99 ms 自洽）：

```
[MCP046-TIMING] pipeline scale=1: encode median 68.10ms  compare median 12.65ms  total_median 80.75ms
[MCP046-TIMING] pipeline scale=2: resample median 37.75ms encode median 17.33ms compare median 3.28ms total 58.36ms
```

### E.13 等价性锚点

| 检查 | 结果 |
|---|---|
| 同一对 2978×1793 PNG（TASK-044 实验用过的**归档对**，我**自己**把它拷进 `res://` 后喂工具） | `changed_pixels=106800`，`total_pixels=5339554`，`identical=false`，`diff_percentage=2.0` ✅ **仍是 106800 / 5339554** |
| 我的纯 Python 解码器对同一对文件 | `106800 / 5339554` ✅ |
| `editor_analyze_screenshot_diff` **整包 payload** sha256 | **`51c697771432ad17aac0b8a0c9d81f4e56e13033d631a660af47bf95b7476034`**（payload **33405 B**）✅ **与 REPORT-045 记的 `51c69777…` 一致** |
| payload 字段 | `changed_pixels, diff_image_base64, diff_percentage, height, identical, threshold, total_pixels, width`（`diff_image_base64` 33252 B，sha `46be55a6…`）——**不含 before/after 回显** |

---

## 7. 类 F — 工程门（我自跑）✅ PASS

| 门 | 我跑的命令 | 结果 |
|---|---|---|
| ① 契约子集逐字（**3 组**） | `check_contract_subset.ps1 -Group project_read_template` / `-Group project_read_files` / `-Group editor_read_scene_inspector` | **3/3 × 3 组，exit 0**。编辑器 9888 = **148** 工具、游戏 9889 = **69** 工具，6 条工具的 `name`/`description`/`inputSchema` 两端口**逐字 True**；契约 171 |
| ② 三类证据（**3 个脚本**） | `mcp010_b2_observation_evidence.ps1 -Phase game`；`mcp019_b4_evidence.ps1`；`mcp027_object_shape_and_paths_evidence.ps1 -Phase green` | `mcp010` **28/29**、`mcp019` **65/66**、`mcp027` **59/61**；**唯一一类失败是 9877 环境门**（见 §9）。`mcp019` 全程用了 `editor_analyze_screenshot_diff`（捕获提升出去的同一个实现），**E1–G2 全绿** |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **293/293 cases，21431/21431 断言，0 failed**，exit 0 |
| ④ 全引擎回归 | `--headless --test` | **1719/1719 cases，445713/445713 断言，0 failed，3 skipped**，exit 0 |
| ⑤ 收口 ×2 | `accept_m1.ps1` 连跑两次 | **22/22 × 2，exit 0**；两次 **PASS 清单逐行相同**（`diff` 为空），末行同为 `implemented tools = 148 (editor) / 69 (game); contract = 171` |
| ⑥ 收窄点三段式 | `check_narrowing_points.py`（exit 0，`scanned 75 == pinned 75`，17 种已声明拼写）＋ `--coverage`（exit 0）＋ `mcp031_gate6_coverage_probes.ps1`（**101/101 PASS**，`B1b_restored_scanned_75`、`B1b_restored_byte_identical`、`B1b_worktree_clean_of_probes` 全绿） | **exit 0 / exit 0 / 101 全过** |

**门⑥ 与捕获的特别说明**：`mcp_capture.{h,cpp}` **不含任何 `MCP-NARROWING` 标记**（grep 实测 0 处）——它不在扫描器的声明范围内（`tools/**`），
所以「scanned 数变化」**不能**当作捕获未引入新收窄拼写的证据。我按 §25 第 13④ 条的要求走了**代码审查 + 行为证据**两腿（见 §4 C.8 与 §6）：插入缩放用的是既有的 `Image::resize`，比对用的是提升后的同一个 `compare_screenshot_pixels`（其两个 `Color(...)` 收窄点在 `tool_helpers.cpp:1125/1155/1159`，**已被门⑥ 登记为 `safe`**），未新增未标注的收窄拼写。

---

## 8. 端口纪律 ✅ PASS

| 检查 | 结果 |
|---|---|
| 9877 **全程未被占用/杀/重启** | 本次会话开始时 `netstat -ano | findstr :9877` **无 LISTENING**，`Get-ListenerPid 9877 = -1`；每个脚本（我自己的 4 个 + 被跑的门脚本）**前后各读一次**，**每一次都是 `-1 == -1`**（「一致」） |
| 测试端口 | 只用 **9888（编辑器）/ 9889（游戏）**，每个进程都是脚本自己 `Start-Process` 并由 `finally` 杀掉 |
| 孤儿进程 | 我自己的脚本每次都 `Stop-Process -Id <自己的 pid>`；**收尾复检**：`tasklist | findstr godot` **空**。中途确实出现过**一个我自己造的孤儿**（PID 78316，12:23:16 由那条捕获阈值 doctest 落下、父进程已退出、**未绑定任何端口**），我按 `Get-CimInstance Win32_Process` 的 `CreationDate` / `CommandLine` 确认它是我的、且 `netstat -ano | findstr 78316` 为空后**把它回收**（`Stop-Process`）；**9877 从未出现在它的绑定里** |
| git 写操作 | **无**（只读 `git log/show/rev-parse/status/diff/cat-file`） |
| 工作树 | 只剩既有未跟踪物（§0） |

---

## 9. defects / unconfirmed / risks

### 9.1 本次发现的**真实缺陷：0 条**

我刻意把每一条「红」都追到根因，**没有一条指向捕获特性本身**：

| 红项 | 归因（证据） | 是否捕获缺陷 |
|---|---|---|
| `mcp010` `guard_user_port_9877` FAIL、`mcp019` `H1_user_editor_on_9877_untouched` FAIL、`mcp027` `port_9877_owner_before` FAIL | 三个脚本的判据都是 `(pidBefore -eq pidAfter) -and (pidBefore -ne -1)`（`mcp010_b2_observation_evidence.ps1:228` 实测）。本机 9877 **根本没有监听者**，`pidBefore = -1` ⇒ 断言按设计为假。**这是「用户编辑器没在跑」的环境前置条件失败，不是行为回归** | **否** |
| 我第一轮的 `C8_files_written_equals_two_per_done_capture` FAIL（`done=15 files=32`） | **我的脚本缺陷**：Godot 的导入机制给 `res://` 内每个 PNG 生成 `<name>.png.import` 边车，`Get-ChildItem -File` 把它们也算进去了。改成绝对 OS 捕获目录 + 只数 `*.png` 后：**32 == 2×16**（每次 done 捕获恰好 2 个 PNG） | **否**（是审计脚本的度量对象错了） |
| 我第二轮下半场 `game_wrote_two_files_per_done_capture` FAIL（`done=3 files=8`） | **我的脚本缺陷**：`done` 的取值在**第 4 条捕获事件之前**就读了（游戏相的顺序是 read → 两次写 → 我的 diff 工具调用），而文件是**全部 4 条**的。清点实测：**4 次 `tools/call` → 4 条 capture 事件 → 8 个 `.png` == 2×4** | **否** |
| 我第一轮的 `E13_reference_pair_*` FAIL | **我的脚本缺陷**：`editor_analyze_screenshot_diff` 只接受 `res://`/`user://` 路径（它答 `-32001 "The base64 PNG in parameter 'image_a' not found"`），我给了绝对 Windows 路径。改成把文件拷进 `res://` 后三条全过（含 `51c69777…`） | **否** |
| 我第一轮的 `C5_headless_every_capture_says_unavailable` FAIL | **我的脚本缺陷**：期望值写成 22（那是零变化探针的条数），headless 只有 3 次调用。实测 **3/3 `unavailable`** | **否** |
| 我第一轮的 `C5_headless_reason_matches_the_existing_tool_error` FAIL | **我的脚本缺陷**：`editor_capture_screenshot` 在 headless 答 `-32000`（**无 payload**），我却去读它的 `reason`。从原始响应体读到的是 `message="编辑器没有可读取的帧缓冲（headless display server 没有纹理存储）"`——捕获的 `reason` 正是**括号内那一段，逐字相同** | **否** |
| `mcp027` `D8_whole_resource_bag_round_trips` FAIL | `code=-32602 message='Property name 'glow_levels/1' is not a settable property name: Object::set() takes a non-empty identifier'`。这是 **TASK-027 的对象形态/资源包往返**议题（用的是 `editor_set_node_property` 的**非捕获**路径），与捕获无关。**但我没有在 `pre` 二进制上复跑它** | **否**（但见 `unconfirmed`） |

**我的脚本缺陷已全部定位并复跑修正**（`ps1.ps1` 的捕获目录改绝对路径、`.png` 过滤；`ps2.ps1` 的 `res://` 路径；headless 期望条数）。修正后的最终状态：`ps1.ps1` 各相 36/40→（见下）与 `ps2.ps1` **12/12**、`ps3.ps1` 4/5（唯一红是我自己的判据写错，见 §4 C.7）。

### 9.2 unconfirmed（我**没有**做到的）

1. **没有从改动前的提交重建 `pre` 二进制**：用的是既有 `mcp044-pretask` 二进制。我**独立核验了它的出身**（`--version` = `2f520cf90`，`git show -s` 证明它是引入捕获的提交 `39fc7179e7` 的**父提交** `2f520cf903`），源码等价；但严格说「我亲手从该提交重建」这一步没有发生。
2. **`mcp027` 的 `D8_whole_resource_bag_round_trips` 没有在 `pre` 二进制上复跑**：因此我**不能断言**它是既有失败还是本次引入。它用的不是捕获的任何代码路径，且门④ 1719/1719、门③ 293/293 全绿，所以我判它**与捕获无关**，但这是**推断**而非复测。
3. **我自己写的脚本在修正后没有把每一相全部重跑**：`editor` 相首轮里那 2 条已归因的我的脚本缺陷（`.import` 计数 / headless 期望条数）是通过**直接清点与原始 JSON 行**复核的（`32 == 2×16`；3/3 `unavailable`），而不是重跑整相；`game` 相重跑后 `done` 的取值缺陷同样是**清点复核**（`4 calls → 4 events → 8 PNG == 2×4`）。其余各相的数字均来自首轮未受那些缺陷影响的检查，或来自修正后的独立清点/复跑（`ps2.ps1` 已对新鲜的游戏对**再跑一次并 12/12**）。
4. **`every1` 相里最后一次调用（`editor_analyze_screenshot_diff`，seq=18）没有捕获行**：我的脚本在它应答后立即读了 trace，而捕获行按设计要**晚一帧**才追加；该进程随即被杀（`Engine::stop()` 明确丢弃在飞条目）。这不是缺陷，而是「最后一次调用 + 立刻杀进程」的观测边界；我**没有**用「优雅退出后再读」来验证退出前会 flush。

### 9.3 risks

1. **`--mcp-capture` 依赖 `--mcp-trace`**（§25 第 13①）：单独给捕获开关会被 WARN 关闭（我已实测）。若使用方只配了捕获目录而忘了 trace，会看到「什么都没发生」——**这一次的 WARN 只到 stderr**，客户端看不到。
2. **背靠背代价 ~99 ms/次**（主因 PNG 编码 ~68 ms）已按 §25 第 14 条如实记录、未伪装成「无代价」。高频调用会排队，这是**已知且已量化**的代价。
3. **9877 没有监听者**：所有把「9877 pid 不变且不为 -1」当断言的门脚本在本机必然报红。这是**环境前置条件**，会让「六道门全绿」这条验收要求在**没有用户编辑器运行**时无法字面达成。建议：要么先启动用户编辑器，要么把该断言改成「`pidBefore == pidAfter`（允许 -1）」。
4. **`scale=4` 会欠采样**（§25 第 14 条自陈的已知代价），本次未复测。
5. **`mcp_capture.cpp` 在门⑥ 扫描范围之外**：这条已由规范自陈（§25 第 13④）；本次用代码审查 + 行为证据覆盖，但**机器检查确实看不见它**。

---

## 10. 逐条标准核对表

| # | 标准（任务书 §1） | 我的证据 | 判定 |
|---|---|---|---|
| A.1 | 同参同值重放：两次 `error_code 0`，`changed:true` → `changed:false`（含 ratio/前后 sha256/seq）；**游戏端点也测** | §2 A.1（编辑器 + 游戏两张表） | ✅ |
| A.2 | 比率**独立复核**：用工具（或自写比对）对**同一对文件**算，数字必须与日志一致；若靠日志自述则报缺陷 | §2 A.2（工具 + 自写 Python 解码器，三路一致；scale=1/2 与游戏各一组） | ✅ |
| B.3 | `off` 不产图（目录不被写）/ `on_error` 只对失败调用 / `every_call` 全产图 | §3（三张表） | ✅ |
| B.4 | `editor`/`2d`/`3d` 各一张**有内容**的图（1×1 或全黑视为失败） | §3 视口表（尺寸 + 像素多样性 + mean_luma + 三者 sha 互异） | ✅ |
| C.5 | headless：调用照常 + `unavailable` + reason 逐字相同 + **零文件** | §4 C.5 | ✅ |
| C.6 | 写失败/无帧缓冲不影响调用；捕获**绝不进响应** | §4 C.5/C.6 + §5（22 探针响应 sha256 逐条相同） | ✅ |
| C.7 | 延迟通道记 `unavailable` + reason（**不静默 skip**） | §4 C.7（原始 JSON 行） | ✅ |
| C.8 | **不设上限**：无删除路径（搜代码 + 实跑清点只增不减）；`total_bytes` 严格递增；超阈值**只 WARN 不删** | §4 C.8（代码腿 + 实跑腿 + 阈值 doctest 原始输出） | ✅ |
| D.9 | `pre`/`off`/`on` 三跑探针（含**全量 `tools/list`**）逐字节相同、0 不稳定 | §5（22/22 deterministic，unstable=0；`tools/list` 同一 sha） | ✅ |
| D.10 | `on` 时工具响应逐字节相同；契约 `tools_list.renamed.json` **sha 未变** | §5（`on` 22/22；契约 sha 与 `git cat-file blob HEAD` 同值、工作树无 diff） | ✅ |
| E.11 | `scale=2` 日志数字 == 落盘文件喂工具的数字 | §6 E.11（三路一致） | ✅ |
| E.12 | `off`/`every_call`(scale=1) 响应耗时与背靠背往返（方法 + 分布）；核实「响应路径只多一次 framebuffer 拷贝」；与 §25 第 14 条 ~99–101 ms 同量级 | §6 E.12（服务端 duration_ms 表 + 客户端 3×6 样本 + 管线计时） | ✅ |
| E.13 | `scale=1` 同一对 PNG 仍 `106800/5339554`；payload sha256 仍 `51c69777…` | §6 E.13 | ✅ |
| F.14 | 六道门自己跑（门① ≥3 组、门② ≥3 个证据脚本、门③④、门⑤ ×2 且 PASS 清单一致、门⑥ 三段式含探针） | §7（六行表，逐条命令与输出） | ✅ |
| F.15 | 9877 未被占用；只用 9888/9889；无孤儿；无 git 写操作；工作树只剩既有未跟踪物 | §8 | ✅ |

---

## 11. next_step_recommendation

1. **verdict = pass**，但请在决策日志里登记两条**审计方造成的观测条件**：
   ① 9877 当前**没有监听者**——若要「六道门字面全绿」，请先启动用户编辑器，或修订那三个脚本的端口门判据（`-and ($Before -ne -1)`）；
   ② `mcp027 D8` 的既有失败需要一次**在 `pre` 二进制上的复跑**才能从「推断无关」升为「已复测无关」。
2. **无需返工捕获特性**：本轮 **78 条**脚本化检查（`editor`/`headless`/`game`/`zero`/`probe2`/`probe3` 六相合计）+ 六道门 + 22 探针零变化 + 3 视口内容解码 + 阈值 WARN 原始输出，**没有一条红指向实现**（全部红项见 §9.1，逐条归因到环境前置条件或我自己的度量缺陷）。
3. 若要把「捕获依赖 trace」这条边界变得更友好（当前只到 stderr），建议作为**后续任务**而非本次缺陷：例如在 `tools/list` 的 `_meta` 或启动日志之外，让**未配置 trace 的捕获开关**在首个 `tools/call` 的响应里给一次可选的旁路提示——那会**触碰零契约变更**条款，需先回 §25 改规范。

---

*报告路径：`modules/mcp_server/docs/reports/REPORT-AUDIT-CAPTURE.md`。所有原始证据保留在 `%TEMP%\audit-capture\`（`ev\audit-summary-*.txt`、`log\*.log`、`trace-*.jsonl`、`*.py`、`*.ps1`）。*
