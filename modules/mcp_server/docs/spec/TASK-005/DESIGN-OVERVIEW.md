# DESIGN-OVERVIEW — TASK-005

工件属阶段二（概要设计）。输入：`docs/spec/TASK-005/REQUIREMENTS.md`（已确认）。本文件只讲系统级决策与取舍。

## 1. 架构分层（不变，仅补共享层）

```
mcp_server/
  mcp_server.{h,cpp}      传输生命周期（已有，不动）
  mcp_http_server.{h,cpp} HTTP/1.1 帧（已有，不动）
  mcp_jsonrpc.{h,cpp}     JSON-RPC 信封 + MCPToolError → 线上错误对象（已有，不动）
  tool_registry.{h,cpp}   注册表 + GDR-16 lint + scope 过滤（已有，不动）
  tools/
    tool_builder.{h,cpp}   ★「工具定义构建 + 参数校验 + 结果封装 + 路径/IO 助手」（不动语义）
    tool_helpers.{h,cpp}   ←【新增】通用助手：_split_lines / _serialize_variant / _join_path /
                             扩展名递归遍历（4 个，从两组成员文件上提）
    project_read_template.{h,cpp}   ← 改用共享助手（删本地副本）
    project_read_analysis.{h,cpp}   ← 改用共享助手（删本地副本）
    project_read_files.{h,cpp}      ←【新增】本组 6 个工具
    registration.{h,cpp}            ← 追加一行 include + 一行调用
  tests/test_mcp_server.{h,cpp}     ← 新增本组用例 + 助手等价性用例
  scripts/accept_m1.ps1             ← 工具清单/计数 13 → 19
  docs/tool-groups.json             ← project_read_files.implemented: false → true
```

## 2. 模块职责与边界

| 模块 | 职责 | 不负责 |
|---|---|---|
| `tool_builder` | 强制显式声明 channel/verb/scope/mutating；参数校验；`content_result` 信封；`normalize_project_path`/`open_project_dir`/`read_project_text_file`/`file_extension` | 通用文本/变体工具（不在其职责内） |
| `tool_helpers` | **纯函数级**通用助手，无状态、无单例依赖（不碰 `Marshalls::get_singleton()`） | 任何工具注册、任何 IO 策略决策 |
| `project_read_files` | 6 个只读工具的**可观察契约**（参数、返回形状、上限、大小写、错误类） | 写文件；改写资源；发明未声明字段 |

## 3. 关键接口（系统级）

```cpp
// tools/tool_helpers.h — namespace MCPTools
String join_path(const String &p_dir, const String &p_entry);
Vector<String> split_lines(const String &p_text);            // Rust str::lines() 语义
Variant serialize_variant(const Variant &p_value);           // 非 JSON 类型 → 普通结构
void collect_files_by_extension(const String &p_path, const Vector<String> &p_extensions,
                                bool p_include_addons, Vector<String> &r_out);
```

- 4 个函数**逐字保留**原 `static` 版本行为；唯一变化是链接性（internal → 命名空间内公共）与命名
  （去掉前导 `_`，因为不再有「本文件私有」含义；调用点同步改名）。
- 上提**不做**任何「顺手优化」：不合并 `_resource_extensions()`/`_reference_extensions()`/`_scene_extensions()`
  这类**组特有常量表**（它们属于 analysis 组语义），也不触碰 template 组的 `_scan_*` 系列。

## 4. 数据流

```
tools/call
  → MCPJsonRpc::handle  → MCPToolRegistry::call_tool  → group handler(Dictionary args, MCPToolError&)
       参数：require_string/optional_string/optional_int/optional_bool  （失败 → -32602）
       路径：normalize_project_path（只允许 res://，折叠 . 与空段，.. 拒绝）
       磁盘：FileAccess / read_project_text_file（不存在 → -32001 + data.suggestion）
       资源：ResourceLoader::load / Image::load / CryptoCore::b64_encode_str
       成功：content_result(payload) → {"content":[{"type":"text","text":"<json>"}]}
```
- 组内所有工具 `channel=project`、`verb` 按映射（`list`/`read`/`validate`/`get`）、`scope=BOTH`、`mutating=false`。

## 5. 备选方案与否决理由

| 决策点 | 备选 | 否决/采纳理由 |
|---|---|---|
| 共享助手落点 | (A) 塞进 `tools/tool_builder.h` | 可工作但污染职责；`tool_builder.h` 是**每个**组都要 include 的工具定义头，把文本工具塞进去使它对不关心文本的组也成为依赖。**未采纳** |
| | (B) 新 `tools/tool_helpers.{h,cpp}` | 与仓库 `tools/<topic>.{h,cpp}` 风格一致，`SCsub` glob 自动纳入构建，职责单一。**采纳** |
| | (C) 放在 `project_read_template.h` 复用 | 依赖方向错误（新组不得依赖别组的头），且 TASK-005 要求「删除本地副本、改共享」。**否决** |
| 共享助手命名 | 保留 `_` 前缀 | `_` 在本仓库表示「文件私有（internal linkage）」；上提后该含义消失，会误导后续读者以为仍私有。**采纳去 `_`** |
| 重构等价性验证 | (A) 只跑 doctest | doctest 不是逐字节对比工具，无法证明「响应逐字节相同」。**不足** |
| | (B) 重构前后各起一次引擎，采同一组请求响应，逐字节 + sha256 比较 | 直接可核对、可复现，且覆盖真实线上信封与 `tools/list`。**采纳**，并同时用 gen/regression 做静态证明（助手只有一处定义） |
| `project_read_resource` 语义 | (A) 迁移源窄语义 `{path,type,loaded}` | 与迁移源一致；契约描述不含属性字段，窄语义不发明未声明行为。**采纳** |
| | (B) 额外序列化资源属性 | 会引入契约未声明的字段（未声明行为变更），且迁移源无对应实现。**否决**，差异入报告 |
| `project_validate_script` | (A) 真编译校验（GDScript 实例 + 源码 + reload/compile） | 语义最诚实（编译能力真存在时）。**首选**，但必须先 spike：doctest 进程无脚本语言，需确认是否可用/是否 SIGSEGV |
| | (B) 纯启发式静态检查 | 只在 A 实测不可用时采用；**不得**把结果描述为「语法正确」，必须用中立措辞并在报告登记 |
| base64 编码 | (A) `Marshalls::get_singleton()->raw_to_base64()` | 依赖 `Marshalls` 单例注册，doctest 进程不保证存在（历史上 `EditorInterface::get_edited_scene_root()` 的无保护解引用已在此进程 SIGSEGV 一次）。**否决** |
| | (B) `CryptoCore::b64_encode_str(ptr, size)` | 引擎内静态函数，无单例依赖，doctest 与线上一致。**采纳** |

## 6. 非功能性要求与应对

| 要求 | 应对 |
|---|---|
| 确定性（DESIGN-DETAIL §17.4） | 目录遍历返回**扫描序**并直接构造 `Array`；不得把 `HashMap` 迭代序放进响应；`tools/list` 用插入序（既有机制） |
| 只读安全 | 6 个工具只用 `FileAccess::READ`/`ResourceLoader::load`/`Image::load`；doctest 用「调用前后 fixture 文件列表逐字节不变」钉死 |
| 大对象风险（AC 极限） | `project_get_resource_preview` 的 base64 体积随图片增长：`max_size` 有默认 256、显式值 `<=0` → `-32602`；`project_read_script`/`_scene_file_content` 与迁移源一致**无截断**（保持契约，不发明上限） |
| 可维护性 | 助手单一事实源（AC-1）；新组文件独立，`registration.cpp` 每批只加一行（PLAYBOOK §17.1 串行纪律） |
| 兼容性 | 全部 `scope=BOTH`，不引入 `MCP_EDITOR_TOOLS_ENABLED` 依赖（本组无编辑器专有 API） |

## 7. 风险与回滚点

| 风险 | 影响 | 回滚点 |
|---|---|---|
| 助手上提时行为被无意改动 | 两个已实现组线上响应变化（最严重） | 提交按「重构」与「新组」分开；重构提交可单独 revert；AC-2 的逐字节证据是判定依据 |
| doctest 进程内 `GDScript` 编译不可用/崩溃 | `project_validate_script` 无法在 doctest 覆盖 | spike 先行；不可用则降级 (B) 并显式登记 |
| `Image::save_png_to_buffer` 在 doctest 进程不可用 | 预览工具测不到正例 | 若不可用，正例交给门② 真实证据，**不得**写假通过测试 |
| 门⑤ 硬编码计数 | 门⑤ 假失败 | 同步 `$ToolNames` 与计数常量；两次连跑 + PASS 清单一致 |
| fixture 与 port 9877 干扰 | 违反硬性纪律 | 门①/门⑤ 自带 pid 守卫；实现者启动前先探测端口占用 |

## 8. 用户确认点（决策者已裁定，交给用户复核）

1. 共享助手落点为**新文件 `tools/tool_helpers.{h,cpp}`**，去 `_` 前缀，4 个函数逐字保留语义。
2. `project_read_resource` 取**迁移源窄语义**（不发明属性字段）。
3. `accept_m1.ps1` 与 `docs/tool-groups.json` **允许**在本次改动面内更新（理由见 REQUIREMENTS §7/§8）。
4. `project_validate_script` 首选真编译校验，**spike 先行**，不可用则诚实降级。