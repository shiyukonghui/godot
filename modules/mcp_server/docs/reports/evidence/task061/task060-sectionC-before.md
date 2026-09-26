## §C 观察者（与 §B **并行**、**只读**、**不阻塞**）

**产出**：`docs/reports/BREAKOUT-OBSERVATIONS.md`（边观察边追加）。

- **只读**：绝不改 scratch 工程、绝不打断开发者进程、绝不占用它的端口；可用**第二条 MCP 连接**做只读探测。
- **以服务端追踪为主**（`%TEMP%\mcp-breakout\trace-*.jsonl`），**但等待与记录交给确定性脚本**：
  **先**跑**一次阻塞调用** `scripts/mcp_watch_run.ps1 -Marker %TEMP%\mcp-breakout\DEV-DONE.marker -TracePath <各 trace> -TimeoutSec 4500 -StaleSec 300 -OutDir %TEMP%\mcp-breakout\watch`，
  **等它返回**（它会给出 `stop_reason`）；**然后**再基于**完整**记录做分析与记录。
  **禁止**用自己的 sleep 循环决定何时收工；**不得**在 `stop_reason=marker` 之前收尾。
- **至少给出**：≥3 条「多次调用才摸清用法」（连续失败后成功，附序列与错误码）、≥2 条缺失工具线索、
  ≥2 条可合并候选（高频 2-3 步序列）、≥2 条异常或矛盾。**没有就如实说没有**（说明查了哪些信号）——**不得凑数**。
- 返回**观察文件路径 + ≤6 行摘要**。
