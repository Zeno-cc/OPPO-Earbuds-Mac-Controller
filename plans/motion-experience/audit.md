# 动效与交互审计

日期：2026-09-29。源码基线：`2becbf0f9e32c9d1b2914c9abcd7ed43a82ab2ee`，本轮开始时 `main...origin/main` 工作区干净。下列文件路径均相对仓库根目录，行号以此提交为准。

## 方法与证据边界

实际使用 `improve-animations`（含 AUDIT 与 PLAN-TEMPLATE）、`apple-design`、`write-swift`；两个只读子代理分别检查窗口/HUD 和控件，主代理复核引用代码并跟踪 Buds → EarbudsSession → CommandQueue。网页技能中的 CSS、300 ms 硬阈值、只能动画 transform 的规则不适用于本项目；这里只借鉴反馈、中断、空间关系和克制原则。用户已要求本轮完整规划，因此直接交付任务，不额外等待技能中“先选择问题”的中间确认。

检查了全部 BudsBar UI/Experience 与主宿主、快捷反馈、更新入口；状态真实性重点阅读 Buds、EarbudsSession、FeatureOperation、CommandQueue、QuickNoiseState，结合 Presentation/ConnectionExperience/QuickControl/FeatureState/Session 等相关测试的现有结构。协议字节编解码不是本轮全面正确性审计对象。

证据分类：

- **C，代码已确认**：支持的用户路径存在明确缺口；不表示已在真机复现。
- **R，体验风险**：调用关系或参数差异可证，视觉/输入后果需要实机判定。
- **V，待验证**：本轮没有足够证据给出通过或失败。

### 有限实机记录

通过 System Events 的辅助功能接口检查已经运行的 `/Applications/OPPO Earbuds Mac Controller.app`，进程 BudsBar，plist 版本 1.5.1。版本号匹配，但没有核对该安装实例的构建源码 SHA，因此实机记录只代表这个安装实例。没有重启、重建或替换它，也未发送耳机设置写命令、修改偏好或安装更新。

- 状态项起初 help 为“OPPO Enco Air5 Pro · 正在连接”；稍后应用自行进入已连接内容，读取到左右耳盒外、ANC/EQ/游戏模式控件。
- AXPress 打开状态项，读取到主 popover；点击 help 为“详情”的按钮后，读到嵌套 inspector 的设备、连接、偏好、快速控制与关于分组。
- 两次采样的 AX popover 尺寸为 394×570、394×553（包含系统外框）。它们不是连续逐帧测量，**不能据此判定布局跳动**。
- 尝试重复按状态项关闭/重开。短等待后 AX 节点仍存在，稍后查询节点消失。AX 生命周期不能证明视觉退场的每一帧或快速反向操作通过，因此这些仍为 V。最后未继续保留可访问的主 popover。
- 本轮没有录屏或帧率/能耗采样，没有测试手机写入、硬件超时、hover 保持、系统减少动态效果和外部点击关闭。不能把 AXPress 成功等同于整套动效真机通过。
- 没有执行自动化测试；阅读测试只能说明既有覆盖，不是本轮通过记录。没有用此前发布验收替代本次体验检查。

## 实际技术结构与操作链

`Package.swift`：macOS 26，Swift tools 6.2，当前 target 使用 Swift 5 language mode，唯一外部包为 Sparkle 2.9.6；没有动画库。主界面是持有型 NSPopover + NSHostingController，详情与说明是 SwiftUI popover；EQ、新功能使用独立 NSPanel；两种 HUD 均为非激活 NSPanel。

| 场景 | 用户动作 → 状态变化 → 界面响应 → 终态 | 本轮判断 |
| --- | --- | --- |
| 主面板 | status action → 刷新现状/首次介绍判断 → NSPopover.show → 设备状态；再次点击/全局外部点击关闭 | 保留原生呈现；首次焦点见 R3 |
| ANC/强度 | Button → Buds.set → queued/sent → 原选中保留、目标 spinner → 设备通知匹配才 confirmed，3 秒未确认则终止 | 业务分离正确；pending 可见性/布局见 R1 |
| EQ/游戏 | setter → 单发写入 → 立即读回 → 真实 FeatureState 更新 → confirmed/不同状态/超时 | 保留；读回失败不能把目标渲染为成功 |
| 快捷控制 | Option/hotkey → `.submitted` 或等首次模式 → 操作终态 → HUD | C1 有丢失/空档 |
| 连接 HUD | 连接观察 → 基线/650 ms 断线去抖/事件 → 槽位与详情等待 → 分阶段 HUD | C2 旧事件未失效；R2 双几何 |
| 刷新信息 | inspector 按钮 → query accepted → symbol rotate → 设备信息缓存更新 | C4 缓存刷新没有独立终态 |
| 自定义 EQ | 本地 draft 跟随 NSSlider → 显式应用 → 等 full list readback → 更新真实曲线/错误 | 保留本地/设备区分和固定窗口 |
| 手机同步 | 设备主动通知或现有 EQ/游戏查询 → apply → Buds.sync → 局部状态 | 不增加动画轮询，不承诺手机修改零延迟 |
| 更新图标 | 灰色点击查询 → busy → 蓝色可用/勾/错误 → 二次点击交给 Sparkle | 紧凑入口保留，R4 失败优先级待调整 |

## 已确认问题（按收益优先）

### C1 · 高：快捷操作的反馈生命周期不完整 → 001

位置：`Sources/BudsBar/QuickActionHUD.swift:35,59–77`，`Sources/BudsBar/Buds.swift:966–970,982–1029,1070–1087`；`Sources/BudsCore/EarbudsSession.swift:285–312`。

1. 所有反馈含 `.submitted` 都固定停留 1.6 秒；会话在实际发送后等待 3 秒，前面还可能有排队。因此等待提示能在命令仍 pending 时退出，随后终态重新弹出，或全程无结果。
2. 首次模式未知时先提示“正在切换”；2 秒后只 `cancelQuickIntent()`，清空 narration 而不发出“未收到当前模式”的终态。
3. SET 尚在 pending 时再按快捷键，`canQuickNoiseControl == false` 进入 `reportQuickFailure`；文案误称未连接，且清空第一次操作的 `pendingQuickFeedback`。第一次真正 confirmed/timeout 时 `resolveQuickFeedback` 已无所属反馈，不再报告结果。此路径是正常连续按键即可到达，非毫秒竞态。

影响：用户可能看到失败但设置随后成功，或不知道请求仍在进行。不能靠更长入场动画修复。保留队列 pending 禁止重复写入与旧退场 completion 的 generation 保护；修复反馈所有权、超时结尾和保持策略。

### C2 · 高：连接 HUD 可以在事件过时后才展示 → 002

位置：`UI/Experience/ConnectionHUD/ConnectionHUDCoordinator.swift:26–38,60–62,88–118`；`ConnectionExperience.swift:57–64`；`ConnectionHUDView.swift:180–185`（前三者均在 `Sources/BudsBar/` 下）。

- Quick HUD 占位时 `.connected` 进入 `waitingEvent`。用户主动断开时 reducer 返回空 effects，等待事件未被撤销；释放槽位后按旧 event 展示，而标题只读 event，不读快照连接布尔值。
- observe 在处理当前连接变化之前就可能先释放 waitingEvent。
- 若旧断线卡片可见，连接恢复但“重新连接浮窗”关闭，新的事件被设置过滤，旧断线卡片仍留到自然退场。

影响：提示与当前事实相反。设置关闭新提示不应使旧提示持续说错。保留初次静默基线、断线去抖、重复抑制、快捷操作优先占位；在状态变化和实际 show 两处作轻量有效性判断即可。

### C3 · 中：减少动态效果仅缩短了部分空间运动 → 003

位置：`Sources/BudsBar/UI/MotionTokens.swift:10–12`；`CompactSegmentedControl.swift:74–79,115`；`DeviceHeaderView.swift:41–43`；`BatteryStripView.swift:52–56,91–94`；`Experience/ConnectionHUD/ConnectionHUDView.swift:17,40,192–196`；`ConnectionHUDPanelController.swift:182–200`。

reduced 仍返回 120 ms 动画，驱动 matchedGeometry 选中底板、头部电量 move、充电图标 scale，以及 HUD 展开尺寸/图像尺寸。HUD 的 AppKit 分支取消了 frame 补间，但 SwiftUI 几何仍动画；退场 `.dismissing` 又切回 compact geometry。

影响：用户选择减少运动后仍看到空间运动。需要区分透明度反馈与几何动画，不能只把统一 duration 缩短。保留 PanelView 已有 opacity 降级和电量读数的 reduced 局部分支。系统 symbolEffect 是否自行降级为 V，不仅凭缺少显式 if 就判错。

### C4 · 中：设备信息已有缓存时，刷新失败没有结果反馈 → 005

位置：`Sources/BudsBar/UI/DeviceHeaderView.swift:164–167,180–198`；`Sources/BudsCore/EarbudsSession.swift:636–672`。

旋转 trigger 只判断 query 是否入队。已有 `.ready` 时不进入 loading；响应无可解码内容或 query 失败时直接保留 ready 并返回，也没有独立 refresh 状态。用户无法区分“刷新成功但数据没变”和“刷新失败”。重复点击可增加视觉 trigger，而查询层可能合并请求。

保留缓存可见是正确的；应补一个实际查询完成的反馈状态，不应清空固件信息，也不应把旋转结束当成功。

### C5 · 中低：快捷键录入成功/取消后旧错误还在 → 006

位置：`Sources/BudsBar/HotKeyRecorderView.swift:21–23,65–78,90–99`。

录制无效字母写入 note，随后有效组合成功或 Esc 都只 stopRecording，没有清 note。于是新组合已生效，旁边仍显示旧橙色错误。不是缺少动画，而是反馈未收尾。成功/取消清理本次 note，保留真正失败时的可读原因。

## 体验风险与待验证项

### R1 · 高收益候选：父级动画与动态测高耦合 → 004

`PanelView.swift:58–64` 的七个 `.animation(value:)` 覆盖 Header、错误、滚动区和 footer；`73–81,157–186` 根据内容测量改 viewport，`App.swift:154–155` 同时启用 preferred/intrinsic sizing。ANC 强度条件插入（`NoiseControlSection.swift:26–47`）；EQ/游戏 pending 文本和 spinner 临时加入（`SoundSection.swift:114–118,155–158`）。同一事务内无关布局可能继承动画；Apple 的事务说明也指出了这个作用域问题，见 design 的来源。

此外控件整体 disabled+opacity 0.48 连 pending spinner 一起变淡（`CompactSegmentedControl.swift:99–106,149–150`）。这不是“没有反馈”，而是等待被画成了不可用。实际可读性、焦点和布局跳动尚未证实，不能声称已有掉帧或崩溃。

### R2 · 中：HUD 的两套几何时钟及中途替换 → 007

AppKit frame 在 `ConnectionHUDPanelController.swift:223–228` 用 easeInEaseOut；SwiftUI surface 在 `ConnectionHUDView.swift:143–149,192–196` 用 response 0.48/damping 0.80 的 spring；两者不是同一条曲线。快照刷新时 `update:61–65` 每次调用 resize，而 surfaceSize 的资料变化没有单独动画触发键。可能出现边缘裁切或资料到达时尺寸不一致；无逐帧证据，不能断言已发生。

`show:45–55` 每次清 isHovering，view 的本地 isHovered 却不清；同区域替换事件时系统是否补发 hover 尚未知。快捷 HUD 每次 show 重新建立 NSHostingView、按当前指针选屏（`QuickActionHUD.swift:62–63,102–111`），同一操作等待→完成之间移动指针跨屏，反馈会改变显示屏。这是确定策略，是否打扰需实机看，建议同一操作固定屏幕。

### R3 · 中：首次介绍与主面板存在两次 key 请求 → 008

`App.swift:349–352` 调用 panelWillOpen，后者同步请求新功能（`Buds.swift:367–374`）；`WhatsNewPanelController.swift:59–61` makeKey 后回到主 popover 再 makeKey。最终回车焦点取决于 AppKit 呈现时序；当前用户已看过新功能，未重置偏好复现。保留非模态独立窗口，后续先验证再协调这两个调用。

### R4 · 低：更新失败的可见图形被旧版本信息优先覆盖 → 006

`SoftwareUpdateButton.swift:58–62` 优先画 availableVersion 的下载图形，失败只在没有版本时画感叹号；`65–72` 的 tooltip/AX 却会说失败。保留蓝色“已发现版本”和 Sparkle 原生错误窗是有价值的；可增加同一小槽位的失败图形，不恢复大更新卡片。此处不是更新逻辑失效。

## 明确保留

- `EarbudsSession.swift:222–342` 操作分阶段；SET 不重试，3 秒确认边界不为动效延长；`CommandQueue` 共用节流、urgent lane、查询合并和 generation 清理。
- 选中高亮取 confirmed，pendingValue 单独显示。手机端报告可以更新真实选中；不因为 Mac 动画没播完而延后设备事实。
- `CustomEqualizerView.swift:15–45,415–453` 的独立非模态 NSPanel、`sizingOptions = []`、连续原生 NSSlider。已有历史窗口尺寸/模态回归约束必须保持。
- EQ 本地保存与耳机应用语义不同；dirty 草稿不会因为手机状态变化被自动覆盖（`108–118`）。关闭未保存草稿会丢弃是现有明确提示，本轮不改为自动保存产品功能。
- 电量按槽位 kind、分段按枚举、曲线按真实 ID 保持身份。未发现需要全局重做 view identity 的证据。
- 连接 HUD 的约 2.65 秒展开阅读期、轻微弹性和阶段次序已有测试及历史认可；不是仅因长于网页范例就要删除。
- 两种 HUD 已有取消工作项与 presentationGeneration 保护。主 popover 外部监听在 didClose 清除；没证据说它泄漏或所有控件会失灵。
- 更新的固定 30×30 槽、两次点击流程和 `.task(id:)` 取消检查是正确的。现有原生窗口没有自定义入场动画不构成问题。
- 未发现生产 UI 使用 repeatForever 自定义循环。现有 2 秒连接本地查询、10 秒音效刷新和 30 秒电量刷新是既有业务节奏；不增加动画用 Timer，不把这些查询直接判为能耗缺陷。

## 值得补足的过渡（不是缺陷计数）

1. pending→真实结果在原位置衔接，尤其快捷 HUD，收益高于新增回弹。
2. 已有稳定布局内的状态文字、图标进行短淡换，避免为一行反馈反复推开控件。
3. EQ 曲线切换与窗口交接只补必要的状态解释；跟手编辑、键盘焦点、菜单项本身保持即时。

**审计结论：存在具体反馈缺口，但没有证据支持“全部动效都差”或“需要重写 UI”。先修状态生命周期，再局部处理动画作用域，最后实机调优 HUD。**
