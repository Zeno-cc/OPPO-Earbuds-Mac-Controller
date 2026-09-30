# 005 — 设备信息刷新显示真实完成结果

- Status: 实现与自动验证完成，实机刷新正常路径通过；异常观感待验收；Priority: P1；Severity: MEDIUM；Category: async feedback
- Commit: `2becbf0f9e32c9d1b2914c9abcd7ed43a82ab2ee`
- 涉及 `Sources/BudsCore/EarbudsSession.swift`、必要的 `FeatureState.swift` 复用、`Sources/BudsBar/Buds.swift`、`UI/DeviceHeaderView.swift`、FeatureStateTests；依赖：无。

## Problem

`DeviceHeaderView.swift:180–192` 以 didEnqueue 增加旋转 trigger；`EarbudsSession.swift:636–672` 保留 ready 缓存，但刷新失败走：

```swift
case .failure:
    if case .ready = self.state.deviceInformationFeature { return }
```

刷新实际失败和数据未变化的成功，用户看起来相同。旋转只证明触发，不能作为完成。

## Target

缓存一直可读；refresh idle→loading→success/failed/cancelled 独立呈现。按下立即显示忙碌；收到本次查询响应才成功；失败有简短可读原因。图标固定16pt槽，状态opacity120 ms easeOut，成功小勾停留1.2秒恢复刷新图形，失败保留到重试/关闭。无位移、无scale；reduced用静态忙碌图形和文字/原生progress，不作自定义旋转。

## Steps

1. 沿用项目现有 FeatureRefreshState 的思路，为 deviceInformation 增加最小 refresh 状态/完成投影，保持 `.ready` 原数据。只在现有query completion更新，不另发查询、不额外轮询。
2. 将成功但值不变也视为一次真实完成；保留generation和query取消约束，断开时loading结束，不能提示成功。
3. Buds同步独立refresh状态。Inspector据此禁用重复手动刷新或合并到原请求；UI不得对一个已合并请求反复启动假进度。
4. fixed图标槽显示busy/成功/失败，失败复用按钮邻近的caption，不扩成大卡片。成功阅读timer仅管理本地短反馈，关闭view取消，不能取消设备查询。
5. 若当前ControlFeature枚举仅表示可写设置，不为省一行把设备信息硬塞入SET操作模型；使用明确的小字段即可。

## Boundaries / Risks

仅新增已有查询的结果可观察性。不能改变固件数据缓存策略、协议命令、重试次数、队列节流、读取周期。风险是generation切换后的旧completion被当成功或新增观察循环；沿用session取消语义并用fake transport检测。

## Verification

- `swift test --filter FeatureStateTests`，为ready缓存刷新新增：相同成功值也结束loading；timeout/格式异常显式失败且缓存仍在；取消不报成功；重复触发保持单请求语义。失败时修状态传递，不用延迟spinner掩盖。
- 实机：点击刷新观察当帧反馈；控制通道不可用时说明原因；两次快速点击不双转/双结果；关详情再打开不残留忙碌。
- Done when：用户能区分“正在刷新”“已完成且没变化”“刷新失败”，没有新增蓝牙流量。
