# SwiftMumble

SwiftMumble 是一个面向 Apple Silicon Mac 的原生 Mumble 客户端。应用使用 SwiftUI、
AppKit、Network.framework 和 AVFAudio 构建，支持连接标准 Mumble/Murmur 服务器，
并针对 macOS 的窗口、菜单、快捷键、Touch Bar 和输入法体验进行了原生适配。

## 主要功能

- 原生 Apple Silicon `arm64` 应用，最低支持 macOS 14
- Mumble TLS 控制连接、加密 UDP 语音和 TCP tunnel 回退
- 服务器收藏、频道树、频道切换、返回上一频道和文字聊天
- 按键说话、语音活动检测和持续发送模式
- 可视化麦克风电平、VAD 阈值与噪声底自动校准
- Opus 编解码、抖动缓冲、RNNoise 降噪、AGC 和基础回声消除
- 用户独立音量、本地静音、主输出音量和发言时自动压低其他声音
- 私聊、富文本消息、系统通知和文字转语音
- 全局及服务器独立快捷键
- Touch Bar 发言、静音、禁听和当前讲话人控制
- 客户端证书身份、服务器密码及访问令牌的 Keychain 存储
- 英文、简体中文、繁体中文和日文界面
- macOS 26 Liquid Glass 效果，并为较旧系统提供原生材质回退

## 环境要求

- Apple Silicon Mac
- macOS 14 或更高版本
- Xcode 26 或兼容 Swift 6.1 的 Xcode 工具链
- 构建 Icon Composer 图标时需要 Xcode 26 的 `actool`

## 构建与测试

```bash
git clone https://github.com/lemonno2333/SwiftMumble.git
cd SwiftMumble
swift test
swift build
```

运行 SwiftPM 可执行目标：

```bash
swift run SwiftMumble
```

生成签名的调试 `.app`：

```bash
./scripts/package-app.sh
open .build/debug/SwiftMumble.app
```

打包脚本会自动查找本机的 Apple Development 签名身份；也可以显式指定：

```bash
SWIFTMUMBLE_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" \
  ./scripts/package-app.sh
```

没有可用签名身份时会使用 ad-hoc 签名。频繁重建 ad-hoc 签名的应用可能导致 macOS
再次询问客户端证书私钥访问权限。

## 项目结构

```text
AppBundle/                  应用 Info.plist、entitlements、本地化权限说明和图标
Sources/SwiftMumbleApp/     SwiftUI/AppKit 应用界面与会话状态
Sources/MumbleProtocol/     Mumble 协议、TLS、UDP、加密和消息模型
Sources/MumbleAudio/        音频采集、Opus、抖动缓冲、混音和音频处理
Sources/MumbleSystem/       Keychain、客户端身份和全局快捷键
Sources/MumbleProbe/        不启用麦克风的协议与音频探测工具
Tests/                      协议、音频和系统单元测试
Vendor/                     固定版本的 Opus 与 RNNoise arm64 XCFramework
scripts/                    依赖生成、应用打包和发布脚本
```

## 图标

应用图标源文件位于 `AppBundle/mumble.icon`，由 Apple Icon Composer 创建。打包时
通过 `actool` 编译为现代 `Assets.car` 和兼容用 `mumble.icns`。

## 隐私

SwiftMumble 仅在需要发言、语音活动检测或本地麦克风测试时申请麦克风权限。服务器
密码、访问令牌和客户端私钥保存在 macOS Keychain 中。

## 第三方组件

- [Opus](https://opus-codec.org/)：音频编解码
- [RNNoise](https://gitlab.xiph.org/xiph/rnnoise)：可选的麦克风降噪
- [SwiftProtobuf](https://github.com/apple/swift-protobuf)：Mumble Protobuf 消息

Opus 与 RNNoise 的许可证文件分别保存在 `Vendor/Opus/COPYING` 和
`Vendor/RNNoise/COPYING`。
