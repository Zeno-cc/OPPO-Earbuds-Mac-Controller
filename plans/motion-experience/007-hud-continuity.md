# 007 — 整理 HUD 几何、身份与中途替换

- Status: 低风险实现与自动/原生几何检查完成，完整实机动效待确认；Priority: P2；Severity: MEDIUM 风险；Category: physicality / interruptibility
- Commit: `2becbf0f9e32c9d1b2914c9abcd7ed43a82ab2ee`
- 依赖：001/002/003。涉及 `Sources/BudsBar/UI/Experience/ConnectionHUD/{ConnectionHUDPanelController,ConnectionHUDView,HUDPresentationState}.swift`、`UI/MotionTokens.swift`，必要的 QuickActionHUD 呈现配合。

## Problem

实施结论（2026-09-30）：完成相同 snapshot/frame 去重、共享 hover、展开内容事件续接、退出重入和 Reduce Motion 中途收敛。原生宿主未提供逐帧裁切证据，保留原外框/卡片形变，不实施固定透明画布；原弹簧及停留不变。验证边界见 README 第三批记录。

AppKit resize（PanelController:223–228）使用easeInEaseOut；SwiftUI surface（View:192–196）使用：

```swift
.spring(response: HUDMotionTokens.springResponse,
        dampingFraction: HUDMotionTokens.springDamping)
```

两者分别驱动外框/卡片几何。每次snapshot更新调用resize；show清isHovering（52行），视图本地hover状态却仍可能true。以上结构可证，裁切和悬停丢失的真实严重度尚需确认。

## Target

保留用户认可的胶囊到卡片形变，独占此处的spring个性。起点：response0.48/damping0.80；紧凑入场220ms easeOut、y+6→0、alpha0→1；资料180ms淡入（最多2pt）；展开保持2.65秒；hover退出1.6秒；退出内容160ms，收回280ms easeOut，alpha消失180ms。无额外整体scale/模糊。Reduce Motion直接最终尺寸淡入/淡出120ms。

**本任务的开始不是立即重构。** 先录制两个具体输入：展开尚未结束收到相反事件；展开后资料补齐改变高度。如果无边缘/反向问题，只做可证的hover同步与无变化resize消除；不因技术上有两种曲线就重写窗口。

## Steps

1. 在原生测试宿主用现有snapshot/event进行上述两种输入，再一次真实连接录像。正常速度和逐帧对比轮廓、文本、指针范围，不在生产UI加入测试开关。
2. 相同snapshot/目标frame不重设NSAnimationContext；原位新事件保留或重新命中当前pointer的hover，不能无条件置false后盼onHover重发。阅读期只因新事件/真实hover退出而调整。
3. 若第一步证实双几何问题，采用明确结构：NSPanel固定覆盖最大350×120画布并锚定屏幕右上；SwiftUI surface右上对齐，作为唯一可见几何驱动。保持其实际卡片尺寸、材质与clip；不扩大可见卡片。窗口/hosting hitTest必须只接收实际surface区域，透明画布区域点击穿透；验证阴影不会被canvas截断。必要的阴影边界由实际shadow测量决定，不能任意留大透明遮挡区。
4. 用现有lifecycle重定向可见目标，不隐藏再重放compact；新事件立即更新标题，资料只在本地淡換。已在退场时收到有效新事件从当前画面续接，旧completion的generation guard保留。
5. 可以保留有意义的compact/expanded阶段，但不为每一行各加timer。几何完成影响展示阶段，不能影响设备确认；纯阅读计时与spring响应分开。
6. 与Quick HUD交接仍允许立即让位；不同时显示两层。001已固定同一快捷操作的screen/host，本任务不重复实现。

## Boundaries / Risks

不更改连接判断、650ms去抖和用户偏好，不把两种HUD合成新的全局通知框架。固定画布方案的主要风险是透明区域吞点击、窗口shadow范围及SwiftUI内容被裁切；任一未解决就不采用该结构，记录该子项未完成，保留已完成的低风险改善。

## Verification

- `swift test --filter ConnectionExperienceTests`：保留阶段顺序、事件size和去重语义；更新仅机械锁死旧时长的断言时必须说明设计变化，不把新参数再全部镜像成测试。
- 实机：compact入场中反向、展开中反向、fadeout中重入；hover不动时换事件；资料迟到；双屏移动指针；点击卡片外但在透明canvas内。要求无旧标题补播、无跳回alpha0、无透明阻挡、hover期间不自动退场。
- 仅在上述录制发现掉帧时用Instruments查对应阶段；不先加缓存/线程/轮询。卡片完全隐藏后不再因呈现执行周期性工作。
- Done when：被证实的问题消失，已有停留与空间归属仍自然；“换一个弹簧参数”本身不算完成。
