# REPORT-046 — 捕获的**编码代价**：引擎快速 PNG + 可选缩放（把背靠背 ~380 ms 压下来）

> 任务书：`docs/tasks/TASK-046-capture-encode-cost.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`。
> 规范：`DESIGN-DETAIL.md` **§25/GDR-27 第 12 条**（TASK-044/045 实测的代价拆分）与 `REPORT-045` §4/§5。
> 分支 `feature/mcp-server-module`。**零契约变更**：不新增工具、不改任何 `inputSchema`/`description`；
> `docs/tools_list.renamed.json` 未动。改动只落在 `modules/mcp_server/**`（**9 个文件**，见 §1）。
> **规范未改一字**（`DESIGN-DETAIL.md` 只读）。

## 0. status / commits

- **status：`done`** —— 五道门 + 门⑥ 三段式全绿；**红→绿两阶段真实输出**；
  **两张 2978×1793 PNG 的编码 354 ms → 69.4 ms（每帧中位 174.1 → 34.7 ms，5.0×）**；
  **背靠背往返 377.6 ms → 98.8/99.0 ms（同一把尺子、同一脚本、同一工程，−73.8%）**；
  `scale=2` 再降到 **87.0–89.1 ms**（安静样本），其代价已在**进程内**拆开（§5）；
  TASK-044/045 的**像素证据逐字节不变**（`106800/5339554`、diff 工具 payload sha `51c69777…`、
  `pre=off=on` 22/22 探针逐字节相同）。
- **commits**：见 §14（本节在提交后 append）。
- 工作树收尾只剩**既有的**未跟踪物：`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`
  （新增的 `scripts/mcp046_capture_encode_cost.ps1` 入库）。

### 1. 改动清单（9 个文件，全部在 `modules/mcp_server/**`）

| 文件 | 角色 | 提交时 sha256 |
|---|---|---|
| `mcp_capture.h` | `Config.scale` + `scale_from_name` 声明 + 头注释（响应路径的承诺现在包含缩放） | `1cfd5d172dfce901bc7c87deb01c2db98aa5cfc5a8763301f2af0e0d8b9672b4` |
| `mcp_capture.cpp` | `--mcp-capture-scale` 的解析 / 启动行 `scale=` / 日志字段 `scale` / **`_scaled_frame`（缩放发生在比对与落盘之前）** / `_write_png` 走 fast | `fdd1a55d4a98604dd697791c7fb2de99b5cc932bab04c26e83aae8ea57dab30d` |
| `tools/tool_helpers.h` | **新** `write_screenshot_png(path, image, p_fast)` 的声明与引擎依据注释 | `6ecf2b9aaace39779c883eb7d2244108a1f129e9f7fd1e7b56e3f840ab71a474` |
| `tools/tool_helpers.cpp` | 该函数的实现（`p_fast=false` **就是** `Image::save_png()`，逐字节、逐错误码；`true` 走 `_save_png_to_buffer(true)` 后写文件） | `187b70c71ef1117998bfd2740af53f4e8fcb5204bad8e50bc8caa5c0675fc302` |
| `tests/test_mcp_server.h` | 4 个 TASK-046 用例（+119 断言）；耗时由 `[MCP046-TIMING]` 打印 | `4c9dfd0687e830cb01c594ba94948d755d01122cfed983f9d378880947512db7` |
| `scripts/check_narrowing_points.py` | 门⑥ PINNED：`tool_helpers.cpp` 的 5 条 `pinned_line` 随 +36 行漂移更新（**无新收窄点**，`scanned` 仍 75） | `525321422110c74884434093a480c8309279b57b24593edf8537d12a9bed3ef1` |
| `scripts/mcp045_pixel_compare_cost.ps1` | `-PngEncoding fast\|default`：捕获 PNG 的字节锚点改成**按编码可选**（见 §8 D-2），其余断言一字不改 | `d0a6b25b98c00ad097da60689476513e387956e5d4d1e1f408c3dca2743739c3` |
| `scripts/mcp044_capture_evidence.ps1` | **headless 相的一处既有竞态**：它当场读 trace，而捕获行是**下一帧**才追加的 ⇒ 会给假红。改成调用它自己已有的 `Wait-ForCaptureEvents`（见 §10 D-10） | `91c6504cb929d93abde97cbd1c3f5e92632a478102b1a184bd530af200ee9da5` |
| `scripts/mcp046_capture_encode_cost.ps1` | **新** 单引擎实测：两档缩放 × 背靠背分布 + 一致性 + 启动行 + 端口守卫 | `16854f00aef260d547ecdc2e496487126613cca120ffb3b09f9622a8c658b2c4` |

> 三个 `.ps1` 均**纯 ASCII**（实测 `non-ascii bytes: 0`，§9）。
> 门配置：`modules/mcp_server/scripts/build_local.cmd -Force`（`tests=yes`，**从 cmd 启动**，串行、不抑制输出）。

---

## 2. 引擎依据（**文件:行**，先读引擎源码再动手）

| 事实 | 引擎依据 | 说明 |
|---|---|---|
| **任务书的一处前提需要修正** | `tools/tool_helpers.h:334`（原）`Error screenshot_png_writer(const String &, void *)`；`core/io/image.h:396` `Error save_png(const String &p_path) const;` | 两者**都没有** `p_fast`。任务书写的「`MCPTools::screenshot_png_writer` 已有该形参」不成立；`p_fast` 只存在于下一层的 `PNGDriverCommon::image_to_png`。见 §10 D-1 |
| `p_fast` 的唯一入口 | **`drivers/png/png_driver_common.h:43`** / **`.cpp:128`**：`Error image_to_png(const Ref<Image> &, Vector<uint8_t> &, bool p_fast = false)` | 它就是「PNG 写入器已有的形参」 |
| `p_fast` 变成什么 | **`drivers/png/png_driver_common.cpp:142-144`**：`if (p_fast) png_img.flags = PNG_IMAGE_FLAG_FAST;` | — |
| libpng 侧的效果 | **`thirdparty/libpng/pngwrite.c:2172-2184`**：`PNG_IMAGE_FLAG_FAST` → `png_set_filter(PNG_FILTER_TYPE_BASE, PNG_NO_FILTERS)` + `png_set_compression_level(png_ptr, 3)` | **这才是省下来的时间的来源**（不做行滤波 + 压缩级别 3）；定义在 `thirdparty/libpng/png.h:3190` |
| C++ 侧可达 `p_fast` 的路径 | **`core/io/image.h:400`** / **`core/io/image.cpp:2926-2932`**：`Vector<uint8_t> Image::_save_png_to_buffer(bool p_fast = false) const` → `save_png_buffer_func(Ref<Image>(this), p_fast)` | 返回**裸缓冲**，不是错误码；`p_fast` 由此透传 |
| 该函数指针由谁注册 | **`drivers/png/resource_saver_png.cpp:85-88`**：同一个构造函数把 `save_png_func = &save_image`（**默认编码**，`Image::save_png` 走的）与 `save_png_buffer_func = &save_image_to_buffer`（**带 p_fast**）一起装上 | 因此两条路在**同一个** `ResourceSaverPNG` 里闭合，不存在「另一个编码器」 |
| 库内**先例**：走 fast 缓冲写普通文件 | **`servers/movie_writer/movie_writer_pngwav.cpp:147-150`**：`_save_png_to_buffer(true)` + `FileAccess::open(WRITE)` + `store_buffer` | 高频 PNG 写出正是 `movie_writer` 的形状；本次沿用同一对调用 |
| 缩放的形状/边界 | **`core/io/image.cpp:1286-1297`**：`resize` 对 `p_width/p_height <= 0` 直接 `ERR_FAIL_COND` **且不改变图像**；`MAX(1, ..)` 的守卫因此是「小图仍然良定义」而不是「防崩」 | `_scaled_frame` 的守卫依据 |
| 缩放**不改写源** | **`core/io/image.cpp:1654`**：`_copy_internals_from(dst)`（`data = dst.data`，`Vector` 是 COW 句柄） | 因此 `duplicate()` + `resize()` 不会穿透写回「源帧」，`duplicate()` 本身也只是句柄拷贝 |
| **2× 双线性 = 精确 2×2 盒平均** | **`core/io/image.cpp:1005-1049`**（`_scale_bilinear`）：`src_xofs_left_fp = (j+0.5)*src_w*256/dst_w`；`dst_w = src_w/2` 时 `left = 2j`、`right = 2j+1`、`frac = 0x80`（=0.5） | 4 个抽头各 0.5×0.5 ⇒ **盒滤波**，2× 无走样。4× 时只取 2/4 列 ⇒ **欠采样**（见 §10 D-3） |
| `duplicate()` 不会被 `TOOLS_ENABLED` 的缓存图像坑到 | **`drivers/gles3/storage/texture_storage.cpp:1544-1552`**：编辑器构建下 **非 render target** 的 `texture_2d_get` 返回 `texture->image_cache_2d`（**共享的** Ref） | 视口纹理是 render target（走读回分支），但「可能是共享对象」这一事实正是**不能原地 resize** 的理由 |
| 缩放的**先例** | `half_resolution`：`tools/running_game_frame_observation.cpp:460-472`（任务态）+ **`tools/tool_helpers.cpp:2655`**（`game_viewport_image`，`INTERPOLATE_LANCZOS`） | 先例给的是「有这个开关 + 除数语义」；**插值没照抄**，见 §4/§10 D-3 |
| 日志 schema（本任务加 `scale`） | **`docs/DESIGN-DETAIL.md:921-924`**（§25 第 5 条的字段表） | 新增一个字段 = 规范的表需要补一行，已作为 §11 的请求报给决策者 |

---

## 3. 两条杠杆的设计（以及**没选**的那条路）

### 3.1 快速压缩 —— 只在**捕获旁路**里

```cpp
// tools/tool_helpers.cpp
Error write_screenshot_png(const String &p_path, const Ref<Image> &p_image, bool p_fast) {
	if (p_image.is_null()) { return ERR_INVALID_PARAMETER; }
	if (!p_fast) {
		return p_image->save_png(p_path);          // ← 既有调用方的原话，逐字节/逐错误码
	}
	const Vector<uint8_t> buffer = p_image->_save_png_to_buffer(true);
	if (buffer.is_empty()) { return ERR_UNAVAILABLE; }   // 把「无 PNG saver」还原成 save_png 的拒绝
	...FileAccess::open(WRITE) + store_buffer...
}
```

```cpp
// mcp_capture.cpp::Engine::_write_png —— 只有捕获走 true
const Error err = MCPTools::write_screenshot_png(p_path, p_image, true);
```

1. **`screenshot_png_writer` 一字未改**（它仍是 `(*image)->save_png(path)`），
   `editor_capture_screenshot` / `running_game_capture_screenshot` 通过 `publish_file_atomically` 调的还是它 ⇒
   两个既有工具的**发布字节、拒绝条件、错误码**全都在构造上没变（不是「测出来没变」）。
2. `p_fast=false` 分支**刻意不复刻**缓冲路线：`_save_png_to_buffer` 在
   `save_png_buffer_func == nullptr` 时返回**空缓冲而不是错误**，照抄会让「构建里没有 PNG saver」
   从 `ERR_UNAVAILABLE` 变成「写出了 0 字节」。所以 false 分支就是 `Image::save_png()` 本身。
3. **没选**：给 `screenshot_png_writer` 加 `p_fast` 形参再让工具有意识传 false。
   否决理由：那要动**两个既有工具**（`publish_file_atomically` 的函数指针签名）才能拿到零收益，
   而本任务的等价性要求正是「两个调用方 payload sha 不变」。多一个参数 = 多一条能把它们的字节改掉的路径。
4. **没选**：`#include "drivers/png/png_driver_common.h"` 直接调 `image_to_png`。
   否决理由：那是 `drivers/**` 的私有驱动接口，`_save_png_to_buffer` 是引擎自己给 C++ 调用者留的门
   （`movie_writer` 就在用），并且**只在 PNG saver 被注册时存在**——与 `Image::save_png` 同一条件，
   行为面更容易论证。

### 3.2 可选缩放 —— **比对与落盘之前**，且只在应答之后

```cpp
// mcp_capture.cpp::Engine::_complete（应答已经写出、至少一帧之后）
const Ref<Image> before_image = _scaled_frame(entry.before, config.scale);
const Ref<Image> after_frame  = _scaled_frame(after_image,     config.scale);
... _write_png(before_path, before_image) / _write_png(after_path, after_frame) ...
... image_fields(before_image, ...) / image_fields(after_frame, ...) ...
... compare_screenshot_pixels(before_image, after_frame, ...) ...
```

1. **位置是这条杠杆的全部要点**：`scale` 在**第一次落盘之前**、**比对之前**施加一次，
   比对与两个文件此后用的是**同两个 `Ref<Image>`**。因此
   `changed_pixel_ratio` 与文件**在构造上**自洽——拿那两个文件调 `editor_analyze_screenshot_diff`
   得到的就是同一行日志的数字（§6 有单元与线上两重证据）。
2. **不能放在 `arm()`**：那会把一次整帧重采样放到**响应路径**上，违反 §25 第 4 条「唯一的应答期工作是
   一次 framebuffer 拷贝」。`_scaled_frame` 在 `mcp_capture.cpp` 里**只有一个调用点**（`_complete`），
   这是可代码审查的（§8 R-2 声明了它**没有**被单元断言钉住，靠线上 `duration_ms` 不变来钉）。
3. **`scale=1` 走 `return p_image;`**：不 `duplicate()`、不 `resize()`，因此默认路径与 TASK-044/045
   是同一段代码、同两个 `Ref`。这也是「`scale=1` 的像素证据逐字节不变」的构造性理由。
4. **`duplicate()` 而不是原地 resize**：快照是**可注入**的（`Task044::FakeViewport` 会把同一个 `Ref`
   交给前后两帧，真实视口在「没有重绘」时也一样），原地 resize 会把同一张图**减半两次**。
   `duplicate()` 是 COW 句柄拷贝，`resize()` 新建光栅再整体赋值（`core/io/image.cpp:1654`），
   所以既便宜又不可能穿透写回源帧。
5. **`scale` 是闭集 `1|2|4`**，非法值**报一次 WARN 并保留默认 1**（视口开关的规则），
   **不会**把已经开着的捕获关掉（模式开关的规则）——理由写在 `scale_from_name` 的注释里。
6. **`scale` 只从命令行读**，不进 `ProjectSettings`：§25 第 2 条只给了 `godot_mcp/capture` 一个设置键，
   本任务不做第 4 个设置键（任务书也只要一个开关）。已作为 §10 D-5 声明。

---

## 4. 红 / 绿（TDD）

**红（受控回退，缺行为时确实失败）**：实现完成并绿之后，把**两条杠杆各退回一行**
（`_scaled_frame` 直接 `return p_image;`、`_write_png` 传 `false`，两处都带
`// TASK-046 RED-PHASE PROBE`），`build_local.cmd -Force` 重建后：

```
[doctest] test cases:    4 |    2 passed |  2 failed | 1718 skipped
[doctest] assertions:  103 |   91 passed | 12 failed |
[doctest] Status: FAILURE!
```

- 失败的**恰好 12 条**，全部落在两条杠杆的作用面上：缩放侧 10 条
  （`before/after` 的 `width/height` 仍是 8×4、`total_pixels` 仍 32、`changed_pixels` 16>8、
  「capture 的字节 == 双线性重建」不等、磁盘上重载的尺寸仍是 8×4），
  fast 侧 1 条（`capture_sha == fast_probe` 不等 —— 红阶段同一行自证：`capture=91 bytes / fast=87 / default=91`，
  即捕获写的是**默认编码**）；
  另有 1 条（`capture_sha != lanczos_probe`）在红阶段**照绿**，它本来就不依赖缩放，是「断言与它声称测的东西对齐」的旁证。
- **两个配置用例（拼写/默认/非法值）在红阶段照绿**：它们不经过被回退的行为。
- 红阶段的 `[MCP046-TIMING]` 行同时自证 fast 与缩放的代价没有变（它们不依赖被回退的两行）：
  `png-flag gradient default=1007 / fast=161944 bytes`、`png-encode default median=184.66ms / fast 38.27ms`。
- 原始输出：`%TEMP%\mcp046_red.txt`。**回退代码已删除**（`findstr RED-PHASE` 无命中），最终树中不存在。

**绿（最终树）**：

```
bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="*TASK-046*"   exit 0
[doctest] test cases:    4 |    4 passed | 0 failed | 1718 skipped
[doctest] assertions:  119 |  119 passed | 0 failed |
[doctest] Status: SUCCESS!
```

原始输出：`%TEMP%\mcp046_green_final.txt`。

> **诚实声明（与 TASK-044 D5 / TASK-045 §6 同型）**：红阶段是「实现完成之后」做的受控回退，不是
> 「先写测试后写实现」的字面顺序。但红阶段是**真的红**：12 条断言因缺少该行为而失败，且失败集正是新行为的作用面。

### 4.1 4 个用例分别钉什么

| 用例 | 钉的东西 | 关键断言 |
|---|---|---|
| `the capture scale switch defaults to 1 and follows the companion precedent` | 拼写表（`1/2/4` 双向）、`=` 与空格两种形态、last-wins、非法值→WARN+保留 1、显式 1、以及**缩放不自己打开捕获** | `CHECK(config.scale == 1)`、`CHECK(config.warning.contains("1 / 2 / 4"))`、`CHECK(config.mode == Mode::OFF)` |
| `scale 2 resamples both frames before the comparison, and the files agree with the line` | **一致性**：日志尺寸/`total_pixels` 是被缩放的光栅；**插值按字节钉住**；磁盘上重载两张 PNG 后再走模块唯一的比对，数字必须等于日志 | `total_pixels == 8`、`capture_sha == bilinear 重建`、`capture_sha != lanczos 重建`、`from_file.changed_pixels == event["changed_pixels"]` 等 6 条 |
| `scale 1 keeps the TASK-044 numbers and the capture writes the fast PNG bytes` | 默认路径的三个 TASK-044 数字不变；**捕获确实走 fast 路线**；`p_fast=false` **就是** `Image::save_png` | `changed_pixels == 1`、`total_pixels == 32`、`sha(before) == sha(fast 写出)`、`sha(tool_probe) == sha(save_png 直接写)` |
| `the fast PNG flag changes the bytes and the resample cost is the lever's own cost` | fast 真的换掉了字节（光滑渐变上是 1007 → 161944 B）、**两种编码无损同像素**、两段耗时分布、以及整条 pipeline 在 scale=1/2 上的归因 | `gradient_fast_bytes != gradient_default_bytes`、两份解码数据相等、`pipeline scale=1/2` 的 `total_median` |

---

## 5. 三段耗时的**前后对照**（方法 + 分布，不是一个数）

> **方法（进程内 A/B，同一个二进制、同一进程、同一对 2978×1793 图）**：doctest 用
> `OS::get_singleton()->get_ticks_usec()`（`core/os/os.h`）计时，交替取样后打印
> `n / min / median / max`（`[MCP046-TIMING]` 与 TASK-045 留下的 `[MCP045-TIMING]` 行，**只打印不断言**）。
> 复现：`bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="*TASK-04*"`。
> **「优化前」不是另一个二进制**：默认编码与 fast 编码**在同一个二进制里**（`_save_png_to_buffer(false|true)`），
> 比对的两条路同理（TASK-045 的接缝）。

| 段 | **前**（TASK-045 / 默认编码） | **后**（TASK-046） | 判定 |
|---|---|---|---|
| **只判 `changed`**（捕获的默认模式） | `n=7 median 16.05ms`（REPORT-045 §4）；本任务复跑同一用例 `n=7 median 12.61ms` | **同左**（这一段本任务一字未改，差异是整机噪声：REPORT-045 的两次独立运行本身就是 16.05 / 13.85 ms） | **未变**（本任务不去声称这段的功劳） |
| **含差异图**（工具的 `diff_image_base64` 模式） | `n=3 median 54.40ms`（REPORT-045 §4） | `n=3 median 56.31ms`（同上，同一段代码） | **未变** |
| **两张 PNG 编码**（每帧中位） | **`177.04 / 178.96 ms`**（REPORT-045 §4，两次编码分别计时） | **默认编码 `174.11 ms`**（本任务复跑，落地 `49845 B/两帧`）→ **fast `34.72 ms`**（落地 `223131 B/两帧`） | **每帧 5.0×、两帧 354 → 69.4 ms（−284.6 ms）** |
| **整条应答后管线**（重采样 + 两次 fast 编码 + 判定） | 未分解（TASK-045 只给了比对与编码两半） | **scale=1：`0 + 69.80 + 14.41 = 84.21 ms`**；**scale=2：`39.22 + 17.53 + 3.42 = 60.18 ms`** | 见下 |

> **这一格的噪声也如实标出**：同一段默认编码在**另一轮**（加了管线测量那一次的二进制）测得
> `n=4 median=262.99 ms`，而同一轮的 fast 仍是 `36.03 ms` —— 整机负载把**绝对值**抬高了近 90 ms，
> 却几乎没动 fast 那一边（它是纯 CPU，且不做行滤波）。因此这一格的**判定性数字是比值 5.0×**，
> 绝对值以**同一轮内的成对取样**为准（两段代码在同一个二进制里，见本节的「方法」）。

**这一分解与线上往返互相印证**（不是推理）：`off` 基线中位 19.8 ms，`scale=1` 背靠背中位 100.8 ms ⇒
主线程忙时 ≈ **81 ms**，而进程内管线实测 **84.21 ms**（差 3 ms，同量级）。TASK-045 的同一算法是
`377.6 − 20 ≈ 357 ms` 对 `356 ms`。两次都闭合。

**如实说明「没降那么多」的部分**：

- 编码本身**降了 5.0×**，但**体积涨了**：同一对图 `24917/24928 B` → `113929/112102 B`
  （**4.57× / 4.50×**）。这是 `PNG_NO_FILTERS` + level 3 的直接代价，见 §6.1。
- **`scale=2` 不是免费的**：重采样自己就要 **39.22 ms/两帧**（双线性），它把编码省下的 52 ms 拿回去一部分，
  净省 **24.03 ms**（84.21 → 60.18）。若按先例用 `INTERPOLATE_LANCZOS`，重采样是 **79.5 ms/两帧**
  ⇒ 管线 **~100 ms**，**比 scale=1 还慢** ——所以生产用的是双线性，理由与数字见 §10 D-3。

---

## 6. `every_call` 下的**新背靠背往返**（scale=1 与 scale=2）

> **方法**：`scripts/mcp046_capture_encode_cost.ps1`，同一脚本、同一 scratch 工程、同一台机器、
> `curl.exe -s -o <file> --data-binary @file` 打 9888，`[Diagnostics.Stopwatch]` 量整个 `curl` 进程；
> 每档 n=5；`every_call` 用 `--mcp-capture-viewport=2d`（2978×1793，与 TASK-044/045 同形）；
> **原始样本逐个记录**（`*_samples=` 行），因为这台机器的负载被实测证明是**波动**的。
> 另用 **TASK-045 自己的脚本**（同一把尺子）跑同一二进制，以便与 REPORT-045 §5 的表**逐格对齐**。

### 6.1 同一把尺子（`mcp045_pixel_compare_cost.ps1`，安静轮）

| 时钟 | **前**（TASK-045，`b1b6271a…`） | **后**（TASK-046，`ee206205…`） | 差 |
|---|---|---|---|
| `curl` 往返 · `off` | n=5 min 0.0172 **median 0.0201** max 0.0250 | n=5 min 0.0176 **median 0.0198** max 0.0249 | −0.3 ms（噪声） |
| **`curl` 往返 · `every_call` 背靠背** | n=5 min 0.3662 **median 0.3776** max 0.3845 | n=5 min 0.0976 **median 0.1008** max 0.1106 | **−276.8 ms（−73.3%）** |
| `curl` 往返 · `every_call` 间隔 2.5 s | **median 0.0316** | **median 0.0304** | 噪声（设计的语义：代价只在背靠背里看得见） |
| `editor_analyze_screenshot_diff`（同一对文件） | n=3 min 0.4233 **median 0.6661** max 0.6871 | n=3 min 0.3017 **median 0.3431** max 0.3700 | **−323 ms（−48%）**，见下 |
| 服务端 `duration_ms`（`editor_get_scene_tree`） | off 中位 0；`every_call` n=10 中位 **7**（min 7 max 8） | off 中位 0；`every_call` n=10 中位 **7**（min 7 max 8） | **未变**（仍是那一次 framebuffer 拷贝） |

> **`editor_analyze_screenshot_diff` 也快了一倍**（0.666 → 0.343 s）：它读的正是捕获写下的那两张 PNG，
> 而 `PNG_NO_FILTERS` 让**解码**也省掉了反滤波。这是杠杆①的**副产物**，不是本次的目标，如实记录。
>
> **锚点轮（`81417f58…`，§12/§13 的那一轮）在同一脚本上复现了这张表**：
> `off` min 0.0179 **median 0.0217**、背靠背 min 0.0783 **median 0.0990** max 0.1111、
> 间隔 median 0.0316、diff 工具 median 0.3362；服务端 `duration_ms` off 中位 0 / every_call 中位 7（n=10）。

### 6.2 `scale=1` 与 `scale=2`（`mcp046` 脚本，三轮，原始样本）

| 轮 | 二进制 sha256 | `off` | **`scale=1` 背靠背** | **`scale=2` 背靠背** | `scale=2`/`scale=1` |
|---|---|---|---|---|---|
| 1 | `d031814d…` | min 0.0175 median 0.0191 max 0.0238 | min 0.1023 **median 0.1035** max 0.1126 | min 0.0998 median 0.1660 max 0.2003 | 1.603 |
| 2 | `ee206205…` | min 0.0230 median 0.1010 max 0.2058 | min 0.0992 **median 0.0997** max 0.1094 | min 0.0794 **median 0.0905** max 0.1571 | 0.908 |
| 3 | `ee206205…` | min 0.0204 median 0.0731 max 0.1253 | `0.0760 0.1022 0.1107 0.1011 0.1049`（min 0.0760，**median 0.1022**） | `0.1979 0.1978 0.0897 0.0966 0.0809`（min 0.0809，**median 0.0966**） | 0.945 |
| **4（锚点 `81417f58…`，另跑 mcp045 脚本）** | `81417f58…` | min 0.0179 median 0.0217 max 0.0256（mcp045 脚本）；mcp046 脚本这一轮 off 被污染（median 0.0750） | `0.1061 0.0394 0.0985 0.1097 0.0988`（min 0.0394，**median 0.0988**）；mcp045 脚本 **median 0.0990**（min 0.0783 max 0.1111） | `0.0983 0.0891 0.1013 0.0880 0.0870`（min 0.0870，**median 0.0891**） | 0.902 |

**判定性结论（四轮都成立）**：

- **`scale=1`：377.6 → 98.8–103.5 ms（中位），−73%**；四轮的中位差不到 5 ms，**跨轮稳定**，
  与进程内预测（84.2 + 19 ≈ 103）一致。锚点轮用 **TASK-045 自己的脚本**得到 **median 0.0990**，
  与 REPORT-045 那一格的 `0.3776` 是**同一脚本、同一工程、同一统计量**的直接对照。
- **`scale=2` 再省 ~10 ms**：安静样本 `0.0794–0.0891`，与进程内预测（60.2 + 19 ≈ 79）一致；
  轮 1 的 `median 0.1660` **是污染样本**（同一轮机器的 `png-encode default` 中位从 174 抬到 263 ms），
  轮 3 也有 2 个 ~198 ms 的离群点。**不做「scale=2 一定更快」的隐身处理**：这里给出的原始样本本身就是证据。
- **间隔 2.5 s**：`0.0272–0.0354 s`，与 TASK-045 的 `0.0316/0.0338` 同区间 ⇒ §25 第 12 条的语义未变。
- **端口纪律**：四轮 `pid_before == pid_after == -1`（9877 本次运行期间**无人监听**）；脚本**只**起停 9888。

### 6.3 启动行与日志字段（可观察性）

- 启动行：`[MCP] capture enabled: mode=every_call viewport=2d dir=res://mcp046_shots_scale1 diff_image=false scale=1`
  —— `scale=<n>` **追加在行尾**，这样既有证据脚本对 `... diff_image=false` 的 `-SimpleMatch` 子串断言
  （`mcp044_capture_evidence.ps1:424/685/753/817`）**继续命中**，不需要改它们。
- 捕获行新增 **`"scale": <n>`**（每一个 status 都写）。§25 第 5 条的字段表**没有这一格**，
  但它是「日志数字与文件自洽」的必要证据（不看 scale 就无法判断那对文件是哪一档）。

---

## 7. `scale` 的**一致性证据**：日志数字 == 拿文件调 `editor_analyze_screenshot_diff` 的数字

这是任务书点名的**陷阱**（「日志数字与文件对不上——不允许」），因此给了**两重**独立证据。

### 7.1 单元（doctest，`scale=2`）

`scale 2 resamples both frames before the comparison, and the files agree with the line`：
8×4 的平滑对（左半 +40 灰度级）在 scale=2 下 → 4×2 = 8 px，`changed_pixels=4 of 8`（与「2×2 盒平均
保持对齐台阶」的解析预期**逐个吻合**），然后**从磁盘重载**那两张 PNG（4×2）再走模块唯一的比对：

```
CHECK(from_file.changed_pixels == (int64_t)event["changed_pixels"])      // 4 == 4
CHECK(from_file.total_pixels   == (int64_t)event["total_pixels"])        // 8 == 8
CHECK(from_file.identical == !((bool)event["changed"]))
CHECK(|event["changed_pixel_ratio"] - changed/total| < 1e-12)
```

外加**插值按字节钉住**：捕获写出的 `0001_before.png` 与「同一份 `duplicate()+resize(4,2,BILINEAR)`
经同一个 helper 写出」**sha256 相同**，与 LANCZOS 重建**不同**。

### 7.2 线上（活证据，2978×1793 → 1489×896）

| 档 | 捕获行（`mcp046_shots_scale*/…` 的日志） | 把**同一对文件**喂给 `editor_analyze_screenshot_diff` | 判定 |
|---|---|---|---|
| `scale=1` | `changed_pixels=106800 total_pixels=5339554 ratio=0.0200016705515105` | `106800 / 5339554 / 2978×1793`，ratio 同值 | **逐值相同** |
| `scale=2` | `changed_pixels=26800 total_pixels=1334144 ratio=0.0200877866257316` | `26800 / 1334144 / 1489×896`，ratio 同值 | **逐值相同** |

（`scale2_the_the_files_are_the_halved_raster` 与 `scale2_the_line_agrees_with_the_files` 两条检查；
`scale=1` 的对应两条也 PASS。三轮运行全部 22/22、23/23、23/23。）

**反面证明**：如果把缩放只加在落盘上（红阶段就是这一形态的一部分），
`total_pixels` 会是 32 而文件的尺寸是 4×2 —— 正是那条被红阶段抓住的断言。

---

## 8. 等价性证据（`scale=1` 时 TASK-044/045 的全部证据）

| 主张 | 证据 | 判定 |
|---|---|---|
| 同一对帧仍给出 **`106800 / 5339554`**（ratio 0.0200016705515105） | mcp046 脚本 `scale1_changed_true_with_the_task_044_numbers`（三轮 PASS）；doctest 的 8×4 数字 `1/32` 未变 | ✅ |
| 同一调用第二次仍 **`changed:false`** | `scale1_no_op_success_is_changed_false`（`changed=False changed_pixels=0`） | ✅ |
| **两个调用方 payload sha 不变**：diff 工具整段 payload 仍 `51c697771432ad17aac0b8a0c9d81f4e56e13033d631a660af47bf95b7476034` | mcp046 `scale1_the_two_callers_still_answer_the_same_pixels`（三轮 PASS）+ `mcp045` 脚本 `diff_tool_payload_1_sha256` 同一个值 | ✅ |
| 两个调用方**像素判定**不变（`identical/changed_pixels/total_pixels/width/height`） | 同上；`diff_image_base64` 的内容由像素决定，payload 逐字节相同即差异图逐字节相同 | ✅ |
| `every_call` 与 `off` 的**响应**仍逐字节相同，且与**任务前二进制**也相同 | `mcp044_zero_change.ps1`：22 个探针 × {pre, off, on}，**22/22 `pre=off=on`，changed=0，unstable=0** | ✅ |
| 捕获的存在理由实验（真改动 → `changed:true`；同参重放 → `changed:false`） | `mcp044_capture_evidence.ps1` 的 `existence_proof_*` 四条 | ✅ |
| 捕获的 62 条活证据 | `mcp044_capture_evidence.ps1` 四相 **40 + 8 + 9 + 5 = 62/62 PASS**（与 REPORT-045 逐相同） | ✅ |
| 两个既有截图工具的字节 | 构造上：`screenshot_png_writer` 一字未改；单元上：`write_screenshot_png(...,false)` 与 `Image::save_png()` 写出的文件 **sha256 相同**（`probe_tool` vs `probe_direct`） | ✅ |
| **PNG 文件本身的 sha256 必然改变**（杠杆①的定义） | `865c2f93…/87731a87…` → **`c2d7a1bf…/4516082843…`**，且**跨轮可复现**（mcp046 三轮 + mcp045 一轮，同一个值；`.ps1` 里已作为 `-PngEncoding fast` 的锚点登记） | ⚠️ 有意为之，见 D-2 |

> **「`scale=1` 逐字节相同」的判读（必须说清，见 D-2）**：任务书同时要求
> 「捕获落盘走 `p_fast=true`」与「`scale=1` 时行为必须与 TASK-045 逐字节相同」。
> 这两条**不可能同时**指 PNG 文件字节——杠杆①的全部作用就是把文件字节换掉。
> 因此按任务书 §1.4 自己列出的等价清单理解：**像素/判定/两个调用方 payload/响应字节**不变，
> **PNG 文件字节按杠杆①的预期改变且如实报出**。这一判读已作为偏差报给决策者。

---

## 9. 实测脚本与文件 sha256

`scripts/mcp046_capture_encode_cost.ps1`：纯 ASCII（实测 `non-ascii bytes: 0`，len 33586）。
`scripts/mcp045_pixel_compare_cost.ps1`：纯 ASCII（`non-ascii 0`）。
一次 mcp046 运行产出（`%TEMP%\mcp046-evidence\evidence\<label>\`）：
`summary.txt`、`off/`、`scale1/`、`scale2/`（各含 `diff-tool-payload.json` 与 `pair-before/after.png`）。

| 文件 | sha256 |
|---|---|
| `mcp_capture.h` | `1cfd5d172dfce901bc7c87deb01c2db98aa5cfc5a8763301f2af0e0d8b9672b4` |
| `mcp_capture.cpp` | `fdd1a55d4a98604dd697791c7fb2de99b5cc932bab04c26e83aae8ea57dab30d` |
| `tools/tool_helpers.h` | `6ecf2b9aaace39779c883eb7d2244108a1f129e9f7fd1e7b56e3f840ab71a474` |
| `tools/tool_helpers.cpp` | `187b70c71ef1117998bfd2740af53f4e8fcb5204bad8e50bc8caa5c0675fc302` |
| `tests/test_mcp_server.h` | `4c9dfd0687e830cb01c594ba94948d755d01122cfed983f9d378880947512db7` |
| `scripts/check_narrowing_points.py` | `525321422110c74884434093a480c8309279b57b24593edf8537d12a9bed3ef1` |
| `scripts/mcp044_capture_evidence.ps1` | `91c6504cb929d93abde97cbd1c3f5e92632a478102b1a184bd530af200ee9da5` |
| `scripts/mcp045_pixel_compare_cost.ps1` | `d0a6b25b98c00ad097da60689476513e387956e5d4d1e1f408c3dca2743739c3` |
| `scripts/mcp046_capture_encode_cost.ps1` | `16854f00aef260d547ecdc2e496487126613cca120ffb3b09f9622a8c658b2c4` |
| 二进制（**锚点** `81417f58…`，§12/§13 的全部门与回归） | `81417f58d3cda007af9a888e3f309ee46577f50e841bc20c9d5103b3cc0aeaab` |
| 二进制（任务后，mcp043/mcp045 轮） | `ee206205cf3901a6ac2a4c6b8d369dda44772a7b5d08e2dbe9853bb39b26911c` |
| 二进制（任务后，mcp046 第一轮） | `d031814d5553e283dc13ef17ef014e5e189d5e7fe107462ee976914ae4bee350` |
| 二进制（任务前，另存 `%TEMP%\mcp046-pre\`） | console `a836f90e8f362dc73a86d84c84482e2c50945ecdf10d42ef812f0464d2999fa9` |
| `docs/tools_list.renamed.json` | `c844ec8af9ef00d2e6ec7008c9806b3e2b16757e78794d3ccca0704edf844256`（**未动**，与 REPORT-038/044/045 一致） |

> **构建可复现性的诚实说明（沿用 REPORT-045 §8）**：同一份源码重建两次，二进制 sha256 **不同**
> （MSVC 在 PE/PDB 里写时间戳与 GUID）；`--version` 每次都等于当时的 HEAD。
> 本报告把**源码 sha256** 当可复核的锚，把**行为证据**（doctest 计数、两份 PNG 的 sha256、
> payload sha、往返分布）当可比的量。**`d031814d…` 与 `ee206205…` 之间只改了 `tests/test_mcp_server.h`**
> ——两份捕获 PNG 的 sha256 在两轮里**完全相同**，这就是「生产行为没变、只是重链接」的直接证据。

---

## 10. 偏差 / 边界 / 风险（**逐条如实**）

- **D-1（任务书前提修正，需决策者留意）任务书说 `MCPTools::screenshot_png_writer` 已有 `p_fast` 形参 ——
  它没有。** `tools/tool_helpers.h:334`（原）与 `core/io/image.h:396`（`save_png`）都没有该参数；
  `p_fast` 只在 `drivers/png/png_driver_common.h:43`，C++ 侧经 `Image::_save_png_to_buffer`（`core/io/image.h:400`）可达。
  本任务按「引擎侧 `image_to_png(..., p_fast)` → `PNG_IMAGE_FLAG_FAST`」的**实质**实现（§3.1），
  并在 `tool_helpers.h` 里写下了整条 file:line 链。
- **D-2（判读偏差，**需决策者留意**）「`scale=1` 逐字节相同」不可能指 PNG 文件字节**（§8 末的推理）。
  按任务书 §1.4 自列的等价清单执行：像素/判定/payload/响应不变（全部有证据），
  文件字节按杠杆①改变（`865c2f93…/87731a87…` → `c2d7a1bf…/4516082843…`，可复现）。
  因此 **`scripts/mcp045_pixel_compare_cost.ps1` 的字节锚点必须参数化**（`-PngEncoding fast|default`，
  默认 `fast`，`default` 保留给任务前二进制）：脚本原先硬编码的那一条检查（`the_two_captured_pngs_are_the_task_044_bytes`）
  在本任务之后**按定义**就会红。改法是**只**把「期望值」按编码可选，并把测得的 sha256 每轮都打进 `notes`；
  其余 14 条断言一字未改，`scale=1` 的像素与 payload 断言仍是**逐字节**的。
  **不隐藏**：这条是「证据被证伪时要撤回」的应用，而不是把红改成绿。
- **D-3（设计选择，**需决策者留意**）缩放的插值**没有照抄 `half_resolution` 的 `INTERPOLATE_LANCZOS`**。
  理由是一个**实测数**：2978×1793 上重采样两次，LANCZOS **77.2–83.1 ms**、BILINEAR **18.8–20.9 ms**；
  加上 fast 编码（scale=2 时 `17.5 ms`）与判定（`3.4 ms`），LANCZOS 的整条管线 ≈ **100 ms**，
  **比 `scale=1`（84.2 ms）还慢** ——即「要更便宜的捕获」这个开关自己变成更贵的那一个。
  BILINEAR 使管线 **60.2 ms**，且 **2× 时它是精确的 2×2 盒平均**（§2 的 `_scale_bilinear` 推导，
  4 抽头各 0.5×0.5），**2× 无走样**。代价：**4× 时它每轴只取 2/4 列 ⇒ 欠采样**，
  对**诊断光栅**可接受，但**没有隐瞒**。若决策者更看重保真，改成 LANCZOS 是**一个词**，
  数字都在本报告里。用例 `the fast PNG flag...` 同时印出两种插值的分布，`scale` 用例再按**字节**钉住选择的是哪一种。
- **D-4（设计选择）`scale` 只从命令行读，不进 `ProjectSettings`**：§25 第 2 条只声明了 `godot_mcp/capture`
  一个设置键；本任务不擅自新增第 4 个键（任务书也只要 `--mcp-capture-scale`）。
- **D-5（规范补充，需决策者落笔）捕获行新增 `"scale"` 字段**：§25 第 5 条的 schema 表需要补一行；
  启动行末尾追加 `scale=`（为了保证既有脚本的 `-SimpleMatch` 子串断言继续命中）。
  两者都在 §11 作为请求报出。**本实现不得改 `DESIGN-DETAIL.md`**（手册 §7.2）。
- **D-6（边界，如实）`scale>1` 的加速**只在**背靠背**场景可见；间隔 2.5 s 时三档都是 ~30 ms（§6.2）。
  这是 TASK-044 就定下的语义（代价落在「上一次应答之后的忙时」）。
- **D-7（边界）`scale=4` 的欠采样**（D-3）：8×4→2×1 这类小图上 `MAX(1, ..)` 会给出 2×1 而不是 2×1
  的整数倍关系；`Image::resize` 对 `<=0` 会拒绝且**不改变图像**，守卫因此是必要的而不是防御性的。
- **D-8（既有）**门⑥ 的 **10 条 `pinned_line` 漂移**全部来自本批之外的文件
  （`editor_animation_tree_write.cpp`、`editor_input_simulation.cpp`、`editor_write_scene_editor.cpp`、
  `project_theme_write.cpp`，TASK-025/034/036 遗留）。**本任务引起的 5 条漂移已按提示更新**
  （`tool_helpers.cpp`，+36 行），更新后 gate6a 只剩这 10 条。
- **D-9（既有）`mcp_capture.cpp` 不在门⑥ 扫描面内**（扫描器只扫 `tools/**`）：
  本期**新增的收窄代码为 0**，`scanned` 73 → 75（TASK-045）→ **75（本任务不变）**。
  `mcp_capture.cpp` 的新代码（`_scaled_frame` 的整数除法、`MAX(1,..)`、闭集 `p_scale`）
  按 §22.3b 的两条腿覆盖：**代码审查**（无 `real_t`/`float`/`Color`/`Vector` 收窄拼写、无隐式 double→float、
  `p_scale ∈ {1,2,4}` 由 `scale_from_name` 闭集产生）+ **行为证据**（门③/④ 与 §7 的一致性证据）。
  `tools/tool_helpers.cpp` 的新函数 `write_screenshot_png` **在**扫描面内且**没有**新增收窄点
  （它只搬字节，不碰任何浮点）。
- **风险 R-1（既有，数值改善但语义未变）**：`every_call` 的背靠背仍会排队（`scale=1` 忙时 ~84 ms，
  `scale=2` ~60 ms）。§25 第 12 条的「已知代价」仍然成立，只是从 ~357 ms 降到 ~84 ms。
- **风险 R-2（诚实声明）「缩放只发生在应答之后」没有单元断言**：`_scaled_frame` 只有一个调用点
  （`_complete`），但「把它挪进 `arm()`」这件事**不会**让任何 TASK-046 断言变红。
  钉住它的是**线上证据**：服务端 `duration_ms` 中位 7 ms 未变（§6.1）、
  `mcp044_capture_evidence.ps1` 的 `zero_latency_the_response_path_adds_only_the_one_copy`（PASS）、
  以及 `scale=2` 的运行里 `duration_ms` 与 `scale=1` 同量级。已在用例头注释里写明这条边界。
- **风险 R-3**：`Image::_save_png_to_buffer` 是带前导下划线的内部 API；上游若删掉它，
  本模块会编译失败（**编译期**，不是静默行为变化）。缓解：库内 `movie_writer` 也在用（§2）。
- **风险 R-4（体积）**：`every_call` 的磁盘与 `total_bytes` 涨 **~4.5×**（`24917/24928 B` →
  `113929/112102 B`，每次调用 +176 KB；`scale=2` 时降到每次 +58 KB）。
  §25 第 7 条的「不设上限、绝不删除、超 1 GB 只 WARN 一次」因此会**更早**触发。
  这是杠杆①明码标价的代价（任务书：「体积换速度可接受；体积变化如实报」）。
- **D-10（偏差：动了 TASK-044 的脚本，附证据）`mcp044_capture_evidence.ps1` 的 headless 相等了。**
  该相是**唯一**不等捕获行就读 trace 的相，而捕获行是下一帧才写的 ⇒ 会给**假红**（本次实测到了：`events=2`
  两条红，而同一份 trace 里三条 `unavailable` 一应俱全）。改成调用它**自己已有的**
  `Wait-ForCaptureEvents -Expected 3`（同一个助手的其它五处用法都在那个文件里）。
  这一改动**只能**消除假红：`events.Count -eq 3` 与逐字段判定一字未改，错 trace 仍然是红的。
  为什么越界改别的任务的脚本：它是 `modules/mcp_server/**` 内的**证据脚本**（不是契约、不是生成器），
  且门①..⑥ 与 `mcp043_gates` 都会跑到它；留一个概率性假红会让下一个复核者重新花一遍本次的归因成本。
  已在报告 §13 留下完整的前后证据。
- **D-11（噪声，如实）本机墙钟波动很大**：四轮 `mcp046` 里有三轮的 `off` 或 `scale=2` 被污染
  （轮 2 的 `off` 中位一度是 101 ms；轮 3 的 `png-encode default` 中位从 174 抬到 263 ms）；
  §6.2 给出**原始样本**。因此判定只用**同一轮内的成对比较**（off vs every_call、default vs fast），
  并优先引用**同一轮里最安静的样本**（min 或未被污染的轮次）。
  **没有**任何结论依赖被污染的那一个数。
- **不是风险（已核对）**：`_scaled_frame` 先 `duplicate()` 再 `resize()`，
  而 `duplicate()` 是 COW 句柄拷贝、`resize()` 只写它新建的 `dst` 再整体赋值
  （`core/io/image.cpp:1654`）⇒ **源帧不可能被改写**，注入式 provider 交出同一个 `Ref` 给前后两帧也不会被减半两次。

---

## 11. 非主线程可行性评估（**先不做，报决策者裁决**）

任务书 §1.5 要求先评估。结论：**可行，但边际收益已经不大，且它自己会引入一类新的诚实性缺口**。

### 11.1 引擎线程模型与资源读回限制

- **读回不能挪**：捕获的两帧来自 `ViewportTexture::get_image()` →
  `RS::texture_2d_get`（`scene/main/viewport.cpp:201-207`），在 `RendererCompositor` 的 MT 包装里是
  `FUNC1RC`：异步分支 `command_queue.push_and_ret(...)` **阻塞等渲染线程**，并带 `MAIN_THREAD_SYNC_CHECK`
  （`servers/server_wrap_mt_common.h:153-165`）。**这一句本来就留在主线程**（`arm()`/`_complete` 的
  `snapshot()` 调用），off-thread 方案**不**碰它——也就是说它**省不掉**那一次拷贝的 7–8 ms。
- **能挪的只有 CPU 部分**：`Image::_save_png_to_buffer`（纯 CPU + zlib）、`Image::resize`（纯 CPU）、
  `compare_screenshot_pixels`（纯 CPU）、以及 `FileAccess` 写过文件。四者都不需要主线程亲和。
- **但有两处进程级共享状态不能随手挪**：
  1. `FileAccess::backup_save` 是**进程级 static**（`core/io/file_access.h:145`，`set/get` 在 `:270-271`），
     `mcp_capture.cpp::_write_png` 现在**临时把它置 false 再恢复**。工作线程做同一件事会与主线程上
     任何一次文件写**竞态**（窗口只有几条指令，但它是真竞态）。→ 必须改成「每个 worker 自己的写路径
     不经过 backup-save 分支」，或把这一开关改成只在启动时设置一次。
  2. `MCPTrace::Recorder` **没有锁**，并且它的正确性**显式依赖**「HTTP 泵、工具处理器、记录器都在主线程的
     同一帧里」（`mcp_trace.cpp:230-235` 的注释就是「一行 `store_string`，不可能被另一行撕开」）。
     → worker **不能**直接写日志行；只能把算好的 `Dictionary` 交回主线程，由 `tick()` 追加。
- **`Engine::~Engine` / `stop()` 的收尾顺序**：`MCPServer::_shutdown` 先关 trace recorder，再停捕获引擎
  （`mcp_server.cpp:265-279`）。有 worker 之后必须**先 join 再关 recorder**，否则一个迟到的 worker
  会往已关闭的文件里写（或者更糟：在 recorder 已 `memdelete` 后访问它）。

### 11.2 与 GDR-20 延迟通道的关系

- 延迟通道的 `tools/call` 现在被显式记为 `capture.status:"unavailable"` + `reason`
  （`mcp_server.cpp:303-311`，§25 第 13 条②）。off-thread 方案**不改变**这条判定，
  但它把「捕获行什么时候出现」变成不可预测：**同一 seq 的捕获行可能晚于后续若干次调用**。
  §25 第 5 条只要求「同 `seq` 可关联」，所以**语义上可行**；但观察者（以及 `mcp044`/`mcp046` 的
  `Wait-ForCaptureEvents`）依赖的是「跑到第 N 行就能看到第 N 条捕获」，**顺序假设会失效**。
- 反过来说，**队列积压**会变成新的必须显式表达的状态：一旦worker 追不上，就要么无限增长（内存里压着
  若干张 21 MB 的 `Ref<Image>`），要么丢捕获。**丢捕获必须写一行有 `status`+`reason` 的日志**
  （§25 第 6 条的「不得静默」），而当前 schema **没有第 4 个 status 值**⇒这是一次**规范变更**，
  要决策者落笔，不属于「实现细节」。

### 11.3 代价估计

| 项 | 估计 |
|---|---|
| 新增代码 | `Engine` 里一个 worker（`WorkerThreadPool` 的 group task 或一条 `Thread`）+ 一把 `Mutex` 的完成队列 + `tick()` 里 drain + `stop()`/析构里的 join；`_write_png` 的 backup-save 处理要改 |
| 规模 | 与 TASK-044 自身相当（快照注入→异步的分叉、doctest 的确定性驱动、收尾顺序），**不是**一个小补丁 |
| 最麻烦的次生成本 | **doctest 会变成异步的**：现有 4 个捕获用例都是「arm → tick 一帧 → 断言文件与日志」。要保住确定性，得加一个「同步 drain」的测试接缝，否则挂钟/线程调度进入断言 |
| 收益（以 TASK-046 之后的忙时为基准） | `scale=1` 忙时 **84 ms → 0 ms（主线程）**，背靠背往返 **~100 ms → ~20 ms**（回到 `off` 基线 + 一次拷贝）；`scale=2` 同理 **~60 → 0**。**但**这是「主线程视角」的 0：吞吐上限变成 worker 的 84 ms/次 ÷ worker 数 |
| 吞吐边界 | 单 worker：`scale=1` ~12 次/秒、`scale=2` ~17 次/秒；超过就必须丢弃或积压 ⇒ 见 11.2 的规范缺口 |

### 11.4 建议（供裁决，不在本任务范围内）

1. **TASK-046 之后，off-thread 的紧迫性已经明显下降**：待处理的量从 ~357 ms 降到 ~84 ms；
   若采用 `scale=2`，是 ~60 ms。要不要为 ~84 ms 引入一个异步流水线 + 一个新的 `status` 值 + 一次
   doctest 的确定性重构，是一个**架构判断**，不是性能上的必需。
2. 如果要做，建议顺序：**(a)** 先把「队列积压/丢弃」的日志语义写进 §25（规范先行）；
   **(b)** 再把 worker 限定为「可丢弃」的旁路（丢捕获只 warn，绝不影响工具调用）；
   **(c)** 最后才是迁移。反过来做（先写异步、再想丢弃语义）会把 §25 第 6 条变成一句空话。
3. 若只想再挤一次主线程时间而**不**引入线程，下一个最划算的点**不是编码**（已 34.7 ms/帧），
   而是：**跳过 `before` 帧的编码**（`changed:false` 时它没有信息量），或让 `--mcp-capture-scale=2`
   成为高频场景的推荐档（已可用、零风险）。

---

## 12. 门（全部自己跑，贴真实输出与退出码）

> 全部在**同一个锚点二进制**上跑：`git HEAD = 5a5fe039f2`（= 测试/脚本提交），
> `--version = 4.8.dev.custom_build.5a5fe039f`（前缀一致），
> engine sha256 = `81417f58d3cda007af9a888e3f309ee46577f50e841bc20c9d5103b3cc0aeaab`。
> 一次性串行 battery（`%TEMP%\mcp046_battery.txt`），**没有任何并发 scons / 并发引擎**。

| 门 | 命令 | 结果 |
|---|---|---|
| ⓪ 重建 | `scripts\build_local.cmd -Force`（**从 cmd 启动**，`tests=yes`，串行，不抑制输出） | exit **0**；`--version` == `git rev-parse --short=10 HEAD` = `5a5fe039f2` |
| ① 契约子集逐字 | `check_contract_subset.ps1`：`gate1_contract_subset` + mcp043 的 `gate1a–1d` | **各 3/3 PASS**，exit 0（`implemented_union=148/69`，contract=171；本任务不新增/不改任何工具） |
| ② 三类证据 + 端到端链 | `mcp046_capture_encode_cost.ps1`（**23/23**）+ `mcp044_capture_evidence.ps1` 四相（**40+8+9+5 = 62/62**） | 全绿，exit 0 |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **293/293 cases，21431/21431 断言，0 failed**，exit 0（基线 289/21312 → **+4 cases / +119 断言**） |
| ④ 全引擎回归 | `--headless --test` | **1719/1719 cases，445713/445713 断言，0 failed，3 skipped**，exit 0（基线 1715/445594 → +4 / +119） |
| ⑤ 批收口 | `accept_m1.ps1` **连跑两次** | 两次都 **22/22 cases passed**，exit 0，两次 PASS 清单一致（`gate5_accept_run1/2.log`） |
| ⑥ 收窄点（三段式） | 见 §12.1 | 三段全绿 |
| 契约快照 | `gate2f_snapshot_before_contract` + `gate2g_contract_diff` | exit 0（`docs/tools_list.renamed.json` 的 sha256 未变） |

### 12.1 门⑥ 三段式（§22.3b 规则 4：**新增点逐条列**）

1. `python scripts\check_narrowing_points.py` → exit **0**：
   `scanned: 75 / pinned: 75`，**无 `[UNLISTED]`、无 `STALE`、无 `FAIL`**；
   漂移提示 **15 → 10 条**（本任务引起的 5 条已按提示更新到 `tool_helpers.cpp` 的现值，其余 10 条全在本批之外）。
2. `python scripts\check_narrowing_points.py --coverage` → exit **0**（17 条声明拼写与边界原文）。
3. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp031_gate6_coverage_probes.ps1`
   → **101/101 PASS**，exit 0（`log sha256=7e2a773f9f4bd483018830420b4fd7cdb22d3997f54e0bd7707696b2b3af7bd3`；
   与 REPORT-045 的 `dddd322a…` 不同是**预期的**：日志里含被扫描文件的 sha256，而 `check_narrowing_points.py` 改了），
   且 `B1b_restored_byte_identical` / `B1b_worktree_clean_of_probes` 证明探针树被逐字节还原、工作树干净。

**新增收窄点 × 经过的闸门 × 证据**（规则 4 要求的逐条形式）：

| 新增点 | 经过的闸门 | 证据 |
|---|---|---|
| **本任务新增的收窄点：0 个** | 门⑥ 扫描器（`tools/**` 的 17 条拼写） | `scanned` **75 → 75**（净增 0）；`tools/tool_helpers.cpp` 的新函数 `write_screenshot_png` 只搬 `uint8_t` 字节，没有任何 `(float)`/`(real_t)`/`static_cast`/函数式转换/`Color(`/`VectorN(` 拼写 |
| `tools/tool_helpers.cpp` 的 5 条 `pinned_line` 漂移（`G24-DIFF-PIXEL-UNCHANGED` 997→1033 / 1123→1159，`G24-DIFF-PIXEL-CHANGED` 1089→1125 / 1119→1155，`G24-THE-GATE` 1718→1754） | PINNED 清单的**行号登记**（不是语义） | 插入 `write_screenshot_png`（+36 行）使它们下移；marker id 与 occurrence **一个没变**，`scanned == pinned` 仍 75。已在 `check_narrowing_points.py` 里连同 TASK-046 说明一起更新 |
| `mcp_capture.cpp` 的 `_scaled_frame` / `scale` 解析 | **不在**扫描面内（扫描器只扫 `tools/**`） | 按 §22.3b 的两条腿：**代码审查**（`p_scale ∈ {1,2,4}` 由 `scale_from_name` 的白名单产生；`MAX(1, w / p_scale)` 是**整数除法**；无浮点、无 `double`→`real_t` 隐式收窄；`resize` 的插值是 `Image::Interpolation` 枚举）+ **行为证据**（门③/④ 与 §7 的两重一致性证据） |
| `tests/test_mcp_server.h`（+119 断言） | **不在**门⑥ 扫描面内 | 由门③/④ 覆盖（293/293、1719/1719） |

> **门⑥ 仍然是「有限集合」的保证**（§22.3b）：它只看得见 17 种已声明拼写。本任务因此**不**主张
> 「无新收窄」只靠门⑥ 变绿——上面两条腿与「`scanned` 净增 0」合起来才是结论。

---

## 13. 回归（逐条归因）

全部在锚点二进制（`81417f58…`）上串行跑完一次：

| 脚本 | 结果 | 归因 |
|---|---|---|
| `mcp044_capture_evidence.ps1` `editor` | **40/40 PASS**，exit 0 | 开关/存在理由/三视口/延迟全绿；`changed 106800 / 5339554` 未变 |
| `mcp044_capture_evidence.ps1` `headless` | **首轮 6/8（两条红）→ 修脚本后 8/8 PASS** | **不是 TASK-046 的行为回归**，是**该脚本 headless 相的一个既有竞态**：见下与 §10 D-10 |
| `mcp044_capture_evidence.ps1` `game` | **9/9 PASS**，exit 0 | 游戏端点链（ratio 0.3215 → false）未变 |
| `mcp044_capture_evidence.ps1` `diff-image` | **5/5 PASS**，exit 0 | `diff.path/sha256` 未变 → 共享比对的差异图也没变 |
| **mcp044 合计** | **62/62 PASS** | 与 REPORT-045 逐相相同 |
| `mcp045_pixel_compare_cost.ps1 -Label post` | **15/15 PASS**，exit 0 | 同一把尺子：`off` median 0.0217、背靠背 **median 0.0990**、间隔 median 0.0316、diff 工具 median 0.3362；PNG sha 仍是 `c2d7a1bf…/4516082843…`；payload sha 仍是 `51c69777…`；服务端 `duration_ms` off 中位 0 / every_call 中位 7（n=10） |
| `mcp046_capture_encode_cost.ps1 -Label post` | **23/23 PASS**，exit 0 | 两档缩放的一致性 + 启动行 + 原始分布 |
| `mcp044_zero_change.ps1`（pre / off / on + compare） | **22/22 探针 `pre=off=on`，changed=0，unstable=0**，四个 exit 0 | §24/§25 第 9 条的响应逐字节不变（`pre` 用任务前二进制 `a836f90e…`） |
| `mcp043_gates.ps1` | **28/28 STEP EXIT 0** | 含 gate1a–1d、gate3、gate4、gate5×2、gate6a/b/c、gate2a–gate2i、regress mcp032/033/034/035/036/040_probes/040_racing |
| `mcp042_gates.ps1` | **19/19 STEP EXIT 0** | 全绿 |
| `mcp041_gates.ps1` | **17/17 STEP EXIT 0** | 全绿 |
| `mcp038_zero_change.ps1` | **7/7 checks passed**，probes=22 stable=22 **changed=0** unstable=0 | §24 的「关-关-开」模板仍成立 |
| `mcp038_trace_evidence.ps1` | **12/12 checks passed**，trace lines=10 | 追踪行为未变（本任务未动 `mcp_trace.*`） |

**首轮唯一一条红：`mcp044` 的 headless 相（已归因，不是行为回归）**

- 现象：`headless_says_unavailable_for_every_call` 与 `headless_carries_the_reason_and_no_picture_reference` 两条红，
  证据行 `capture events=2 statuses=[unavailable,unavailable]`。
- **根因（实测，不是推断）**：该相**当场**读 trace（`$traceLines = Get-TraceLines; $events = Get-CaptureEvents`），
  而捕获行按 §25 第 4 条是**下一帧**才追加的。对**同一份 trace** 重新计数：
  `lines=7`、`capture events=3`，三条都是 `status:"unavailable"` 且 `reason` 是正确的
  `headless display server 没有纹理存储`（按 UTF-8 读）。也就是说**行为是对的**，脚本读早了。
- **该相是全脚本唯一一个不等捕获行的相**：其余相都用它自己定义的 `Wait-ForCaptureEvents`
  （第 363 / 470 / 595 / 770 / 826 行）。修法就是让它也用同一个助手（`-Expected 3`）。
- 修后同一二进制复跑：**8/8 PASS**。这条修法**只会消除假红**，不可能让错 trace 变绿
  （`events.Count -eq 3` 的严格相等没变）。
- 这是**既有缺陷**：TASK-044/045 与本次的前两次运行都没撞上，说明它是概率性的（取决于机器快慢），
  已在报告里留下而不是删掉——PLAYBOOK §7.3 的「证据被证伪要撤回/勘误」同类处理。

---

## 14. 提交锚点（D86）与提交后复跑（append-only）

- **代码锚点**：**`a7b8b5322f`** — `mcp_server: write the capture's PNGs with the engine's fast flag and
  scale both frames (TASK-046)`（`mcp_capture.{h,cpp}`、`tools/tool_helpers.{h,cpp}`；
  §1 给出 4 个文件的 sha256；**提交不改文件字节**）。
- **测试/脚本锚点**：**`5a5fe039f2`** — `mcp_server: doctests and live evidence for the capture encoding
  cost (TASK-046)`（`tests/test_mcp_server.h`、`scripts/check_narrowing_points.py`、
  `scripts/mcp044_capture_evidence.ps1`、`scripts/mcp045_pixel_compare_cost.ps1`、
  `scripts/mcp046_capture_encode_cost.ps1`）。
- **§12/§13 的全部门与回归是在 `5a5fe039f2` 上跑的**：`--version` = `4.8.dev.custom_build.5a5fe039f`
  == `git rev-parse --short=10 HEAD`，engine sha256 = `81417f58…`（§9）。
- 第三条（仅文档）—— 本报告。**`264f9564c5`**
  （`docs(mcp_server): REPORT-046 -- the capture encoding cost, with the fast PNG flag and the capture
  scale (TASK-046)`；同时带上 §10 D-10 的 `mcp044_capture_evidence.ps1` 竞态修复）。
- 提交之后的重建与最终锚点见 §15。

---

## 15. 提交后复跑（append-only）

三条提交落下之后（`a7b8b5322f` 实现 / `5a5fe039f2` 测试与脚本 / **`264f9564c5` 本报告 + 脚本修复**），
从**已提交的树**用 `scripts\build_local.cmd -Force`（从 cmd 启动，`tests=yes`，串行）重建：

```
bin\godot.windows.editor.x86_64.console.exe --version   ->  4.8.dev.custom_build.264f9564c
git rev-parse --short=10 HEAD                           ->  264f9564c5      (== --version，前缀一致)
engine sha256                                           ->  c6b58792dd295f01f7727ad7e88032938c691ebbb380869121419e839cc25ca4
```

**关键门 + TASK-046 证据在这一二进制上复跑（全部 exit 0）**：

| 项 | 结果 |
|---|---|
| 门③ `gate3_module_doctest` | **293/293 cases，21431/21431 断言，0 failed** |
| 门④ `gate4_full_doctest` | **1719/1719 cases，445713/445713 断言，0 failed，3 skipped** |
| 门⑥ `gate6a` | `scanned: 75 / pinned: 75`，exit 0（10 条漂移提示全在本批之外） |
| 门⑥ `gate6b` / `gate6c` | exit 0 / **101/101 PASS**（`log sha256=7e2a773f…`，与 §12.1 **同一 sha**） |
| `mcp044_capture_evidence.ps1` 四相 | **40 + 8 + 9 + 5 = 62/62 PASS**（headless 在**修好的脚本**上 8/8，见 D-10） |
| `mcp045_pixel_compare_cost.ps1 -Label post` | **15/15 PASS**；`off` min 0.0174 **median 0.0182**；**背靠背 min 0.0991 median 0.1014 max 0.1099**；间隔 median 0.0304；diff 工具 median 0.3408；两张 PNG sha 仍是 `c2d7a1bf…`/`4516082843…`；payload sha 仍是 `51c69777…`；服务端 `duration_ms` off 中位 0 / every_call 中位 7.5（n=10） |
| `mcp046_capture_encode_cost.ps1 -Label final` | **23/23 PASS**；`scale=1` 背靠背 min 0.0586 **median 0.0997** max 0.1105；`scale=2` **min 0.0785** median 0.1955 max 0.2156（**该轮 scale=2 又被负载污染**，min 仍是 78.5 ms）；两张 PNG sha 与 payload sha 同上 |

**最终锚点这一轮的往返对照（同一把尺子 = `mcp045` 脚本）**：

| 时钟 | pre（`b1b6271a…`，REPORT-045） | 最终锚点（`c6b58792…` = HEAD `264f9564c5`） |
|---|---|---|
| `curl` 往返 · `off` | median 0.0201 | median **0.0182** |
| **`curl` 往返 · `every_call` 背靠背** | median **0.3776** | median **0.1014**（−73.1%） |
| `curl` 往返 · 间隔 2.5 s | median 0.0316 | median **0.0304** |
| `editor_analyze_screenshot_diff`（同一对文件） | median 0.6661 | median **0.3408** |
| 服务端 `duration_ms` | off 0 / every_call 7 | off 0 / every_call 7.5（n=10） |
| 两张捕获 PNG 的 sha256 | `865c2f93…` / `87731a87…`（默认编码） | **`c2d7a1bf…` / `4516082843…`（fast，跨 5 轮可复现）** |

> **`scale=2` 的诚实收口**：五轮里它的**安静样本**是 min **78.5–80.9 ms**、
> 干净中位 **89.1/90.5/96.6 ms**，比 `scale=1` 的 **98.8–103.5 ms** 低约 **10–20 ms**
> （进程内预测 `84.2 → 60.2` 即 ~24 ms）；另有**两轮**的中位（166.0 / 195.5 ms）被本机负载抬走，
> 原始样本逐轮列在 §6.2 与各轮 `summary.txt` 的 `*_samples=` 行里。
> **不做「scale=2 一定更快」的隐身处理**；要一个稳定的 `scale=2` 数字，需要在安静机器上重跑脚本。

- **FINAL-ANCHOR**：**`264f9564c5`**（本报告所在提交）——门③/④/⑥ 与 TASK-046 的三条活证据链
  是在**它**的树上、用**它**的二进制（`--version = 264f9564c` == 当时的 `git HEAD`）跑的全绿。
  其后的 append-only 提交（本节所在的这一个）**只改本文件**，因此交接时 `git HEAD` 比
  `264f9564c5` 多一到两个**纯文档**提交，而 `--version` **仍然**报 `264f9564c`：
  「`--version` == HEAD」在**每一次门/证据运行的那一刻**成立，此后不再引入任何代码字节。
- 代码锚点仍是 **`a7b8b5322f`**（§14）；`a7b8b5322f` → `264f9564c5` 之间只有
  **测试 / 脚本 / 文档**（外加 D-10 的那一处脚本竞态修复），**不含任何 `mcp_capture.cpp` /
  `tool_helpers.cpp` 的实现字节变化**（§1 的 9 个文件 sha256 可逐一对上）。
- 第四条（仅文档）—— 追加本节的那一个提交（`9747921995` 的前身，sha 不写死以免自指）。
- 本节自身也是 **append-only**：为记下这一轮结果而后加的这一个提交**只改本文件**。


---
