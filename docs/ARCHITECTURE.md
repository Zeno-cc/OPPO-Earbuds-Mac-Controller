# 架构说明

应用分成纯协议核心和 macOS 界面两层，蓝牙数据只沿一个方向进入状态模型，界面操作也只通过会话层发送命令。

```text
SwiftUI / AppKit 界面
        │
        ▼
Buds（应用状态、设备选择、系统电量兜底）
        │
        ▼
EarbudsSession（连接状态、命令队列、状态归并）
        │
        ▼
ControlTransport ── RFCOMMTransport ── IOBluetooth
        │
        ▼
BudsProtocol + DeviceProfile（帧编解码、型号差异）
```

## 模块职责

- `BudsCore` 不依赖 AppKit、SwiftUI 或蓝牙硬件，负责帧编解码、设备能力、会话状态和命令顺序。
- `RFCOMMTransport` 是唯一直接读写 OPO RFCOMM 控制通道的组件。
- `EarbudsSession` 接收传输事件，将协议报告归并为电量、佩戴状态和降噪状态。发送设置后等待耳机回报，不提前修改真实状态。
- `Buds` 负责 macOS 蓝牙设备发现、自动连接、用户连接意图、系统电量兜底和界面可观察状态。
- `PanelView` 根据设备能力显示功能。未适配型号不会显示可写的降噪控制。

## 设备选择

应用只枚举已配对且提供 `oppointeraction` 服务的设备。选择优先级固定为：

1. `BUDSBAR_ADDRESS` 环境变量指定的设备；
2. 用户上次选择的设备；
3. 只有一台兼容设备时自动选择；
4. 有多台且没有历史选择时，由用户从面板中选择。

切换设备时会先关闭旧设备的控制会话，避免命令发往错误的耳机。
