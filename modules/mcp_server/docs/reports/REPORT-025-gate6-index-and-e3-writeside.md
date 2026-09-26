# REPORT-025 — 门⑥ 护栏改按标记身份索引（+ 对 REPORT-023 的勘误）· E-3 **写侧**闭合（读回形状必须能写回）

* **status**：**完成**。两项均在范围内落地；门①–⑥ 全绿；**对已验收报告 REPORT-023 的一条声称作出显式勘误**（§3.2，澄清而非洗白：该声称是**错的**）；对读回形状矩阵**逐项**做了写回实测，**19/19** 两端点全部往返成功；发现并如实登记 **3 个我方证据脚手架自身的缺陷**（§11.5）；**未**越权改规范、未新增工具、未改契约。
* **任务书**：`docs/tasks/TASK-025-gate6-index-and-e3-writeside.md`（按 `docs/tasks/PLAYBOOK-group-port.md` 执行）
* **分支 / HEAD（门运行时的提交）**：`feature/mcp-server-module` · `dfda642459`
* **二进制自报**：`4.8.dev.custom_build.dfda64245`（`modules/mcp_server/scripts/build_local.cmd -Force`，**tests=yes**；`--version` 前缀 == `git rev-parse --short HEAD`）
* **端口纪律**：全程只用 **9888（编辑器）/ 9889（游戏）**。用户 Godot 4.7.1-mono 的 **9877（PID 36392）只读采样，未占用/未杀/未重启**（每次运行前后 pid 同为 36392，由各脚本自带的 guard 断言）；**未 push**。
* **本批两项**：① `check_narrowing_points.py` 的引脚**索引方式**改为按标记身份（行号仅作注释），失败条件保留；② E-3 **写侧**补 `Vector4i`/`Rect2`/`Rect2i` 分量表，使读回值可原样写回。
* **改动文件**：`scripts/check_narrowing_points.py`、`tools/running_game_node_write.{h,cpp}`、`tests/test_mcp_server.h`、2 个新证据脚本、本报告。**其它一切只读**。

---

## 1. commits

| sha | 一行说明 |
|---|---|
| `f9c0510194` | `TASK-025 (1): pin narrowing points by (file, marker id, occurrence), not by line` — 门⑥ 护栏的索引方式（§3） |
| `a95b824053` | `TASK-025 (2): E-3 write side - Vector4i/Rect2/Rect2i component tables` — 写侧分量表 + 4 个 doctest（红→绿） |
| `6f77e987ad` | `TASK-025: gate-6 index experiments and E-3 write-side evidence scripts` — 两个证据脚本 |
| `dfda642459` | `TASK-025: gate-6 experiment E0 must read the pre-TASK-025 script from a fixed commit` — 修 E0 的取源（§11.5c） |
| （本报告） | `TASK-025: REPORT-025 (gate-6 index erratum and the E-3 write-side closure)` |

> **决策日志**：`DECISIONS.md` 在 harness 仓库（`F:\moonbit-hof-rs\DECISIONS.md`），对本模块执行者**只读**；PLAYBOOK §7.2 禁止在本 fork 内新建竞争性规范/日志文档。因此本批的决策记录由**本报告 + `docs/DESIGN-DETAIL.md`（决策者维护）** 承担，与 TASK-023 的处置一致。

---

## 2. 逐工具表（PLAYBOOK §4；本批**没有**新增/改名工具，`inputSchema` 未动）

| new_name（未改） | 迁移源位置（**仅类别参考**） | 引擎依据（为什么这是自然形态） | 自然契约（本次改动的输出面） | C++ 落点 | 与迁移源的差异及理由 |
|---|---|---|---|---|---|
| `editor_set_node_property` | `godot_mcp_gdext/src/commands/node.rs:221`（只说明「有这类工具、写一个节点属性」） | `Object::set()` 是唯一写路径；一个 JSON 对象要落进 `Vector4i`/`Rect2`/`Rect2i` 属性，只能由调用方**按分量命名**，因为 `Variant::can_convert(DICTIONARY, VECTOR4I/RECT2I/RECT2)` 为 **false**（`core/variant/variant.cpp` 的转换关系表）；分量名与槽宽取自引擎自己的声明（`core/math/vector4.h`、`core/math/rect2.h`） | 入参对象新增三种可接受形态：`{x,y,z,w}`→`Vector4i`、`{x,y,width,height}`→`Rect2`/`Rect2i`；返回 `{node_path,property,old_value,new_value}` 不变，`new_value` 是**写后回读**（TASK-014 D-1） | `tools/running_game_node_write.cpp`（`vector_from_dictionary` / `vector_component_hint` / `_vector_components`）；两工具共用 | 迁移源**没有**这三类分量映射（它的 `_parse_value_for_type` 只到 `Color`）。本实现按「工具真的能用」补齐，而不是复刻它的能力边界（PLAYBOOK §6.6 / D74 §8b） |
| `running_game_set_node_property` | `addons/godot_mcp_rs/mcp_runtime_agent.gd`（类别参考） | 同上（两端点共用 `prepare_node_property_value` → `shape_vector_from_json` → `coerce_to_property_type`） | 同上（编辑器侧与游戏侧接受**同一批**形态，门② 实测两端各自 19/19 往返） | 同上 | 同上 |
| `editor_get_node_properties` / `running_game_get_node_properties` | `editor.rs` / `addons/godot_mcp_rs/*` | **读形状未改**（TASK-024b 已统一为「对象/数组」）；本批只是让这些形状**真的能喂回**（GDR-25 §23.1 规则 1） | 不变 | —（只读工具无改动） | 无 |
| （护栏脚本，非工具） | — | `GDR-24` §22.3 明确「按文件/标记登记理由」 | `PINNED` 由「行号键」改为「标记 id → 出现序列表」；`--json` 报告结构随之变化（新增 `occurrence` 字段） | `scripts/check_narrowing_points.py` | 这是**门脚本**，不是产品工具；见 §3 |

---

## 3. 门⑥：新旧索引方式对照 · 三组实验 · **对 REPORT-023 的勘误**

### 3.1 实测的旧行为（源码级事实，非推断）

改前的 `report()`（`git show 0b120996ff:modules/mcp_server/scripts/check_narrowing_points.py`）核心两行：

```python
pinned = PINNED.get(point["file"], {}).get(point["line"])      # ← 按【行号】查表
if pinned is None or pinned["id"] != point["marker"]:
    unlisted.append(point)                                     # ← 位移即 UNLISTED（失败）
```

且紧随其后的 `moved` 判定 `if pinned["line"] != point["line"]` **恒为假**（因为 `pinned` 就是按当前行号取到的），
即「行号漂移只提示不失败」这条设计**在旧实现里是一段死代码**。

`stale` 判定则**本来就是**按 `(file, marker id)` 计数比较的（`seen[(file, marker)]` 与每个 marker 的 pin 数），
这正是「声称与实现不符」被忽略的原因：**三条失败条件里有两条确实是按标记身份工作的**，
只有 `unlisted` 这一条（也就是「位移即假红」的来源）按行号。

**实测后果（TASK-024b 已发生）**：E-3 的新分支插在 `serialize_variant`（位于 `value_fits_slot` 上方）之后，
门⑥ 立刻报 `FAIL: tools/tool_helpers.cpp:986 G24-THE-GATE`，只能手工把引脚从 `851` 改成 `986`；
TASK-024b 的脚本注释里也留下了「The pin is line-keyed in practice」的记录。

### 3.2 **对 REPORT-023 该条声称的勘误（显式、append-only）**

| 项 | 内容 |
|---|---|
| **被勘误的声称（一）** | `REPORT-023-narrowing-guardrail.md` §5（第 208–211 行）：**「pin 的身份是『文件 + marker id + 该文件内的出现次序』，`line` 只作展示：调换/移动行号只产生 `moved` 提示（不 fail），**新增**收窄点才 fail。」** |
| **被勘误的声称（二）** | 同报告 §11 deviations 第 4 条（第 318–319 行）：**「门⑥ 的 pin 身份是 marker 而不是行号……改为『文件 + marker id + 出现次序』。」** |
| **实际行为（改前，实测源码）** | 引脚按 **`{file: {line: pin}}` 的绝对行号**索引。任何**在该点之上**的无关改动（加空行、加注释、在别的函数里插代码）都会让该点被记为 `UNLISTED` → **门⑥ 红**。`moved` 提示是死代码（§3.1）。 |
| **为什么勘误是必要的** | ① 这是**对一份已验收报告的事实修正**，不是措辞问题：声称的是一条**核心设计不变式**（「位移不失败」），而它当时并不成立；② 它已经在**下游造成了实际成本**（TASK-024b 必须手工重钉 `851 → 986`，且该次手工重钉被写进了它的 deviations）；③ 若不更正，后续批次会继续相信「护栏不需要重钉」，从而在**门⑥ 偶然红**时把它当成噪声而跳过。 |
| **更正后的现状** | 本次改动把实现改成**声称早就描述的样子**：`PINNED` 为 `file -> {marker id -> [按出现序排列的 pins]}`，查表按 `(file, marker id, 该标记的出现序)`，`line` 只是注释（漂移仅产生 `moved` 提示）。**三条失败条件一条不少**，且都被**重新演示**（§3.4）。脚本自身的 docstring / `PINNED` 注释自 TASK-023 起就这样写，现在起它们**与实现一致**。 |
| **没有洗白的细节** | REPORT-023 §5 那次「红演示」的**结论仍然成立**（新增未标注收窄点确实 fail）——因为一个**新增**的点在行号键下同样无 pin，两条路都会红。被否定的只是「位移不失败」这条**设计声称**，不是那次演示的观测。 |

### 3.3 新索引（实现）

```python
PINNED = {
    "tools/running_game_node_write.cpp": {
        "G24-NW-COMPONENTS": [ _pin(...127...), _pin(...141...), ... ],   # 列表位置 = 出现序
        "G24-NW-RECT-COMPONENTS": [ _pin(...220...) ],
    },
    ...
}
```

* 查表：`pins = PINNED[file][marker]`；`occurrence = 该 (file, marker) 此前已匹配的扫描点数`；
  `occurrence >= len(pins)`（源码里该标记的出现**多于**登记）→ `unlisted`；
* `_self_check()`：加载时断言「每个 pin 的 `id` == 它所在的 marker 键」，防止重排时把理由挂错标记；
* **失败条件（一条未削弱）**：①存在**未标注**的收窄点 → `unannotated`；②某点的 `(file, marker, 出现序)` 无对应 pin（含「出现次数多于登记」）→ `unlisted`；③某 pin 的 `(file, marker)` 在源码里的出现次数**少于**登记数（标记被删/改名）→ `stale`；
* **位移不再失败**：行号漂移只进 `moved` 报告（`--list` 打印当前行；`--json` 的 `moved[]` 带 `occurrence`）。

### 3.4 三组实验（必需）+ 新旧对照（附加）

脚本：`modules/mcp_server/scripts/mcp025_gate6_index_experiments.ps1` → **22/22 checks passed，exit 0**。
每一组在真实树上改、跑、再用 `git checkout --` 还原，并**逐次断言文件 sha256 与改前逐字节相同**。

| 实验 | 操作（真实工作树 / `%TEMP%` 副本） | 期望 | **实测输出** | 还原 |
|---|---|---|---|---|
| **E1 位移不假红** | `tools/tool_helpers.cpp` 的 `G24-THE-GATE` 点**上方插入 20 行注释**，**不重钉** | exit **0** | `exit=0`；`note: 1 pinned line number(s) drifted ... tools/tool_helpers.cpp marker=G24-THE-GATE occurrence=0 pinned_line=986 now=1006`；报告里**没有**任何 `FAIL:` | sha256 还原 == 改前 |
| **E2 新增未标注点仍红** | 同一文件的 `G24-GAME-SCENARIO-STRENGTH` 标记上方插入 `const real_t task025_experiment_unannotated = (real_t)1.0e300;`（无标记、无 pin） | exit **1** | `exit=1`；`FAIL: 1 narrowing point(s) carry no `// MCP-NARROWING:` marker:` 并打印该行文本 | sha256 还原 == 改前 |
| **E3 陈旧条目仍红** | 把源码里的标记 id `G24-GAME-SCENARIO-STRENGTH` 改名（pin 不动） | exit **1** | `exit=1`；`FAIL: 1 pinned marker(s) have no matching narrowing point any more: ... marker=G24-GAME-SCENARIO-STRENGTH pinned=1 found=0` **且** `FAIL: ... marker=G24-GAME-SCENARIO-RENAMED`（新名字无 pin） | sha256 还原 == 改前 |
| **E4 还原后基线** | 三组实验全部还原 | exit **0** | `exit=0`；**无** `drifted` 提示；`git status --porcelain` 对这两个文件为空 | sha256 == 改前 |
| **E0 新旧对照** | 取 **TASK-025 起点的提交 `0b120996ff`**（`-PreTask025Commit`，**不是 HEAD**）的 `tools/**` 与护栏脚本到 `%TEMP%`（`git archive` + `git show`，**不碰仓库**），施加**与 E1 完全相同**的 20 行位移 | 旧脚本：假红 | 旧脚本未扰动时 `exit=0`；同一位移后 **`exit=1`**：`[UNLISTED] tools/tool_helpers.cpp:1006 G24-THE-GATE` + `FAIL: 1 narrowing point(s) are not pinned in this script's PINNED list`（**假红**）；同一位移在 TASK-025 脚本下是 `exit=0` + `moved` 提示（E1/E4b） | 仓库未被改动 |
| **E0′ 取源自检** | 断言取到的「旧脚本」**真的是旧的** | 必须为真 | `the copy from 0b120996ff looks its pin up by line (`.get(point["line"])`); the TASK-025 script does not` —— 这条自检是**必需的**：它抓到过一次真实错误（脚本第一版从 `HEAD` 取源，而 TASK-025 已经把自己的新脚本提交进 HEAD，于是 E0 在拿新脚本跟它自己比，E0b/E0c 假失败，见 §11.5c） | — |

**门⑥ 点数由 29 变为 30**：新增的 1 点即 `Rect2(...)` 那一行的 4 个 `(real_t)` 收窄（E-3 写侧新增），
按新规则标注为 `MCP-NARROWING: G24-NW-RECT-COMPONENTS`（`pregated`，理由见 §4）。

---

## 4. 读回 → 写回矩阵（**逐项**结论 + 引擎依据）

**方法**：门②脚本 `mcp025_e3_writeside_evidence.ps1` 在一个 scratch 工程的 `main.gd` 上导出**矩阵的每一项**，
先用写工具灌入种子值，再对每一项做 **读 → 把读到的值原样写回 → 再读**，比较用的是**结构化**比较器
（`Test-ValueEqual`：逐层比对对象/数组/数字，**不是**把响应拼成字符串比），两端点各跑一遍。
**结果：编辑器 9888 `19/19`、游戏 9889 `19/19`**（`code=0` 且 `new_value` 与读回值相等 且 再读相等）。

| # | 读回形状（TASK-024b 定形） | 目标类型 | 写侧路径 | 引擎依据（分量/元素落在哪个 C++ 成员） | 结论 |
|---|---|---|---|---|---|
| 1 | `{x,y}` | `Vector2` | 既有 | `core/math/vector2.h`：`real_t x, y` → `ValueSlot::REAL_T` | ✅ 往返 |
| 2 | `{x,y}`（整数） | `Vector2i` | 既有 | `core/math/vector2.h`：`int32_t x, y` → `INT32` | ✅ 往返 |
| 3 | `{x,y,z}` | `Vector3` | 既有 | `core/math/vector3.h`：`real_t x,y,z` → `REAL_T` | ✅ 往返 |
| 4 | `{x,y,z}`（整数） | `Vector3i` | 既有 | `core/math/vector3.h`：`int32_t` → `INT32` | ✅ 往返 |
| 5 | `{x,y,z,w}` | `Vector4` | 既有（TASK-021 A-3） | `core/math/vector4.h`：`real_t` → `REAL_T` | ✅ 往返 |
| 6 | `{x,y,z,w}`（整数） | `Vector4i` | **本批新增** | `core/math/vector4.h`：**`int32_t x, y, z, w`** → `INT32` | ✅ 往返（改前 `-32602`） |
| 7 | `{r,g,b,a}` | `Color` | 既有 | `core/math/color.h:39-42`：**`float r,g,b,a`（任何构建都是 32 位）** → `FLOAT32`（GDR-24） | ✅ 往返 |
| 8 | `{x,y,width,height}` | `Rect2` | **本批新增** | `core/math/rect2.h`：`Point2 position; Size2 size;`（`Point2`/`Size2` = `Vector2`）→ `real_t` → `REAL_T` | ✅ 往返（改前 `-32602`，且**改前读回形状本来就是对象**） |
| 9 | `{x,y,width,height}`（整数） | `Rect2i` | **本批新增** | `core/math/rect2.h`：`Point2i`/`Size2i` = `Vector2i` → `int32_t` → `INT32` | ✅ 往返（改前 `-32602`） |
| 10 | `[int,…]` | `PackedByteArray` | 既有 | 元素 `uint8_t` → `ValueSlot::UINT8`（`_container_element_slot`） | ✅ 往返 |
| 11 | `[int,…]` | `PackedInt32Array` | 既有 | 元素 `int32_t` → `INT32` | ✅ 往返 |
| 12 | `[int,…]` | `PackedInt64Array` | 既有 | 元素 `int64_t` → `WIDE` | ✅ 往返 |
| 13 | `[float,…]` | `PackedFloat32Array` | 既有 | 元素 `float`（任何构建）→ `FLOAT32` | ✅ 往返 |
| 14 | `[float,…]` | `PackedFloat64Array` | 既有 | 元素 `double` → `WIDE` | ✅ 往返 |
| 15 | `[string,…]` | `PackedStringArray` | 既有 | 元素 `String` → `WIDE` | ✅ 往返 |
| 16 | `[{x,y},…]` | `PackedVector2Array` | 既有（逐元素走同一分量表） | 元素 = `Vector2`（见 #1） | ✅ 往返 |
| 17 | `[{x,y,z},…]` | `PackedVector3Array` | 既有 | 元素 = `Vector3`（见 #3） | ✅ 往返 |
| 18 | `[{x,y,z,w},…]` | `PackedVector4Array` | 既有（TASK-021 A-3） | 元素 = `Vector4`（见 #5） | ✅ 往返 |
| 19 | `[{r,g,b,a},…]` | `PackedColorArray` | 既有 | 元素 = `Color`（见 #7） | ✅ 往返 |

**写侧落点（唯一，未新开绕过分支）**：三条新分支全部挂在**既有**的两个结构上——
`_vector_components()`（分量名 + 目标类型 + **槽宽**）与 `vector_from_dictionary()`（折叠），
而每个分量在此之前已被 `_check_components()` 推过 **`coerce_to_property_type`** 与
**`_component_fits_slot`**（即 GDR-22 的唯一闸门 `value_fits_slot`）。因此：
**没有任何形状特化的新比较、没有新的写入路径**（任务书 §2.2 的硬要求）。

**引擎本身不可写的项：本矩阵内「无」**（逐项结论见上表：19/19 都是可写的数据成员，经 `Object::set` 落盘）。
因此任务书 §2.3 的「逐项列引擎依据 + 可读原因」在本批**没有产生需要登记的只读项**；
作为对照，**工具对真正写不进去的东西给出的可读原因是实测过的**：

```
B2_rect_x_1e300   -> -32602  Parameter 'value.x' is the number 1e+300, which does not fit in the 32-bit
                            float slot this value is copied into (this build's single-precision real_t:
                            ...): the engine's own copy would write inf ... The largest 32-bit float is about 3.4e38.
B2_rect_i_x_3e9   -> -32602  Parameter 'value.x' is the integer 3000000000, which does not fit in the 32-bit
                            signed integer component this property stores: the engine's own copy would write
                            the low 32 bits (-1294967296) instead of the value you sent.
                            Send an integer between -2147483648 and 2147483647.
B2_missing_height -> -32602  Parameter 'value' sets 'rect_i', which is a Rect2i, so the object has to provide
                            its components ("x", "y", "width" and "height")
C1_set_missing_property -> -32001 + data.suggestion（属性不存在）
```

> `3e9` 是**刻意**选的：它**能**落进 `int64`（所以 `coerce_to_property_type` 的范围关会放行），
> 但**不能**落进 `Rect2i` 的 `int32_t` 成员 —— 因此这条 `-32602` **只可能**来自
> `_component_fits_slot(INT32)`，即「新表项把分量送进了既有的槽宽闸门」的直接证据（用 `1e20` 会因为更早的
> `FLOAT→INT` 范围关而拒绝，**证明不了**槽宽）。doctest 用同一个值断言同一件事。
>
> 另外，三条拒绝**之后**重新读取，`rect`/`rect_i` 仍是旧值（`B2_refusals_left_the_property_untouched`）——
> 即「拒绝」不是「静默写默认值」（PLAYBOOK §3 的 D-1/D-2 判据）。

---

## 5. 零字符串手术链（GDR-25 §23.1）：**读 → 写 → 再读**，两端点各一遍

实测（门② `E_chain_read_write_reread_six_steps` 通过；逐步标注调用方字符串处理次数）：

```
1 editor_get_node_properties          -> .v4i={"w":4,"x":1,"y":2,"z":3}, .rect={...}, .rect_i={...}   (string ops: 0)
2 editor_set_node_property(rect_i = step1 .rect_i) -> code=0 .new_value={"height":40,"width":30,"x":1,"y":2}  (string ops: 0)
3 editor_get_node_properties          -> .rect_i 与 step1 逐字相同                                     (string ops: 0)
4 running_game_get_node_properties    -> .v4i={"w":4,"x":1,"y":2,"z":3}, .rect={...}                  (string ops: 0)
5 running_game_set_node_property(v4i = step4 .v4i) -> code=0 .new_value={"w":4,"x":1,"y":2,"z":3}      (string ops: 0)
6 running_game_get_node_properties    -> .v4i 与 step4 逐字相同                                        (string ops: 0)
```

调用方**字符串处理次数合计 = 0**。这**不是**一句声称：脚本里链路段被 `# CHAIN-BEGIN`/`# CHAIN-END` 包起来，
证据脚本会**读自己的源码文本**、在该区间内检索
`.Split(` / `.Replace(` / `.Substring(` / `.Trim(` / `-match ` / `-replace ` / `[double]` / `[int]` / `[regex]` / `ConvertTo-Json`
共 10 个禁用记号，实测 `<none>`（check id `E_chain_region_has_no_string_surgery_tokens`）。

**本批如何让它成立**：TASK-024b 之后 step1/step4 的 `.v4i`/`.rect_i` 已经是对象，但**喂回 step2/step5 会被 `-32602` 拒**——
调用方要么自己把对象「转形」（违反规则 1），要么退回字符串形态再解析。补齐写侧分量表后，第 1→2 与第 4→5 步之间**没有任何调用方处理**。

---

## 6. 红 / 绿证据（真实输出）

**红阶段**（旧实现 + **最终测试文本**；`--headless --mcp-port=0 --test --test-case="[MCPServer]*"`）

```
[doctest] test cases:  205 |  201 passed |  4 failed | 1429 skipped
[doctest] assertions: 8094 | 8070 passed | 24 failed |
[doctest] Status: FAILURE!          （exit=1，log: %TEMP%\task025_red_module.log）
```

失败集中在 4 个新用例（节选）：

```
./modules/mcp_server/tests/test_mcp_server.h(14160): ERROR: CHECK( ok ) is NOT correct!          ×3
       logged: Vector4i / Rect2 / Rect2i: shape_vector_from_json refused: ... does not list Dictionary -> Vector4i / Rect2i
./modules/mcp_server/tests/test_mcp_server.h(14253): ERROR: CHECK( v4i_hint == "\"x\", \"y\", \"z\" and \"w\"" )
./modules/mcp_server/tests/test_mcp_server.h(14254): ERROR: CHECK( rect_hint == "\"x\", \"y\", \"width\" and \"height\"" )
./modules/mcp_server/tests/test_mcp_server.h(14306): ERROR: CHECK( error.message.contains("32-bit float") )
./modules/mcp_server/tests/test_mcp_server.h(14325): ERROR: CHECK( error.message.contains("32-bit signed integer") )
（其余为 !accepted / code==-32602 / message 命名分量）
```

**绿阶段**（新实现；同一二进制自报 `dfda64245` == HEAD）

```
[doctest] test cases:  205 |  205 passed | 0 failed | 1429 skipped
[doctest] assertions: 8102 | 8102 passed | 0 failed |
[doctest] Status: SUCCESS!          （exit=0）
```

**基线**：TASK-024b 为 **201 例 / 8021 断言** → 本批 **+4 例 / +81 断言**（4 个新用例：矩阵往返 / 分量表与折叠 /
槽宽拒绝 / 缺失分量拒绝）。**门③/④ 均未下降**（门④见 §7）。

---

## 7. 门（全部在 `--version == HEAD == dfda64245` 的二进制上重跑）

| 门 | 命令 | 结果 | exit | log（%TEMP%）/ sha256 |
|---|---|---|---|---|
| ⓪ 构建 | `modules\mcp_server\scripts\build_local.cmd -Force`（**tests=yes**） | `exit code = 0`；`--version = 4.8.dev.custom_build.dfda64245` == `git rev-parse --short HEAD`(`dfda642459`) | 0 | `mcp_server_build_local.log` |
| ① 契约子集逐字 | `check_contract_subset.ps1 -Group editor_node_write` | **3/3 PASS**：编辑器 9888 **91 工具**、游戏 9889 **53 工具**（与 TASK-024b 完全一致 → 未增删工具）；本组 10 个工具 name/description/inputSchema 两端口**逐字 True**；`implemented=113 / contract=171`；`guard_user_port_9877 pid 36392→36392` | 0 | `task025_gate1.log` `b2428f77117e403ef66ea0017f0d30c2780158b5a3a88dc16fbcc6ee624b6eb3` |
| ② 三类证据 + 跨工具链 | `mcp025_e3_writeside_evidence.ps1` | **110/110 checks passed** | 0 | `task025_e3_evidence_console.log` `8b4aef59a7c6ef86f0abcc5f8c17068f2bb325295135bb66b1588b67bfb7a3b3`；证据目录 `%TEMP%\task025-e3-writeside\evidence`（243 个请求/响应与状态探针文件；`evidence.log.txt` `ea216672a0e5afb4832fc4608b57de4d612ed2a804c1a9930b62684e5f9af85d`） |
| ②（回归）| `mcp024b_ergonomics_batch2_evidence.ps1` **重跑** | **66/68**：失败的 **2 条正是** `GAP_v4i_*` / `GAP_rect_i_*`（它们断言的「这个缺口还在」已被本批闭合，实测 `code=0`）；**其余 66 条与 TASK-024b 的 PASS 完全一致** | 1（**预期**，见 §9） | `task025_rerun_024b_console.log` `38e53e5cc20c4681ce7ddc8ed336de737af6eabac52f9338f3c91150cefcc2a7`；`evidence.log.txt` `17322753916d4ccc1073cb46650ec562740c4f58b10ed73d00c140cc322b1364` |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **205/205 passed / 8102/8102 断言 / 0 failed / SUCCESS!**（基线 201 / 8021） | 0 | `task025_gate3_module.log` `f4e8c3ebd1f289a6f700f053087e394ed78a5d22a7e5f7f716fc7dad7bbcd054` |
| ④ 全引擎回归 | `--headless --test` | **1631/1631 passed / 432384/432384 断言 / 0 failed / SUCCESS!**（基线 1627 / 432303） | 0 | `task025_gate4_full.log` `8e2b2a72b8bb3a3647a9e58a0145b1e514ec95bf2f4dcc60051a28e7821ea040` |
| ⑤ 批次收口 | `accept_m1.ps1` **连跑两次** | 两次 **22/22 cases passed**；两次 PASS 清单**逐字相同**（脚本比对 `identical=True`，0 FAIL） | 0 / 0 | `task025_gate5_run1.log` `464cca061e9a4fe1a03948225527c907d584604f54e7d9d445c1a0cc35379593`、`task025_gate5_run2.log` `14eb74399c8db1208bbdcc3ba4b685cd527ee7cc00865f5c041dbf839bacd28d` |
| ⑥ 收窄点清单（GDR-24） | `python modules\mcp_server\scripts\check_narrowing_points.py` | **扫描 30 点 / 30 pins 全部标注并登记**，**0 条 `moved`**：`PASS: every narrowing point of the module is annotated and pinned` | 0 | `task025_gate6.log` `9c93a6c6b2319a1ef5815aa62a8810c94533dd70cc2f12d95703f04c056c1d85` |
| ⑥ 三组实验 | `mcp025_gate6_index_experiments.ps1` | **22/22 checks passed**（E1 位移 PASS / E2 未标注 exit 1 / E3 陈旧 exit 1 / E4 还原 PASS / E0 新旧对照 + 取源自检） | 0 | `task025_gate6_experiments_console.log` `38472e6c6bc7af5ec23bee93c8a725917c61182a583cbf70d32a721a7b31103a` |

**红/绿 log**：`task025_red_module.log` `9e9c8697b7cf89b5ee707c3e4a4ddfc28582f0b2c2f250a41924cd4d0cf24919`（红）；`task025_gate3_module.log` `f4e8c3eb…`（绿，HEAD 绑定）。

**构建绑定（防空绿/假红，R-1）**：四个提交 `f9c0510194`/`a95b824053`/`6f77e987ad`/`dfda642459` 落地后，用 `-Force` **重建**并校验 `--version == HEAD`，**全部门在这一次构建上重跑**。其中 `dfda642459` 只改一个 `.ps1`（不参与编译），因此门③/④ 的数字与上一轮逐字一致（205 / 8102；1631 / 432384），门① 的工具数也不变（91 / 53）。

---

## 8. 门② 三类证据与「不可构造」类声明

| 类 | 证据 |
|---|---|
| **成功** | 矩阵写入：编辑器 `19/19`、游戏 `19/19`（§4）；读回形状 + 写回 `code=0` + `new_value` 结构化相等 + 再读相等 |
| **缺参 → `-32602`** | `C1_set_missing_value`（`value` 缺失）；`C2_get_missing_param`（`path` 缺失）；游戏侧 `D2_game_set_missing_value` / `D2_game_get_missing_param` |
| **底层失败 → `-32001` + `data.suggestion`** | `C1_set_missing_node`（节点不存在）；`C1_set_missing_property`（**属性**不存在，TASK-014 D-1）；`C2_get_missing_node`；游戏侧 `D2_game_set_missing_node` / `D2_game_get_missing_node` |
| **可读拒绝（本项特有的一类）** | `B2_rect_x_1e300` / `B2_rect_i_x_3e9` / `B2_missing_component`（§4 的三个真实报文，都不是笼统的 `-32602`）|
| **不可构造类声明** | **本项没有「不可构造」的三类**：成功/缺参/底层失败在两端点都真实构造并执行了。唯一**不构造**的是「矩阵内存在**引擎本身不可写**的项」这一**假设**——实测该假设不成立（19/19 可写），已在 §4 显式登记为「空集」，并给出每项的引擎依据。 |

---

## 9. TASK-024b 证据脚本重跑（回归）与对 `GAP_*` 断言的处置

`mcp024b_ergonomics_batch2_evidence.ps1` **原文未改**重跑：**66/68**。

```
[FAIL] GAP_v4i_object_read_back_is_refused_by_the_write_side
       editor_set_node_property(v4i = the read-back object) -> code=0 message=''
[FAIL] GAP_rect_i_object_read_back_is_refused_by_the_write_side
       editor_set_node_property(rect_i = the read-back object) -> code=0 message=''
```

**这 2 条失败是本批唯一期望的结果**：它们是 TASK-024b **刻意写下的「缺口存在」断言**（`-32602` 期望值），
而本批正是闭合该缺口，于是它们如实变成 `code=0`。其余 **66 条与 TASK-024b 的 PASS 清单一致**（形状、依赖读数、
schema 不变、端口 guard 全部不变）。处置上采取 **append-only**：**不改** TASK-024b 的脚本/报告
（它是那一刻的历史记录），把「该断言已被本批取代」写进本报告；**没有削弱任何既有检查**。

---

## 10. 本批改动文件的 sha256

| 文件 | sha256 |
|---|---|
| `tools/running_game_node_write.cpp` | `c71027ad4f51b3aceb7ce06e238b8ec9614ac8d2c8307cf3b934595b88568564` |
| `tools/running_game_node_write.h` | `aa0e4dfef7074a24c0018b651a7f4f72548df23bbeee9b1205ad0682e3d3b5c3` |
| `tests/test_mcp_server.h` | `01c351b8ac537336f414d72b489ccf722bdba381833440c76c7cff424cfe3718` |
| `scripts/check_narrowing_points.py` | `e9a98dea4dafb6c4c136e439c3843d302e3b10635e61507eb89a22db33489dcf` |
| `scripts/mcp025_gate6_index_experiments.ps1` | `a896dac8c2812056deaa125deee8b46329d8851316654d7162a72cc12fd5ccd1` |
| `scripts/mcp025_e3_writeside_evidence.ps1` | `004ae5fdb6bae0618639dd2d1f635930f59c5ad0620de196a140d83e4b54f81f` |
| 门日志（§7 引用） | `task025_gate6.log` `9c93a6c6…`；`evidence.log.txt` `ea216672…`；`task025_gate1.log` `b2428f77…` |

> 契约/生成器**未触碰**：`docs/tools_list.renamed.json`、`docs/tool-rename-map.json`、`docs/tool-groups*.json`
> 与三个生成器均未改，契约 sha / 文档指纹不变（门① 逐字 PASS + 工具数 91/53 不变为独立证据）。

---

## 11. deviations（与手册/任务书的任何偏离，逐条显式列出）

1. **门⑥ 的点数从 29 变为 30**：E-3 写侧新增的 `Rect2(...)` 一行含 4 个 `(real_t)` 收窄（按行扫描），
   已按新规则标注 + 登记（`G24-NW-RECT-COMPONENTS`，`pregated`）。这是**新实现代码**带来的必然增量，
   不是放宽或收紧判据。
2. **`running_game_node_write.h` 的注释被更新**（**纯注释**，无行为变化）：该头文件里
   `vector_component_hint` 的示例列表与 `shape_json_from_json` 的覆盖清单在 TASK-021 A-3 加 `Vector4` 时就已陈旧
   （未列出 `Vector4`），本批补上 `Vector4i`/`Rect2`/`Rect2i` 并说明「列表必须等于读侧能答出对象的类型集合」。
   改动后**重建并重跑全部门**（§7），故报告里的 sha 与门结果同源。
3. **TASK-024b 的证据脚本原文未改**（§9）：其 `GAP_*` 两条断言在本批之后**必然失败**。
   「回归重跑全绿」在本项上**结构性不可能**，因此以「66/68 + 失败恰为那 2 条且原因是被闭合」作为等价判据，
   未修改历史证据脚本、未放宽任何断言。
4. **E0（新旧对照）没有在「同一棵树」上比**：`PINNED` 描述的是**它写就时的源码**，改前的脚本在当前树上
   本就会因行号键而整体 `UNLISTED`（这正是缺陷），无法作为「基线」。因此 E0 让改前脚本跑在
   **TASK-025 起点提交 `0b120996ff`** 的 `git archive` 副本上（其自己描述的树），再施加**与 E1 逐字相同**的位移；
   新旧两侧的对照点是「**同一个改动**下各自的判定」，已在 §3.4 写明。取源是**参数**（`-PreTask025Commit`）
   并有自检（§11.5c），不是隐含假设。
5. **发现并如实登记 3 个我方脚手架缺陷**（都在本次运行中被抓到并修掉，**都不是实现缺陷**）：
   (a) 新 doctest 初版用了 `"字面量" + GodotString`，本引擎没有该 `operator+` 重载 → `test_main.obj` 编译失败
   （`error C2678`，见 `mcp_server_build_local.log` 的历史段），改为 `String(字面量) + …`；
   (b) 证据脚本的 `Test-Shape` 对 `object_rgba` 误用 `.x` 判数型 → `color` 假红（19/18），改为按该形状的**首分量**判定；
   (c) 门⑥ 实验 E0 第一版从 **`HEAD`** 取「旧脚本」，而 TASK-025 已把自己的新脚本提交进 HEAD → E0 实际上在**拿新脚本跟它自己比**，
   `E0b/E0c` 假失败（19/21）。改为按 `-PreTask025Commit`（默认 `0b120996ff`）取源，**并加一条自检**
   `E0_pre_task025_script_is_really_the_old_one`（断言取到的脚本确实含 `.get(point["line"])` 这一旧查表行）把这类错误变成门失败而不是静默。
   三处都记在此处，因为它们都说明「假红/假绿必须追到根因」，而且 (c) 正是本任务的主题（**声称在跑哪份代码，必须被验证而不是假定**）。
6. **未新建 `DECISIONS.md` / 规范章节**：见 §1 的说明（PLAYBOOK §7.2；规范由决策者维护）。
   `check_narrowing_points.py` 的 docstring 与 `--list` 文案属于**门脚本自身的文档**，可随之更新。
7. **本报告只给 as-built 矩阵表**：§4 的「读回→写回矩阵」是**实现现状的登记**；
   是否把它写进 `docs/DESIGN-DETAIL.md` §23（GDR-25）由**决策者**决定（实现者不自行写规范）。

---

## 12. blockers

**无**。（未遇到网络/依赖/工具阻塞；未安装依赖；未访问 `100.105.152.101:18080`；未占用 9877。）

---

## 13. next_step_recommendation

1. **交独立验收子代理**按本报告与门证据复核，重点：
   * §3.4 的三组实验是否**真的**证明了三条失败条件仍然有效、且位移不再失败；
   * §3.2 的勘误是否充分（REPORT-023 的两处声称、实际行为、现状）；
   * §4 的 **19×2** 往返是否每一项都独立可复现（不是「样本代表」）；
   * §9 的「024b 重跑 66/68」是否被误读为回归失败。
2. **建议决策者**：把 §4 的矩阵表与「写侧分量表规则（= 读侧能答出对象的类型集合）」登记进
   `docs/DESIGN-DETAIL.md` §23 / GDR-25 的可执行判据（实现者不自行写规范）。
3. **仍挂在 E-3 家族上的残留**（本批**未**处理、也未声称处理）：`Transform2D/3D`、`Basis`、`Quaternion`、
   `Plane`、`Projection`、`AABB` 的读回**仍是 `stringify()` 字符串**（REPORT-024b §3.2 表末行；
   目前没有任何工具读回它们）。若将来有工具读回，按本批同一条规则（读侧形状必须可写回）一并处理。
4. 其余顺手性项（E-2/E-6/E-8/E-9、G-1/G-3/G-4）仍按 REPORT-024b §9 的拆分建议独立成批。
