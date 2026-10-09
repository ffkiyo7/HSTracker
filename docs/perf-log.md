# 对局性能日志（PerfLog）

每局自动记录 HSTracker 自身的 CPU、内存和 overlay 刷新开销，让每一局正常对局都成为一次 Release 实测。代码：`HSTracker/Utility/PerfLog.swift`。

## 开关

- Release 默认开，Debug 默认关（Debug 的数字被未优化代码和启动时 1000 局 smoke 模拟主导，不作数）。
- 每局开始时读一次设置，改完下局生效：

```
defaults write net.hearthsim.hstracker perf_log -bool false   # 关
defaults write net.hearthsim.hstracker perf_log -bool true    # 开（Debug 也可强开，行内 build 字段会标 Debug）
defaults delete net.hearthsim.hstracker perf_log              # 回默认
```

## 文件

- 位置：`~/Library/Logs/HSTracker/perf/perf-YYYYMMDD-HHmmss.jsonl`，一局一个，文件名是对局开始的本地时间。
- 保留最新 100 个，开新局时删最旧的。一局约 1 行/秒、每行约 150 字节，20 分钟一局约 180 KB。
- 菜单里打开日志目录（`openLogDirectory`）进的就是 `~/Library/Logs/HSTracker/`，`perf/` 在它下面。

## 格式（JSON Lines，每行一个对象）

`game_start`：`time`（ISO 8601）、`mode` / `game_type` / `format`、`build`（Release / Debug）、`version`、`interval_s`。

`sample`（约每秒一行，对局进行中）：

| 字段 | 含义 |
|---|---|
| `t` | 距开局秒数 |
| `cpu_pct` | 本进程上一秒的 CPU，100 = 占满一个核（`getrusage`，含所有线程） |
| `footprint_mb` | `phys_footprint`，即活动监视器「内存」列 |
| `refreshes` | 上一秒 overlay 刷新次数（`OverlayRefreshScheduler`） |
| `refresh_ms` / `refresh_max_ms` | 上一秒这些刷新的总耗时 / 最长一次：从发起刷新到主线程跑完它排的所有 block，含主线程排队 |
| `main_lag_ms` | 一个 block 等主线程的时间（上一次探测的结果），反映悬停、刷新会卡多久 |
| `gpu_sys_pct` | GPU 忙碌度，**整机的**（含炉石本身），取自 IOAccelerator `Device Utilization %`；macOS 不给 app 读自己的 GPU 时间。读不到就没有这个字段 |

`game_end`：`reason`（`game_end` 正常结束 / `restarted` 没收到结束就开了新局 / `app_quit` 对局中退出 / `timeout` 超过 3 小时未结束）、`mode`、`duration_s`、`samples`、`cpu_avg_pct` / `cpu_p95_pct` / `cpu_max_pct`、`footprint_start_mb` / `footprint_max_mb` / `footprint_end_mb`、`refreshes` / `refresh_total_ms` / `refresh_max_ms`、`main_lag_p95_ms` / `main_lag_max_ms`。

崩溃或强退时没有 `game_end` 行，前面的 `sample` 行都已落盘。

## 怎么看

```
python3 scripts/perf-summary.py          # 最近 20 局，一局一行
python3 scripts/perf-summary.py -n 50
python3 scripts/perf-summary.py ~/Library/Logs/HSTracker/perf/perf-20261009-210000.jsonl
```

单局细看：`jq -c 'select(.event=="sample")' 文件` 或导进表格按 `t` 画线。

## 开销

开着时：每秒一次 `getrusage` + `task_info` + 一次 IORegistry 读 + 一行写盘，都在自己的 utility 队列；主线程上只有每秒一个空 block（测 lag）和每次刷新一次加锁计数。不在对局中时什么都不跑。关着时 overlay 每次刷新多一次加锁判断。
