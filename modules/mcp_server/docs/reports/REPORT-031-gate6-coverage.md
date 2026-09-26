# REPORT-031 — 门⑥ 的覆盖面：**声明边界** + 逐拼写探针回归（M4d 第四次验收 D2，high）

- **status**：完成。**选路线 A**（扩展扫描器 + 声明覆盖 + 逐拼写探针），**实测否决路线 B**（编译器级检查，
  含被否决的 B′ 变体）。五道门 + 门⑥ 全部自跑通过；TASK-028/029/030 证据脚本重跑无回退。
  `DESIGN-DETAIL.md` **未改**（§22.3b 的反馈见 §9，报给决策者）。`PLAYBOOK` §3 门⑥ 已按 §22.3b 改写。
- **commits**：
  - `71e25a16db` TASK-031 D2: declare the gate-6 narrowing coverage and probe every spelling
    （`scripts/check_narrowing_points.py`、`scripts/mcp031_gate6_coverage_probes.ps1`、`docs/tasks/PLAYBOOK-group-port.md`）
  - 本报告是紧随其后的第二条提交。**它自身的 sha 不写死在文内**（自引用会立刻过期），
    读法：`git log -1 --format=%h -- modules/mcp_server/docs/reports/REPORT-031-gate6-coverage.md`。
  - 两条提交都只碰 `scripts/**` 与 `docs/**`；`git diff --name-only 07614971f0 HEAD` 恰好这 4 个文件。
- **构建**（第 0 步）：`modules/mcp_server/scripts/build_local.cmd -Force`（`tests=yes`），串行、不抑制输出；
  `exit 0`，`Time elapsed: 00:00:37.92`；`--version` 自报 `4.8.dev.custom_build.07614971f`
  == `git rev-parse --short HEAD`（`07614971f0`，跑门前核对）。
  **门全部在该二进制上跑**；TASK-031 的两条提交只动 `scripts/**` 与 `docs/**`
  （`git diff --name-only 07614971f0 HEAD` 只有那 3 个文件），**没有任何编译输入被改动**，故不重建二进制。

---

## 1. 选了哪条路线：A，以及 B 的实测代价

### 1.1 结论先行

| | 路线 A（扩展扫描器） | 路线 B（编译器级收窄告警） |
|---|---|---|
| 可行性 | **可行**（已实现，85/85 探针 + 当前树 0 误报） | **不可行**：告警无法只作用于本模块源码 |
| 挡住五个 M4d 探针 | **5/5 红**（另加 11 种拼写 = 16/16 有探针） | 即使能开也只挡住 1/5（见 §1.3）；而它**根本开不起来**（见 §1.2） |
| 构建代价 | 0（纯脚本，~1–2 s） | 实测 `/we4244` 作用域内**构建失败**；全模块每编译单元再降级为告警会产生 1200+ 行噪声（见 §1.4） |
| 能否补上「运行时 double 隐式进 real_t」 | 不能（已声明为边界） | 能（这正是它唯一不可替代的价值）——但代价见 §1.4 |

**为什么不是「A 与 B 都做」**：B 的第一形态（把告警升级为错误）**开不起来**；B′ 形态（降级为告警 + 用构建日志按路径过滤）
能开，但它引入「解析本地化编译器输出 + 强制全模块重编」这条脆弱链路，且它唯一的新增覆盖正是我们已**显式声明为边界**的那一类。
按 §22.3b 规则 3，只有在「采用编译器检查能覆盖更多拼写」时才该以编译器为准；实测它覆盖不了本模块（§1.2），
因此**保留 A、把 B/B′ 的实测代价写清并交决策者**，而不是默默采用一个开不起来或高噪声的机制。

### 1.2 B 的致命点：告警**作用域无法只到本模块**

事实链（全部实测，非推断）：

1. `SConstruct:944-957` 在 MSVC 上**全局禁用**了 C4244（以及 C4245/C4267/C4305），
   原文注释就是：`"/wd4244",  # C4244 C4245 C4267 (narrowing conversions): Unavoidable at this scale.`
   警告级别是 `/W4`（`SConstruct:961`）。
2. 本模块的 SCsub 本来就是 `env_mcp = env_modules.Clone()`，所以**可以把 `/wd4244` 过滤掉、只给本模块的
   translation unit 加 `/we4244`**——这一步技术上成立（我照此做了两次实验）。
3. **但 translation unit 会包含引擎头。** 实测日志 `%TEMP%\task031_expB_build2.log`
   （sha256 `da71fd18db631105ab4971341d0f9f8d381cab028964d74c3ec8a12fb8c43b4a`，54 856 B）：

   ```
   scons: *** [bin\obj\modules\mcp_server\mcp_deferred.windows.editor.x86_64.obj] Error 2
   .\core/math/math_funcs.h(224): error C4244: "return": 从"double"转换到"float"，可能丢失数据
   .\core/math/vector3.h(444): error C4244: "参数": 从"double"转换到"real_t"...
   .\core/math/color.h(206): error C4244: "参数": 从"double"转换到"float"...
   scons: building terminated because of errors.
   INFO: Time elapsed: 00:00:16.84     EXIT_CODE=2
   ```

   - **exit 2，18.67 s 后在**（`-j8`）**第 8 个编译单元就终止**；日志里 **301 行** `error C4244`，
     落在 **24 个不同位置**：**17 个是引擎头**（`core/math/{math_funcs,math_funcs_binary,vector2,vector2i,vector3,vector3i,vector4,vector4i,color,projection}.h`、
     `core/string/ustring.h`、`core/templates/hashfuncs.h`、`core/typedefs.h`、
     `core/object/method_bind.h`、`core/variant/{binder_common,method_ptrcall,variant_internal}.h`），
     7 个是本模块自己的（`mcp_deferred.h:181`、`tool_registry.h:159`、`mcp_deferred.cpp:94/155/166/198`、
     `mcp_http_server.cpp`）。
   - 这只是**下界**：构建在 8 个 TU 后就被掐断，整个模块（70 个工具文件 + 12 个模块文件）远不止这些。
   - `error C4056` / `C2398` 在这个日志里是 **0 行**——因为还没编到含那类常量的 TU 就死了。

   即：**把“收窄告警”升级为错误 = 构建在不许修改的引擎代码上失败。** MSVC 没有「只对某个目录的头文件关闭告警」的开关
   （`/external:I`+`/external:W0` 需要把引擎 include 路径整体标成 external，属于改 SConstruct/引擎侧配置，超出
   `modules/mcp_server/**` 许可），GCC/Clang 侧同理（`-Wfloat-conversion` 在模板实例化的普通头文件里同样触发）。
4. 第一次实验还留下一条流程证据：我先用 `env.get("msvc")` 判编译器 —— **错**（`env.msvc` 是 Python 属性不是 env 变量），
   于是 GCC 分支的 `-Wfloat-conversion` 被送给了 `cl`，日志 `%TEMP%\task031_expB_build.log`
   （sha256 `120820c0481b4737b45459bee0c1b371b59a50eae1d6e5662de272a506d3d3bf`）里是
   `cl: 命令行 error D8021 : 无效的数值参数"Wfloat-conversion"`。改用 `env.msvc` 后才是上面的 1.2 结果。
   （保留此条是因为它证明实验确实跑过、且 `SCsub` 已按 sha 逐字节还原，见 §6。）

**实验后还原**：`SCsub` 恢复为 `git checkout` 之外的手工还原（备份 + 比对），
sha256 `094f4b32c96eccf802c5543a5283d6e5bdb3c0de94e04cea71673024f5baca06` 与实验前**逐字节相同**，
`git status` 里**没有** SCsub。

### 1.3 即使能开，B 也挡不住五个探针里的 4 个（合成 TU 实测）

用 vcvars64（VS 2022 Enterprise，toolset `14.42.34433`）直接编译一个镜像 Godot 构造签名的 TU
（`Color(float,float,float,float)`、`Vector3(float,float,float)`），`cl /nologo /c /W4 /we4244 /we4056 /EHsc`：

| M4d 探针 | 常量写法下的实测诊断 | 结论 |
|---|---|---|
| ① `const real_t x = 1.0e300;` | 只有 `warning C4056: 浮点常量算术溢出`（**没有 C4244**） | 需另加 `/we4056` 才致命 |
| ② `static_cast<float>(1e300)` | **无任何诊断**（显式转换不触发 C4244） | **挡不住** |
| ③ `::Color(1e300, 0, 0, 1)` | 只有 `C4056`（常量实参） | 需 `/we4056` |
| ④ `Vector3{1e300, 0, 0}` | **`error C2398`（花括号收窄，默认即错）** | 挡住（与 flag 无关） |
| ⑤ `Color` 换行 `(1e300,...)` | 同 ③ | 需 `/we4056` |

对照（**运行时**非恒量，即 JSON `double` 进 `float` 的真实形态）：
`float f = d;` → `error C4244`；`Color c(d, 0, 0, 1);` → `error C4244`；`Vector3 v{d, 0, 0}` → `error C2398`。
→ 编译器检查真正无可替代的是**运行时隐式收窄**；而「新增收窄点的拼写」五个探针里有 2 个（②③⑤）编译器管不到
（② 显式转换不报警；③⑤ 只报常量溢出的 C4056，与「收窄」不是同一件事），这恰好是路线 A 的地盘。
**两条路线互补，但 B 的第一形态开不起来**，所以选择是 A + 显式声明边界。

### 1.4 被考虑并否决的 B′：告警不致命 + 构建日志按路径过滤

设想：SCsub 里把 `/wd4244` 换成 `/w44244`（只降级为告警，构建不失败），再加一个门脚本解析构建日志，
只把路径落在 `modules/mcp_server/**` 的 `C4244/C2398/C4056` 当失败。实测代价与否决理由：

1. **噪声**：本模块 70+ 个工具文件、每个 TU 都会把 §1.2 那 17 个引擎头的告警再吐一遍；按当前 8 个 TU 已 301 行估算，
   全模块是 **1500–3000 行**级别。构建日志变得不可读，而 `SConstruct` 全局禁用它的理由正是「Unavoidable at this scale」。
2. **重编成本**：告警只在**发生编译**时出现，所以门必须强制重编整个模块（否则「0 告警」是假绿）；
   实测模块全量重编约 38 s（`-j8`，本机），而且每次门都要付。
3. **信号被整数收窄淹没**：C4244 不区分 `double→float` 与 `int64→int`；本模块自身的 7 处命中全是后者
   （`__int64 → int`，如 `mcp_deferred.cpp:94/155/166/198`、`tool_registry.h:159`、`mcp_deferred.h:181`）。
   要让它可用，得先给这些点加显式转换或白名单——**而显式 `(int)` 转换不在门⑥ 的声明集合里**（TASK-023 起就显式排除），
   于是又多一份需要维护的例外表。
4. **收益**：唯一新增的是「运行时隐式 `double→real_t/float`」这一类——而它**已经被 `--coverage` 显式声明为不覆盖**，
   并由 §22.3b 规则 2/4 指给「代码审查 + 行为证据」。用一个脆弱的新机制去替换一条明确的书面声明，
   在本项目的证据体系里是**净负**。
5. **本地化解析**：日志里的中文诊断在本机 PowerShell 下是乱码（GBK/UTF-8 错配），只有 ASCII 的 `C4244` 与路径可
   可靠匹配；这不是不能做，而是又一处「靠文本形状」的脆弱点——正是本任务要摆脱的东西。

→ 因此**不采用 B′**，但把它连同实测数字列入本报告，供决策者日后（若真需要机器覆盖运行时隐式收窄时）复用。

---

## 2. 覆盖声明（拼写集合）

`python modules/mcp_server/scripts/check_narrowing_points.py --coverage`（`exit 0`，
`%TEMP%\task031-gate6-probes\logs\B1_coverage.log`），**16 条声明拼写**：

| pattern id | 拼写 | 对应探针 |
|---|---|---|
| `cast_real_t` | `(real_t)`（允许 `( real_t )`） | P6（M4d 对照）、S05–S15 之外的全部控制 |
| `cast_float` | `(float)` | S01 |
| `cast_static_real_t` | `static_cast<real_t>` | S02 |
| `cast_static_float` | `static_cast<float>` | P2（M4d ②） |
| `cast_func_real_t` | `real_t( ... )`（函数式转换） | S03 |
| `cast_func_float` | `float( ... )`（函数式转换） | S04 |
| `ctor_color` | `Color( )` / `Color{ }` / `Color name{ }` / `Color name = { }`，可 `::`、可跨行 | P3、P5、S05、S10、S11 |
| `ctor_color_arg_literal` | `Color name( ... )`，且实参里有装不进 32 位 float 的字面量 | S14 |
| `ctor_vector2` / `ctor_vector2_arg_literal` | 同上两种形态 | S06 / S12 |
| `ctor_vector3` / `ctor_vector3_arg_literal` | 同上 | P4（M4d ④）/ S13 |
| `ctor_vector4` / `ctor_vector4_arg_literal` | 同上 | S07 / S15 |
| `lit_float_range` | `real_t/float NAME = \| { \| ( <装不进 32 位 float 的字面量>` | P1（M4d ①）、S08 |
| `dbl_cast_into_float` | `real_t/float NAME = \| { \| ( (double) ...` | S09 |

**判据与运行时闸门同一份语义**：字面量只在**32 位副本彻底丢值**时报点
（`|v| > FLT_MAX` → `inf`；`v != 0` 而 `(float)v == 0` → `0`），
即 `MCPTools::value_fits_slot` 的 `FLOAT32`/`REAL_T` 分支（`tools/tool_helpers.cpp:1127-1149`）在源码层的镜像；
**范围内的精度损失（`1.1`）不报**（与闸门一致）。

**扫描形状的改动（这是能挡住 ③⑤ 的关键）**：扫描从「逐行」改为「整文件 code-only 文本」——
按字节保长地把 `/* */` 块注释、`//` 行注释、字符串/字符字面量涂白（换行保留），再在全文本上跑正则并按 offset 反推行号。
行扫描看不见跨行构造，而块注释必须处理：`tools/**` 里有 2032 行 `/*`（基本都是 2000 行级的许可证横幅）。

**`--coverage` 同时声明「不覆盖」的四条**（原样摘自输出）：

1. 运行时 `double` 隐式写进 `real_t`/`float`（`real_t x = some_double;`、`Color(some_double, ...)`、`Vector2 v(x, y)`）——
   需要类型信息；编译器能看见但**无法只作用于本模块**（§1.2）。
2. 只有经过表达式才越界的值（`real_t x = 1e300 / 2.0;`、构造实参是变量或函数调用）。
3. 整数收窄（`(int)`、`(uint8_t)`、`Vector2i`、packed int）——TASK-023 起显式排除。
4. `tools/**` 之外（模块其它源码与引擎都不扫）。

---

## 3. 五个探针的前后证据

### 3.1 「前」：在 `HEAD` 的干净副本上复现 D2（旧脚本 exit 0）

`git archive HEAD modules/mcp_server` → `%TEMP%\task031-before\`（**不碰工作树**），
旧脚本 sha256 前 16 位 `2f2931bf4f5dbb95`，且 `--coverage`/`lit_float_range`/`cast_static_float` 三项**都不存在**
（确认它是 pre-TASK-031 的版本）。把五个 M4d 探针原样追加到该副本的 `tools/running_game_read_scene.cpp`：

```
python <copy>\modules\mcp_server\scripts\check_narrowing_points.py --json  ->  exit 0
scanned=30  pinned=30  points_mentioning_audit_probe=0
```

（json 落盘 `%TEMP%\task031-before\before_five.json`，sha256 `d7eee214fbc78c1f691a64f2acc582a581ddbe98c6fa13c8bfe69a9684da60a8`）
→ **五个探针全部不可见**，与 `REPORT-AUDIT-M4d.md` §C 表一致。对照组（同一副本、只换成 `(real_t)` 写法）：

```
const real_t audit_probe_h = (real_t)1.0e300;
-> exit 1, [UNLISTED] tools/running_game_read_scene.cpp:797 UNMARKED
   FAIL: 4 narrowing point(s) carry no `// MCP-NARROWING:` marker
```

### 3.2 「后」：新脚本 + 探针回归脚本（85/85，exit 0）

`powershell -NoProfile -ExecutionPolicy Bypass -File modules/mcp_server/scripts/mcp031_gate6_coverage_probes.ps1`
（`%TEMP%\task031-probes-final.txt`，sha256 `27e58ebd1952d27444a7cd8b9239d04769b4a01893aeba568d0dd6b28e264dec`）
**85/85 PASS，exit 0**；汇总日志 `%TEMP%\task031-gate6-probes\gate6-coverage-probes.log.txt`
（sha256 `3eb9eff287ec9025343f7e884b77f806bd09bc4715ac9472db56c9123757c2c1`）。

| 探针 | 插入文本 | 期望 | 实况 |
|---|---|---|---|
| P1（M4d ①） | `const real_t audit_probe_c = 1.0e300;` | exit 1 | **exit 1**，`patterns=[lit_float_range]` |
| P2（M4d ②） | `const float audit_probe_d = static_cast<float>(1.0e300);` | exit 1 | **exit 1**，`patterns=[cast_static_float]` |
| P3（M4d ③） | `const Color audit_probe_e = ::Color(1.0e300, 0.0, 0.0, 1.0);` | exit 1 | **exit 1**，`patterns=[ctor_color]` |
| P4（M4d ④） | `const Vector3 audit_probe_f = Vector3{1.0e300, 0.0, 0.0};` | exit 1 | **exit 1**，`patterns=[ctor_vector3]` |
| P5（M4d ⑤） | `const Color audit_probe_g = Color`↵`(1.0e300, 0.0, 0.0, 1.0);` | exit 1 | **exit 1**，`patterns=[ctor_color]` |
| P6（M4d 对照） | `const real_t audit_probe_h = (real_t)1.0e300;` | exit 1 | **exit 1**，`patterns=[cast_real_t]`（无回退） |
| S01–S15 | 其余声明拼写各一（见 §2 探针列） | exit 1 | **15/15 exit 1**，pattern id 与声明一一对应 |
| B5 | 注释/块注释/字符串里的拼写 + `double`（WIDE）目标 + 范围内 `1.5f` | 不红 | **exit 0**，无 `task031_fp` 点 |
| B6 | `const real_t task031_boundary_result = p_v;`（`p_v` 是运行时 `double` 形参） | 不红（已声明） | **exit 0**，无该点 |
| B7 | 范围内构造 `Vector2 task031_boundary_direct(1.0, 2.0);` + 变量赋值 | 不红（已声明） | **exit 0**，无 `task031_boundary` 点 |

**每个探针都自带还原证据**：24 个探针各有一条 `*_reverted_byte_identical`（共 24 项，全 PASS）——
探针后 `git checkout --` 回来，`running_game_read_scene.cpp` 的 sha256 必须回到
基线 `9f768a53b72bb380d11ca5a935d25596ac22ca61fb8c84959248e1085a1ae439`
（85 = 7 项基线/覆盖声明 + 2 项声明自洽 + 24×3 项探针 + 4 项收尾），且结尾 `B1b_worktree_clean_of_probes` 断言
`git status --porcelain -- <file>` 为空、`B1b_restored_byte_identical` 为真。

**探针当场抓到一个真实缺口（本轮最重要的过程证据）**：第一次跑（`term` 输出 `60/62`）时
`S05_ctor_color_brace` **FAIL —— exit 0**。原因：`const Color name{...}`（**具名对象的列表初始化**）
不是临时量构造，`Color\s*(?=[({])` 看不见它；M4d 的 ④ 探针是临时量 `Vector3{...}`，所以从未暴露。
→ 于是把构造模式扩到 4 种无歧义形态（`T( )`、`T{ }`、`T name{ }`、`T name = { }`），
并新增用**字面量值**判定的 `T name( ... )` 形态（避免与「返回该类型的函数声明」混淆——当前树有 3 处
`Vector2 _f(...)` 这类声明）；补 S10–S15 与
`B4_every_declared_id_has_a_red_probe` / `B4_m4d_five_are_all_probed` 两条自洽断言后，**85/85**。

---

## 4. 误报评估

| 判据 | 实况 |
|---|---|
| 当前树 exit 0 | **exit 0**（`%TEMP%\task031-gate6-new2.txt`，sha256 `f11f127d476d64120699d46614412e50f544f396c7e1bfddec3a7067dad2e2ed`） |
| 点数 | `scanned=30 pinned=30`，`unannotated=0 unlisted=0 stale=0 moved=0` |
| **扩展是否引入新误报** | **否**：扩展前基线同为 `scanned=30 pinned=30`（`%TEMP%\task031-gate6-baseline.txt`），逐点 `Compare-Object` **零差异**；即 16 种声明拼写对当前 70 个文件 / 25 185 行**新增 0 命中** |
| 注释/字符串误报 | 已由 B5 探针覆盖：`//` 注释、`/* */` 块注释、字符串字面量里的 `1.0e300`/`Color(...)`/`Vector3{...}` **全部不可见**（2032 行块注释横幅是必须处理它的原因） |
| 合法加宽误报 | B5：`const double x = 1.0e300;`（WIDE 槽，合法）不可见；`const float f = 1.5f;`（范围内）不可见 |
| 函数声明误报 | 已实测：`Vector2 _get_screen_size()`、`Vector2 _node_position(Node *)`、`const Vector2 target((real_t)x, (real_t)y)` 都不新增点（前两者无字面量，后者本就被 `(real_t)` 命中） |
| 理论上的剩余误报面 | ①返回 `Color/VectorN` 且**默认实参是越界字面量**的函数声明会被 `*_arg_literal` 报点——但那本身就是一个缺陷，报出来是对的；②`T name = { }` 的空列表初始化（值初始化、全 0）会被 `ctor_*` 报点——只是要求标注，不产生假红 |

> 门⑥ 现在**只对它声明过的 16 种拼写负责**；`--coverage` 第 3 段原样打印四条「不覆盖」。
> 这句话同时写进了脚本 docstring、`--coverage` 输出、PASS 行与 `PLAYBOOK` §3。

---

## 5. 门⑥ 在保证体系中的新定位（按 §22.3b 规则 2/3）

- **门⑥ = 三道腿之一**：机器检查（本门）+ **代码审查**（新增写值路径必须点名它经过的闸门）
  + **行为证据**（M4 的静态错值反例矩阵）。**门绿 ≠ 覆盖面完整**，这一点现在写进了脚本 PASS 行、
  docstring、`--coverage` 的 `guarantee_position` 字段与 `PLAYBOOK`。
- 与 GDR-22 的分工不变：GDR-22 管「判对了没有」（`value_fits_slot` 只有一份实现），GDR-24 管「判到了没有」。
  本任务修的是 GDR-24 的**证明方式**：从「无边界宣称」改为「声明集合 + 逐拼写探针 + 明示边界」。
- 编译器级检查**没有**被采用，所以 §22.3b 规则 3 的「退化为标注一致性检查」**未发生**；
  但规则 3 的前提（编译器能覆盖更多拼写）在本仓库**不成立**——这条建议由决策者写进规范（见 §9）。
- 后续批次的硬要求（已写进 `PLAYBOOK`）：任何新增/修改收窄代码，报告里必须逐条列
  「新增点 × 它经过的闸门 × 证据」，不得只贴门⑥ 变绿。

---

## 6. 改动清单与 sha256

| 文件 | 状态 | sha256 |
|---|---|---|
| `modules/mcp_server/scripts/check_narrowing_points.py` | M | `46f09c36e4bfb0210cd83a6c5bbddc7fb42b5bde1e47d5e821b885e42f2d8c68` |
| `modules/mcp_server/scripts/mcp031_gate6_coverage_probes.ps1` | 新增 | `cfea71e6c8d3b67e2db4ef10fd76e057d9b04c5d7ed49c9f41b2de78e2eb1b69` |
| `modules/mcp_server/docs/tasks/PLAYBOOK-group-port.md` | M | `89a4f908b39ef5e43d6ee4b5857ed8b25184c5222c6a818965613d6f569fcf8e` |
| `modules/mcp_server/SCsub`（仅实验用，已还原） | 未改 | 实验前后均为 `094f4b32c96eccf802c5543a5283d6e5bdb3c0de94e04cea71673024f5baca06` |

- 两个脚本**纯 ASCII**（`mcp031_gate6_coverage_probes.ps1` 非 ASCII 字节数 **0**；
  `check_narrowing_points.py` 非 ASCII 字节数 **0**）——本机 PowerShell 5.1 按 ANSI 读无 BOM 脚本。
- `git status --porcelain` 收尾只剩既有未跟踪物：`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`。
- 探针实验的每个插入点都用 `git checkout --` 还原并逐字节比对（见 §3.2）。

---

## 7. 五道门 + 门⑥ 的真实输出与退出码

| 门 | 命令 | 退出码 | 关键实况 | 日志 sha256 |
|---|---|---|---|---|
| ① 契约子集逐字 | `check_contract_subset.ps1 -Group project_read_template` | **0** | `3/3 checks passed`；editor 9888 = **91** tools、game 9889 = **53** tools、contract = 171；`guard_user_port_9877: pid_before=36392 pid_after=36392` | `b49ffd36b915bcfde5e0b1deca8dab7365d562b838597fb663d378974d237c98` |
| ② 三类证据 | TASK-031 未新增工具 → 无新证据面；由 ③④⑤ 与 028/029/030 重跑覆盖 | — | 本任务不改任何工具行为（只改脚本/手册） | — |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **0** | `220 \| 220 passed \| 0 failed`，assertions `8481 \| 8481 passed \| 0 failed`，`Status: SUCCESS!` | `45e24b9261b06a28094d081435c744fd358f5c16cd13e986992bc124a00da3d4` |
| ④ 全引擎回归 | `--headless --test` | **0** | `1646 \| 1646 passed \| 0 failed`，assertions `432763 \| 432763 passed \| 0 failed`，`Status: SUCCESS!` | `14df176f7f0de4500abedae6425915f30d06f309db0d5364c60b62ec16e4bec5` |
| ⑤ 收口（连跑两次） | `accept_m1.ps1` ×2 | **0** / **0** | 两次均 `22/22 cases passed`；两次 PASS 清单 `Compare-Object` **完全一致**；`implemented tools = 91 (editor) / 53 (game); contract = 171` | run1 `357c6876a16b6f3c765343b14b77c5d3a712767e64be646a2bfb5562fdfae2b7`；run2 `37cd0cd393b08799b66c27478a139ffe7033769b4c3cee0ec520078d617683d8` |
| ⑥ 收窄点清单 | `check_narrowing_points.py`（+ `--coverage`）+ `mcp031_gate6_coverage_probes.ps1` | **0** / **0** / **0** | 门：`scanned=30 pinned=30`、`unannotated=0 unlisted=0 stale=0 moved=0`、`16 declared spellings`；`--coverage exit 0`；探针 **85/85 PASS** | 门 `f11f127d…`；coverage `B1_coverage.log`；探针 `3eb9eff2…`；探针输出 `27e58ebd…` |

（② 的说明：TASK-031 不新增/修改任何工具，故不存在新的成功/缺参/底层失败三角；其回归面由 ①③④⑤
以及 §8 的三个证据脚本重跑覆盖。）

---

## 8. 证据脚本重跑（确认无回退）

| 脚本 | 退出码 | PASS / FAIL | summary.json sha256 |
|---|---|---|---|
| `mcp028_subpaths_clear_import_evidence.ps1` | **0** | **54 / 0** | `18e118f655419ba9e84563112d0ee4f0cd372dd1cb066e7c11e0a7d501e87221` |
| `mcp029_clear_default_evidence.ps1` | **0** | **40 / 0** | `f450b13cd034e18d8287ee78ffaa6ebfcbb29dd8877835ad40e640e327860d7b` |
| `mcp030_live_open_scene_write_evidence.ps1` | **0** | **44 / 0** | `0cebccf9e860f94ae929bf50770912307eeaf5f5950f49fc8865ebd527864186` |

三个脚本的 `port_9877_owner_after` 断言均 PASS（用户 9877 未被占用/重启）。

---

## 9. `DESIGN-DETAIL` §22.3b 的反馈（**未改规范**，按指示报给决策者）

三处建议（都属于「补一条实测事实」，不改 §22.3b 的规则本身）：

1. **规则 3 的前提在本仓库不成立，建议落笔**：§22.3b 规则 3 写「若采用编译器级检查且它能覆盖更多拼写，
   则以编译器为准」。实测（本报告 §1.2）MSVC `/we4244` 对 `modules/mcp_server/**` **无法作用域化**：
   本模块 TU 包含的 17 个引擎头本身就触发 C4244（`SConstruct` 全局 `/wd4244` 的注释即 `Unavoidable at this scale`），
   升级为错误会让构建在不许修改的引擎代码上失败。建议在 §22.3b 增一句：
   「**本仓库实测**：编译器级收窄检查不可作用于本模块（详见 `REPORT-031` §1.2），故规则 3 暂不适用，
   运行时隐式收窄由代码审查 + 行为证据承担。」
2. **建议把「逐 pattern id 的探针」写进规则 1**：现在 `mcp031_gate6_coverage_probes.ps1` 已机器断言
   「`--coverage` 声明的每个 id 都必须有一个『插入即 exit 1』探针」；把这条写进规范可防止将来只探一部分拼写。
3. **建议把「边界也必须打印」写进规则 1**：本次让 `--coverage` 同时打印「不覆盖」的四条（§2），
   使“不覆盖什么”与“覆盖什么”一样可核对；建议规范要求这一条。

---

## 10. deviations / blockers / next_step_recommendation

### deviations（逐条显式）

1. **选 A 而非 B**：任务允许任选并对 B 说「若可行则优先」；实测 B 不可行（§1.2），故按 §1.1 的理由选 A，
   并把 B 与 B′ 的实测代价留在报告里。**这不是降低要求，而是把「过度声称」换成「声明边界」。**
2. **声明集比任务列举的多**：任务点名 5 种（+ 建议的 `static_cast<real_t>`、`(double)` 赋值、`real_t x{...}`、
   `Vector2(` 分行、`Color` 换行），实现为 **16 条 pattern id**（含函数式转换、具名列表初始化、
   具名直接初始化的越界字面量、块注释/跨行处理）。
3. **探针回归放在新脚本** `mcp031_gate6_coverage_probes.ps1`（§22.3b 允许「在脚本或证据里」），
   而不是塞进 `check_narrowing_points.py`；好处是扫描器保持纯 Python、无子进程。
4. **`PLAYBOOK` §3 门⑥ 单元格从一条命令变成三条**（门 + `--coverage` + 探针脚本）——任务授权改手册。
5. **门跑在 pre-commit 二进制上**：门于 `07614971f0` 上跑完，随后的两条提交只含 `scripts/**`/`docs/**`
   （`git diff --name-only 07614971f0 HEAD` 仅 3 个文件），无编译输入变化，故未再重建；
   若决策者要求「`--version` 必须等于提交后的 HEAD」，重建即可（预计只多一次版本文件重编 + 链接）。
6. **点的粒度仍是「一行一个点」**（与 TASK-023 一致）：同一行命中多个拼写只产生一个点，
   因此 `PINNED` 的 `(file, marker id, occurrence)` 身份与 30 个既有 pin **一位未动**
   （扩展前后 `Compare-Object` 零差异）。整文件扫描只改变了「能看见什么」，没有改变「怎么索引」。
7. `--coverage` 的文本输出经过 `_wrap_ascii` 重排（换行位置与脚本内单行字符串不同），
   仅是显示格式；机读形态在 `--json` 的 `coverage` 字段里。
7. 未修改 `DESIGN-DETAIL.md`（按指示）；`§22.3b` 的反馈见 §9。

### blockers

无。

### next_step_recommendation

1. 决策者按 §9 把三条实测事实落进 `DESIGN-DETAIL` §22.3b（尤其第 1 条：编译器路线的**实测不可用**）。
2. 后续任何批次只要新增/修改收窄代码，按新的门⑥ 三件套跑（门 + `--coverage` + 探针），
   **并在报告里逐条列「新增点 × 经过的闸门 × 证据」**（§22.3b 规则 2/4）。
3. 若将来真的需要「机器覆盖运行时隐式 `double→real_t`」，再评估 §1.4 的 B′（附实测代价），
   并作为**独立**的补充门，而不是替换门⑥。

---

## 附：本报告引用的原始证据位置（全部可再生）

| 证据 | 位置 | sha256（前 16） |
|---|---|---|
| 门⑥ 基线（扩展前） | `%TEMP%\task031-gate6-baseline.txt` | — |
| 门⑥（扩展后） | `%TEMP%\task031-gate6-new2.txt` | `f11f127d476d6412` |
| 探针回归输出（85/85） | `%TEMP%\task031-probes-final.txt` | `27e58ebd1952d274` |
| 探针回归汇总日志 | `%TEMP%\task031-gate6-probes\gate6-coverage-probes.log.txt` | `3eb9eff287ec9025` |
| D2 复现（旧脚本，HEAD 副本） | `%TEMP%\task031-before\before_five.json` | `d7eee214fbc78c1f` |
| 路线 B 实验 2（301×C4244 / exit 2） | `%TEMP%\task031_expB_build2.log` | `da71fd18db631105` |
| 路线 B 实验 1（D8021，流程证据） | `%TEMP%\task031_expB_build.log` | `120820c0481b4737` |
| 第 0 步构建日志 | `%TEMP%\task031_gate_build.log` | `8e05d1f36d9fb8e1` |
| 门①②③④⑤ 输出 | `%TEMP%\task031_gate{1,3,4,5_run1,5_run2}.txt` | 见 §7 |
| 合成 TU 编译器判定 | `%TEMP%\task031-probe\{probe.cpp,probe2.cpp,run.bat,run2.bat}` | — |
