# TASK-016 — DESIGN-OVERVIEW（阶段二工件，决策者维护）

## 1. 输入

`docs/spec/TASK-016/REQUIREMENTS.md`（已确认，含 Q1–Q7 裁决）。

## 2. 总体形状

本批**不新增架构层**：沿用 GDR-19 §17 的既有分层（`MCPToolRegistry` + `ToolBuilder` + `MCPToolError`
+ `content_result`），三件事各自映射到一个可独立提交、可独立验收的改动单元：

```
U1  助手上提（纯重构，零行为变更）
    tools/tool_helpers.{h,cpp}  <-- 新增两个共享定义
        ^              ^
        |              |
        |              +-- editor_read_scene_inspector.cpp   删除本地 _edited_scene_root
        +----------------- editor_write_scene_editor.cpp    删除本地 _find_node / _edited_scene_root
        +----------------- editor_node_write.cpp            删除本地 _find_node / _edited_scene_root

U2  editor_node_read（6 个，mutating=false，scope=editor）
    tools/editor_node_read.{h,cpp}  +  registration.cpp（include + 一行）+ manifest implemented=true

U3  editor_node_instantiate（4 个，mutating=true，scope=editor）
    tools/editor_node_instantiate.{h,cpp}  +  registration.cpp（include + 一行）+ manifest implemented=true
```

## 3. 模块划分与职责边界

| 模块 | 职责 | 明确不做 |
|---|---|---|
| `tools/tool_helpers.*` | 跨组**纯函数**共享件：路径拼装、序列化、原子写、编辑器守卫、节点解析、属性类型/写 | 不持有状态、不查单例的 IO 策略（`_edited_scene_root` 是唯一例外，它本就只是单例读取） |
| `tools/editor_node_read.*` | 6 个只读观察工具 + 为 doctest 可断言而导出的节点级入口 | 不写任何节点；不碰磁盘 |
| `tools/editor_node_instantiate.*` | 4 个「创建特定引擎类型节点」的写工具 | 不实现通用 `editor_add_node` 的语义（那是已验收的 B1 组）；只做类型特化 + 必要的默认值 |
| `tools/running_game_node_write.*` | 已有：`write_node_property`（一份定义） | 本批**不复制**第二份；U3 若需要属性写入一律复用它 |
| `tools/registration.cpp` | 唯一共享文件：每组一行 include + 一行注册调用 | 不改既有注册顺序 |

## 4. 关键接口与数据流

### 4.1 U1：上提后的共享签名（`namespace MCPTools`）

```cpp
// 编辑场景根：SceneTree::get_edited_scene_root()（编辑器持续同步的镜像），
// 不是 EditorInterface::get_edited_scene_root()（无 null 检查，doctest 进程实测 SIGSEGV）。
Node *edited_scene_root();
// 迁移源 node.rs:148-165 的 find_node： "." / 裸根名 -> 根；相对路径命中；带根名前缀重试。
Node *find_node(Node *p_root, const String &p_path);
```

命名去下划线：与 TASK-005/009/011 的既有上提体例一致（`game_current_scene` / `require_editor_ui`）。

### 4.2 U2：读族的数据流

```
tools/call(editor_get_node_properties)
  -> require_editor_ui(-32000)
  -> edited_scene_root()（null -> -32000 no edited scene）
  -> find_node(root, path)（null -> -32001 + suggestion）
  -> 属性表遍历（跳过 '_' 前缀与 "script"，见 4.4）
  -> serialize_variant（每值）
  -> content_result({node_path, type, properties})
```

其余 5 个工具同形：`require_editor_ui` → `edited_scene_root` →（有 `node_path` 者）`find_node`
→ 遍历/收集 → `content_result`。

### 4.3 U3：实例化族的数据流

```
tools/call(editor_add_scene_instance)
  -> require_editor_ui(-32000)
  -> edited_scene_root()
  -> find_node(root, parent_path)（null -> -32001）
  -> ResourceLoader::load(scene_path) -> PackedScene::instantiate()（失败 -> -32001/-32000）
  -> set_name(可选) / add_child / set owner=root
  -> content_result({node_path, scene_path, name})
```

`editor_add_raycast` / `editor_add_mesh_instance` / `editor_add_gridmap` 复用
`editor_node_instantiate.h` 内部的一个 `_add_typed_child(parent, node, name, root)` 与
U2 的 `find_node`，**不**复制解析语义；需要设属性的（gridmap 的 mesh_library）复用
`MCPTools::write_node_property`（`tools/running_game_node_write.h`）。

### 4.4 属性可见性规则（读族唯一有争议的一处）

迁移源 `node.rs:256`：`if name.starts_with('_') || name == "script" { continue; }`。
该规则**保留**（怪癖，PLAYBOOK §6.8），并与写族形成可解释的对称：写族通过
`write_node_property` 写 `script` 之类仍允许，读族只是不在**全量列举**里暴露内部/脚本属性。

与 TASK-016 §3 的「未知属性一律 -32001」不冲突：那条约束的是**调用方点名要求**的属性。

## 5. 备选方案与否决理由

| 方案 | 否决理由 |
|---|---|
| 上提时把 `_find_node` 改名为 `find_node` 并**同时**统一 `get_node_path` 与 `find_node` 的语义 | 迁移源里 `get_node_path`（精确匹配）与 `find_node`（含根名前缀重试）是两套语义，统一会改变已验收工具的行为；§1.4 明令不改行为 |
| 上提 `_relative_path` 一并共享 | 目前只有 1 份定义，无重复可消除；增加改动面而不降低重复 |
| 读族 `node_path` 回显原文（照迁移源） | PLAYBOOK §6.7 已裁定「归一后回显」，且回显解析后路径才能被门② 的链式调用直接喂回 |
| `properties` 过滤留空即回 `{}` | 任务书 §2.3 硬要求；这也是「静默成功」缺陷模式 |
| 把 10 个工具合成一个大组文件 | GDR-18：一组一个 `channel`+`scope`+`mutating`；读/写 `mutating` 不同，必须分文件 |
| `instantiate` 用 `ClassDB::instantiate` 通用路径 | `add_scene_instance` 走 `PackedScene`，`add_raycast`/`add_mesh_instance`/`add_gridmap` 有类型特化默认值（`RayCast2D/3D` 由 `dimension` 选、`GridMap` 要 `mesh_library_path`）；通用路径丢信息，且 `editor_add_node` 已覆盖通用场景 |

## 6. 风险与回滚点

| 风险 | 缓解 | 回滚点 |
|---|---|---|
| 上提改坏已验收 B1 行为 | A2 的 before/after 逐字节证明 + 门③/④；before 二进制来自重构前提交 | `git revert` U1 单个提交 |
| 删除本地副本漏掉一处调用 | 编译期必报（internal linkage 消失后未包含头即未声明）；`grep -c` 断言 | 同 U1 |
| doctest 计数断言（76/59/40）随注册增长失效 | 两个 U 各自更新 `tests/test_mcp_server.h` 的计数断言（这是**预期**的测试改动） | 同 U2/U3 |
| 读族 6 个工具在 doctest 里不可达（无 SceneTree） | 按既有体例：把节点级逻辑导出成 `MCPTools::*` 入口，doctest 直接断言裸 `Node` | 无 |
| scratch 工程 `.tscn` BOM 导致 `--import` `0xC0000005` | 用 `[IO.File]::WriteAllBytes` / `-Encoding utf8NoBOM`；显式校验 `--import` 退出码 | 无 |
| 9889 游戏端点起不来 | 沿用 `mcp015` 脚本既有做法；先做「端口未监听即声明不可构造」的诚实降级 | 无 |

## 7. 技术选型

不引入任何新依赖。全部用引擎既有 API（`Node`/`SceneTree`/`EditorInterface`/`PackedScene`/
`ResourceLoader`/`ClassDB`/`StringName`）。测试用仓库既有 doctest（`--test`）+ 既有 PowerShell 门脚本 +
`curl.exe`。理由：成熟、已在 76 个工具上验证过、零新增维护面。