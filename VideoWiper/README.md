# VideoWiper - 一键删除相册所有视频

删之前务必确认备份完整,删除会同步 iCloud,不可撤销。

## 方法 A:有 Mac + Xcode(推荐,5 分钟)

1. Mac 上打开 Xcode > Create New Project > iOS > App,名字填 VideoWiper, Interface 选 SwiftUI。
2. 把本目录下 `VideoWiperApp.swift` 和 `ContentView.swift` 覆盖进项目(替换默认生成的同名文件)。
3. 选中 Target > Info 页,添加两个 key(没有会自动用默认,但最好加上):
   - `Privacy - Photo Library Usage Description` = "需要访问相册以统计和删除视频"
   - `Privacy - Photo Library Additions Usage Description` = "需要访问相册以删除视频"
4. iPhone 用数据线连 Mac,手机上点"信任"。
5. Xcode 顶部设备选你的 iPhone,点 Run(▶)。
   - 用个人 Apple ID 登录即可真机调试: Xcode > Settings > Accounts 添加 Apple ID,Target > Signing 选你的 Team。
6. 手机上打开 VideoWiper:
   1. 点"1. 请求权限并统计视频",选"允许完全访问",确认数量(应该 ~2391 个)。
   2. 点"2. 删除相册里所有视频",过两道确认(弹窗 + 手输"删除"),再在系统弹窗点删除。
7. 去 相册 > 最近删除 > 清空,才真正释放空间。

## 方法 B:没 Mac(Windows/Linux + Sideloadly/AltStore)

在这台 Linux 上装不了 Xcode,无法直接打出 ipa。你需要:
1. 找一台 Mac 或 Windows 电脑,装 Sideloadly 或 AltStore。
2. 在那台电脑上按方法 A 编译,或用 Sideloadly 加载编译产物安装到 iPhone。
3. 免费 Apple ID 签名有效期 7 天,装一次用完删 App 即可,不影响已删的视频。

## 方法 C:不想写代码(零构建,用快捷指令)

其实这个需求不用写 App 也行:
1. iPhone 打开"快捷指令" > 新建 > 添加操作"查找照片"(筛选器:媒体类型=视频) > 添加"删除照片"。
2. 运行前会显示数量让你确认,系统同样会弹确认框。
3. 缺点是不能手输"删除"二次确认,容易误触,本 App 已解决这个问题。

## 原理

- `PHAsset.fetchAssets(with: .video)` 拿到所有视频
- `PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(...) }` 删除
- iOS 会强制弹系统级确认框,App 删不掉"最近删除",必须手动清空
