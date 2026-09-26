# REPORT-034 · B5 批次 2：音频 / 粒子 / 主题 / 3D 材质 / 导航 / 性能 15 个工具 + 4 处 schema 缺口

- 任务书：`docs/tasks/TASK-034-b5-audio-particle-theme.md`
- 手册：`docs/tasks/PLAYBOOK-group-port.md`
- 代码锚点（D86）：`fc724ce49a5645250590ad7848e146d2cb617379`；`--version` = `4.8.dev.custom_build.fc724ce49`
- 构建：`modules/mcp_server/scripts/build_local.cmd -Force`（`tests=yes`），日志 `%TEMP%\mcp_server_build_local.log`，最后一次 `exit code = 0`
- 结论：**范围①②全部落地，六道门全绿**；1 处实现缺陷（advance_condition 写入顺序）由本批次门②在其证据里抓出并已修复；3 项需上报、未擅自改契约的缺陷见 §7

---

## 1. 范围与结果

| 范围 | 内容 | 结果 |
| --- | --- | --- |
| ① | 4 处 schema 缺口走 `SCHEMA_OVERRIDES` 再生契约 | ✅ 契约 sha256 `bc8c37a0…fdf27`，`generator_version=1.9.0`，`overrides` 14 → 17 |
| ② | 8 组 15 个工具 | ✅ 全部注册、可调用、三态证据齐备（§6.2） |
| ③ | `docs/tool-groups-b5.json` 仅改 8 个 `implemented` 布尔 | ✅ 文件 sha256 `0d079762…f3faf`（12020 B） |
| ④ | 门①–⑥ + 回归（mcp030 / mcp032 / mcp033） | ✅ 全部通过（§6） |

**B5 进度**：本批次前 14/58 工具、3/26 组；本批次 +15 工具、+8 组 → **29/58 工具、11/26 组**（`editor_audio_write` 4、`editor_particle_write` 4、`editor_audio_read` 2、`editor_particle_read` 1、`editor_theme_write` 1、`editor_scene_3d_write` 1、`editor_navigation_read` 1、`editor_profiling_read` 1）。

进程口径：编辑器端点 142 个注册工具 / 120 个可见；游戏端点 53 / 53（本批 15 个全部 editor-scope，游戏端点 `tools/call` 答 `-32601`）。测试端口 9888/9889；用户自己的编辑器 9877（pid 36392）在每次运行前后被断言 pid 不变，全程未触碰。

---

## 2. 契约、4 处 schema 缺口与「不可达 → 可达」

### 2.1 结构化 diff（HEAD 契约 vs 再生契约）

`git show HEAD:modules/mcp_server/docs/tools_list.renamed.json` 与工作区文件逐字段比对（脚本 `%TEMP%\task034\diff_contract.py`，输出 `%TEMP%\task034_contract_diff.txt`）：

- 两侧都 171 个工具、`result.tools[].name` 集合完全一致、顺序一致；
- `inputSchema` 只有 3 个工具变化，正是任务书 §0 的四个成员：

| 工具（旧名） | 新增成员 | 新增理由（契约 `_meta.overrides[].reason` 摘要） |
| --- | --- | --- |
| `add_state_machine_state` → `editor_add_state_machine_state` | `animation` | 迁移源有 `animation`，`AnimationNodeAnimation::set_animation` 是**声明式**成员，契约未声明则该参数不可达，新建 Animation 状态永远指不到动画 |
| `set_blend_tree_node` → `editor_set_blend_tree_node` | `animation` | 同上，`bt_node_type=Animation` 时该节点的动画 |
| `add_state_machine_transition` → `editor_add_state_machine_transition` | `xfade_time` / `priority` / `advance_condition` | 分别对应 `set_xfade_time`（`animation_node_state_machine.h:86`）、`set_priority`（:98）、`set_advance_condition`（:78），此前**没有任何工具可写** |

- 其余差异只有 `_meta.generator_version`（1.8.0 → 1.9.0）与 `_meta.overrides`（14 → 17）两处；
- `_meta.map_sha256` **未变**：`2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd`（`docs/tool-rename-map.json` v1.1 未改）；
- 三个 override 都是 `mode=replace`，`reason` 逐字引用被同步更新的 `required` 成员（`["node_path", "state_name"]`、`["node_path", "blend_tree_state", "bt_node_name", "bt_node_type"]`、`["node_path", "from_state", "to_state"]`），符合生成器的 `mode=replace` 规则。

### 2.2 不可达 → 可达的前后证据

「前」有两份独立证据，「后」有三份：

| 侧 | 证据 | 结果 |
| --- | --- | --- |
| 前（契约） | `s0_head_has_no_animation_member_on_add_state` 等 7 项：HEAD 契约里这 4 个成员**不存在** | PASS |
| 前（线上） | `s0_unreachable_state_has_empty_animation`：按旧契约能构造的调用（不带 `animation`）建出的状态 `animation=''`、`animation_given=false` —— 结构上不可达 | PASS |
| 后（契约） | `s0_now_has_*` 7 项：再生契约里 4 个成员存在 | PASS |
| 后（线上 schema） | `s0_live_schema_editor_add_state_machine_state_animation` 等 5 项：`tools/list` 的 `inputSchema.properties` 真的声明了它们 | PASS |
| 后（线上行为） | `s0_reachable_state_names_animation`（写入并回读 `idle`）、`s0_transition_members_read_back`（`xfade_time=0.35`、`priority=3`、`advance_condition=go_now`）、`s0_structure_reads_animation_back`（另一个工具读到同一值） | PASS |
| 后（闭环） | `s0_condition_parameter_is_the_engine_spelling` + `s0_condition_parameter_fed_back`：过渡答出的 `advance_condition_parameter="parameters/conditions/go_now"` 被**原样**喂回 `editor_set_animation_tree_parameter` 并成功 | PASS |

第三个成员 `animation` 还额外做了「另一个工具读到同一值」的跨界闭环：`editor_get_animation_tree_structure` 答 `state 'Idle' → animation='idle'`，该字符串被原样喂进 `editor_get_animation_info`（`s0_animation_name_fed_back`），返回同一个动画。这条链跨 5 个工具、0 次字符串手术。

> ⚠️ 本批次的**唯一实现缺陷**就出在这条链上（§5.2）：`advance_condition` 的写入顺序错，导致过渡答出的参数名当时还不在动画树的参数表里，喂回去会 `-32001`。门②在真实端点上抓到了它，修复见 §5.2。

---

## 3. 引擎依据（每个工具一行）

命名规则：每行给 ①引擎 API（带 `文件:行`）②契约里的自然形状 ③与迁移源的分歧及理由。全部引擎行号对应锚点 `fc724ce49a`。

### 3.1 `editor_audio_write`（4）

| 工具 | 引擎依据 | 自然契约 | 与迁移源的分歧 |
| --- | --- | --- | --- |
| `editor_add_audio_bus` | `AudioServer::add_bus(int)` `servers/audio/audio_server.cpp:677` + `AudioServer::set_bus_name` `:763` | `{name, after_bus_index?=-1}` | 迁移源把 `after_bus_index` 硬塞进 `add_bus`；`add_bus` 对越界值**截断/钳制**（`p_at_pos` 非法即追加），故本实现先按服务器总线数校验（越界 → `-32602`）。重名会让 `set_bus_name` 静默改名为 `"Music 2"`，应答若仍声称 `Music` 就是说谎，故重名 → `-32000`（带 `suggestion`） |
| `editor_add_audio_bus_effect` | `AudioServer::add_bus_effect(int, Ref<AudioEffect>, int)` `:923`；`ClassDB::instantiate` + `Object::cast_to<AudioEffect>` | `{bus_index, effect_type, name?}` | 迁移源对未知类名静默不做事；此处先实例化并 cast，既非 AudioEffect 就 `-32602` 并列出 `AudioEffect` 系列要求 |
| `editor_add_audio_player` | `AudioStreamPlayer2D/3D` 实例化 + `Node::add_child` + `Node::set_owner` | `{parent_path?=".", name?="AudioPlayer"}` | 迁移源只建 2D；本实现按场景根类型选 2D/3D 并在应答里答 `type`，读回 `bus`/`playing` |
| `editor_set_audio_bus_property` | 六个类型化 setter：`set_bus_volume_db(float)` `:821`、`set_bus_send` `:849`、`set_bus_name` `:763`、`set_bus_mute/solo/bypass_effects`；成员宽度 `AudioBusLayout::Bus::volume_db` 是 `float` `servers/audio/audio_bus_layout.h:55` | `{bus_index, property, value}` | 迁移源用通用 `set(property, value)`，对 `volume_db` 会接受 `1e300` 让引擎静默变 `inf`；此处先 `coerce_to_property_type(..., FLOAT32)`（`1e300` → `-32602`），`applied` 在成员自身宽度上比较；`send` 必须指向已存在的总线（`-32001`），总线 0 改名被拒（引擎静默失败） |

### 3.2 `editor_audio_read`（2）

| 工具 | 引擎依据 | 自然契约 | 分歧 |
| --- | --- | --- | --- |
| `editor_get_audio_info` | `AudioServer::get_mix_rate/get_output_latency/get_bus_count/get_output_device*/get_playback_speed_scale` + `Engine::is_editor_hint()` | `{}` | 迁移源只答总线名数组；此处 `source:"engine_process"` + `buses[]`，结构就是 `_bus_record`（与 layout 同一形状，GDR-25 §23.4） |
| `editor_get_audio_bus_layout` | 同上一行 + `get_bus_effect_count/get_bus_effect` | `{}` | 迁移源漏 `send`/`bypass_effects`/效果链；此处每条总线 8 个字段 + `effects[]`（`{type,name,index,enabled}`） |

### 3.3 `editor_particle_write`（4）

| 工具 | 引擎依据 | 自然契约 | 分歧 |
| --- | --- | --- | --- |
| `editor_create_particles` | `GPUParticles2D/3D` 实例化；`process_material` 属性 `scene/2d/gpu_particles_2d.cpp:984` | `{parent_path?=".", particle_type?="GPUParticles2D", name?="Particles"}` | 只接受两种 `GPUParticles*`：`CPUParticles*` 没有 `process_material` 槽，建出来全家都用不了，故 `-32602` 并说明 |
| `editor_set_particle_preset` | 迁移源预设表（fire/smoke/magic/explosion/rain/snow）逐项落到 `ParticleProcessMaterial` 类型化 setter（`set_spread` `scene/resources/particle_process_material.cpp:1420` 等） | `{node_path, preset}` | 迁移源不认的预设名静默返回成功；此处 `-32602` 并列出六个合法名 |
| `editor_set_particle_color_gradient` | `Gradient::set_offsets` `scene/resources/gradient.cpp:147`、`set_colors` `:156`；`GradientTexture1D::set_gradient` → `ParticleProcessMaterial::set_color_ramp` `:1716` | `{node_path, colors:[{offset,color}]}` | 迁移源把 offset/颜色当浮点数组直接拼；此处逐点校验 offset∈[0,1]、颜色接受 `{r,g,b,a}` 对象或引擎自己的 HTML/颜色名（同一 `coerce_to_property_type`），失败**全不回写** |
| `editor_set_particle_material` | `ParticleProcessMaterial` 的 30 个参数按各自成员宽度写入（`spread` 是 `float` `particle_process_material.h:323`，`emission_*` 是 `real_t`，Vector3/Color/枚举各有其形） | `{node_path, material_params:{...}}` | 迁移源用通用属性写入并静默丢未知键；此处用**受控参数表**（迁移源集合 + 发射几何），未知键 `-32602` 并点名，宽度不符 `-32602`，全有或全无 |

### 3.4 `editor_particle_read`（1）

| 工具 | 引擎依据 | 自然契约 | 分歧 |
| --- | --- | --- | --- |
| `editor_get_particle_info` | 节点成员 `Object::get`（`amount`/`lifetime`/`one_shot`/`emitting`/`draw_passes`/`draw_pass_1`/`texture`）+ `process_material` cast + `Gradient::get_offset/get_color` | `{node_path}` | 迁移源只答 `amount`/`lifetime`；此处答节点成员 + `params`（与写入同一字典形状）+ `colors`/`color_ramp`/`color_stop_count`，与写侧一一对应可原样回灌 |

### 3.5 `editor_theme_write`（1）

| 工具 | 引擎依据 | 自然契约 | 分歧 |
| --- | --- | --- | --- |
| `editor_set_control_theme` | `Control::set_theme(Ref<Theme>)`；`ResourceLoader::load` + `Object::cast_to<Theme>`；`Theme::get_type_list(List<StringName>*)` `scene/resources/theme.cpp:1358` | `{node_path, theme_path?}` | 迁移源把 `theme_path` 当必填且不清空；此处缺省即**清空**并答 `cleared:true`（GDR-25 §23.5 的 `null` 语义），加载到非 Theme 资源 → `-32602`，路径不存在 → `-32001` |

### 3.6 `editor_scene_3d_write`（1）

| 工具 | 引擎依据 | 自然契约 | 分歧（含 E-4） |
| --- | --- | --- | --- |
| `editor_set_material_3d` | `MeshInstance3D::set_surface_override_material(i, mat)` `scene/3d/mesh_instance_3d.cpp:375`（`ERR_FAIL_INDEX` 对 `mesh->get_surface_count()`）；读侧 `_get_property_list` 暴露 `surface_material_override/<i>` `:115` | `{node_path, material_path, material_slot?}` | **E-4 的原始缺陷**：迁移源读了 `material_slot` 却硬编码 0。本实现把槽位真正交给 `set_surface_override_material`，越界 → `-32001` 并答 `0..N-1`，非数字拼写 → `-32602`，应答答出 `material_slot`/`surface_count`/`surface_materials[]`（§5.1 有「不同槽写不同材质 → 分别读回」的实测） |

### 3.7 `editor_navigation_read`（1）

| 工具 | 引擎依据 | 自然契约 | 分歧 |
| --- | --- | --- | --- |
| `editor_get_navigation_info` | 子节点遍历（引擎顺序）+ `NavigationRegion2D/3D`（`scene/2d/navigation/navigation_region_2d.h`、`scene/3d/navigation/navigation_region_3d.h`）+ `NavigationPolygon::get_vertices/get_polygon_count` / `NavigationMesh::get_vertices/get_polygon_count` + `NavigationAgent2D/3D` | `{node_path?="."}` | 迁移源返回扁平 map；此处按 `regions[]`/`agents[]` 分类，每条答 `{node_path,type,path,...}`，并答 `region_count`/`agent_count`。两面 `enum` 字段一律给引擎名 + 数值（`baked`/`enabled` 等） |

### 3.8 `editor_profiling_read`（1）

| 工具 | 引擎依据 | 自然契约 | 分歧 |
| --- | --- | --- | --- |
| `editor_get_performance_monitors` | `Performance::get_monitor_name(Monitor)` `main/performance.cpp:174`，遍历 `0..MONITOR_MAX` `main/performance.h:130`，`Performance::get_monitor` | `{}` | 迁移源用**自造**键名（`fps`/`objects` 等）；此处键就是引擎自己的 `get_monitor_name`（`time/fps`、`object/nodes`…），并答 `source:"engine_process"`，读不到单例时答 `-32000` 且带 `unavailable_reason` |

---

## 4. 范围②：零字符串手术链（GDR-25 §23.1）

门②脚本自己数「字符串手术」次数（`$script:StringOps`），结束时断言为 0（`zero_string_surgery_chain`）。两条链全部用 JSON 解析器给出的对象原样传递，没有任何 `-replace`/`Split`/`Join`/`Substring`：

**链 A：音频（5 个工具）**

1. `editor_add_audio_bus{name:"Music"}` → 答 `index=1`
2. `editor_add_audio_bus{name:"SFX", after_bus_index:<1>}` → 答 `index=2`（**上一个应答的索引喂进下一个请求**）
3. `editor_set_audio_bus_property{bus_index:<2>, property:"volume_db", value:-6.5}` → 答 `applied=true`
4. `editor_add_audio_bus_effect{bus_index:<2>, …}` → 答 `effect_index=0`
5. `editor_get_audio_bus_layout{}` → `buses[2]` 里读到上面写的值；`buses[0].name`（`Master`）被原样喂进第 6 步的 `send`
6. `editor_set_audio_bus_property{bus_index:<2>, property:"send", value:<Master>}` → `applied=true`，回读 `new_value` 同一字符串

**链 B：粒子（5 个工具）**

1. `editor_create_particles{}` → 答 `node_path="Fx"`、`process_material.{type,path}`
2. `editor_set_particle_preset{node_path:"Fx", preset:"fire"}` → 答 `material_params[]`（含 `stored`）
3. `editor_set_particle_material{node_path:"Fx", material_params:{spread, direction, color, emission_shape, emission_sphere_radius}}` → 答 `changed_count=5`、`ignored_count=0`
4. `editor_set_particle_color_gradient{node_path:"Fx", colors:[3 个停止点，其中一个用引擎自己的 `#00ff00` 拼写]}` → 答 `stop_count=3`
5. `editor_get_particle_info{node_path:"Fx"}` → 答 `params`（30 项）与 `colors`（3 项）
6. 把第 5 步的 `params` **整个字典**喂回 `editor_set_particle_material` → `changed_count=30`、`ignored_count=0`；把 `colors` 数组喂回 `editor_set_particle_color_gradient` → `stop_count=3`

两条链都跨 ≥4 个工具、0 次字符串手术，读形状=写形状（GDR-25 §23.4）。

---

## 5. 关键实现决策与自我缺陷

### 5.1 E-4 的多槽位证据（`editor_set_material_3d`）

- 先用 `editor_execute_gdscript` 给 `Mesh` 造一个 **2 面** `ArrayMesh`（`mesh.get_surface_count()` 回读 = 2；单面 `BoxMesh` 不足以暴露硬编码 0）；
- `editor_set_material_3d{node_path:"Mesh", material_path:"res://materials/a.tres", material_slot:"0"}` → 答 `material_slot="0"`、`surface_count=2`、`set=true`；
- `…{material_path:"res://materials/b.tres", material_slot:"1"}` → 答 `material_slot="1"`；
- 再用**另一个工具**读回：`editor_get_node_properties{path:"Mesh"}` 的 `surface_material_override/0.path = res://materials/a.tres`、`surface_material_override/1.path = res://materials/b.tres`，两者不同（`slot_07/08/09`）。

这正是「不同槽写不同材质、分别读回各自正确」的证据：迁移源那样硬编码 0 的实现会让槽 1 永远保持旧材质（或把槽 0 的材质写到槽 0 两次），本实现不会。

### 5.2 自我缺陷：`advance_condition` 的写入顺序（本批次内发现并修复）

- **现象**（门②第一次运行）：`s0_condition_parameter_fed_back` FAIL —— `editor_add_state_machine_transition` 答出的 `advance_condition_parameter="parameters/conditions/go_now"` 喂回 `editor_set_animation_tree_parameter` 得到 `-32001 Parameter 'parameters/conditions/go_now' of this AnimationTree not found`，错误 `suggestion` 里列出的 22 个参数确实没有它。
- **根因**：原实现先 `transition->set_advance_condition(...)` 再 `machine->add_transition(...)`。而 `AnimationNodeStateMachine::add_transition` 正是把过渡的 `advance_condition_changed` 连到状态机 `_tree_changed` 的地方（`scene/animation/animation_node_state_machine.cpp:1581`）；该信号是 `AnimationTree` 唯一得知「参数表多了一个 `conditions/<name>`」的途径（`AnimationTree::_tree_changed` `scene/animation/animation_tree.cpp:760`，刷新是 **deferred** 的 `_update_properties`，:765）。条件在连接建立**之前**写，信号就没人听，树缓存里永远没有该参数 —— 本工具答出一个**自己都喂不回去**的名字。
- **修复**：把 `set_advance_condition` 移到 `add_transition` **之后**（`tools/editor_animation_tree_write.cpp`，带注释写清依赖的信号链与两个引擎行号），并新增 `s0_condition_parameter_fed_back` 这条链式断言把它钉住。
- **修复后**：门② 114/114 全绿；TASK-033 的 75 项证据（同为动画族）与门③/④ 全部重跑通过。

### 5.3 粒子族：`process_material` 是单槽位（与任务书 §1 措辞的偏差，需上报）

任务书 §1 的 E-4 段要求「按引擎真实槽位写入」并提到迁移源硬编码槽 0。粒子族的实际引擎形状不同：

- `GPUParticles2D/3D` 的 `process_material` 是**一个**对象属性（`scene/2d/gpu_particles_2d.cpp:984`），没有索引槽；E-4 的「硬编码 0」风险在这族**不存在**。
- 因此本族的答案用 `process_material_slot:"process_material"` **显式点名**槽位，并且当槽里放着**不是** `ParticleProcessMaterial` 的材质（如 `ShaderMaterial`）时拒绝改写（`-32602`）—— 迁移源会直接覆盖用户的工作。
- 命名与「多处索引槽」的等价证据由 `editor_set_material_3d`（真索引槽，§5.1）提供；任务书 §1 措辞中关于粒子的部分按此记录为偏差。

### 5.4 整数 default 归一化复用 TASK-033 的同一处实现

本批次有 2 个整数 default 需要归一化：新工具 `editor_add_audio_bus.after_bus_index`（default `-1`）与 §0 的 `editor_add_state_machine_transition.priority`（default `1`）。两者都调用 TASK-033 抽出的**同一个** `MCPTools::schema_with_integer_defaults(const Dictionary&, const Vector<StringName>&)`（`tools/tool_helpers.cpp`），没有第二份实现。该 helper 这次被改成**深拷贝**（`Dictionary::duplicate(true)`）——本 fork 的 `Dictionary` 是共享容器（`core/variant/dictionary.h:109` 是唯一的复制入口），浅拷贝下写成员会连带改调用者的字典；doctest 里新增了「调用者的字典未被就地修改」的断言。

### 5.5 参数校验先于编辑器前置条件

15 个工具里，凡是「参数本身不成立」的拒绝（缺参、类型错、空串、越界索引、未知键、宽度不符）都在 `require_editor_ui()` **之前**发生。本批次内曾有两个例外（`editor_set_particle_color_gradient` 的空数组、`editor_set_particle_material` 的空字典落在 `require_editor_ui` 之后），doctest 抓到后统一前移，`set_particle_*` 的公开入口仍各自保留同一守卫（防御性重复）。

### 5.6 失败不假装成功

- `applied`/`created`/`set`/`cleared` 都与引擎回读值绑定：`volume_db` 的 `applied` 在成员自身 `float` 宽度上比较（`0.1` 不会被误报为未生效）；粒子参数写入是**全有或全无**（两遍：先全量校验、再全量落盘），任何一项不合格整次调用不改任何东西（doctest 有「被拒后 `spread` 仍是原值」的断言）。
- 空 `colors` / 空 `material_params` / 空 `name` / 非有限浮点 / 越界 `after_bus_index` / 重名总线 / 未知效果类 —— 全部 `-32602` 或 `-32000`（带 `suggestion`），绝不静默。

### 5.7 real_t 与 float 的宽度说明（诚实边界）

本构建**没有** `precision=double`（`SConstruct:611-612` 只在 `precision=double` 时定义 `REAL_T_IS_DOUBLE`，本构建命令未设置），故 `core/math/math_defs.h:143-147` 走 `typedef float real_t` 分支 —— 本构建 `real_t == float`，粒子参数表里 `REAL_T` 与 `FLOAT32` 两类槽位**同宽**。表按 API 声明的类型记录（`emission_*` 的 setter 取 `real_t`，其余取 `float`），在 `precision=double` 构建上才会有行为差异；遗留缝隙见 §7.3。

---

## 6. 逐门证据与日志

### 6.1 门①–⑥

| 门 | 命令 | 结果 | 证据位置 |
| --- | --- | --- | --- |
| ① 契约子集（逐组） | `scripts/check_contract_subset.ps1 -Group <8 个组名>`（9888/9889 各自起真实进程） | **8/8 组全绿，每组 3/3**（`editor_9888_contract_subset`、`game_9889_contract_subset`、`guard_user_port_9877`） | `%TEMP%\task034_gate1.log` |
| ② 行为证据 | `scripts/mcp034_b5_audio_particle_theme_evidence.ps1`（本批次新增，纯 ASCII） | **114/114**，summary sha256 `6d0875805e750322917f9c9ec6259cefafbd20b43886c1932685c07810ae4fec` | `%TEMP%\task034-b5-batch2\evidence`（每请求/响应各一份，响应 sha256 逐条打印；`class_evidence.txt` 是三态表） |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **239/239 用例、12198/12198 断言**，`Status: SUCCESS!` | `%TEMP%\task034_modtest4.log` |
| ④ 全量 doctest | `--headless --test` | **1665/1665 用例、436480/436480 断言**，`Status: SUCCESS!` | `%TEMP%\task034_fulltest.log` |
| ⑤ M1 验收（跑两遍） | `scripts/accept_m1.ps1` ×2 | 两次都 **22/22 cases**；派生并集 142 工具；编辑器端点 120 / 游戏端点 53 | `%TEMP%\task034_gate5_run1.log`、`run2.log` |
| ⑥ 窄化闸门（三段） | ①`python scripts/check_narrowing_points.py`；②`--coverage`；③`scripts/mcp031_gate6_coverage_probes.ps1` | ①**38/38 pinned，PASS**；②17 个已声明拼写 + 未覆盖边界照旧；③**101/101**，log sha256 `b85bd631bf2d8da215da30f32992e0bcd7683e942673c0b4ad2c4baafc32d132` | `%TEMP%\task034_probes2.log`、`%TEMP%\task034-b5-batch2\logs\gate6_coverage.log` |

门⑥本批次**新增/重钉的窄化点**（`scripts/check_narrowing_points.py` 的 `PINNED`）：

| 文件:行 | marker | 类别 | 理由（要点） |
| --- | --- | --- | --- |
| `tools/editor_animation_tree_write.cpp:417`、`:746` | `G24-ANIM-POSITION` | gated | TASK-033 两个位置的**行号漂移**（321/562 → 417/746），本次按新行号重钉 |
| `tools/editor_animation_tree_write.cpp:563` | `G24-ANIM-XFADE` | gated | 新增：`xfade_time` 是 `float` 成员，`value_fits_slot(FLOAT32)` + 有限性/非负校验在其上方 |
| `tools/editor_audio_write.cpp:310`、`:317` | `G24-AUDIO-VOLUME` | gated / safe | 新增：落盘拷贝（gated）与 `applied` 比较宽度（safe，不落盘）两个点，同一 marker |
| `tools/particle_shared.cpp:204` | `G24-PARTICLE-WIDTH` | safe | 新增：`values_agree` 的比较宽度（`(double)(float)`），不落盘 |

`scripts/mcp031_gate6_coverage_probes.ps1` 里硬编码的基线计数「34」随本次 §22.3b 三段式同步改为「38」（`B1_baseline_scanned_38` / `B1b_restored_scanned_38`）——这是该脚本的既有约定（TASK-033 也曾从 30 改为 34），不是掩盖：点数增长来自本批次 3 个新文件里的 4 个点。

门⑥三件套符合 §22.3b 规则 4（机器检查 + 代码评审 + 行为证据互为补充）：机器检查只覆盖 17 个已声明拼写，行为证据是门②里 `1e300 → -32602` 的实测（`particle_11_slot_width_32602`、`audio_…` 的宽度拒绝、doctest 的宽度用例）。

### 6.2 三态证据表（15 个工具 × 成功 / 缺参 / 底层失败）

门②对每个工具各打一组，全部写成一行（`class_evidence.txt`）。不能构造的类别**显式声明理由**，不静默跳过：

- 三个无参读取（`editor_get_audio_info`、`editor_get_audio_bus_layout`、`editor_get_performance_monitors`）与 `editor_get_navigation_info`（全部成员可选）**没有必填成员**，其 `-32602` 见证改为**未声明参数**（`{mcp034_undeclared:1}` → `-32602 Unknown parameter…`，TASK-032 D4 的命名规则），表里写 `no-required-argument`；
- `editor_add_audio_player`、`editor_create_particles`、`editor_get_navigation_info` 的必填集为空，缺参一格同样以未声明参数见证；
- 三个无参读取「无引用可失」，底层失败一格标 `n/a` 并说明（它们的失败只有「进程没有 AudioServer/Performance」的 `-32000`，该分支另有 `audio_server_or_error` 的 doctest 与 `unavailable_reason` 断言）。

`editor_add_audio_bus` 的底层失败见证取**重名**（`-32000` 带 `suggestion`，而不是让引擎静默改名 `"Music 2"`）；`after_bus_index` 的越界另有 `audio_16_after_bus_index_range_32602`（`-32602`）。其余 11 个工具的底层失败都是「节点/总线/资源不存在 → `-32001`」。doctest 里进程没有 `AudioServer`（`Main::test_setup()` 不起服务器，正如不起 `SceneTree`），因此三个依赖服务器的拒绝在 doctest 里以「`-32602`（有服务器）或 `-32000`（无服务器，且带 `suggestion`）」两种合法答案断言，真实侧证据由门②提供。

### 6.3 回归

| 脚本 | 结果 |
| --- | --- |
| `mcp030_live_open_scene_write_evidence.ps1` | 22 checks，0 failed |
| `mcp032_d3_d4_d6_evidence.ps1` | 39 checks，0 failed |
| `mcp033_b5_animation_evidence.ps1` | 75/75 checks passed（含动画族与 §0 同族的过渡链，验证 §5.2 的顺序修复没有回退它） |

### 6.4 其它约束

- **契约指纹**：`docs/tools_list.renamed.json` sha256 `bc8c37a0906955b55ca160ab866d342527fff6bbc96041f81a0517bbea2fdf27`（生成器 1.9.0 / overrides 17 / 171 工具 / `map_sha256` 未变，见 §2.1）。
- **`docs/tool-groups-b5.json`**：只改了 8 个 `implemented: false → true`（`editor_audio_write`、`editor_audio_read`、`editor_particle_write`、`editor_particle_read`、`editor_theme_write`、`editor_scene_3d_write`、`editor_navigation_read`、`editor_profiling_read`），文件 sha256 `0d079762d8d7a3be4efa35000b5f11acf0f2c33c2e75aaf49ed1640118f3faf`。
- **`.ps1` 纯 ASCII**：`mcp034_…_evidence.ps1` 经字节级检查，`>127` 的字节数 = 0（同时 `[Parser]::ParseFile` 语法检查通过）。
- **D86 锚点有效性**：本报告全部引擎行号对应 `fc724ce49a5645250590ad7848e146d2cb617379`；`--version` 回显 `4.8.dev.custom_build.fc724ce49`。门③④⑤⑥与门②均在该锚点上重跑（不是复用 TASK-033 的结论）。
- **用户端口**：每次门运行都有 `guard_user_port_9877` / `port_9877_owner_unchanged` 断言（pid_before == pid_after == 36392）。

---

## 7. 未改动、需上报的缺陷（不擅自修补契约）

### 7.1 `editor_set_material_3d.material_slot` 的声明类型与引擎 API 不一致（**未改，需决策**）

- 契约把 `material_slot` 声明为 `string`；引擎的 API 是 `set_surface_override_material(int p_surface, …)`（`scene/3d/mesh_instance_3d.cpp:375`），本质是整数索引。
- 本实现按契约**收十进制字符串**（`"0"`/`"1"`，空串 = 槽 0），非数字拼写 `-32602`、越界 `-32001`；这等于把类型风险留给客户端（客户端自然会传 `0`，得到 `-32602`「must be a string」）。
- 修它需要一条**新的 `SCHEMA_OVERRIDES` 条目**（把 `material_slot` 改成 `integer`）—— 任务书 §0 只授权了 4 个成员，故**未擅自修改**，在此上报请决策。`tools/editor_scene_3d_write.h:59` 有对应注释。

### 7.2 `editor_add_audio_bus.after_bus_index` 的语义边界（**未改**）

`AudioServer::add_bus` 对越界位置钳制为「追加」，本实现按服务器总线数前置拒绝（`-32602`）。若产品希望「越界即静默追加」（迁移源行为），这是一个契约级决策（要么改文档、要么当前行为即正确）；本实现选择「不静默」，理由与 §5.6 一致。

### 7.3 `emission_sphere_radius` 的成员宽度缝隙（**未改，仅记录**）

成员声明是 `float`（`scene/resources/particle_process_material.h:344`），setter 取 `real_t`（:465）。本构建 `real_t == float`（§5.7），缝隙不存在；但在 `precision=double` 构建上，按 setter 类型记 `REAL_T` 会让一个 `1e300` 通过槽位检查再被 setter 内部窄化为 `inf`。彻底修法是把该参数的宽度按**成员**类型记（`FLOAT32`），届时常规构建与 double 构建都正确；本次未改，避免在无实测构建的情况下动宽度表。

---

## 8. 遗留风险与下一步建议

1. **`material_slot` 类型**（§7.1）：建议下一个批次加一条 `SCHEMA_OVERRIDES`，把 `editor_set_material_3d.material_slot` 改为 `integer`，并同步 `check_contract_subset` 的期望与三态证据（改动很小，但属于契约变更，需显式授权）。
2. **`emission_sphere_radius` 宽度**（§7.3）：建议在引入 `precision=double` 构建前修掉；当前仅记录。
3. **B5 剩余 29 个工具 / 15 组**：下一批建议按组的耦合度切（`editor_tilemap_*`、`editor_shader_*`、`project_theme_*` 各自独立；`os_android_*` 与 `project_export_read` 依赖 Android 导出环境，风险最高，建议放最后并预先 spike）。
4. **门②脚本可复用**：`mcp034_b5_audio_particle_theme_evidence.ps1` 的三态表 + 链式断言骨架可直接照搬到后续批次；脚本内 `$script:StringOps` 的「0 次手术」自证机制值得保留（它把 GDR-25 §23.1 从口头约定变成机器事实）。
5. **门⑥点数维护**：每批次新增窄化点都要重钉 `PINNED` 行号并同步 probes 里的基线计数（本批次 34 → 38）。这是一处持续的人工维护点，若日后行号漂移频繁，建议把 `_pin` 的第二个参数改成「marker 出现序号」以外的稳定锚（例如 pin 到紧邻的代码片段 sha）。