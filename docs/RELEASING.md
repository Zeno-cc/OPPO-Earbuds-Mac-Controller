# v1.6.0 发版准备与公开发布

只在本机使用 Sparkle 2.9.6 的专用 Keychain 账户 `com.aniketbudhwani.budsbar.updates` 签名。`Resources/SparklePublicKey.txt` 仅保存公钥；私钥应由维护者在仓库外备份，不能提交、写入 CI 或随安装包分发。备份未确认时不要公开发布。

1. 确认待发布源码已提交且工作树干净，`Resources/Info.plist` 两个版本字段均为 `1.6.0`，候选提交的 CI 已通过。先跑 `swift test`、`swift test -c release`、`python3 -m unittest discover -s Tests/ReleaseTests -v`、`bash build.sh debug`、`bash scripts/test-update-signatures.sh`。
2. 运行 `bash scripts/prepare-release.sh 1.6.0`。脚本只在本地构建 Release App，并产出被 Git 忽略的 `dist/v1.6.0/`，不会安装或上传。签名需要访问本机 Keychain。
3. 运行 `bash scripts/verify-release.sh 1.6.0` 复核 DMG、ZIP、appcast 与正式 Keychain 公钥。不要修改签名后的 ZIP 或 appcast。
4. 单独完成隔离的 1.5.1 → 1.6.0 更新验收；记录下载、验证、安装、重启及更新后蓝牙权限和耳机控制结果。`/Applications` 手动安装需要额外批准；v1.5.0 用户的第一次升级必须手动安装 DMG。未执行的专项应明确记录，不宣称通过。
5. 仅在获公开发布批准后，核对候选提交的 CI，再创建 `v1.6.0` tag/Release，上传 `OPPO-Earbuds-Mac-Controller-v1.6.0-macOS.dmg`、`BudsBar-1.6.0.zip`、`appcast.xml`，以 `docs/RELEASE_NOTES_v1.6.0.md` 作为发布说明。读取公开 Release 资产及 `releases/latest/download/appcast.xml` 确认链接有效，再将 `install.sh` 的明确 tag/文件名切到 v1.6.0。

准备期间安装脚本固定指向已公开的 v1.5.1 资产，不使用尚未存在的 v1.6.0 下载链接。候选源码推送、生成本地签名资产与公开发布是不同动作；准备完成不会让正式客户端发现 1.6.0。
