# 008 — 窗口交接与 EQ 编辑细节

- Status: 焦点问题经原生宿主证实并修复，EQ 局部反馈完成；完整实机矩阵待确认；Priority: P2；Category: hierarchy / focused interaction
- Commit: `2becbf0f9e32c9d1b2914c9abcd7ed43a82ab2ee`
- 依赖：003、004。下列两个子项可独立验收，不要求一起重写。

## 008a 首次介绍的焦点交接（风险先验证）

实施结论：隔离原生 `.app` 确认原路径丢失介绍 key；改为介绍/主面板互斥路由后，介绍保持 key，Return 可关闭，下次入口打开主面板。Dock 隐藏等专项仍待确认。证据在 Trellis 第三批 `research/focus-observation.md`。

**问题/位置：** `Sources/BudsBar/App.swift:349–352`：

```swift
buds.panelWillOpen()
popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
popover.contentViewController?.view.window?.makeKey()
```

panelWillOpen可同步调`WhatsNewPanelController.show()`，其先makeKey介绍窗口，随后上面又makeKey主popover。最终焦点归属尚未实机验证。

**设计/步骤：** 使用隔离preferences的原生测试实例验证首次入口；不要清除用户正式“已看过”设置。若回车焦点竞争成立，让本次展示请求返回明确的“介绍/主面板”选择，只由一个宿主取得key；介绍关闭后不自动叠弹控制面板。保持独立非模态NSPanel、当前屏幕居中和重复打开只置前。AppKit默认窗口呈现，不新增scale/offset或等待动画完成的延迟。

**边界/风险：** 仅 App.swift、Buds.panelWillOpen、WhatsNewPanelController 必要返回值/接线和相关PresentationTests；不改窗口类型，不用sheet。风险是首次面板变得无法再次打开；首轮介绍关闭后再次点菜单栏必须直接打开面板。若实机未出现焦点竞争，记录通过并不为这项改代码。

**验收：** 首次出现介绍时回车触发“知道了”，关闭后主面板可点开；详情里的再次介绍同样置前；Dock关闭时仍可前台操作；窗口已可见时重复请求不重播。`swift test --filter PresentationTests` 检查现有非模态与定位约束。不开真实安装更新验证焦点。

## 008b EQ 的局部状态过渡（保留直接操控）

实施结论：仅标题/状态文字淡换，动作按钮立即替换，不动画化推子或 editor。完整业务回归通过；真实入口/窗口布局已检查，曲线编辑和取消动效仍待用户确认。

**现状/位置：** `Sources/BudsBar/UI/CustomEqualizerView.swift:25–45`由AppKit拥有尺寸；`108–118`在确认readback后加载曲线；`296–334`固定footer状态槽；`415–453`为连续NSSlider。没有动画不等于缺陷；这些都是应保留的基础。

**目标/步骤：**

1. 在曲线切换、应用结束、确认删除→取消的同位置状态文字/按钮组使用140ms easeOut opacity；位移0、scale1，Reduce Motion100msopacity。只对这些子视图应用，不包围editor。
2. 十个推子、草稿预览、输入文字实时更新，无spring、无numeric滚动延迟。切换曲线立即更新十段值，局部标题/状态可淡换，不按频段stagger。
3. 保持status行30pt、错误可两行与底部操作固定位置。新旧删除按钮在过渡时只有当前语义的按钮可点击/可访问，不留下透明旧热区。
4. 手机端修改仍通过dirty/stale约束处理：保护草稿、说明冲突，不为了平滑覆盖内容。full list确认后才改“使用中”；失败仍能本地保存。关闭重开依现有草稿策略，不新增自动保存功能。

**边界/风险：** 不改LocalEqualizerStore、协议create/update/delete、曲线ID、NSSlider tick/范围、NSPanel的`sizingOptions = []`。风险是动画导致焦点丢失、名称字段被重建或透明按钮残留；保持stable identity，不给整个editor换`.id`。

**验收：** 本地草稿拖动/方向键/归零始终跟手；选择两条曲线不飞动全部推子；失败保留草稿；confirm-delete取消后旧删除按钮不能触发；关闭再打开按原语义恢复；低高度屏幕footer和滚动都可达。仅演示状态变化可用native preview；“耳机确认”必须另有真实设备或fake transport证据。`swift test --filter CustomEqualizerTests` 和 `swift test --filter PresentationTests` 用于保护业务边界与窗口约束，不宣称它们验证了动效观感。
