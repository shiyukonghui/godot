# ACCEPTANCE — Godot 内置 MCP 模块（`modules/mcp_server`）

验收记录按里程碑追加。每条结论必须可追溯到**独立执行**的命令输出，不采信实施者陈述。

---

## M0 — 工具链 + 非 mono 基线构建：**PASS**

- 验收方：全新独立子代理（`d243cc13-f583-4bb1-b467-6c4fded2826d`），未参与实施，未采信实施者结论。
- 实施摘要：装 SCons 4.11.1（`NO_PROXY=*` 绕过注册表代理）、跑官方依赖脚本（D3D12 Agility SDK / AccessKit / Pix / Mesa NIR
  → `%LOCALAPPDATA%\Godot\build_deps`）、`scons platform=windows target=editor module_mono_enabled=no -j8` 13.2 分钟 exit 0。

### 通过项（每条均为验收方独立复现）

| 项 | 方法 | 关键证据 |
|---|---|---|
| HEAD 与工作区干净 | 命令 | `HEAD=57277407e77e61b161f35dbd7aeb510f7a9e26a6`；`status --short` 仅 4 个 `??`（wrapper 脚本 + graphify 产物），**无 ` M`**；`diff --stat`/`diff --cached --stat`/`stash list` 全空 |
| 产物与字节数 | 命令 | `176,900,608` exe / `300,544` console.exe / `4,821,064` D3D12Core.dll / `4,932,640` d3d12SDKLayers.dll，与声称逐一一致 |
| 溯源确实是本源码所出 | 反例探测 | PE `machine=0x8664`、`link_ts=2026-09-21 11:54:42 UTC` 与文件 mtime **逐秒吻合**；版本串内嵌日期 `2026-09-18 15:41:32 UTC` 恰等于 HEAD 提交时间；`bin\D3D12Core.dll` 与依赖源同名文件 **SHA256 完全相同** |
| 非 mono | 反例探测 | 176 MB exe mmap 扫描：`GodotSharp`/`godot_mono`/`ModuleMono`/`hostfxr`/`coreclr` 全 absent；`bin/obj` 2983 个对象中 mono 匹配 **0**；PE 导入表仅系统 DLL |
| 与在用的 4.7.1-mono 不是同一二进制 | 命令 | 路径不同、`176,900,608` vs `179,589,128`、SHA256 `463676D2…` vs `8EC33BA6…` |
| 增量重建可复现 | 命令 | 同命令复跑：`scons: '.' is up to date.`、`done building targets`、`Elapsed 00:00:24.01`、**EXIT_CODE=0**（cmd 重定向 + `$LASTEXITCODE`，无管道污染） |
| 日志完整无错误 | 读文件 | `build-m0.log` 3242 行，以 `done building targets` + `EXIT_CODE=0` + `BUILD END` 收尾；`ERROR|error C|fatal error` **零匹配**；attempt1 失败原因确为 AccessKit + D3D12 依赖缺失（EXIT_CODE=255） |
| 未越界 | 命令 | hof-rs 无被跟踪改动；`godot_mcp_gdext` status 空且 19:00 后修改文件数 0；`runs\**` 最新 mtime 早于构建开始；9877 构建前后均在 `Listen`，编辑器进程 PID 36392 存活未重启 |

### 未阻断的发现（记入已知偏差）

- **ANGLE 渲染驱动被警告级静默跳过**（`angle=no` 事实上生效）：`build-m0.log:4`，bin 内无 `libEGL.dll`/`libGLESv2.dll`。
  不在 M0 验收标准内；若后续需要，补跑 `python misc\scripts\install_angle.py` 并以 `angle=yes` 重建。
- **`msgfmt` 缺失**：仅生成 `.po` 未生成 `.mo`（4 处 WARNING）。不在依赖路径上。
- nit：日志中链接器中文输出乱码（GBK 按 UTF-8 呈现），关键 ASCII 证据完整。
- nit：官方依赖脚本对 ARM64 PIX 库的 MinGW 适配失败（x86_64 不受影响，脚本仍 exit 0）。

### 未验证边界

- **U1** clean 全量重建的位级可复现性未验证（只验证到「同命令判定完全 up-to-date」）。
- U2 未采集运行中 4.7.1 编辑器的 `--version`（刻意为不干扰用户会话；已用路径/大小/SHA256 替代）。
- U3 未验证 4.8 产物的前台 GPU 渲染路径（只跑 headless）。
- U4 设计文档未规定 ANGLE 是否必须启用（本文件据此在 M0 只记为已知偏差）。

### 后续里程碑必须遵守的环境事实

- **用户正在使用的编辑器占用 9877**（4.7.1-mono，PID 36392）。因此 M1 起的端口相关验收**一律使用非默认端口**
  （编辑器侧 9888、游戏侧 9889），默认端口 9877 的**解析逻辑**只做单元测试，不实际占端口。
- 构建工具链固定为：SCons 4.11.1 / Python 3.9.7 / MSVC 14.42.34433 / WinSDK 10.0.26100.0。
- 模块单元测试用引擎自带 doctest：`SCsub` 中 `if env["tests"]: env_mcp.add_source_files(env.modules_sources, "./tests/*.cpp")`，
  以 `tests=yes` 构建后用 `--test` 运行（范式见 `modules/jsonrpc/tests/test_jsonrpc.cpp` 与 `modules/jsonrpc/SCsub:10-11`）。

---

## M1 — 模块骨架 + HTTP/1.1 子集 + JSON-RPC 2.0 + 2 个工具：**PASS（独立验收）**

- 验收方：全新独立子代理（`78058364-2395-453d-a3cc-60fffc69c65b`），未参与实施，未采信实施者数字；
  全部证据由其自建 PowerShell/Python 客户端与独立命令产出，产物在 `%TEMP%\m1acc`，**未修改任何文件**。
- 代码落点：fork 分支 `feature/mcp-server-module`，HEAD `95dcb24c761edbf0cbfc34cd86bdb95dbb83157e`；
  `git diff --name-only 57277407e7..HEAD` = 17 个文件，**全部在 `modules/mcp_server/` 下**（过滤后 0 命中）；工作树无被跟踪改动。
- 结论：**14/14 验收行通过；实施者可复跑的数字逐个精确复现；未发现伪造**。

### 独立复现的数字（验收方自己跑的）

| 项 | 结果 |
|---|---|
| 构建 | `scons platform=windows target=editor tests=yes module_mono_enabled=no -j8` → exit 0（增量 31 s） |
| 模块 doctest | **30 passed / 172 assertions / 0 failed**，exit 0 |
| 全引擎 `--test` | **1456 passed / 424453 assertions / 0 failed / 3 skipped**，exit 0（不是 1455/1454） |
| `accept_m1.ps1` | **17/17，exit 0，连跑两次**均通过 |
| D24 防回归（响应归属） | 自建客户端，两条连接**交错写入字符串 id 与数字 id**（读之前全部写出）：12 个响应**值与 JSON 类型**全对，**零跨连接泄漏** |
| D35 死连接回收 | 16 条「发完即关」连接后，新请求 **28 ms**（复测 29 ms）被服务；第 17 条超限连接无响应；`connections` 回到 1 |
| D36 活连接未被误判 idle | 流水线 8 条（180 B 填充）→ 读完 → 等 4 s → 再 8 条：**16/16 全部服务，零问题**；30 s idle 回收另测正常 |
| G4 并发 100 | 自建客户端，8 连接 × 100 流水线：**100/100，mismatches 0** |
| chunked-only | **HTTP/1.1 411 Length Required**（**确认 D33 的「400」措辞错误**，TE 完全未解析） |
| chunked + Content-Length 并存 | **Content-Length 生效，TE 被忽略** |
| `Expect: foo-bar` | 200 + id 正确，**无 417**（静默忽略） |
| `Expect: 100-continue` | 中断 body 请求：**87 ms** 内回 `HTTP/1.1 100 Continue`，**恰好一次**，随后 200 |
| JSON-RPC 信封 | `initialize` 与 GDR-6 结构一致；`notifications/initialized` → **202 + Content-Length: 0 + 空 body**；`123`/缺 method → `-32600`；未知 method → `-32601`；坏 JSON → `-32700`；缺 name/非对象 arguments → `-32602`；id 保真：`9007199254740993`（无浮点丢失）、`1.5`、`null`、字符串 id 全部逐字回显 |
| 畸形输入电池 | 无 CL 的 POST → 411；>8 KiB 头 → 400 + 关闭；三段半包 → 200；body 少 1 字节 → 不提前响应再 200；两条流水线且第一条不完整 → 均正确；`Connection: close` → 第二条不答；DELETE/PUT/PATCH/HEAD/OPTIONS → **405**；`GET /other` → **404** |
| 游戏进程（自建二进制，9889） | `is_editor:false`、**同一份 2 工具**（名字/inputSchema/描述全同）；不带 `--mcp-port` → 9889 **未监听**、引擎存活 |
| fixture 双重编码 | 独立原始字节分析：326390 字节、**有 UTF-8 BOM**、**174/174** 条描述 `latin-1→utf-8` 复原成功且**反向重编码逐字节相等** |
| 9877 守卫 | 全部运行前后 `9877 Listen PID 36392` 不变，且 36392 是机器上唯一残留 godot 进程 |

### 未验证项（验收方明确无法复现，需如实保留）

- **U-1/U-2**：D35/D36 的**反事实 A/B 数字**（「修前 8517 ms 不可用」「修前 case8 失败」）需回退代码并重建才能复现，
  按只读约束未做；**修复后的正向行为已被独立确认**。
- **U-3**：实施者所说的「第一次 16/17」无法复现（两次都是 17/17），属历史事实，不影响判定。
- **U-4**：「6 轮×100 = 600/600」未复跑（只跑了 1 轮 100 + 若干单连接批次）。
- **U-5**：§9 的「并发 100 请求」实际是**8 条连接上的 100 条流水线请求**（引擎 `SocketServer::MAX_PENDING_CONNECTIONS = 8`），
  比「100 条同时连接」弱；**门的表述需在设计里重述**（已在 §14 GDR-15 处理）。

### 独立验收发现的产品/测试缺陷与处置

| id | 级别 | 问题 | 处置 |
|---|---|---|---|
| D-1 | major（测试质量） | `accept_m1.ps1:651-658` 的「413 后连接已关闭」断言**恒真**：把读超时当关闭；同一 socket 18 ms 后还能服务请求 | **修正断言为正向证明**（再发一条请求要求无响应 / `Receive` 返回 0），见 §14 GDR-12 |
| D-2 | major（对等门） | description 相等性无法强制，「原始或还原任一命中」会放行**输出乱码**的实现；影响 B1–B5 所有批次 | **重采 fixture 为干净 UTF-8** 并要求**逐字相等**（去掉兜底），见 §14 GDR-13 |
| D-3 | minor（跨里程碑） | `tools/call` 未知工具名返回 `-32601`，而 GDR-6 原文写 `-32001` 用于 not-found | **判为设计表述需澄清**：参照实现 `commands/mod.rs:109` 对未知工具就是 `method_not_found`；`-32001` 专用于**工具内部找不到资源**（如 `no_scene`/文件不存在），见 §14 GDR-14 |
| D-4 | minor | `ParseStatus::HEADER_TOO_LARGE` 映射 400，而 `reason_phrase()` 里 431 是死代码 | 采纳 **431**（语义正确），见 §14 GDR-12 |
| D-5 | minor | 非法 UTF-8 body 被 `String::utf8` 静默替换为 U+FFFD 并**接受**（200），边界此前未定义 | 保留宽松行为但**写入规范**，并加 verbose 警告，见 §14 GDR-12 |
| D-6 | nit | 裸 LF 结束头部不被识别（HTTP/1.1 要求 CRLF，合规但会给客户端 30 s 静默） | 明确回 **400**，见 §14 GDR-12 |
| D-7 | nit | JSON-RPC `id: true` 被原样回显（规范仅允许 string/number/null） | 保留宽松行为，写入规范 |
| D-8 | nit | 「工作树干净」表述不准确（有 4 个 M0 期未跟踪物，但无被跟踪改动） | 已在本文件与 M0 节如实登记 |