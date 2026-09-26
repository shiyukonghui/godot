# TASK-011 — 新增「延迟响应通道」（GDR-20）+ 移植 4 个**跨帧**工具

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-011-deferred-response-channel.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 背景（为什么必须做）

B2 里有 4 个工具**在当前「一请求一帧」模型下无法实现**：
`running_game_get_node_property_samples`（旧 `monitor_properties`）、
`running_game_find_node_when_available`（旧 `wait_for_node`）、
`running_game_capture_frames`（旧 `capture_frames`），它们都需要**让游戏推进 N 帧**；
B4 的 `assert_*` / `run_test_scenario` / `watch_signals` 与 B5 的录制族同样需要。
TASK-010 已给出最小证明：**同一帧取 N 次样本得到 N 个相同的值**。

决策者已批准新增**延迟响应通道**（`F:\moonbit-hof-rs\DECISIONS.md` D57 / `DESIGN-DETAIL` **GDR-20**）。

## 1. 第一部分：实现延迟响应通道（框架改动，**先做**）

硬性设计要求（缺一不可）：

1. **保持「无 FIFO」原则**：pending 请求按 **(连接, 请求 id)** 关联；
   响应**始终**写回发起它的那条连接。**禁止**引入全局 FIFO 或「按到达顺序配对」。
2. **状态机归框架**：工具处理器可以返回
   - 「已完成结果」，或
   - 「**pending 句柄**」（含 `tick()` → `Pending` | `Done(result)` | `Failed(error)`）；
   `MCPHttpServer` / `MCPJsonRpc` 负责逐帧推进，**工具实现保持简单**。
3. **绝不阻塞主线程**：禁止 `sleep`/忙等；`tick()` 必须是非阻塞的。
4. **每帧推进预算有上限**（例如 `pending_ticks_per_frame`），不得让 pending 饿死常规请求。
5. **超时**：默认 **30 秒**（可配置），超时以 **`-32000` + `data.suggestion` + `data.timeout_ms`** 收尾；**不得静默丢弃请求**。
6. **连接断开必须清理**该连接上的 pending，**不得泄漏**（连接数与 pending 数都要可观测）。
7. 帧时钟用 `SceneTree` 的帧计数。
8. **先证明状态机正确，再用真实工具验证**：写**受控的假 pending 工具**（仅测试用）覆盖：
   ①正常完成；②超时；③断连清理；④**多个 pending 交错**（不同连接）时响应不串线；
   ⑤pending 期间常规请求仍被及时响应（预算不饿死）。

## 2. 第二部分：移植 4 个跨帧工具

| 新名 | 旧名 | 组 |
|---|---|---|
| `running_game_get_node_property_samples` | `monitor_properties` | `running_game_frame_observation`(3) |
| `running_game_find_node_when_available` | `wait_for_node` | 同上 |
| `running_game_capture_frames` | `capture_frames` | 同上 |
| `running_game_capture_frames`（若 capture 组另有工具则按 manifest 为准） | `get_game_screenshot` → 见 manifest | `running_game_capture` |

> **以 `docs/tool-groups-b2.json` 为准**：把 `running_game_frame_observation` 与 `running_game_capture`
> 两组的成员**全部**实现（共 4 个），并在报告里给出成员清单（新名 + 旧名 + 组）。

要求：
1. 每个工具都要用真实游戏进程给证据：**跨帧采样必须真的产生不同样本**
   （例如一个逐帧移动的节点：N 次采样得到**递增**的值；若是静态节点则说明并改用会变化的观测量）。
2. `capture_frames` 必须给出**多帧**且可区分（例如帧序号/时间戳/校验和不同），不得是同一帧的副本。
3. 超时路径要有真实复现：构造一个「永远不会满足」的等待（例如等待一个不存在的节点名），
   验证**超时后返回 `-32000` 且带 `timeout_ms`**，并且**服务在超时后仍能正常服务后续请求**。
4. 断开路径要有真实复现：**在 pending 期间关闭连接**，验证服务不崩溃、pending 被清理
   （给出 pending 计数的前后值）。

## 3. 门

按 `PLAYBOOK-group-port.md` §3 五道门（门①按组跑两次：`running_game_frame_observation` 与 `running_game_capture`），
外加 §1 的 5 类状态机证明与 §2 的跨帧/超时/断连真实证据。
**注意**：本任务改了 HTTP/JSON-RPC 核心，**必须**证明 M1 以来的既有门全部不回归
（`accept_m1.ps1` ×2 必须仍全过；特别是 keep-alive、流水线、413/431、`Expect: 100-continue`、并发 100 等用例）。

## 4. 报告

按手册 §4，写到 `docs/reports/REPORT-011-deferred-response-channel.md`；
另加三节：「延迟通道的设计与 5 类状态机证明」「4 个跨帧工具的真实证据（跨帧可区分）」
「对既有门无回归的证据（尤其 HTTP 边缘用例）」。**返回值：≤15 行总结 + 报告路径。**