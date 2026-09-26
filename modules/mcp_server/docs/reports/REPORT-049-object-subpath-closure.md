# REPORT-049 — TASK-049: the resource `properties` bag must take the engine's own property names (D8 closure)

> 任务书：`docs/tasks/TASK-049-object-subpath-closure.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`（§3 六道门、§4 报告格式、§7 纪律）。
> 缺陷：`mcp027` 的 `D8_whole_resource_bag_round_trips` 失败 —— 写 `glow_levels/1` 回
> `-32602 "Property name 'glow_levels/1' is not a settable property name"`，而**读侧刚刚产出的就是这个形状**
> → 与 GDR-25「读到的值必须能原样写回」（`DESIGN-DETAIL` §23.4 双向闭合规则）直接冲突。
>
> **结论锚点（D86：每条结论都标它被测出来的提交）**：
>
> | 锚点 | 值 |
> |---|---|
> | 二进制 `--version` | `4.8.dev.custom_build.319398189`（`--version` 只报 9 位） |
> | 提交（含本批实现与测试） | **`3193981897283b85a5b8851ff40548d32cdf85a0`** |
> | 被测提交（修复前红阶段） | `f07352c9d1`（`git rev-parse --short HEAD` 当时） |
> | 契约 | `docs/tools_list.renamed.json` **未被本批改动**（`git diff` 空），sha256 = `443f1df2e9a3c5b0a2ad1c4ce532a4cfb6f33d22d0401a02448a0ca0bede914f` |
> | 契约与 `c844ec8a…` 的关系 | 那个 sha 是 **TASK-043 之前的修订 `806d5396b`** 的（`scripts/mcp043_gates.ps1:36-37` 把它固定为契约 diff 的左侧基线），**不是**当前契约；当前契约自 `47b5008bac`（TASK-043）起就是 `443f1df2…`（三处 `git cat-file` 实测，见 §8.2） |
>
> `status: **done**` —— 修法 (a) 落地、红→绿、门①–⑥ 全过、回归全过；**一条遗留缺陷 F-1**（值形状，非名字形状）**按要求报给决策者，不在本批擅改契约**（§8.1）。
>
> **关于「二进制 == HEAD」**：所有证据产自 `319398189`（实现+测试提交 `3193981897…`）。本报告**自身所在的那个提交**
> （`docs(mcp_server): REPORT-049 …`，即本报告的 HEAD）**只加文档**：`git diff --name-only 3193981897..HEAD` =
> 本报告 + 本任务书（`git diff --stat … -- modules/mcp_server` 只有这两个 `.md`）。
> 因此该二进制与本报告的 HEAD **代码逐字节等价**，
> 只是 `--version` 字符串仍报 `319398189`；在 HEAD 重建会得到 `--version …<docs 提交前 9 位>…` 与**完全相同的行为**。
> 回归批次里 `mcp041/042/043` 的 summary 已逐字记下 `binary --version: 4.8.dev.custom_build.319398189` 与
> `git HEAD: 319398189`（当时两者相等）。

---

## 1. 缺陷、最小复现与根因（以引擎为准）

### 1.1 最小复现（可粘贴；真实请求/响应，`%TEMP%\task049-repro\evidence\`）

工程里放一个空 `Environment` 资源（`[gd_resource type="Environment" format=3]` + 空 `[resource]`），
9888 上先读后写：

```json
// A1: {"method":"tools/call","params":{"name":"project_read_resource","arguments":{"path":"res://environment.tres"}}}
// → 200, result.properties 里含 "glow_levels/1" = 0.0 … "glow_levels/7"
// A2: {"method":"tools/call","params":{"name":"project_edit_resource",
//      "arguments":{"path":"res://environment.tres","properties":{"glow_levels/1":1.5}}}}
```

修复前（f07352c9d1）实测响应：

```
code=-32602 message='Property name 'glow_levels/1' is not a settable property name: Object::set() takes a non-empty identifier'
```

修复后（319398189）：

```
code=0 changed['glow_levels/1'].new=1.5        (A_minimal_repro_is_taken)
properties['glow_levels/1'] = 1.5              (A_write_read_back_is_1_5)
a second process (game, port 9889) reads properties['glow_levels/1'] = 1.5   (C1, 全新进程读同一文件)
the saved .tres spells 1 'glow_levels/...' line(s): glow_levels/1 = 1.5      (C2, 文件真值)
```

### 1.2 根因（写侧多了一道本模块自造的门）

修复前的判定顺序（`tools/project_write_resource_scene.cpp`，提交 `f07352c9d1`）：

| 行 | 代码 | 说明 |
|---|---|---|
| `:147-149` | `static bool _is_settable_property_name(const StringName &p_name) { return String(p_name).is_valid_identifier(); }` | **自造的**名字形状门：`String::is_valid_ascii_identifier()`（`core/string/ustring.cpp:4354-4374`，只认 ASCII 标识符字符） |
| `:534-539` | `if (!_is_settable_property_name(key)) { … -32602 … return false; }` | **先**过这道门，**再**问对象有没有这个属性；`glow_levels/1` 在第一道门就被判死 |
| `:540-547` | `if (!names.has(key)) { … -32001 + suggestion … }` | 真正正确的判据（对象自己的属性表）被放在后面，永远轮不到 `/` 名字 |

消息文本本身也写着这条门的来源：`"…Object::set() takes a non-empty identifier"` —— 它**不是**引擎的判据，
是本模块 TASK-037 加给两个资源写工具的（`tools/project_write_resource_scene.h` 不变式 4）。

### 1.3 引擎的判据（`file:line` 证据链，第一参考源）

| 事实 | 依据 |
|---|---|
| `Object::set(name)` 按**对象自己的属性表**解析名字：`set_native()` 先查 `get_gdtype().members()`，命中 `GDType::Member::Property` 就把 `index`（`ADD_PROPERTYI` 的下标）作为第一个参数交给 setter | `core/object/object.cpp:349-393`（index 分支 `:364-368`）；`core/object/object.h:47-48`（`ADD_PROPERTY` / `ADD_PROPERTYI` 定义） |
| 该表就是所有读者枚举的那张表（`get_property_list()`），所以「读到的名字」与「`set()` 能收的名字」是同一个集合 | `core/object/object.cpp:395-427`（`get_native` 同表）；`core/object/class_db.cpp:1376-1394`（`get_property_list` 返回有序自身属性） |
| `Environment` 的 7 个 `glow_levels/N` 是**真实属性名**（不是数组属性）：`ADD_PROPERTYI(PropertyInfo(Variant::FLOAT, "glow_levels/1", PROPERTY_HINT_RANGE, "0,16,0.01,or_greater"), "set_glow_level", "get_glow_level", 0)` … `glow_levels/7`, index 0…6 | `scene/resources/environment.cpp:1464-1470`；setter/getter 收下标：`:618-621` / `:624-629` |
| 引擎里**没有** `glow_levels` 这个属性（读侧「卷成数组」的形状是凭空发明的，不是引擎语义） | 同上：只有 `glow_levels/N`；`environment.cpp:1642-1649` 里 `glow_levels` 只是 C++ 私有成员 `PackedFloat32Array` |
| `ShaderMaterial` 的 `shader_parameter/<uniform>` 是**逐实例**名字（`_get_property_list()` 按该实例持有的 shader 的 uniform 列表生成），所以任何「类级枚举」都不可能是完整判据 | `scene/resources/material.cpp:248-358`（`:341` 加前缀 `shader_parameter/`） |
| 检查器分组/分类标签（`ADD_GROUP`/`ADD_SUBGROUP`/`ADD_CATEGORY`）**在属性表里但不在成员表里**：`ClassDB::add_property_group` 只调用 `add_to_ordered_properties` | `core/object/class_db.cpp:1300-1311`；`Object::get_property_list` 会带上它们（所以读者必须按 `property_is_label` 跳过：`tools/tool_helpers.cpp:2322-2327`） |
| 关节的 `/` 名字同样是真实属性（`params/bias`、`angular_limit/upper` …） | 现场普查结果见 §4（`ClassDB` 实测） |

### 1.4 读侧到底产出什么形状（实测，不含推断）

`project_read_resource`（`tools/project_read_files.cpp:388-454`）把 `get_property_list()` 里
带 `PROPERTY_USAGE_STORAGE` 的**每一个**名字按引擎原拼写塞进 `properties`：

```
A1 实测（9888）：the reader answered 64 keys (101 stored total, truncated=True dropped=37);
                 the '/' names are: glow_levels/1 … glow_levels/7
A_read_side_does_not_roll_the_sub_paths_up: 'glow_levels' is not a key of the answer: True
```

即：**只有 `glow_levels/1`…`glow_levels/7` 这种形状，没有 `{"glow_levels":[…]}` 这种形状**；
`Environment` 存储属性共 101 个，读者的 64 条上限（`MAX_RESOURCE_PROPERTIES`，`project_read_files.cpp:386`）
使这次「整包」实际是 64 个键（**登记为残留，见 §8.3**）。

---

## 2. 修法：选 (a)「写侧接受引擎自己的名字」，理由逐条

任务书 §1.3 给了二选一。选 **(a)**，判据是 §1.3/§1.4 的三条引擎事实：

1. **读侧的形状已经是引擎的形状**。`glow_levels/1` 是 `ADD_PROPERTYI` 的**字面属性名**，`.tres` 文件里存的
   也是这个拼写（§5 C2 实测 `glow_levels/1 = 1.5`）。改读侧就变成「模块自己发明一个与引擎/文件都不同的形状」。
2. **不存在可以「卷」出来的目标形状**。`glow_levels` 不是属性（§1.3 第 4 行），所以 (b) 的「读侧改产出数组」
   必须**同时**在写侧发明一个「整数组替换」的入口 —— 那是新增一个引擎没有的写路径，而不是闭合既有的一对。
3. **(a) 是把写侧对齐到本模块已有的规则，不是新开例外**。节点写族（`editor_set_node_property` /
   `running_game_set_node_property` / 跨场景写）从来就按「对象有没有这个属性」判（`MCPTools::object_has_property`，
   `tools/tool_helpers.cpp:1385-1397`），所以它们在**同一个名字形状**上本来就是闭的（§5 D2/D3 实测
   `HingeJoint3D.angular_limit/upper` 读得到、写得进、再读相等）。缺陷恰恰是两个**资源**写工具多背了一道
   `is_valid_identifier`。

### 2.1 落地后的精确规则（`tools/project_write_resource_scene.cpp`）

一个 `properties` 键的判定，按顺序：

1. **空名** → `-32602`（`Object::set()` 无法寻址一个无名属性；这是参数错）。
2. **只在属性表里以「检查器标签」出现**（`PROPERTY_USAGE_GROUP/SUBGROUP/CATEGORY`）→ `-32602`，消息点名
   「是分组/分类标签，不是属性，没有值也没有 setter」（与节点读者 TASK-032 D3 的判定同口径）。
3. **对象自己的属性表里有这个名字**（`Object::get_property_list()`，非标签）→ **接受**，值照旧走
   `property_value_from_json → shape_vector_from_json → coerce_to_property_type` 一次收窄门，再 `Object::set()`；
   写后回读、`changed` / `properties_set` / `ignored` 三件套**逐字不变**（TASK-037 D2 / `DESIGN-DETAIL` §20.6）。
4. **表里没有** → 若名字**不是**标识符（`:` 子属性路径、`a.b`、`a[0]`、含空格、`metadata/*`）→ `-32602`；
   若是标识符 → `-32001` + `data.suggestion`（TASK-014 D-1 形状）。**这两种拒绝逐字保留**。

即：**判据从「名字长得像标识符」换成「对象自己的属性表」**；`is_valid_identifier` 只降级为第 4 步的
「这到底算不算一个名字」的兜底（`MCPTools::resource_bag_name_is_addressable`，导出给 doctest 钉住两半）。

「**不得只放宽检查而不保证写后等价**」这一点没有被牺牲：接受某名字之后，是否真的写进去仍由写后回读决定
（`_stored_value_matches_request`，差异进 `ignored` 并给 `requested/stored/reason`）。§5 的 B2 实测
64/64 键在 `changed` 里回读等于读到的值、`ignored` 为空、7 个 `/` 名字都在 `properties_set` 里。

### 2.2 收窄点（门⑥ 三段式：**本批新增 0 个**）

改动只碰**名字判定**，没有新增/移动任何 `double → float/real_t` 收窄：
`git diff` 里 `project_write_resource_scene.cpp` 的收窄点只有既有的 `G24-RESOURCE-SET-WIDTH`
（比较用宽度，TASK-023 D-7）。门⑥a 的 `scanned=75 pinned=75` 与修复前一致（REPORT-048 亦为 75/75），
唯一差别是它把**本文件**那一条的行号从 `190` 报告为 `238`（我在这条之上插入了新代码）——
这是该脚本声明的**信息性**附注（按 marker id + occurrence 匹配，报告行号漂移不算失败），
沿用 REPORT-048 的处理（不手改共享门脚本），并在 §6 逐字记录。

### 2.3 为了让规则可被机器钉住而做的导出（不是契约变更）

`_write_resource_properties`（file-static）→ **`MCPTools::write_resource_properties`**（头文件声明），
另导出 `MCPTools::resource_bag_name_is_addressable`。理由与 `MCPTools::set_project_setting`、
`MCPTools::write_node_property`、`MCPTools::read_named_properties` 完全同源：**doctest 要能在没有活的工程文件时
直接喂一个 `Resource` 给这条规则**（本缺陷能活到现在，正是因为这条规则以前在 doctest 里不可达）。
工具响应形状、契约、`tools/list` 均**零变化**（门① 逐字 3/3，见 §6）。

---

## 3. 红 / 绿（真实输出）

### 3.1 红（`f07352c9d1`，tests 先行；`build_local.cmd -Force` 后

```
bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="*TASK-049*"
[doctest] test cases:  3 |  0 passed | 3 failed | 1722 skipped
[doctest] assertions: 17 | 11 passed | 6 failed |
[doctest] Status: FAILURE!
```

关键失败（因**缺行为**而失败，不是编译错）：

```
23347: ERROR: CHECK( !error.is_error() )  中红
  logged: writing 'glow_levels/1' alone: code -32602: Property name 'glow_levels/1' is not a settable property name: Object::set() takes a non-empty identifier
23263: ERROR: the bag the reader answered was refused: code -32602: Property name 'glow_levels/1' …identifier
23362: ERROR: 64 of 64 keys of the reader's own bag did not close
23392: ERROR: the bag the reader answered was refused: code -32602: Property name 'shader_parameter/albedo' …identifier
```

（红阶段的第三个用例当时用**真** `HingeJoint3D`，在 doctest 进程里因 `PhysicsServer3D` 不可用而 SIGSEGV；
这是**测试夹具**的问题不是实现的问题，绿灯前改成同文件自有的 `Node3D` 子类 `Task049::SubPathNode`
把「规则」钉住，真关节的闭环改由线上 9888 证据覆盖 —— 与 TASK-028 当年为 `v4:x` 用 `CompoundHolder` 同法。）

### 3.2 绿（`319398189`）

```
bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="*TASK-049*"
[doctest] test cases:  4 |  4 passed | 0 failed | 1722 skipped
[doctest] assertions: 53 | 53 passed | 0 failed | 0 failed
[doctest] Status: SUCCESS!          (exit 0)
```

四个用例：

| 用例 | 钉住什么 |
|---|---|
| `TASK-049 D8: the resource bag the reader answered is written back as it is` | ①`Environment` 整包（读侧答出的 64 键原样喂回）**逐键**三层等价；②单键 `glow_levels/1` 最小复现；③前置断言「读侧答出的确实是 `/` 形状、且**没有** `glow_levels` 卷起键」 |
| `TASK-049 D8: a per-instance 'shader_parameter/<uniform>' name round-trips too` | 逐实例名字（类级枚举够不到）同样闭合；**并且**钉住 F-1 边界：`null` 写非 Object 属性 → `-32602` 且**文件 sha 不变** |
| `TASK-049 D8: a node property name of the same shape is closed on both sides` | 节点写族的同一规则（读得到 `params/bias` → 写得进 → 再读相等 → 对象真的持有 2.0） |
| `TASK-049: the engine's non-identifier property names are an enumerated family, and the fallback stays narrow` | 引擎普查（`ClassDB`，984 条非标识符**属性**名 / 189 条标签）+ `ProjectSettings` 实例级普查（≥100 条 `/` 键）+ 兜底判据两半（`glow_levels/1` 兜底答 false、`script` 答 true、`a:b`/`a.b`/`a[0]`/`metadata/*`/空名答 false） |

---

## 4. 同类排查：「读侧能产出、写侧不接受」的名字形状（机器普查 + 逐条处置）

普查方式：9888 上 `editor_execute_gdscript` 跑 `ClassDB.get_class_list()` × `class_get_property_list(c, true)`，
按 `is_valid_identifier()` 与 `PROPERTY_USAGE_GROUP|SUBGROUP|CATEGORY` 分类（脚本 `F1/F2` 段，原始响应落盘 + sha256）。

**实测（319398189，`F1/F2`）**：

```
non-identifier *property* names: 984; inspector labels: 189; Environment glow_levels entries: 7
shapes (real properties only): slash=984 dot=0 colon=0 bracket=0 empty=0 space=0 other=0
```

即**类级**非标识符属性名**全部是 `/` 形状**，分布在 9 个类：

| 类 | 条数 | 例 |
|---|---|---|
| `AnimatedTexture` | 512 | `frame_0/texture`、`frame_0/duration` |
| `AudioStreamInteractive` | 252 | `clip_0/name`、`clip_0/next_clip` |
| `Generic6DOFJoint3D` | 90 | `linear_limit_x/upper_distance`、`angular_limit_y/erp` |
| `AudioStreamSynchronized` | 64 | `stream_0/volume`、`stream_0/stream` |
| `AudioEffectChorus` | 24 | `voice/1/delay_ms`、`voice/4/cutoff_hz` |
| `SliderJoint3D` | 22 | `linear_ortho/damping`、`angular_limit/lower_angle` |
| `HingeJoint3D` | 10 | `angular_limit/upper`、`params/bias` |
| `Environment` | 7 | `glow_levels/1` … `glow_levels/7` |
| `PinJoint3D` | 3 | `params/bias`、`params/damping`、`params/impulse_clamp` |

**实例级**（类级普查看不见的两类，正是「判据必须是对象自己的表」的理由）：

| 形状 | 读工具 → 写工具 | 处置 |
|---|---|---|
| `shader_parameter/<uniform>`（每个 `ShaderMaterial` 按自己 shader 的 uniform 生成） | `project_read_resource` → `project_edit_resource` | **本批修复**（§3.2 用例 2、§5 B4/B6） |
| `application/config/name` 等 `ProjectSettings` 键（单例在启动时建表） | `project_get_settings` → `project_set_setting` | **本来就闭合**：写侧只拒空白键（`tools/project_setting_write.cpp:142-145`），实测 37 个 `application/*` 键读写往返（§5 D5/D6） |

**逐形状处置表**（任务书点名的 `/`、`.`、`[i]`、下标、`:`）：

| 形状 | 读侧会不会产出 | 处置 | 证据 |
|---|---|---|---|
| `/`（属性名） | **会**（984 条类级 + 实例级 2 类） | **本批接受**（属性表成员） | §3.2/§5 A/B/D |
| `/`（`ProjectSettings` 键） | 会 | 已闭合，不动 | §5 D5/D6 |
| `/`（`metadata/foo`） | **不会**（`Object::get_property_list()` 不枚举 metadata；模块也没有读者答它） | 保持 `-32602`（**显式登记的边界**，不是遗漏）；节点写族另侧为了 `metadata/*` 走 `Object::set` 的前缀分支 | 源注释 + §3.2 用例 4 |
| `:`（子属性路径 `material:albedo_color`） | **不会**（类级/实例级普查里 `colon=0`） | 资源包**保持** `-32602`（消息明说「节点写者收 `:` 路径，资源包收引擎自己的名字」）；节点写族本来就走 `Object::set_indexed`（TASK-028 G-1） | §5 E4 + REPORT-028 |
| `.`、`[i]`、下标、含空格 | **不会**（`dot=0 bracket=0 space=0`，非标识符属性名 100% 是 `/`） | 保持 `-32602`（参数形状错）；另：`"not a property"` 这类名字本来就在 TASK-037 的 `-32602` 契约里 | §5 E1 + §3.2 用例 4 |
| 空名 | 不会（空名条目**全是**标签，已被过滤） | `-32602`（专用消息） | §5 E2 |
| 其他「读侧产出、写侧不接受」的**值**形状（非名字） | — | **发现 F-1，报决策者**（§8.1） | §5 B7/B8 |

---

## 5. 线上证据（门②）：`scripts/mcp049_subpath_closure_evidence.ps1`，**35/35 PASS，exit 0**

二进制 `319398189`；证据目录 `%TEMP%\task049-subpath-closure\evidence`（每个响应 `curl.exe -s -o` 落盘 + sha256，
日志 `evidence.log.txt`，本次 log sha256 = `9fe2314b1c89b90a421274509ecf0cdf682199e90065d21863bc99170cfcbe5d`）。
门②要求的「三类证据」与「跨工具活证据链」都在其中：

**成功类**（真实响应片段）

| id | 结论 |
|---|---|
| `A_read_side_answers_sub_path_names` | 读侧答 64 键（101 存储属性，truncated/dropped 如实报告），`/` 名字恰为 `glow_levels/1..7` |
| `A_minimal_repro_is_taken` | `code=0 changed['glow_levels/1'].new=1.5`（修复前同请求是 `-32602`） |
| `A_write_read_back_is_1_5` | 再读 `properties['glow_levels/1'] = 1.5` |
| `B1_whole_bag_is_taken_as_read` | 64 键整包原样喂回：`code=0` |
| `B2_level2_changed_is_the_read_back_truth` | **64/64** 键 `changed[].new` == 读到的值（`<none>` 不匹配） |
| `B2_no_key_was_ignored` | `ignored` 为空（没有「接受但没写进去」） |
| `B2_sub_path_keys_are_reported_as_set` | `properties_set` 含全部 7 个 `/` 名字 |
| `B3_level3_reread_equals_what_was_read` | 再读 64 键与第一次读**逐键**相等（`<none>` 差异） |
| `B6_shader_bag_round_trips` | `ShaderMaterial` 整包（含 2 个 `shader_parameter/*`）：`code=0`、0 个不匹配键 |
| `D2/D3` | 节点族：`editor_get_node_properties` 答 `angular_limit/upper=1.5707963267949`、`params/bias=0.3`；写 `42.5` → `code=0 new_value=42.5` → 再读 `42.5` |
| `D5/D6` | 设置族：37 个 `application/*` 键（全 `/` 形状）；写 `application/config/name` → `code=0` → 再读同值 |
| `C1` | **全新游戏进程（9889）**读同一 `.tres`：`glow_levels/1 = 1.5`（文件真值，与编辑器进程的资源缓存无关） |
| `C2` | 落盘文件确实写着 `glow_levels/1 = 1.5` |

**缺参/参数形状失败类**：`E1` `"not a property"` → `-32602`（消息点名「既不是 `Object::set()` 收的标识符，
也不是 `Environment` 自己的属性表条目，`glow_levels/1` 这类表内名字会被原样接受」）；`E2` 空名 → `-32602`；
`E4` `glow_levels:1` → `-32602`（`:` 路径仍不收）。

**底层失败类**：`E3` `no_such_property_xyz` → `-32001` + `data.suggestion`（逐字保留 TASK-014 D-1 形状）。

**跨工具活证据链（0 次字符串手术）**：`A1 read`（响应）→ `B1 write`（**把响应里的 `properties` 对象原样当参数**）
→ `B3 read`（同一 `.tres`）→ `C1 read`（另一个进程）；链上无一处对响应做 `Split/Replace/Substring/Trim`；
唯一的字面量是调用方自己选的资源地址 `res://environment.tres`。

**端口纪律**：`port_9877_guard` = `pass=True listening=False pid_before=-1 pid_after=-1 ours=False same_pid=True
asked_by_us=False classification=environment_fact_no_listener_before_or_after our_pids=[52352,72264] our_ports=[9888,9889]`；
`port_9888/9889_free_after` 均 PASS。

---

## 6. 六道门（真实输出与退出码；二进制 `319398189`）

| 门 | 命令 | 结论 | 关键输出 |
|---|---|---|---|
| ① 契约子集逐字 | `check_contract_subset.ps1 -Group project_write_resource_scene` | **exit 0，3/3 PASS** | `PASS editor_9888_contract_subset`（148 工具）、`PASS game_9889_contract_subset`（69 工具）；四个工具在两端点 `name=True description=True inputSchema=True`；`guard_user_port_9877 PASS`。契约文件 **未改**（sha `443f1df2…`） |
| ② 三类证据 + 活链 | `mcp049_subpath_closure_evidence.ps1` | **exit 0，35/35 PASS** | §5 |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **exit 0** | `test cases: 297 \| 297 passed \| 0 failed \| 1429 skipped`；`assertions: 21484 \| 21484 passed \| 0 failed`（REPORT-048 基线 293 / 21431：**+4 用例 / +53 断言，全部来自本批**） |
| ④ 全引擎回归 | `--headless --test` | **exit 0** | `test cases: 1723 \| 1723 passed \| 0 failed \| 3 skipped`；`assertions: 445766 \| 445766 passed \| 0 failed`（基线 1719 / 445713：同为 +4 / +53，0 failed 不变） |
| ⑤ 收口 | `accept_m1.ps1` 连跑两次 | 见 §7.2 | 两次 PASS 清单一致 |
| ⑥ 收窄点三段 | `python scripts\check_narrowing_points.py`；`--coverage`；`powershell -File scripts\mcp031_gate6_coverage_probes.ps1` | **三段 exit 0** | a: `scanned : 75 narrowing point(s) in 16 file(s)`；`pinned : 75`；b: `coverage : 17 declared spelling(s)`，集合内每种拼写都有探针；c: **101/101 checks passed**，`log sha256=a1515e0a465f0c910e34580b4fb66764a81218701b34ad37411a501f059a64d8`。**本批新增收窄点 0 个**；a 段信息性附注由 10 条变 11 条（新增的正是 `tools/project_write_resource_scene.cpp` 的 `G24-RESOURCE-SET-WIDTH` 行号 190→238，因为我在它上方插了代码；按 marker id + occurrence 判定，非失败，沿用 REPORT-048 的处理） |

---

## 7. 回归（任务书点名）

### 7.1 点名脚本

| 脚本 | 结论 | 说明 |
|---|---|---|
| `mcp027_object_shape_and_paths_evidence.ps1 -Phase green` | 见 §7.3 | **本缺陷的原始现场**：`D8_whole_resource_bag_round_trips` 现在通过 |
| `mcp019_b4_evidence.ps1` | 见 §7.3 | B4 测试/断言族 |
| `mcp010_b2_observation_evidence.ps1 -Phase game/-Phase scope/-Phase count` | 见 §7.3 | B2 观察组三相位 |
| `mcp041_gates.ps1` / `mcp042_gates.ps1` / `mcp043_gates.ps1` | 见 §7.3 | 三套 gate battery（各含门③④的复跑与描述/契约/端口探针） |

### 7.2 门⑤ `accept_m1.ps1` 两次

见 §7.3（`%TEMP%\task049-regress\summary.txt`）：两次 PASS 清单一致。

### 7.3 实测输出（真实日志 `%TEMP%\task049-regress\`，二进制 `319398189`）

`%TEMP%\task049-regress\summary.txt`（逐字）：

```
TASK-049 regression battery
binary --version: 4.8.dev.custom_build.319398189
git HEAD: 319398189                    <- 见下注
STEP mcp027 EXIT 0
STEP mcp019 EXIT 0
STEP mcp010_game EXIT 0
STEP mcp010_scope EXIT 0
STEP mcp010_count EXIT 0
STEP mcp041_gates EXIT 0
STEP mcp042_gates EXIT 0
STEP mcp043_gates EXIT 0
STEP gate5_accept_run1 EXIT 0
STEP gate5_accept_run2 EXIT 0
DONE
```

> 注：批次脚本里 `for /f` 抓 `git rev-parse --short=9 HEAD` 的那行在 cmd 下没抓到（`git HEAD:` 后面是空行，
> stdout 上出现一次 `fatal: Needed a single revision`）——**这是批次脚本自身的取数瑕疵，不是被测脚本的失败**：
> 每个门脚本自己打的 `git HEAD: 319398189` 与 `binary --version` 都正常（见 mcp041/042/043 的 summary）。
> `319398189` 就是本批提交 `3193981897283b85a5b8851ff40548d32cdf85a0` 的前 9 位。

| 回归 | 真实结论 |
|---|---|
| `mcp027 -Phase green` | **60/60 checks passed**；**`D8_whole_resource_bag_round_trips` 由 FAIL 转 PASS**，其余 D8 项（`D8_resource_*` 9 条）保持 PASS。证据 `%TEMP%\task027-object-and-paths-green\evidence` |
| `mcp019` | `TASK-019 evidence summary: 66 checks, 66 passed, 0 failed` |
| `mcp010 -Phase game` | `=== phase game: 29/29 checks passed ===` |
| `mcp010 -Phase scope` | `=== phase scope: 15/15 checks passed ===` |
| `mcp010 -Phase count` | `=== phase count: 12/12 checks passed ===` |
| `mcp041_gates.ps1` | **17/17 STEP EXIT 0**（含 gate1/3/4/5×2/6a/6b/6c + mcp032–036 + probe037 + mcp040×2）；`git HEAD: 319398189`；收尾工作树只剩既有未跟踪物 + 本报告/任务书 |
| `mcp042_gates.ps1` | **19/19 STEP EXIT 0**（含 gate1/3/4/5×2/6a/6b/6c + rewrite/port-guard/task041 证据 + mcp032–036 + probe037 + mcp040×2） |
| `mcp043_gates.ps1` | **28/28 STEP EXIT 0**（含契约快照 `gate2f`、4 个组门①、gate3/4/5×2/6a/6b/6c、描述/reload/契约 diff 探针 + mcp032–036 + mcp040×2） |
| 门⑤ `accept_m1.ps1` run1 / run2 | **各 22 PASS / 0 FAIL，两次 PASS 清单逐字相同（`pass lists identical: True`）**；`guard_user_port_9877` 两次都在 PASS 清单里 |

> 说明：mcp041/042/043 三套 gate battery **各自内部又跑了 `accept_m1` 两次**（`STEP gate5_accept_run1/run2 EXIT 0`，
> 各 48–49 s）——所以本批合计 `accept_m1` **共 8 次全过**，其中报告里点名的「连跑两次」是 `%TEMP%\task049-regress\`
> 里那两次（各自独立进程、独立直跑）。

---

## 8. 发现、遗留与对规范的偏差

### 8.1 发现的相邻缺陷 **F-1（值形状，报决策者，未修）**

**现象**（319398189 实测，既可复现于 9888 也可复现于 doctest）：

```
B7_unset_uniform_reads_null:      shader_parameter/albedo = null; shader_parameter/uv1_scale = null
B8_null_for_a_non_object_property_is_refused_and_writes_nothing:
  code=-32602 message='Parameter 'properties' cannot be written to a Vector3 property: the value is a Nil (null)…
     type_convert would answer {"x":0.0,"y":0.0,"z":0.0} …'
  file sha256 before=10d8d2a4ccda after=10d8d2a4ccda
```

**机制（引擎侧）**：`ShaderMaterial::_get_property_list()` 对「从未赋值」「类型与 uniform 不符」的 uniform 会去要
引擎的默认值 `RenderingServer::shader_get_parameter_default()`（`scene/resources/material.cpp:342-347`）；
`--headless` 进程的渲染服务器给不出默认值 → `param_cache` 里是 `null` → 读侧如实答 `null`。
写侧对**非 Object** 属性收到 `null` 会拒绝（`coerce_to_property_type`：`Variant::can_convert(NIL→Vector3)` 不成立，
`type_convert` 会把无值对象变成 `{0,0,0}`，即「静默写默认值」——这正是 TASK-020/021/022 要消灭的形状），
于是「读到的 `null`」写不回去 → 严格按 GDR-25 §23.4 算**未闭合**。

**为什么不在本批修**：修它必须动**值**语义（要么读侧替引擎编一个默认值，要么写侧为 `null` 开一个「清除/不写」
的语义），两者都会碰到契约描述与「不得静默写默认值」的既有判据 → 属于设计决策，任务书 §1.5 明确要求
「要改描述就停下来报我」。**建议（供决策者裁决）**：优先方案是**读侧**——`null` 只在「声明的类型是
`Variant::NIL` 或 `OBJECT`」时是诚实答案，其余情形应给出引擎的**声明默认**
（`PropertyInfo` 的默认值 / `ClassDB::class_get_property_default_value`；对 shader uniform 则是
`shader_get_parameter_default` 不可用时的 uniform 字面默认），并把「引擎答不出默认」显式报告为字段
（例如 `unset_properties: [...]`），而不是答一个写不回去的 `null`。
本批只把它**钉成机器可判的边界**（doctest 用例 2 末段 + 线上 `B7/B8`），并在 §4 表里登记。

### 8.2 对 REPORT-048 一处引用的澄清（避免把旧锚点当现值）

REPORT-048 §1.3 记录 `mcp043 gate2f_snapshot_before_contract` 的输出为
`806d5396b:…tools_list.renamed.json sha256=c844ec8af9ef… (expected c844ec8af9ef…)`。
这是**正确**的：`c844ec8a…` 是**修订 `806d5396b`**（TASK-043 之前）的 sha，被 `scripts/mcp043_gates.ps1:36-37`
固定为契约 diff 的左侧基线。**当前**契约的 sha 是 `443f1df2e9a3c5b0a2ad1c4ce532a4cfb6f33d22d0401a02448a0ca0bede914f`
（实测：`806d5396b` → `c844ec8a…`，`47b5008bac`（TASK-043）→ `443f1df2…`，`HEAD` → `443f1df2…`）。
写在这里是为了下一次读报告的人不会把两者混为「契约变了」。

### 8.3 登记残留

1. **`project_read_resource` 的 64 键上限**（`MAX_RESOURCE_PROPERTIES`，`tools/project_read_files.cpp:386`）：
   `Environment` 有 101 个存储属性，mcp027 的名字叫「whole resource bag round trips」，实际往返的是**64 个键**
   （响应里 `truncated:true dropped:37` 是诚实的）。本批**不动**这个上限（它在 TASK-026 里被登记为上限残留，
   改它属于行为放大，需要决策者同意）。**报告措辞建议**：把 mcp027 的用例 id 或消息改成「the bag the reader
   answered」，以免「whole bag」被读成 101 个属性。
2. **`metadata/*`**：读侧不产出、写侧 `-32602`（§4 表）——显式边界，不是遗漏。
3. **资源包的 `:` 路径**：不支持（§4 表）；若要 G-1 对等，属独立批次（需要分量槽位判定，会新增收窄点）。

---

## 9. deviations / blockers / next_step_recommendation

**deviations（与任务书/手册的偏离，逐条）**

1. 任务书 §1.3 让我二选一；我选 (a)，理由写在 §2（不是「随手选一个」）。
2. 任务书没要求导出内部函数；为了让规则**可被机器钉住**，把 `write_resource_properties` 与
   `resource_bag_name_is_addressable` 导出（§2.3）。工具响应/契约零变化（门① 3/3 逐字）。
3. 红阶段第三个用例起初用真 `HingeJoint3D`（会 SIGSEGV），改成同文件自有 `Node3D` 子类；
   真关节的闭环改由线上证据覆盖（§3.1、§5 D2/D3）。
4. 回归批次的门⑤/回归输出只在 §7.3 逐字填「跑过的」；未跑的绝不推断（D86）。
5. 没有新建任何竞争性规范文档；报告只有这一份（PLAYBOOK §7.2）。

**blockers**：无（9877 全程 `listening=False`，`asked_by_us=False`；构建串行、未抑制输出；未 push）。

**next_step_recommendation**

1. 决策者对 **F-1** 做裁决（§8.1 建议方案：读侧给「声明默认」+ 显式 `unset_properties` 字段），
   若同意则单开一批（会动 `project_read_resource` 的响应形状 → 需要契约描述 override）。
2. 顺手把 mcp027 的 `D8_whole_resource_bag_round_trips` 名字/消息改成「the bag the reader answered」（§8.3-1），
   避免 64/101 被读成「整包」。
3. 若希望 `metadata/*` 或资源包的 `:` 路径也闭合，按 §8.3-2/3 单开批次。

---

## 10. 文件 sha256 与提交锚点

| 文件 | sha256（319398189） |
|---|---|
| `modules/mcp_server/tools/project_write_resource_scene.cpp` | `987c068cfd800b0bcf572afc929411091724496116a04d1d7a1da29a7f416636` |
| `modules/mcp_server/tools/project_write_resource_scene.h` | `9e47a4f384ebb2cdf491d8826f9578b66e7b967a89d5095deb3909172f69a8ec` |
| `modules/mcp_server/tests/test_mcp_server.h` | `ebaa7546e63116ad0d2d974ca30eb71eaf682721614deeb11faea3ec3298f162` |
| `modules/mcp_server/scripts/mcp049_subpath_closure_evidence.ps1`（新） | `2dc8b7ea4c6e1c466fd7ef22c9c5213c620abf7b70961ad61a9f08963f05db84` |
| `modules/mcp_server/docs/tools_list.renamed.json`（**未改**） | `443f1df2e9a3c5b0a2ad1c4ce532a4cfb6f33d22d0401a02448a0ca0bede914f` |

| 提交 | 一行说明 |
|---|---|
| `3193981897283b85a5b8851ff40548d32cdf85a0` | `fix(mcp_server): let the resource property bag take the engine's own property names (TASK-049)`（实现 + 4 个 doctest + 线上证据脚本） |
| （本报告所在提交） | `docs(mcp_server): REPORT-049 (TASK-049)`；报告自身即 HEAD，故正文不引用自己的 sha |
