# 002 — 让过时的连接提示失效

- Status: 实现与自动验证完成，待实机验收；Priority: P0；Severity: HIGH；Category: lifecycle / truthfulness
- Commit: `2becbf0f9e32c9d1b2914c9abcd7ed43a82ab2ee`
- 涉及：`ConnectionHUDCoordinator.swift`、必要的 `ConnectionExperience.swift`/`App.swift` 接线，ConnectionExperienceTests/QuickControlTests；均位于现有 BudsBar/Tests 路径。
- 依赖：无，完成后与 001 联合检查槽位交接。

## Problem

`Sources/BudsBar/UI/Experience/ConnectionHUD/ConnectionHUDCoordinator.swift:26–38` 在处理当前 observation 前可能 show waitingEvent；`88–118` 延迟回调没有检查当前连接是否仍符合 event。`ConnectionExperience.swift:57–64` 主动断开时：

```swift
lastPresentation = nil
return []
```

这是正确的“不发主动断线通知”，却没有使已等待/显示的连接卡片失效。新事件因偏好关闭而被过滤时，旧相反提示也未撤下。

## Target

任何时候 connected/reconnected 只对当前已连接设备有效，unexpectedDisconnected 只对当前非主动断开的未连接状态有效。新提示关闭不影响旧提示清理。等待区只保留一个最新有效事件；资料齐备/槽位释放/延迟到期都要再验证。不会排队补播一串历史事件。

过时语义立即清除；若没有新 HUD 占位，可 120 ms opacity 淡出旧表面；快捷操作接管仍 dismissImmediately，避免重叠。无位移/缩放新增；Reduce Motion 同为短 opacity。合法连接提示的既有 650 ms 去抖、5 秒去重和阅读停留保持。

## Steps

1. coordinator 先接收最新 observation 并撤销冲突 waitingEvent/readiness work item，再更新可见内容、处理 reducer effects。不得先展示旧等待事件再检查新状态。
2. 在 `retryDeferredPresentation`、readiness completion、show 前复用一个小的 event/observation 适用性判断，同时检查 isEnabled 和 isSlotBusy；不建立通用事件过滤框架。
3. 主动断开、当前设备切换、rebaseline 清理等待与可见事件。若现有接线不能识别设备切换，使用 Buds 现有 selectedDeviceAddress 或明确的切换通知作局部失效依据，不拿名字当稳定身份。
4. 恢复连接时撤下旧断线卡片，再根据设置决定是否呈现新卡片。断线时立即作废旧连接展示，新的断线通知仍按 650 ms 去抖。
5. 补上述路径的测试；现有首个 observation 静默基线和快速重连去抖测试保留。

## Boundaries / Risks

不调整 Bluetooth 连接策略、不扩大 reducer 为整个应用状态机，不改变用户开关语义。风险是取消所有等待导致真正新连接丢失，或误把“资料不齐”当“事件过期”；测试分别覆盖有效等待与无效等待。

## Verification

- `swift test --filter ConnectionExperienceTests` 和 `swift test --filter QuickControlTests`：检测去抖、去重、槽位顺序改变；失败则恢复合法事件次序。
- 新增：slotBusy→connected→主动断开→释放，不出现 connected；断线卡片→重连但 reconnect 开关关闭，旧卡片消失；readiness 等待中主动断开不补播；合法事件等待后仍正常展示；切设备不出现旧设备名/旧回执。
- 实机：快捷操作提示出现时主动断开/重连、分别关闭相关 HUD 开关后重复。无错标题、无双 HUD。无需改变实际通信时长制造动画。
- Done when：所有展示事件与最新连接事实一致，偏好仍按原义工作。
