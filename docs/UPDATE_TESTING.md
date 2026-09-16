# 更新测试与实机验收

## 自动化

Swift 的状态模型、配置、ObjC delegate selector 测试：`swift test` 和 `swift test -c release`。
Python 的配置、危险 ZIP、版本/签名字段测试：`python3 -m unittest discover -s Tests/ReleaseTests -v`。其中合成签名仅用于结构测试，不冒充真实密码学验证。

macOS CI 的 `test-update-signatures.sh` 使用一次性 Keychain identity，签名并验证真实 App ZIP 和 feed，检查修改 ZIP/XML 后拒绝。
`test-update-install.sh` 仅允许 GitHub CI，使用官方 Sparkle CLI 在临时目录进行真正 App 替换：先拒绝篡改包，再升级补丁号并验证安装后的代码签名。
这时 App 没有运行，因此不代表图形界面、Relaunch 或蓝牙权限已经验收。

测试密钥不会成为正式信任根，不发布任何测试版本，不修改 /Applications。正式 publish 脚本拒绝带测试标记的构建。

## GUI 和生产签名必须人工确认

在独立 macOS 用户/VM 中，用安全备份的签名密钥及正式公钥构建候选版，使用隔离的测试 feed 验证，不能把假高版本发布给所有用户。DEBUG 的 localhost feed 仅允许显式测试构建；Release 固定官方 feed。

至少记录：

| 场景 | 要求 |
| --- | --- |
| 正常更新 | 发现、下载、验证、替换、Relaunch 后版本正确 |
| 离线/404/签名失败 | 不影响现有耳机功能，不替换旧 App |
| 取消/延后/取消授权 | 原应用保留，后续可重新检查 |
| /Applications 与用户 Applications | Sparkle 正常权限流程 |
| 只读 DMG | 拒绝或正确引导，不使用 sudo/cp 绕过 |
| Dock 关闭 | 更新窗口可见，Popover 不遮挡 |
| 设置保存 | 设备选择、HUD、电量偏好、本地 EQ 方案不丢失 |
| 蓝牙/TCC | 记录重新授权情况，电量和 ANC 恢复 |
| 睡眠/唤醒/退出 | 无重复 updater 或遗留安装流程 |

第一版内置 updater 需要人工安装一次。生产 feed 在 Release 公开后才可匿名验证，Draft 地址 404 正常。严格区分“代码和 CI 通过”与“生产密钥就绪、完整实机验收完成”。
