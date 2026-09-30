# 006 — 收尾小型设置控件的反馈

- Status: 006a 实现完成待实机验收；006b 实现/自动验证完成；Priority: 006a P1、006b P2；Category: feedback consistency
- Commit: `2becbf0f9e32c9d1b2914c9abcd7ed43a82ab2ee`
- 本文件含两个独立小任务，可分别实施/验收；依赖：无，淡换采用已有MotionTokens/003约定。

## 006a 快捷键录入错误清理

**问题/位置：** `Sources/BudsBar/HotKeyRecorderView.swift:65–78,90–99` 的成功和Esc路径只stopRecording，`note`还在，视图21行继续显示旧错误：

```swift
Text(note ?? detail)
// valid key accepted:
stopRecording()
```

**目标/步骤：** 成功录入、Esc、再次点录制按钮主动取消时清理本次note；无效输入/系统拒绝时仍显示具体原因并保持录制。确定停止录制的统一出口是否都应清理，避免为此新增复杂enum。错误文字可以120 ms opacity淡换，位移0/scale1；焦点和热键恢复立即发生，Reduce Motion同样只淡换。

**边界/风险：** 不改Carbon注册、持久化、组合键冲突规则或原有clear功能。注意成功路径已安装新组合，结束录制恢复操作不能把旧组合注册回去；沿用现有Buds状态读取。

**验收：** 无效字母→有效组合后旧橙字消失；无效→Esc后原组合有效；无效→点击取消同样恢复；Delete清除仍正确；关闭详情时监听释放。不需要为纯note赋值写实现镜像测试；运行现有 `swift test --filter QuickControlTests` 防注册/可观察性回归，重点用一次实机输入序列验收。该任务可独立提交给执行者，完成不依赖006b。

## 006b 更新图标的失败语义

**问题/位置：** `Sources/BudsBar/UI/SoftwareUpdateButton.swift:58–62`：

```swift
if updates.presentation.availableVersion != nil { return "arrow.down.circle.fill" }
if showsNoUpdateCheck { return "checkmark.circle" }
if case .failed = updates.presentation.phase { return "exclamationmark.circle" }
```

此前发现版本而后失败时，可见图形仍像可直接下载，tooltip却说失败。属于显著性风险，更新本身未被判故障。

**目标/步骤：** busy优先；非busy时failed优先显示感叹号，保留availableVersion和原点击重试逻辑；有版本仍可保留蓝色，错误由形状+help表达。固定30×30尺寸；图形仅120 ms opacity淡换，无旋转/回弹/位移；reduced同。无更新的小勾仍1.5秒，沿用`.task(id:)`取消检查，不重建一个timer服务。

**边界/风险：** 只改图标投影及必要的局部视觉；不碰Sparkle feed/签名/下载/安装，不恢复大更新卡片。避免先改失败图形却把此前发现版本清空。

**验收：** `swift test --filter UpdatePresentationTests` 保持Later保蓝/Skip清版本/失败保留已发现版本；若抽出纯symbol投影，可补failed+available的一个有效组合测试。实机或preview注入busy/found/noUpdate/failed：形状和AX文字一致、尺寸不变。无需再次真实安装更新；preview不属于真实Sparkle端到端验收。
