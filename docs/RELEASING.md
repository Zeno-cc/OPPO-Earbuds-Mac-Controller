# 签名更新发布流程

## 一次性建立信任根

需要持久化 Mac、Xcode 26+、Python 3、GitHub CLI。不要在临时容器生成生产私钥。

```bash
bash scripts/setup-updates.sh
```

脚本使用官方 generate_keys，Keychain account 为 `com.aniketbudhwani.budsbar.updates`，只把公钥写入 `Resources/SparklePublicKey.txt`。公钥可以提交；私钥不得提交、粘贴到聊天或上传 Release。维护者应安全备份私钥。脚本不导出私钥，不覆盖不同的已有公钥。

也可通过 `SPARKLE_PUBLIC_ED_KEY` 构建时注入公钥。缺公钥时 Debug 可审阅 UI，但 updater 不启动；Release 打包直接失败。

## 构建、准备与验证

```bash
swift test
swift test -c release
bash build.sh debug
bash scripts/verify-app-bundle.sh
```

build.sh 在临时目录组装 App，保留 Sparkle.framework 符号链接、原嵌套签名和完整许可，清理开发路径、设置 bundle-relative rpath，最后 ad-hoc 签主 App。它不修改 /Applications，不执行 quarantine 清除或提权。

先修改并提交 Info.plist 两个版本字段、`docs/release-notes/X.Y.Z.html`，版本严格递增。以本版为例：

```bash
bash scripts/release.sh 1.5.1
bash scripts/verify-release.sh dist/v1.5.1
```

要求工作区干净且版本一致。生成 DMG、ditto ZIP、最终签名 appcast.xml 和记录源提交/哈希的 manifest.json。签名后不得修改 XML/ZIP。验证包括结构、版本、Bundle ID、最低系统、固定下载 URL、文件长度/哈希、官方 feed 验签及使用 App 内置公钥验证 ZIP。

私钥默认从 Keychain 读取；CI 可通过 SPARKLE_PRIVATE_KEY_FILE 指向受限临时文件。不要把私钥值作为命令行参数。工具与框架都来自同一个 pinned Sparkle artifact。

## Draft 与公开发布

```bash
bash scripts/publish-release.sh 1.5.1
```

只创建/更新 Draft，上传后重新下载并校验字节；不会 Publish、合并、安装或覆盖已公开版本。已有 tag 必须指向构建提交。Draft 匿名下载 URL 404 属正常情况，发布前使用带权限的 GitHub CLI 验证。

审阅后人工 Publish，并标记正式版本为 Latest。固定 feed：
`https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller/releases/latest/download/appcast.xml`

每个成为 Latest 的正式 Release 都必须包含签名 appcast 与 ZIP；只上传 DMG 不够。客户端定时拉取，GitHub/CDN 缓存可能延迟，不承诺发布瞬间送达。

已公开产物不可变，修复需更高版本。当前为单版本全量 feed；未来提高最低系统或改变架构前，先扩展发布器以保留最后兼容版本。首次含 updater 的 v1.5.1 必须人工安装一次。

## 安全与发版门禁

EdDSA 不等于 Apple 公证。应用仍 ad-hoc 签名，Gatekeeper/TCC 可能提示，不保证蓝牙授权永不重置。

必须启用 SURequireSignedFeed、SUVerifyUpdateBeforeExtraction，且 SUSignedFeedFailureExpirationInterval=0，禁止签名失败最终降级放行。

CI 构建/测试/签名正反例通过后，仍须在独立测试用户中完成真实安装与 Relaunch、设置保留和蓝牙回归，并配置正式公钥与有安全备份的私钥。没有生产密钥和这些实机结果，不得将 PR 声称为已经可以公开发布。
