# 009 — EQ 推子的原生触觉刻度

状态：实现与自动验证完成，用户已确认触控板手感满意；鼠标降级专项未独立验收。

## 设计

保持现有原生 NSSlider、±6 dB / 1 dB / 13 刻度、键盘及 VoiceOver。
仅原生指针拖动中实际改变刻度时请求系统触觉：普通刻度 alignment，
落到 0 dB 使用 generic，归零不叠加第二次震动。系统接口提供模式而非
可配置强度，因此“归零更明确”是待实机调优的设计目标，不保证更强。

自定义请求间隔至少 50ms；快拖或一帧跨多格丢弃中间反馈，不排队。
被限频的值仍立即写入 Binding，并更新去重基线；同一刻度不补播。
点击轨道后的起始值重新对齐；每次拖动开始/结束重置局部反馈状态。
键盘、VoiceOver、点击和程序加载曲线不请求自定义触觉。

每次反馈重新获取 NSHapticFeedbackManager.defaultPerformer，硬件能力、
输入设备和用户偏好由系统处理；不做能力轮询，不模拟声音或视觉抖动。
Reduce Motion 不增加空间动画，触觉独立遵循系统 performer 的设置。

依据：Apple SDK NSHapticFeedback.h 与
[NSHapticFeedbackManager](https://developer.apple.com/documentation/appkit/nshapticfeedbackmanager)。

## 边界和实现

新增 UI/EQHapticSlider.swift，EQBandSlider 创建该 NSSlider 子类；coordinator
先同步更新原 Binding，再通知触觉路径。原生 mouseDown 跟踪循环和控件
绘制均交给 super。不改推子范围、曲线存储、协议、命令队列或应用时机。
无新依赖、系统版本提升或触觉设置页面。

## 验证与手动验收

6 项 EQSliderHapticTests 覆盖刻度去重、两方向归零、快拖丢弃不补播、
跨多格只反馈一次、下一次拖动重置和原生 coordinator 即时更新。
全量测试及本地 Debug 构建结果见本轮实施记录；测试不能证明硬件震感。

请用 Force Touch 触控板慢拖、快速跨多格、从正/负值归零及保持同值，
检查无持续震动、无松手后补播；确认键盘和切换曲线不震动。普通鼠标
及无触觉设备应仍正常调节。保留前几批未提交改动，不覆盖 /Applications。
