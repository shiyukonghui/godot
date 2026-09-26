# TASK-AUDIT-ADDED — 独立验收：**新增的 4 个工具**（与移植批次同标准）

> 你是**独立验收方**，未参与实现；**不得采信**任何 `REPORT-*` 与决策者结论。
> 规范依据：`DESIGN-DETAIL` **§26/GDR-28**（尤其**第 5 条「新增不是降级通道」**）与 §20/§22/§23。
> 报告 `docs/reports/REPORT-AUDIT-ADDED.md`。返回决策者：**≤12 行总结 + 报告路径 + verdict**。

## 0. 基准与范围

- 开工先 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ 校验 `--version` == HEAD。
- 验收对象：**4 个新增工具** —— `project_build_csharp`、`project_write_text_file`、
  `project_validate_scripts`、`editor_set_node_script_batch`，以及 M-5 给**既有**工具加的 `sample_stride`。
- 契约应为 **175 条**（171 移植 + 4 新增）；`_meta.added_tools` / `added_count` / `tool-groups-added.json` 必须自洽。

## 1. 必须核实（逐项给**你自己跑出**的证据）

1. **机制自洽**：`ADDED_TOOLS` 与两张 override 表**分离**且**幂等**（自己重生成，逐字节比对跟踪文件 = 无手改）；
   结构化 diff 证明 **171 条移植条目逐字未变**、新增**恰为那 4 条**、`_meta` 只动预期字段；
   `--check-completeness` 的四桶互斥（`171+4 = 66+105+4`）与 `--added` 的组规则**自己跑**。
2. **对等门**：从**实时 `tools/list`** 解析名字（**禁止文本包含判断**），核实并集 == 契约 175；
   逐条 `name`/`description`/`inputSchema` **逐字相等**（两端点各自可见部分）；`scope` 双向零泄漏 + 跨端点 `-32601`。
3. **`project_build_csharp`**：①**自己从零**（只用工具）建一个最小 C# 工程并构建成功（给真实 exit code 与产物 sha256）；
   ②**故意错的 `.cs`** → **非零**且捕获到诊断（**不得**伪造成 0）；③**超时真的杀子进程**（给子进程消失的证据）；
   ④**能力缺失**（把 PATH 里的 `dotnet` 藏起来或用非 C# 构建）→ **`-32000` + 建议**；
   ⑤**并发/重入**下**不得**留下孤儿 `dotnet`/`MSBuild` 进程（收尾清点）。
4. **`project_write_text_file`**：①写 `.csproj`/`NuGet.config` 后**读回 sha 与盘上一致**；
   ②四类拒绝（`project.godot` / 场景资源 / 脚本 / 越界路径）各一条，且**建议指向正确工具**；
   ③`overwrite:false` 命中已存在 → **`-32000` + 点名 `overwrite:true`**，且**文件字节未变**（前后 sha）；
   ④**没有任何删除路径**（代码腿 + 运行腿）。
5. **`project_validate_scripts`**：批量一致性与逐文件分类（`ok`/`invalid`/**`language_unavailable`**/**`unverifiable`**）；
   **语言不可用不得记成 `valid:false`**；`paths` 越界 → `-32602`；与**单数**工具结论**一致**。
6. **`editor_set_node_script_batch`**：①**全成功或全回滚**（构造一个中间失败，证明回滚且树状态未变）；
   ②`keep_existing:true` **跳过并计入 `skipped[]`**（**不得**覆盖已挂脚本）；③逐节点**读回核实**（`attached` 真值）。
7. **M-5 `sample_stride`**：**默认路径与改动前逐字节相同**；显式步长下点数/字节数正确；`0`/非整数 → `-32602`。
8. **顺手性（GDR-25）**：**≥1 条跨 ≥4 工具的零字符串手术链**（含**从零建工程 → 写文件 → 写脚本 → 构建**这条闭环），
   逐步确认调用方字符串处理为 0；返回值可直接喂回。
9. **六道门**自己跑（门① ≥3 组、门② 抽 ≥3 个脚本、③④、⑤ ×2 且 PASS 清单一致、⑥ 三段式）；
   **9877 全程未被我们占用**、只用 9888/9889、收尾无孤儿、无 git 写操作。

## 2. 纪律

不得修改任何文件（临时实验**逐字节还原并留证**）；临时文件 `%TEMP%\audit-added\`；不得安装依赖；
证据 `curl.exe -s -o` + sha256、请求体 `ConvertTo-Json`；不抑制 scons 输出；不并发 scons；**`.ps1` 纯 ASCII**；
**D86**：引用任何结论须标提交锚点并**复测**。

## 3. 报告

`verdict`（分类：机制自洽 / 对等门 / 四个新工具 / M-5 / 顺手性 / 工程门 / 端口）、逐项**你自己的证据**、
`defects`、`unconfirmed`、`risks`、`next_step_recommendation`。**返回值 ≤12 行 + 报告路径 + verdict**。