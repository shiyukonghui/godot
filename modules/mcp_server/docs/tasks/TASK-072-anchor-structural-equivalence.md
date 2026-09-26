# TASK-072 — 修「锚点假红」：`engines_match_head` 升级为**结构性等价证明**（同时保留真陈旧必红）

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件。
> 来源：`REPORT-071-guard-inventory-and-test-config.md` §门⑤（唯一非零 = `mcp052/mcp053` 的 `engines_match_head`，
> 因 mono 二进制自报 `3cbaacd6b` 而 HEAD 为 `4512d14c7`，两者差异**只含 docs/scripts、不含编译输入**）。
> 报告（**绝对路径**）`...\modules\mcp_server\docs\reports\REPORT-072-anchor-structural-equivalence.md`。契约 **176**（条数不变）。

## 1. 问题与裁决（D130）

现状：锚点检查要求二进制自报版本**精确等于 HEAD 短 sha** → **每次提交都会移动 HEAD**，于是
**只改文档/脚本的提交**也会让 mono/plain 锚点检查**假红**。TASK-071 已经出现（`FAILED STEPS: 2`，实际无回归）。
**假红会腐蚀对门的信任**，所以必须**机械化**，不能靠「记得重建 mono」。

## 2. 要求

1. **升级判据**（保持「真陈旧必红」）：
   - 设二进制自报锚点 `A`、当前 `HEAD` 为 `H`。**通过**当且仅当：
     ①`A` 是 `H` 的**祖先**（`git merge-base --is-ancestor A H` 成立；`A == H` 也算通过）；
     ②`git diff --name-only A..H` 中**没有编译输入**（约定一个**显式白名单**：只有
       `*.md / *.json / *.txt / *.ps1 / *.py / *.cmd / *.sh / .gitignore / .gitattributes` 等**非编译**后缀才算安全；
       **任何** `*.cpp / *.h / *.hpp / *.c / *.cs / *.tscn / *.tres / *.gd / *.godot / SConstruct / SConscript / *.build` 出现 → **红**）。
   - **三种结论**必须可区分并机器可读：`ANCHOR_EQUAL`（`A == H`）/ `ANCHOR_STRUCTURAL_EQUIVALENT`（祖先且无编译输入，
     **必须打印安全差异文件清单与计数**）/ `ANCHOR_STALE_COMPILED`（**红**，打印导致红的文件清单）。
   - **非祖先**（`A` 不在 `H` 历史里，例如切分支/前进后又回退）→ 也判**红**（`ANCHOR_NOT_ANCESTOR`）。
2. **不要削弱**：`ANCHOR_STRUCTURAL_EQUIVALENT` **不得**被当成「等于 HEAD」写进证据摘要；证据里必须保留
   **二进制自报锚点 + HEAD + 判据 + 差异清单**，让后来者能自己判断。
3. **能力保留的反例演示（最关键）**：
   - ①**只改 `.md`** 后不重建 → 必须 **`ANCHOR_STRUCTURAL_EQUIVALENT`**（**不红**）；
   - ②**改一个 `.cpp`** 后不重建 → 必须 **`ANCHOR_STALE_COMPILED`（红）**；
   - ③**非祖先**场景（构造一个不在历史的 sha，或用 `--force` 式的假锚点）→ 必须 **红**；
   - ④**真重建** mono 到 HEAD → `ANCHOR_EQUAL`。
4. **落地**：把该判据实现为**单一可复用函数/脚本**（例如 `scripts/check_engine_anchor.ps1`），
   由 `mcp052`/`mcp053`（以及其它做锚点检查的脚本）**统一调用**；**不得**各自复制一份判据。
5. **重建 mono 并复跑** `mcp052`（**53/53**）与 `mcp053`（**73/73**），给重建窗口（START-END）与 `--version`。

## 3. 门与纪律

第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；五道门 + 门⑥ 三段式 +
`--check-completeness/--added/--generator-version` + `accept_m1` ×2（清单一致）+ `check_exit_propagation.py`；
回归相关脚本**逐条归因**；**mono 与 plain 需时严格串行**（START-END 不得重叠）；**绝不占用/杀/重启 9877**；
端口 9888/9889；禁止 push；`.ps1` 纯 ASCII；**红相位输出当场保存**；结论按 D86 标锚点；产物**绝对路径**。