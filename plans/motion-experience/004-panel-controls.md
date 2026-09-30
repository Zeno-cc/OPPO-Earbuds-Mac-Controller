# 004 — 收窄主面板动画，稳定等待反馈

- Status: 实现与自动验证完成，有限实机检查；完整体验待验收；Priority: P1；Severity: MEDIUM（体验风险）；Category: cohesion / layout
- Commit: `2becbf0f9e32c9d1b2914c9abcd7ed43a82ab2ee`
- 依赖：003；涉及 `Sources/BudsBar/PanelView.swift`、`UI/{CompactSegmentedControl,NoiseControlSection,SoundSection,DeviceHeaderView,BatteryStripView,MotionTokens}.swift`；App.swift 原则上只验证不改。

## Problem

PanelView:58–64 在根部同时监听连接、错误、模式、电量、EQ/游戏状态；内容测高又在73–81/157–186改变viewport。SoundSection:114/155 的 spinner/文本动态插入可能推动其他内容。CompactSegmentedControl:149–150：

```swift
.disabled(!isEnabled || pendingValue != nil)
.opacity(isEnabled ? 1 : 0.48)
```

调用方 pending 时把 isEnabled 传 false，连等待标记也弱化。这些代码关系已确认；是否产生显著抖动、焦点问题需实机，不预先断言性能故障。

## Target

稳定的真实选中+清晰的目标pending，局部180 ms easeOut选中变化、120 ms opacity等待切换。自定义plain按钮按下当帧变色、释放100 ms easeOut；不缩放整排控件。pending仍锁定同功能重复提交，但不是低对比不可用态。主popover保持368pt内容宽、现有最大高度与固定header/footer。

## Steps

1. 先记录一次当前ANC展开、EQ提交/确认、游戏pending、错误多行出现；只记录可见几何与焦点，不改系统全局动画速度。
2. 移除根级业务模型 `.animation`，在 Header内容、实际电量槽、选中底板、pending、连接内容切换放置精确局部动画。父级不带动任意子树。纯测高赋值用无动画transaction，保留0.5pt阈值。
3. 将可交互条件与视觉状态分开：offline/unsupported可以弱化；busy目标spinner正常对比，已确认selection仍可辨。传入真实available和pending，最终disabled仍严守业务限制，不借视觉重构放开重复SET。
4. 游戏行固定一个12–16pt等待槽，不让出现spinner挤动toggle。EQ/ANC等待优先复用控件内/现有说明位置，避免平时新增整排空白。错误允许自然换行，不强行压成单行。
5. ANC强度区域在confirmed后淡入180ms；测高不继承动画，窗口外层交给原有hosting sizing。先保证无多次反复测高、无永久空白；如录屏显示外层一次尺寸变化仍生硬，再独立评估，不能直接添加第二套AppKit resize时钟。
6. 选中底板重定向到新confirmed值；首次读取与重开直接呈现当前值，重复同值不重播。滑块、文字输入、焦点环不继承淡入/缩放。
7. 只对确实缺少pressed表现的plain控件用轻量ButtonStyle的configuration.isPressed，保留Button而非onTapGesture；先尊重已有系统响应。

## Boundaries / Risks

不修改BudsCore、Panel尺寸上限、菜单栏L/R布局、EQ窗口sizingOptions；不靠全局固定高度压住抖动。风险是移除祖先事务后遗漏局部反馈，或复杂窗口测高出现裁切；用实机/既有Presentation回归判断，不能靠新增整页动画补救。

## Verification

- `swift test --filter PresentationTests`：防popover模态和EQ sizing约束回归。仅新增可测试的显示投影断言，不写扫描每个.animation字符串的测试。
- 实机：ANC→通透、手机再改ANC；待确认期间再按；游戏失败；关闭重开；错误两行；滚到下半部后强度区变化。确认header/footer无无关弹动、控制点不被spinner挤走、滚动仍可达、真实selected与手机一致。
- 键盘/VoiceOver：pending可读，失去可用性后恢复仍可继续操作；reduced按003行为。
- Done when：布局只因真实内容结构变化而变化，同值刷新不动；pending清楚，未知/失败不显示伪成功。
