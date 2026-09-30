# 001 — 补齐快捷操作反馈闭环

- Status: 实现与自动验证完成，待实机验收；Priority: P0；Severity: HIGH；Category: feedback / interruptibility
- Commit: `2becbf0f9e32c9d1b2914c9abcd7ed43a82ab2ee`
- 预计范围：Buds、QuickActionHUD、App 的反馈接线及 QuickControlTests；依赖：无。

## Problem

`Sources/BudsBar/QuickActionHUD.swift:35,59–77` 对 pending 和终态使用同一自动退出时间：

```swift
private static let holdDuration: TimeInterval = 1.6
let work = DispatchWorkItem { [weak self] in self?.hide() }
```

会话实际发送后还等 3 秒确认。`Buds.swift:983–984` 的 busy guard 会调用 reportQuickFailure；该方法 `1070–1072` 把原本的 pendingQuickFeedback 清空。`1011–1029` 的未知模式意图超时也只清理，不发终态。连续按键能吞掉第一次真实结果。

## Target

同一操作维持同一可见 HUD：waitingForMode/queued/sent → confirmed/failed → hidden。未知模式文案“正在读取当前模式…”；到期显示“未收到当前模式，未执行切换”。重复按键保留原操作，不延长业务截止，不发送新命令、不覆盖为“未连接”。

入场 alpha 0→1，160 ms easeOut；状态文字淡换 120 ms；退场 alpha 1→0，160 ms easeOut，scale=1、位移=0。pending 无显示端的 1.6 秒退出任务；成功从确认起停留 1.6 秒、失败从终态起停留 2.6 秒。Reduce Motion 用 100 ms opacity，无空间变化。以上为调优初值。

## Repo conventions

`FeatureOperation` 已有 id/generation/phase；`QuickNoiseState` 已有 pendingSince；沿用这些身份与期限。QuickActionHUD 已有 presentationGeneration 防旧 completion；保持它，复用一个 hosting view/model，以属性更新替代每次重建。UI 阻止重复写入与动画中断是两回事。

## Steps

1. `Buds.swift` 区分“操作正在 pending”和“控制通道不可用”。前者直接保留现有 narration；后者才报错。保证一次被接受的快捷操作拥有自己的终态；仅在必要的反馈投影中记录现有 operation ID，不改 Core 目标判断。
2. 用原 pendingSince 计算未知模式剩余时间，重复触发不得重设截止。真正超时先产生失败回执，再清理意图。主动取消与超时分开，避免打开面板也误报超时。
3. `.submitted` 的呈现持续到业务终态，实际 sent 的 3 秒规则仍由 EarbudsSession 管理；queued 不伪装为 sent。若操作取消/断开，消费该操作终态，不留下无限 spinner。
4. QuickActionHUD 持有稳定可观察内容，按反馈种类安排停留。长错误最多两行并一次选择足够高度，不能截掉原因。一次反馈开始时记录 screen，结果复用，下一次操作再选屏。
5. `App.swift` / `Buds.panelWillOpen` 接线：面板接管时撤下快捷 HUD、取消尚未发出的未知模式意图；已发操作继续完成并由面板渲染。不让旧回执关掉新 HUD。
6. 更新/补充 QuickControlTests 的反馈归属用例。仅为这些路径提供最小测试入口，不构造新的通用 Coordinator 框架。

## Boundaries / Risks

不改 SET 单发、队列优先级、协议、3 秒确认、2 秒未知模式窗口。不把“等待中再按”实现为目标覆盖队列。最大风险是取消显示时误取消设备写入，或终态回调错误归属；用已有 ID/generation 与具体路径测试拦住。

## Verification

- `swift test --filter QuickControlTests`：检测重复输入吞终态、旧 completion 隐藏新反馈；失败则修反馈归属，不能延长计时绕过。
- `swift test --filter FeatureStateTests`：检测目标在确认前被渲染/业务确认规则意外变化；失败则撤回 Core 改动。
- 添加精确 fake-clock 场景：pending 超过 1.6 秒仍可见；发送后 3 秒终止；未知模式 2 秒产生一次失败；等待中多按两次只一个 SET；迟到报告不追补旧 success；旧 fade 未结束来新 feedback 不消失。
- 实机：快捷键连续三次、pending 时打开面板、失败长文、结果前跨屏移动指针。检查一条连续反馈、真实选中、无未连接误报。开启减少动态效果复查一次。
- Done when：每个未被用户主动接管的请求都有可理解终态；同功能重复输入不丢第一次终态；无多余写入。
