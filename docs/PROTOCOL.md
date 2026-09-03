# OPO 控制协议记录

本文只记录已由 OPPO Enco Air5 Pro 和 realme Buds T500 Pro 实机流量确认的行为。

## 传输

- 蓝牙服务：`0000079a-d102-11e1-9b23-00025b00a5a5`
- 传输方式：Classic Bluetooth RFCOMM
- 帧格式：`aa len b2 b3 opcode:u16be seq payloadLen:u16le payload...`
- `len` 是从自身之后到帧尾的字节数，总帧长为 `len + 2`。
- 已观测帧没有尾部校验和。
- RFCOMM 可能拆分或合并帧，解码器会缓存残片并按 `aa` 重新同步。

## 已观测消息

- `00 01`：控制通道建立后的 hello。
- `04 02`：耳机主动上报状态。
- `04 04`：设置降噪模式，载荷为 `01 01 value`。

状态载荷是 `type count` 加若干组 `id value`：

- `type 01`：电量；`id 01/02/03` 分别表示左耳、右耳、充电盒。
- `type 02`：佩戴状态；当前确认 `00` 为盒内，`03` 为使用中。
- `type 03`：降噪状态；不同型号使用各自的 Profile 解释值和宽度。

## 写入规则

- OPPO Enco Air5 Pro 与 realme Buds T500 Pro 使用不同的模式值，写入必须经过对应型号 Profile。
- 未识别型号不允许写入。
- Set 命令只发送一次，耳机随后的状态报告是唯一成功依据，界面不会乐观更新。
- 当前抓包没有发现 Query opcode，因此不实现推测性的查询、超时重发或轮询命令。

任何新增命令都应先取得实机请求与回报，再加入 fixture 和测试；不能仅凭相似型号推断。
