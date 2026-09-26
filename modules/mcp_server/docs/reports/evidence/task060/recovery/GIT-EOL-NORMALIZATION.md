# TASK-062 — git EOL 归一化声明（**不是**内容丢失，但会影响「从提交复算 sha256」）

## 事实

本仓库根的 `.gitattributes` 含一条**仓库级**规则：

```
* text=auto eol=lf
```

本机还有 `core.autocrlf = true`。因此**任何被 git 判定为文本的文件**在写入 git 对象时会做
**CRLF → LF** 归一化；`eol=lf` 又让 `git checkout` 总是写 LF。
**这是仓库既有约定，不是 TASK-062 引入的**——证据：本任务之前已入库的证据文件在工作树里
`CR` 字节数 = **0**（例：`evidence/racing/0001-editor_play_scene.response.json`、
`evidence/task061/route.txt`）。

## 影响范围（在本批 535 个 staged 文件里）

| 类别 | 文件数 | 说明 |
|---|---|---|
| 工作树 **无 CR** → 提交对象与工作树**逐字节相同** | **508** | 含全部 `c1`–`c4` 的请求/响应原文与它们的 `.sha256` 边车、3 份 `BREAKOUT-*.md`、全部 `recovery/*.tsv`/`*.md`（TASK-062 自己的产物已刻意写成 LF） |
| 工作树**有 CR** | **27** | 见下 |
| ├ 其中 CR 是**孤立 CR**（非 CRLF）→ 提交对象仍**逐字节相同** | **6** | `b0-bootstrap/import-attempt.log`、`b0-bootstrap/import-full.log`、`trace-recovered/logs/{c3-stop,import-bootstrap.attempt1,reset-taskkill,restart-taskkill}.log`（进度条用 `\r`，不是换行） |
| └ 其中 CRLF → 提交对象被归一化为 LF，**字节数变小、sha256 变** | **21** | 见 `GIT-EOL-NORMALIZATION.tsv` |

机器可读对照：**`GIT-EOL-NORMALIZATION.tsv`**
（列：`path` / `cr_bytes` / `worktree_bytes` / `worktree_sha256` / `committed_blob_bytes` /
`committed_blob_sha256` / `identical`）。
其中 `worktree_sha256` = 本批清单（`MOVE-AFTER.sha256.tsv`、`TRACE-RECOVERY-MANIFEST.sha256.tsv`、
`POST-RECOVERY-MANIFEST.sha256.tsv`）里记的值；`committed_blob_sha256` = git 对象里真正存的值
（用 `git show :<path>` 复算）。

## 对被归一化的 21 个文件的正确读法

- 它们的 **LF 版本哈希**（`committed_blob_sha256`）是**从提交可复算**的那个；
- 它们的 **CRLF 版本哈希**（`worktree_sha256`）是「**回收现场拿到的原始字节**」，只在本机工作树成立；
- **两者只差换行符**，文本内容一致（`committed_blob_bytes` = 工作树字节 − CR 数）。
- **`c1`–`c4` 的请求/响应原文与 `.sha256` 边车全部属于「无 CR」一类**，
  所以「边车 ↔ 文件」的自校验**在任何一次干净 clone 后依然成立**（TASK-062 已实测 127/127 相符）。

## 为什么不改 `.gitattributes`

`* text=auto eol=lf` 是**引擎仓库的既有政策**（上游 Godot 自带）。TASK-062 的任务书限定
「本批只动 `docs/**`（必要时 `scripts/**` 的取证脚本）」，因此**不去改仓库级配置**；
改为**把这个差异显式记录并可复算**（本文件 + `GIT-EOL-NORMALIZATION.tsv`）。
若决策者希望证据逐字节保真，正确的做法是**单独一批**给 `docs/reports/evidence/**` 增加
`-text` 规则（会改变以后所有证据文件的入库行为，需要独立决策）。
