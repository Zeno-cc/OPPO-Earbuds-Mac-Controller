# OPPO 耳机 Mac 控制器

一款 macOS 菜单栏耳机控制工具，用于在 Mac 上查看耳机电量、切换降噪模式，不必每次都打开手机上的耳机应用。

## 能做什么

- 显示左耳、右耳和充电盒电量。
- 切换降噪、关闭降噪和通透模式。
- 在降噪模式下选择深度、中度、轻度或智能强度。
- 连接或断开耳机。
- 可选开机自动启动。
- 与手机上的耳机设置保持同步：在任意一端切换模式，另一端会自动更新。

如果耳机没有提供左右耳的独立电量，应用会显示系统可取得的合并电量。充电盒合上后可能暂停上报电量，应用会保留本次使用期间最后一次获取到的充电盒电量。

## 已验证的耳机

- OPPO Enco Air5 Pro
- realme Buds T500 Pro

其他真我、OPPO 或一加耳机也可以尝试连接；不同型号支持的功能可能有所不同。

## 安装

[![前往下载](https://img.shields.io/badge/前往-GitHub%20Releases-blue?style=for-the-badge&logo=github)](https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller/releases)

在 Releases 页面下载 `.dmg` 安装包。双击打开后，把应用图标拖到“应用程序”快捷方式即可完成安装。

如果 macOS 阻止打开，请在终端执行：

```bash
xattr -cr "/Applications/OPPO Earbuds Mac Controller.app"
```

## 怎么使用

1. 先在 Mac 的“系统设置 > 蓝牙”中配对耳机。
2. 启动应用，点击菜单栏中的耳机图标。
3. 打开面板右上角的开关，连接耳机。
4. 在面板中查看电量，或点击需要的降噪模式。

点击右上角“更多”按钮，可以打开或关闭“开机自动启动”。

首次启动时，请允许应用访问蓝牙。

## 许可证

[MIT License](LICENSE)
