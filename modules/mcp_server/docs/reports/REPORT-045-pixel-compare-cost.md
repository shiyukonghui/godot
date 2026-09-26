# REPORT-045 — 捕获的后续代价：像素比对改用 `Image::get_data()` 原始字节遍历

> 任务书：`docs/tasks/TASK-045-pixel-compare-cost.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`。
> 规范：`DESIGN-DETAIL.md` **§25/GDR-27 第 12 条**（TASK-044 实测的代价）与 `REPORT-044` §6-②（D4）。
> 分支 `feature/mcp-server-module`。**零契约变更**：不新增工具、不改任何 `inputSchema`/`description`；
> `docs/tools_list.renamed.json` 未动。改动只落在 `modules/mcp_server/**`（6 个文件，见 §0）。
> **规范未改一字**（`DESIGN-DETAIL.md` 只读）。

## 0. status / commits

- **status：`done`** —— 五道门 + 门⑥ 三段式全绿；**红→绿两阶段真实输出**；两个调用方的线上证据**逐字节不变**；
  **同一对 PNG 仍给出 `changed_pixels 106800 / total_pixels 5339554`**；背靠背往返 **453.6/458.6 ms → 377.6/386.3 ms**
  （同一次测量方法下 **−17.5% / −15.8%**），并给出**为什么没有更大**的实测归因（PNG 编码 357 ms，本任务未触及）。
- **commits**：
  - **`46d85b2e1d`** — `mcp_server: compare screenshots over the raw image bytes (TASK-045)`
    —— **这是承载全部实现代码的锚点（D86）**（`tools/tool_helpers.{h,cpp}`）。
  - **`548a1e2131`** — `mcp_server: doctests and live evidence for the raw-byte pixel comparison (TASK-045)`
    （4 个 doctest 用例 + 1 个实测脚本 + 门⑥ 的两处簿记）。
  - 第三条（仅文档）—— 本报告。
  - **构建时**（每一次门/battery 运行的那一刻）`git rev-parse --short HEAD` = `677061482b`，
    `bin\godot.windows.editor.x86_64.console.exe --version` = `4.8.dev.custom_build.677061482`
    —— **`--version` == HEAD 在运行时成立**。§12 给出提交后的重建与最终锚点。
- 工作树收尾只剩**既有的**未跟踪物：`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`
  （新增的 `scripts/mcp045_pixel_compare_cost.ps1` 已随第二条提交入库）。

### 改动清单（6 个文件，全部在 `modules/mcp_server/**`）

| 文件 | 角色 | 提交时 sha256 |
|---|---|---|
| `tools/tool_helpers.h` | 快路径的声明 + 两个 test-only 接缝 + 头注释 | `54d2938fb1eb9f03bd10f0fe410da811ff310c193b3470b2afb7657dc15f2429` |
| `tools/tool_helpers.cpp` | **原始字节快路径**（`raw_pixel_layout` / `raw_pixel_byte` / `raw_pixel_colour`）/ 逐像素回退保留 | `cc764a4e66a326dd5acf7b25adb5f88007234563cb5f22e037f5579ab0c07539` |
| `tests/test_mcp_server.h` | 4 个 TASK-045 用例（+5125 断言）；耗时由 `[MCP045-TIMING]` 打印 | `20f6b34a6e0f41558ec50a00a65e7e0307c015c6b900a2d741e20d2e8fde4ee2` |
| `scripts/check_narrowing_points.py` | 门⑥ PINNED：两个 `G24-DIFF-PIXEL-*` 各多一个 occurrence | `09049e125e374527d961a85fc9bda3ecbe0bb3e811fa216905f41490e378e4a7` |
| `scripts/mcp031_gate6_coverage_probes.ps1` | 门⑥ 探针脚本的 `scanned == pinned` 常数 73 → 75 | `932623363424a34597cc7873875dfebd811756d1d0b063fe4d97df7ab3e761ba` |
| `scripts/mcp045_pixel_compare_cost.ps1` | **新** 单引擎实测：捕获数字 / 两个调用方 / 三档往返分布 | `3b876cb250311fa6be3d8551df121183630ce0678e3d06df64ced24ffe3f43d6` |

> 新增 `.ps1` 为**纯 ASCII**（实测 `non-ascii bytes: 0`，§8）。
> 门配置：`modules/mcp_server/scripts/build_local.cmd -Force`（`tests=yes`，**从 cmd 启动**，串行、不抑制输出）。

---

## 1. 引擎依据（**文件:行**，先读引擎源码再动手）

| 事实 | 引擎依据 | 说明 |
|---|---|---|
| 原始缓冲可取且**不拷贝** | **`core/io/image.h:392`**：`const Vector<uint8_t> &get_data() const _LIFETIME_BOUND_;` | 返回**引用**（`Vector` 是 COW 句柄），不是 Godot 3 的 `PackedByteArray get_data()` 拷贝语义 |
| 图像格式 | `core/io/image.h:350`（声明）/ **`core/io/image.cpp:893`**（`Image::Format Image::get_format() const`） | 快路径的判据之一 |
| 像素→字节的索引 | **`core/io/image.cpp:3810-3818`**：`uint32_t ofs = p_y * width + p_x;`（**3816**）→ `_get_color_at_ofs(data.ptr(), ofs)`（3817） | `ofs` 是**像素下标**，行距 = `width` **像素**，即 `width * pixel_size` **字节**，**无行填充** |
| 每像素字节数 | `core/io/image.h:421`（声明）/ **`core/io/image.cpp:137-241`**（`get_format_pixel_size`） | L8=1、LA8=2、RGB8=3、RGBA8=4、RGBA4444=2、RGB565=2、RGBAF=16…（与上一条相乘即字节偏移） |
| 各格式的解码 | **`core/io/image.cpp:3558-3693`**（`Image::_get_color_at_ofs`） | L8 `3560-3563`（`float l = p_ptr[p_ofs] / 255.0; Color(l,l,l,1)`）、LA8 `3564-3568`、R8 `3569-3572`（`Color(r,0,0,1)`）、RG8 `3573-3577`、RGB8 `3578-3583`、RGBA8 `3584-3590` |
| 打包格式不是原始字节 | `3591-3596` → `color_from_rgba4444`（`3522-3528`，`/15.0` 量化）、`color_from_rgb565`（`3541-3546`） | 故 4444/565 **不进**快路径 |
| 压缩格式**取像素就报错** | **`3689-3691`**：`ERR_FAIL_V_MSG(Color(), "Can't get_pixel() on compressed image, sorry.")` | 快路径必须**排除**压缩格式，否则会连这条错误日志一起改掉行为 |
| 阈值的定义 | **`core/math/color.h:233`**：`get_r8() = int32_t(CLAMP(Math::round(r * 255.0f), 0.0f, 255.0f))`（g/b 见 235/237） | 「每通道字节差」就是它 |
| 缓冲长度 | `core/io/image.cpp:3842-3844`（`get_data_size()` = `data.size()`）/ `2542`（`initialize_data` 校验）。mipmap 时基级仍在偏移 0 | 快路径的守卫用 `data.size() >= width*height*pixel_size` |
| **调用方①是 RGBA8** | `scene/main/viewport.cpp:201-207`（`ViewportTexture::get_image()` → `RS::texture_2d_get`）→ `drivers/gles3/storage/texture_storage.cpp:1647`/`1722`（`Image::create_from_data(..., FORMAT_RGBA8, ...)`） | 捕获的两帧（2978×1793）落在快路径集合内 |
| **调用方②是 RGBA8** | `core/io/image.cpp:4650`（`load_png_from_buffer`）→ **`drivers/png/png_driver_common.cpp:94-95`**（`PNG_FORMAT_RGBA → FORMAT_RGBA8`）；写出侧 `156-157`（`FORMAT_RGBA8 → PNG_FORMAT_RGBA`） | 工具读的两张 PNG 解出来还是 RGBA8 —— 格式往返**在集合内闭合** |

---

## 2. 快路径的设计（以及**没选**的那条路）

```cpp
const Image::Format format_a = p_a->get_format();
const RawPixelLayout layout = raw_pixel_layout(format_a);       // 六格式之一才有 usable
const int64_t needed = total * (int64_t)layout.pixel_size;
const bool raw_path = raw_path_enabled && layout.usable && format_a == p_b->get_format() &&
        p_a->get_data().size() >= needed && p_b->get_data().size() >= needed;
```

1. **取原始字节**：`const uint8_t *bytes = p_a->get_data().ptr();`，按
   `row = bytes + y * width * pixel_size`、`pixel = row + x * pixel_size` 线性遍历 —— 与
   `image.cpp:3816` 的 `y*width+x` 下标**逐像素等价**。
2. **六个格式**（`L8 / LA8 / R8 / RG8 / RGB8 / RGBA8`）。`L8`/`LA8` 的 r/g/b 都来自同一个字节
   （引擎给 `Color(l,l,l,·)`），`R8`/`RG8` 的缺省通道在引擎里恒为 `0.0`，故布局用 `-1` 表示「该格式从不填」，
   取 0 —— 三条字节差与 `get_r8/get_g8/get_b8` 的三条差**同值**。
3. **每通道字节差直接用整数算**：`|byte_a - byte_b|`，`MAX(dr, MAX(dg, db)) > threshold` 原样。
   `!p_build_diff_image`（**捕获的默认模式**）时整条循环**一次 `Color` 都不构造**。
4. **差异图**：改动像素 `Color(1,0,0,CLAMP(max_diff/255.0,0.3,1.0))`（`max_diff` 与逐像素路径同源）；
   未改动像素走 `raw_pixel_colour()`，用**引擎自己的表达式** `float r = byte / 255.0;` 重建 `Color`，
   再做同样的 `* 0.3` —— 因此与逐像素路径**逐位相同**（§3 有穷举 + 差分双向证明）。
5. **格式不同时：退回逐像素路径**（**不用 `Image::convert()` 归一化**）。理由三条：
   - `convert()` 会多做一次整图拷贝，且它对 float/half/16-bit 源的取整路径**不是** `Color::get_r8`
     的那条（`_quantize_unorm_fast` 系 truncate(x+0.5)，与 `Math::round` 在边界上有别），
     「逐位等价」就不再是构造性成立的；
   - **没有调用方是这个形状**：捕获比的是同一视口的相邻两帧、工具比的是同一台引擎写出的两张 PNG，
     格式相同（§1 最后两行给了 file:line）；
   - 回退路径顺手保住了**第三类行为**：压缩图上 `get_pixel()` 的那条 `ERR_FAIL_V_MSG`（`image.cpp:3690`）
     与逐像素路径**一起**保留，快路径从不碰它。
6. **不变量**：非六格式（float/half/16-bit/4444/565/压缩）一律走原循环；`data.size()` 不足时也走原循环。
   原循环**逐字保留**（连两个 `MCP-NARROWING` 标记一起），因此任何未覆盖格式的行为字节级不变。

**test-only 接缝**（与 `MCPCapture::set_warn_total_bytes_for_tests` 同形）：
`set_compare_screenshot_pixels_raw_path_for_tests(bool)` 强制走哪条路，`compare_screenshot_pixels_last_call_used_raw_path_for_tests()`
报告「刚才那次真的走了快路径」——后者是**红阶段会失败的那条断言**（等价性断言在两条路上都成立，必须另有一条钉住「快路径被真的执行」）。

---

## 3. 等价性证据

### 3.1 有穷举证明的桥：`Color::get_r8()` == 存储字节

快路径的全部风险集中在一步：`get_r8(byte/255.0)` 是否恒等于 `byte`。
`TASK-045: Color::get_r8 answers the stored byte in the raw path's six formats` 对
**6 个格式 × 3 个通道 × 全部 256 个字节值**做了穷举（`core/math/color.h:233` 的 `round(c*255.0f)` 与
`core/io/image.cpp:3585` 的 `p_ptr[i]/255.0` 在同一表达式下误差 < 1.5e-5，远小于 0.5）。

### 3.2 差分证明：两条路的**判定与差异图都逐字节相同**

`TASK-045: the raw-byte path and the per-pixel loop agree bit for bit`：每个格式一组确定性伪随机图
（37×11，含 8 个完全相同、8 个差 1、8 个差 255 的像素）× {threshold 0, 10, 255} × {画/不画差异图}，
**同一对图**在两条路上各跑一次，比较 `width/height/changed_pixels/total_pixels/identical/diff_percentage`
以及（画图时）**差异图的 `get_data()` 原始字节**；同时 `CHECK` 快路径确实被走、被强制关掉时确实没被走。

`TASK-045: every format outside the six keeps the engine's per-pixel answer`：
`FORMAT_RGBAF` / `FORMAT_RGB565` / `FORMAT_RGBA4444` 三种非覆盖格式，以及 **RGBA8 vs RGB8 的混合格式对**，
与**测试内独立写的** `get_pixel`/`get_r8` 参考循环逐值相同，且断言快路径**未被走**。

### 3.3 两个调用方：线上证据逐字节不变

| 调用方 | 任务前（二进制 `5f37033c…`） | 任务后（二进制 `b1b6271a…`） | 判定 |
|---|---|---|---|
| **捕获**（`mcp_capture.cpp::_complete`） | `changed:true` `changed_pixels=106800` `total_pixels=5339554` `ratio=0.0200016705515105`；第二次同参 `changed:false/0` | **逐值相同** | ✅ |
| 捕获写下的两张 PNG | `865c2f93…` / `87731a87…` | **同一个 sha256** | ✅ |
| **工具**（`editor_analyze_screenshot_diff`） | `identical=false changed_pixels=106800 total_pixels=5339554 diff_percentage=2.0 2978×1793` | **逐值相同** | ✅ |
| 工具的 `diff_image_base64` | `sha256=46be55a6…` | **同一个 sha256** | ✅ |
| 工具的**整段 payload** | `sha256=51c697771432ad17aac0b8a0c9d81f4e56e13033d631a660af47bf95b7476034`（33405 B） | **同一个 sha256、同一个字节数** | ✅ |
| 工具自带 doctest（TASK-007 起未改一行） | 绿 | 绿（含在门③ 289/289 与门④ 1715/1715 内） | ✅ |
| 尺寸不一致的拒绝 | `-32602`，文案 `image_a is WxH and image_b is WxH`（**先尺寸、后 4096 上限**） | 未改（尺寸检查在两个路径之前，逐字保留） | ✅ |

> 「整段 payload 同 sha256」是最强形态：它把 `changed_pixels`、`diff_percentage`、
> **整个 `diff_image_base64`** 一次性逐字节比掉了 —— 即差异图内容（那两种差异色）也没变。

### 3.4 大图（捕获真实尺寸）上的等价

`TASK-045: the capture's own 2978x1793 pair ...`：对 2978×1793、改动 400×267=106800 像素的一对图，
断言 `total_pixels == 5339554`、`changed_pixels == 106800`、`diff_percentage == snapped(106800/5339554*100, 0.01)`，
并在 `p_build_diff_image=true` 下断言两条路的差异图 **21 MB 原始字节相同**、尺寸为 `5339554*4`。

---

## 4. 优化前后耗时实测（**测量方法与分布**，不是一个数）

> **方法（进程内 A/B，同一个二进制、同一进程、同一对图）**：doctest 用
> `set_compare_screenshot_pixels_raw_path_for_tests()` 在同一对 2978×1793 RGBA8 图上**交替**跑两条路，
> 每次用 `OS::get_singleton()->get_ticks_usec()`（`core/os/os.h`）计时，n 次后打印
> `n / min / median / max`（`[MCP045-TIMING]` 行，**只打印不断言**——挂钟断言是必然 flaky 的断言）。
> 复现命令：`bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="*TASK-045*"`。
> **两条路都在同一个二进制里**，所以「优化前」不是另一个二进制、也不是推断。

最终二进制 `b1b6271a…`（`--version 4.8.dev.custom_build.677061482`）：

| 模式（同一对 2978×1793，5339554 px） | 原始字节快路径 | 逐像素 `get_pixel` | 中位加速 |
|---|---|---|---|
| **只判 `changed`**（= 捕获的默认模式 `p_build_diff_image=false`） | `n=7 min=14.09ms median=16.05ms max=22.88ms` | `n=7 min=88.33ms median=92.15ms max=99.53ms` | **5.7×** |
| **画差异图**（= 工具的 `diff_image_base64` 模式） | `n=3 min=53.58ms median=54.40ms max=55.75ms` | `n=3 min=130.23ms median=135.03ms max=136.80ms` | **2.5×** |
| 同一对图的 **PNG 编码**（本任务**未触及**的另一半） | — | `before=24917 B in 177.04ms / after=24928 B in 178.96ms` | — |

另一次独立运行（同一源码、重建后的另一二进制 `4f7f7503…`）给出同量级分布：
只判 `changed` `raw median 13.85ms`（min 13.63/max 14.20）vs `per-pixel median 92.10ms`（min 88.73/max 100.20）→ **6.7×**；
画差异图 `53.21ms` vs `122.83ms` → **2.3×**；PNG 编码 `177.68ms / 179.13ms`。

**归因（实测，不是推理）**：捕获的主线程忙时 ≈ 往返 − 正常往返 ≈ `377.6 − 20 ≈ 357 ms`，
而**两张 PNG 的编码实测就是 `177.0 + 179.0 = 356.0 ms`** —— 也就是说 TASK-044 记的「约 400 ms」
里，**比对只占 ~89 ms，编码占 ~356 ms**；本任务把 89 ms 那一半压到 14 ms（**省下 ~75 ms**），
编码那一半**原样**。这与下面 §5 实测的往返差（**−80 ms**）在同一个量级上互相印证。

---

## 5. 新的**背靠背往返**数字（`--mcp-capture=every_call`）

> **方法**：`scripts/mcp045_pixel_compare_cost.ps1 -Label pre|post`，同一脚本、同一 scratch 工程、
> 同一台机器；`curl.exe -s -o <file> --data-binary @file` 打 9888，`[Diagnostics.Stopwatch]` 量整个 `curl` 进程；
> 每档 n=5；`every_call` 用 `--mcp-capture-viewport=2d`（2978×1793，与 TASK-044 同形）。
> `pre` 用**任务前二进制**（`git HEAD 677061482b` 的构建，sha256 `5f37033c…`，另存副本），
> `post` 用本任务二进制（`b1b6271a…`）。

| 时钟 | **pre**（`5f37033c…`） | **post**（`b1b6271a…`） | 差 |
|---|---|---|---|
| `curl` 往返 · `off` | n=5 min 0.0180 **median 0.0189** max 0.0251 | n=5 min 0.0172 **median 0.0201** max 0.0250 | +1.2 ms（噪声） |
| **`curl` 往返 · `every_call` 背靠背** | n=5 min 0.4361 **median 0.4577** max 0.4822 | n=5 min 0.3662 **median 0.3776** max 0.3845 | **−80.1 ms（−17.5%）** |
| `curl` 往返 · `every_call` 间隔 2.5 s | n=5 min 0.0291 **median 0.0318** max 0.0337 | n=5 min 0.0303 **median 0.0316** max 0.0345 | −0.2 ms（噪声） |
| `editor_analyze_screenshot_diff`（同一对图，n=3） | min 0.4233 **median 0.8223** max 0.8475 | min 0.3429 **median 0.6661** max 0.6871 | **−156 ms（−19%）** |
| 服务端 `duration_ms`（`editor_get_scene_tree`） | off pre 中位 0；`every_call` 中位 7（n=10） | off 中位 0；`every_call` 中位 7–8（n=10） | 未变（仍是那一次 framebuffer 拷贝） |

**TASK-044 自己的脚本（同一把尺子）**，`scripts/mcp044_capture_evidence.ps1 -Phase editor`：

| 项 | **pre** | **post** | 差 |
|---|---|---|---|
| `zero_latency_client_round_trip`（背靠背） | min 0.4520 **median 0.4586** max 0.4765 | min 0.3803 **median 0.3863** max 0.3936 | **−72.3 ms（−15.8%）** |
| 间隔 2.5 s | min 0.0291 median 0.0313 max 0.0342 | min 0.0302 median 0.0329 max 0.0342 | 噪声 |
| 服务端 `duration_ms` | off median 0 → on median 7（n=11） | off median 0 → on median 8（n=11） | 未变 |

**如实结论（含「没降那么多」的部分）**：

- 背靠背往返**确实降了**，但**不是数量级**：`453.6→377.6 ms`（本次同日测量 `457.7→377.6`），
  约 **−17.5%**；在 TASK-044 那个脚本里是 `458.6→386.3 ms`（**−15.8%**）。
- **降幅与比对自身的省下量吻合**：进程内 A/B 说省 ~75 ms、实测往返省 ~80 ms。
- **剩下的 ~357 ms 是两张 2978×1793 PNG 的编码**（实测 `177.0 + 179.0 ms`），**本任务范围之外**，
  也**不是**本任务能声称的战果。TASK-044 把「编码 + 比对 ≈ 400 ms」合在一起记，本任务把它**拆开了**：
  **比对 ~89 ms（已修）+ 编码 ~356 ms（仍在）**。
- **间隔 2.5 s 的往返没有变化**（31.8 → 31.6 ms）：这正是设计的语义 ——
  代价只落在「上一次应答之后的忙时」里，请求间有空隙时就看不见。
- 服务端响应路径仍是 **+7~8 ms**（一次 framebuffer 拷贝），TASK-044 的「零延迟」判据**未被本次改动影响**。

---

## 6. 红 / 绿（TDD）

**红（受控回退，缺行为时确实失败）**：最终树建成并绿之后，在
`tools/tool_helpers.cpp` 把快路径判据临时替换为 `const bool raw_path = false;`
（一行，带 `TASK-045 RED-PHASE PROBE` 注释），`build_local.cmd -Force` 重建后：

```
[doctest] test cases:    4 |    2 passed |  2 failed | 1714 skipped
[doctest] assertions: 5125 | 5088 passed | 37 failed |
[doctest] Status: FAILURE!
```

- 失败的**恰好是 37 条**「快路径真的被走了」的断言（6 格式 × 3 阈值 × 2 模式 = 36，加大图 1 条），
  `CHECK( MCPTools::compare_screenshot_pixels_last_call_used_raw_path_for_tests() )` 逐条报错；
- **另外两个用例（穷举 `get_r8`、非覆盖格式回退）在红阶段照绿** —— 它们本来就不依赖快路径被走，
  这正是「断言与它声称测的东西对齐」的旁证；
- 红阶段的时间行同时自证：`raw-byte median=96.31ms` vs `per-pixel median=96.54ms`（**1.0×**），
  即快路径**真的不在了**；PNG 编码行 `184.95 / 181.31 ms`（与本任务无关，两阶段同值）。
- 原始输出：`%TEMP%\mcp045_red.txt`。**回退代码已删除**，最终树中不存在。

**绿（最终树，二进制 `b1b6271a…`）**：

```
bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="*TASK-045*"   exit 0
[doctest] test cases:    4 |    4 passed | 0 failed | 1714 skipped
[doctest] assertions: 5125 | 5125 passed | 0 failed |
[doctest] Status: SUCCESS!
```

原始输出：`%TEMP%\mcp045_green_final.txt`。

> **诚实声明（与 TASK-044 D5 同型）**：红阶段是「实现完成之后」做的受控回退，不是「先写测试后写实现」的字面顺序。
> 但红阶段是**真的红**：37 条断言因缺少该行为而失败，且失败集正是新行为的作用面。

---

## 7. 门

| 门 | 命令 | 结果 |
|---|---|---|
| ⓪ 重建 | `scripts\build_local.cmd -Force`（**从 cmd 启动**，`tests=yes`，串行，不抑制输出） | exit **0**；`--version` = `4.8.dev.custom_build.677061482` == `git rev-parse --short HEAD` `677061482b` |
| ① 契约子集逐字 | `check_contract_subset.ps1`（mcp043 的 gate1a–1d + mcp042 的 gate1） | **各 3/3 PASS**，exit 0（契约零变化：本任务不新增/不改任何工具） |
| ② 三类证据 + 端到端链 | `mcp045_pixel_compare_cost.ps1 -Label post` (**15/15**) + `mcp044_capture_evidence.ps1` 四相（§9） | **15/15 + 62/62**，exit 0 |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **289/289 cases，21312/21312 断言，0 failed**，exit 0（基线 285/16187 → **+4 cases / +5125 断言**，只增不减） |
| ④ 全引擎回归 | `--headless --test` | **1715/1715 cases，445594/445594 断言，0 failed，3 skipped**，exit 0（基线 1711/440469 → +4 / +5125） |
| ⑤ 批收口 | `accept_m1.ps1` **连跑两次** | 两次都 **22/22 cases passed**，exit 0 |
| ⑥ 收窄点（三段式） | 见 §7.1 | 三段全绿 |

### 7.1 门⑥ 三段式（§22.3b 规则 4：**新增点逐条列**）

1. `python scripts\check_narrowing_points.py` → exit **0**：
   `scanned: 75 / pinned: 75 / coverage: 17 declared spellings`，**无 `[UNLISTED]`、无 `STALE`、无 `FAIL`**；
   剩下 10 条 `pinned_line` 漂移提示**全部来自本批之外的文件**（`editor_animation_tree_write.cpp`、
   `editor_input_simulation.cpp`、`editor_write_scene_editor.cpp`、`project_theme_write.cpp`，TASK-025/034/036 遗留），
   本任务引起的漂移已按提示更新到 `tool_helpers.cpp` 的现值。
2. `python scripts\check_narrowing_points.py --coverage` → exit **0**（17 条声明拼写与边界原文）。
3. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp031_gate6_coverage_probes.ps1`
   → **101/101 PASS**，exit 0（`log sha256=dddd322a41a0fab4d15954c751a4db454bc2f46854046af075ecf4f33f46b185`），
   且 `B1b_restored_byte_identical` / `B1b_worktree_clean_of_probes` 证明探针树被逐字节还原、工作树干净。

**新增收窄点 × 经过的闸门 × 证据**（规则 4 要求的逐条形式）：

| 新增点 | 经过的闸门 | 证据 |
|---|---|---|
| `tools/tool_helpers.cpp:1089` **`G24-DIFF-PIXEL-CHANGED` occurrence 0**（快路径的「改动像素」色） | 门⑥ 扫描器（`ctor_color` 拼写）+ PINNED 清单 | 扫描器报 `[safe] …G24-DIFF-PIXEL-CHANGED`；`scanned` 73 → **75** |
| `tools/tool_helpers.cpp:997` **`G24-DIFF-PIXEL-UNCHANGED` occurrence 0**（`raw_pixel_colour` 的 `byte/255.0 * 0.3`） | 同上 | 同上 |
| `tools/tool_helpers.cpp:1119` / `1123`（原 TASK-044 的两个点，occurrence 变成 1） | 同上 | 行号随插入漂移，PINNED 已更新 |
| `tools/tool_helpers.cpp` 的 `G24-THE-GATE` | 门⑥ 行号漂移提示 | `pinned_line` 1707 → **1718**，已更新（非语义变化） |
| `scripts/mcp031_gate6_coverage_probes.ps1` 的 `scanned == pinned` 常数 | 门⑥ 探针脚本自身的 `B1`/`B1b` 断言 | **73 → 75**，并同步注释里的增量链（73→75，TASK-045）；这不是放宽闸门：它仍断言「探针树还原后扫描数回到任务前的真值」 |
| `tests/test_mcp_server.h`（5125 条新断言） | **不在门⑥ 扫描面内**（扫描器只扫 `tools/**`） | 由门③/④ 覆盖；本轮新增代码只有 **2 个** 收窄点，已如上逐条登记 |
| 本批**未新增**任何其他拼写 | 门⑥ 三段 | `scanned` 净增**恰好 2**，与「两处 `Color(...)`」一一对应 |

---

## 8. 实测脚本与文件 sha256

`scripts/mcp045_pixel_compare_cost.ps1`：纯 ASCII（实测 `non-ascii bytes: 0`）。
一次运行产出（`%TEMP%\mcp045-evidence\evidence\<label>\`）：`summary.txt`、
`diff-tool-payload-1.json`（工具应答的 payload 原文）、`diff-tool-response-1.json`（含 envelope 的响应原文）、
`pair-before.png` / `pair-after.png`（那两张 24917 / 24928 字节的捕获 PNG）。

| 文件 | sha256 |
|---|---|
| `tools/tool_helpers.h` | `54d2938fb1eb9f03bd10f0fe410da811ff310c193b3470b2afb7657dc15f2429` |
| `tools/tool_helpers.cpp` | `cc764a4e66a326dd5acf7b25adb5f88007234563cb5f22e037f5579ab0c07539` |
| `tests/test_mcp_server.h` | `20f6b34a6e0f41558ec50a00a65e7e0307c015c6b900a2d741e20d2e8fde4ee2` |
| `scripts/check_narrowing_points.py` | `09049e125e374527d961a85fc9bda3ecbe0bb3e811fa216905f41490e378e4a7` |
| `scripts/mcp031_gate6_coverage_probes.ps1` | `932623363424a34597cc7873875dfebd811756d1d0b063fe4d97df7ab3e761ba` |
| `scripts/mcp045_pixel_compare_cost.ps1` | `3b876cb250311fa6be3d8551df121183630ce0678e3d06df64ced24ffe3f43d6` |
| 二进制（`bin\godot.windows.editor.x86_64.console.exe`，任务后） | `b1b6271a1490822b98bde1fbe5fedd487fa905e1add19ef64968668beb19c2e8` |
| 二进制（任务前，另存） | `5f37033cb4a7a03dee36f650f37a1270b7c31ce3c58944c6f5c5b97b4e27557a` |
| `docs/tools_list.renamed.json` | `c844ec8af9ef00d2e6ec7008c9806b3e2b16757e78794d3ccca0704edf844256`（**未动**，与 REPORT-038/044 一致） |

> **构建可复现性的诚实说明**：同一份源码重建两次，二进制的 sha256 **不同**
> （`4f7f7503…` → `b1b6271a…`，MSVC 在 PE/PDB 里写时间戳与 GUID），`--version` 两次都等于 HEAD。
> 因此本报告把**源码 sha256** 当作可复核的锚，把**行为证据**（doctest 计数、往返分布、payload sha256）
> 当作可比对的量，而不是拿二进制 sha256 当等价的依据。

---

## 9. 回归（逐条归因）

| 脚本 | 结果 | 归因 |
|---|---|---|
| `mcp044_capture_evidence.ps1` `editor` | **40/40 PASS**，exit 0 | 捕获的开关/存在理由/三视口/延迟全绿；`changed 106800 / 5339554` 未变 |
| `mcp044_capture_evidence.ps1` `headless` | **8/8 PASS**，exit 0 | `unavailable` + reason 未变 |
| `mcp044_capture_evidence.ps1` `game` | **9/9 PASS**，exit 0 | 游戏端点链（ratio 0.3215 → false）未变 |
| `mcp044_capture_evidence.ps1` `diff-image` | **5/5 PASS**，exit 0 | `diff.path/sha256` 未变 → **共享比对的差异图也没变** |
| **mcp044 合计** | **62/62 PASS** | 任务书 §2 要求的 62 条活证据 |
| `mcp045_pixel_compare_cost.ps1`（pre / post） | **15/15** ×2，exit 0 | 本任务的等价性 + 三档往返分布 |
| `mcp043_gates.ps1` | **28/28 STEP EXIT 0** | 见 §7（gate1a–1d、gate3、gate4、gate5×2、gate6a/b/c、gate2a–2i、regress mcp032/033/034/035/036/040_probes/040_racing） |
| `mcp042_gates.ps1` | **19/19 STEP EXIT 0** | 全绿 |
| `mcp041_gates.ps1` | **17/17 STEP EXIT 0** | 全绿 |
| `mcp038_zero_change.ps1` | **7/7 checks passed**，probes=22 stable=22 **changed=0** unstable=0 | §24 的「关-关-开」模板仍成立 |
| `mcp038_trace_evidence.ps1` | **12/12 checks passed**，trace lines=10 | 追踪行为未变（本任务未动 `mcp_trace.*`） |

**首轮归因的一次真实失败（已修正，如实记录）**：第一次跑 `mcp043_gates.ps1` 时
`gate6c_coverage_probes EXIT 1`，失败两条：`B1_baseline_scanned_73` 与 `B1b_restored_scanned_73`
—— 探针脚本把「当前树的收窄点总数」硬编码成 73（TASK-044 的现值），本任务新增 2 个点后真值是 **75**。
这是**簿记失配，不是行为缺陷**：`check_narrowing_points.py` 本身（`scanned == pinned` 的权威判定）当时已 exit 0。
修法是把常数与增量链一起更新为 75（§7.1 末两条已逐条登记），随后**整条 mcp043 battery 复跑 28/28 EXIT 0**、
`gate6c` **101/101 PASS**；`mcp042` / `mcp041` 在常数修正后同一步也是 EXIT 0。

---

## 10. 偏差 / 边界 / 风险（**逐条如实**）

- **D1（设计选择）格式不同时回退，不 `convert()`**：理由见 §2.5。代价：一个「内容相同、格式不同」的对
  仍然是老的逐像素代价。**两个调用方都不是这个形状**（§1 末两行给 file:line），所以这是**有意的边界**而非缺口。
- **D2（设计选择）快路径只覆盖 6 个格式**：float/half/16-bit/4444/565/压缩一律走原路径。
  4444/565 的桥也是可证的（`255/15 = 17` 精确、`n5*255/31` 无 .5 边界），但**没有调用方**，不予实现。
- **D3（偏差，**需决策者留意**）背靠背往返只降了 ~17%，不是数量级**：实测把 TASK-044 的「~400 ms」
  拆成 **比对 ~89 ms（本任务已修到 ~14 ms）+ 两张 PNG 编码 ~356 ms（未动）**。
  若要让 `--mcp-capture=every_call` 真正「廉价」，下一步必须处理 **PNG 编码**（省掉或降级编码、
  或把编码/落盘/比对移出主线程）——**已作为 §13 的下一步建议**报决策者。
  本条**只影响性能，不影响任何正确性**：`changed` 判定与差异图逐位不变。
- **D4（边界）`Color` 的重建用引擎的表达式而非引擎的函数**：`raw_pixel_colour` 复写了
  `_get_color_at_ofs` 六个分支里 `byte / 255.0` 那一句。风险是**上游改解码**时漂移；
  缓解是 §3.1 的穷举 + §3.2 的差异图逐字节差分（后者是**直接**对照，不依赖推理）。
  非覆盖格式**没有**这个风险（它们仍调用 `get_pixel`）。
- **D5（偏差）红阶段是受控回退**：见 §6 末尾的诚实声明。
- **D6（既有）门⑥ 的 10 条 `pinned_line` 漂移提示**：全部来自本批之外的文件，非本任务引起。
- **D7（既有）`mcp_capture.cpp` 不在门⑥ 扫描面内**（扫描器只扫 `tools/**`）：本任务未动该文件。
- **风险 R-1**：本任务把上限从「比对」移到「编码」后，`every_call` 的主线程忙时仍 ~357 ms；
  **高频背靠背调用仍会排队**（§25 第 12 条的已知代价仍然成立，只是数值从 ~450 降到 ~380）。
- **风险 R-2**：`get_data()` 返回的引用在 `compare_screenshot_pixels` 内被持有于两幅图的
  `Ref<Image>` 生命周期内，无失效路径；但**若将来有人把 `p_a`/`p_b` 换成临时对象**，
  `_LIFETIME_BOUND_` 只能靠编译器告警拦住 —— 已在源码注释里写明。
- **风险 R-3**：两个 test-only 接缝是**文件级可变全局**（`raw_path_enabled`、`raw_path_used_by_last_call`）。
  生产二进制里没有任何调用点，且每个用例在进入时显式 `set(true)`，所以「上一个用例忘了还原」不会污染下一个用例；
  但它确实是进程级共享状态，只有在「有人把接缝用进生产路径」时才会变成真风险 —— 已在头文件注释里写明用途。
- **不是风险（已核对）**：`texture_2d_get` 返回的 `Image` 可能是按 `alloc_width` 建的
  （`texture_storage.cpp:1647`），但那条路径下 `get_width()` 报的就是 `alloc_width`，
  而快路径用的行距是 `p_a->get_width() * pixel_size` —— 与 `get_pixel` 的 `y*width+x`（`image.cpp:3816`）
  **用的是同一个 `width`**，因此行距不可能与逐像素路径不一致。

---

## 11. 对决策者的请求（§25 落笔）

1. **修订 §25 第 12 条**：把「~400 ms」拆成**实测**的两半 ——
   **比对 ~89 ms（TASK-045 已降到 ~14 ms）** + **两张 PNG 编码 ~356 ms（仍在）**；
   并把背靠背往返的现值写成 **453.6/458.6 → 377.6/386.3 ms**（不是「无代价」，也不是「已解决」）。
2. **§25 第 12 条补一句边界**：像素比对本身在只判 `changed` 时已是 **~16 ms 中位（5.7×）**；
   要让 `every_call` 在高频下不再排队，**下一个任务必须是 PNG 编码**（本任务的范围外，未动）。

---

## 12. 提交锚点（D86）

- 代码锚点：**`46d85b2e1d`**（`mcp_server: compare screenshots over the raw image bytes (TASK-045)`），
  本报告给出 6 个文件的 sha256；**提交不改文件字节**。
- 测试/脚本锚点：**`548a1e2131`**。
- `--version` 在**每一次**门/battery 运行的那一刻等于当时的 `git HEAD`（`677061482` ⊂ `677061482b`）。
- 本节为 **append-only**：提交后的重建与最终锚点见 §13（提交后追加）。

---

## 13. 提交后复跑（append-only）

三条提交落下之后（`46d85b2e1d` 实现 / `548a1e2131` 测试与脚本 / `07d886438a` 本报告），
从**已提交的树**用 `scripts\build_local.cmd -Force`（从 cmd 启动，`tests=yes`，串行）重建：

```
bin\godot.windows.editor.x86_64.console.exe --version   ->  4.8.dev.custom_build.07d886438
git rev-parse --short=10 HEAD                           ->  07d886438a      (== --version，前缀一致)
engine sha256                                           ->  e7c18b29cc820ccfdd7ae72b2ab64abef918af7259887d49815836fa0cc1323b
```

**整条 battery 在这一二进制上复跑（10 个 STEP 全部 EXIT 0）**：

| 项 | 结果 |
|---|---|
| `mcp045_pixel_compare_cost.ps1 -Label post` | **15/15 PASS**；`diff_tool_payload_1_sha256=51c697771432ad17aac0b8a0c9d81f4e56e13033d631a660af47bf95b7476034`（**与 pre 逐字节相同**）、`diff_image_base64 sha=46be55a6…`、两张 PNG sha 仍是 `865c2f93…`/`87731a87…`；`changed 106800 / 5339554` |
| `mcp044_capture_evidence.ps1` 四相 | **40 + 8 + 9 + 5 = 62/62 PASS** |
| 门③ `gate3_module_doctest` | **289/289 cases，21312/21312 断言，0 failed** |
| 门④ `gate4_full_doctest` | **1715/1715 cases，445594/445594 断言，0 failed，3 skipped** |
| 门① `gate1a–1d` / `gate1` | 各 **3/3 PASS** |
| 门⑤ `gate5_accept_run1/2` | 两次 **22/22 cases passed** |
| 门⑥ `gate6a` | `scanned: 75 / pinned: 75`，exit 0（10 条漂移提示全在本批之外） |
| 门⑥ `gate6c_coverage_probes` | **101/101 PASS**（`log sha256=dddd322a…`，与前次运行**同一 sha**） |
| `mcp043_gates.ps1` | **28/28 STEP EXIT 0** |
| `mcp042_gates.ps1` / `mcp041_gates.ps1` | **19/19** / **17/17 STEP EXIT 0** |
| `mcp038_zero_change.ps1` / `mcp038_trace_evidence.ps1` | **7/7**（probes=22 stable=22 changed=0）/ **12/12** |

**最终锚点这一轮的往返数字（与 §5 同一脚本、同一工程）**：

| 时钟 | pre（`5f37033c…`） | 最终锚点（`e7c18b29…` = HEAD `07d886438a`） |
|---|---|---|
| `curl` 往返 · `every_call` 背靠背（mcp045 脚本） | n=5 min 0.4361 median **0.4577** max 0.4822 | n=5 min 0.3841 median **0.3950** max 0.7724（含一次 0.77 s 系统级离群） |
| `curl` 往返 · `every_call` 背靠背（**mcp044 脚本**） | n=5 min 0.4520 median **0.4586** max 0.4765 | n=5 min 0.3677 median **0.3765** max 0.3866 |
| `curl` 往返 · 间隔 2.5 s | median 0.0318 / 0.0313 | median 0.0687 / 0.0623（**该轮机器明显更吵**，见下） |
| `editor_analyze_screenshot_diff`（同一对图） | n=3 median 0.8223 | n=3 median 0.6682 |

> **诚实说明（这一轮的噪声）**：最终锚点这一轮里**间隔取样**的三档数字比 §5 那一轮高一倍多
> （0.05–0.08 s vs 0.029–0.035 s），服务端 `duration_ms` 也从 `median 7–8` 抬到 `median 8.5 / max 11`，
> 说明该轮机器整体更忙；**背靠背**这一档在两轮里一致（`0.3765`–`0.3950` vs pre 的 `0.4577`/`0.4586`），
> 因此 §5 的对照表引用的是**较安静的那一轮**，本节如实给出最终锚点轮的原值，两者不矛盾。
> 判定性结论（背靠背 **降 ~72–80 ms**、payload **逐字节不变**）在两轮里都成立。

- **FINAL-ANCHOR**：**`07d886438a`**（本报告所在提交）——`--version` == `git HEAD` **在提交之后仍然成立**，
  且 10/10 STEP（含门①/③/④/⑤/⑥、mcp044 的 62 条活证据与全部历史回归 battery）全绿。
- 代码锚点仍是 **`46d85b2e1d`**（§0 / §12）；两者之间只有测试/脚本/文档两个提交，**不含任何实现字节变化**
  （§8 的 6 个文件 sha256 可逐一对上）。
- 本节自身也是 **append-only**：为记下这一轮结果而后加的这一个提交**只改本文件**，
  不含任何代码或测试字节变化。

---

## 14. 勘误（append-only）

- **E-1（首轮）**：`mcp045_pixel_compare_cost.ps1` 初版把「三次相同调用的**响应体** sha256 相同」
  当作可重复性判据，实测 FAIL —— 响应 envelope 里含请求的 `id`，**构造上就不可能相同**。
  已改为比较 **payload**（`result.content[0].text`）的 sha256，并在脚本注释里写明原因；
  **pre/post 两轮在改后的脚本上都是 15/15**。这条留在这里而不是删掉：它是「判据必须与语义对齐」的第 N 个实例。
- **E-2（首轮）**：首轮 `mcp043_gates.ps1` 因门⑥ 探针脚本的 73 常数而 `gate6c EXIT 1`，
  已在 §9 末尾如实归因，并在修正后整条复跑 28/28。