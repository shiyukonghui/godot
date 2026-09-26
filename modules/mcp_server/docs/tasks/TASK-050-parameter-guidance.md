# TASK-050 — A 档（零契约成本）：**O-1 缺必填参数补建议** + **N-7 所有 -32602 附可接受参数** + **N-2 跨语言诚实性**

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件；证据原文见 `docs/reports/REPORT-AUDIT-RACING-BACKLOG.md`
> （**已独立确认**：O-1 confirmed、N-7 成立、N-2 成立）。报告 `docs/reports/REPORT-050-parameter-guidance.md`。
> 返回决策者的内容**只允许**是「≤10 行总结 + 报告路径」。

## 1. **O-1（横切 171 条）**：缺必填参数时**必须**给 `data.suggestion`

独立确认实测：缺必填参数的 `-32602` 响应**没有** `data.suggestion`（93 B），而**有**建议的同类错误是 223 B。
→ **在注册表的两个入口**（`MCPToolRegistry::call_tool` / `call_deferred_tool`，**不要**改 ~30 个 handler）
统一补：**缺必填参数** → `-32602` + `data.suggestion`，内容**点名**缺失参数**并列出该工具接受的参数名**（按契约 `inputSchema` 顺序，确定性输出）。
**必须**覆盖：immediate 与 deferred 两条入口、以及**契约里声明的必填**参数被省略/为空两种情形。

## 2. **N-7（同族加强）**：`-32602` 一律附**可接受参数**（含**嵌套路径**）

不止「缺必填」：**任何** `-32602`（含未知参数名、类型不符、越界）都应在 `data.suggestion` 里给出
**该参数的可接受形态**；对**嵌套**结构要能**定位到路径**（例如 `events[0].type`），不要只说「类型错」。
**范围控制**：若某类 `-32602` 的建议内容**无法确定性生成**（例如引擎侧语义拒绝），
就**明确说明原因**并给**指向正确工具/字段**的建议——**不得**留空。

## 3. **N-2（诚实性缺口）**：非 Mono 构建下 `project_validate_script` 对合法 `.cs` 报 `valid:false`

实测：非 Mono 构建里 `get_language_for_extension("cs")` 为 null 时**回退 GDScript**（`project_read_files.cpp:302-305`），
于是把「**这门语言不可用**」报成「**编译失败**」（`ERR_PARSE_ERROR`）。
→ 改为**能力感知的诚实回答**：语言不可用 → 明确说明「本构建不含该语言的脚本后端」+ `data.suggestion`
（用 Mono 构建 / 该语言不可用），**不得**把「无从解析」冒充「解析失败」；`valid` 字段语义要写清。
**契约描述**若需同步澄清 → 走 `DESCRIPTION_OVERRIDES`（append）+ 重生成 + 指纹，门① 逐字通过。

## 4. 门与纪律

第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；五道门 + 门⑥ 三段式
（新收窄点逐条列，§22.3b 规则 4）；回归 `mcp041/042/043` 门批次 + `mcp010/019/027` + `mcp044/045/046`；
**横切改动要特别小心**：`-32602` 的**错误码与既有消息文本不得改变**（只**增补** `data.suggestion`），
否则会打破大量既有证据脚本 → 逐条归因受影响的脚本（**不得**为让脚本变绿而放宽断言）；
**绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push；构建串行、不抑制输出；`.ps1` 纯 ASCII；结论按 D86 标锚点。