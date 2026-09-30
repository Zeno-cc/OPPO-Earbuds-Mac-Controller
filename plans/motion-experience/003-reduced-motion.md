# 003 — 分开空间运动与透明度反馈

- Status: 实现与自动验证完成，待实机验收；Priority: P1；Severity: MEDIUM；Category: accessibility / scope
- Commit: `2becbf0f9e32c9d1b2914c9abcd7ed43a82ab2ee`
- 涉及：`Sources/BudsBar/UI/{MotionTokens,CompactSegmentedControl,DeviceHeaderView,BatteryStripView}.swift`、`UI/Experience/ConnectionHUD/{ConnectionHUDView,ConnectionHUDPanelController}.swift`，必要的 PresentationTests；依赖：无。

## Problem

当前 token：

```swift
static func state(reduceMotion: Bool) -> Animation? {
    reduceMotion ? .easeOut(duration: fast) : .easeOut(duration: standard)
}
```

`CompactSegmentedControl:115` 的 matchedGeometry、`DeviceHeaderView:43` 的 move、`BatteryStripView:56` 的 scale 仍被它驱动；HUD container reduced 分支同样返回 120 ms 动画。用户要求的是降低空间运动，不是将原运动加快。

## Target

几何与反馈各有 token：正常局部 state/selection 180 ms easeOut，feedback 120 ms easeOut；reduced 几何 nil、位移0、scale1，反馈100–120 ms opacity。保持原生控件语义和 pending 文本。

## Steps

1. 在现有 MotionTokens 增加/明确 scoped opacity 与 geometry 的方法。调用点显式选择，避免全局 `.transaction(disablesAnimations: true)` 误吞有用反馈。
2. reduced 分支不使用 matchedGeometry；显示静态已确认底板，只淡换颜色。正常分支沿用 stable namespace。
3. Header 电量出现与充电标记 reduced 使用 opacity，不附带 move/scale；数字与条直接更新。检查同时发生 charging+level 时上层事务不会重新给长度/数字加动画。
4. 连接 HUD reduced 在 orderFront 前设置最终 surface/窗口尺寸，opacity 0→1 为120 ms；保持2.65秒；同一最终几何淡出120 ms。不要设置 dismissing 导致 compact geometry 动画，也不要先显示compact再瞬间放大。
5. 系统偏好在窗口可见期间改变时，取消自定义几何补间、稳定到当前语义目标，保留剩余反馈与输入能力，不重启整个HUD。用 SwiftUI environment 与 AppKit 系统偏好通知/读取，不能加轮询。
6. 原生 symbolEffect 先在 macOS26 验证系统降级；如仍明显旋转/pulse，reduced 改为静态忙碌/结果符号。无需替换 ProgressView 自己画动画。

## Boundaries / Risks

不改业务延迟、成功条件、系统最低版本，不顺带改变所有正常用户的曲线。风险是 nil animation 被祖先事务覆盖，或取消几何后内容不可见；必须看真实生成的界面，单测返回 nil 不足以验收。

## Verification

- `swift test --filter PresentationTests`：检查已有面板/控件边界未破坏；`swift test --filter ConnectionExperienceTests`：检查 lifecycle 保持。
- 对新增纯 reduced presentation 决策写一个针对性用例，验证最终尺寸先确定、退场不切compact；不对每个 duration 写镜像断言。
- 系统设置开/关“减少动态效果”：切 ANC/EQ、连入/断开、电量充电图标、HUD退出；要求无自定义移动/缩放、反馈仍可读。动画中途开启一次，检查终态可操作。
- Done when：reduced 只剩必要的淡换/原生进度提示，正常模式的主要节奏没有被全局移除。
