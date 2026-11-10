# iPhone-backup

两个小工具:

- `backup_iphone_usb.sh`:Linux 上用数据线把 iPhone 照片备份到本地(依赖 libimobiledevice / ifuse,失败回退 gphoto2)。
- `VideoWiper/`:iOS App,统计相册里所有视频,双重确认后一次性删除(删完记得去 相册 > 最近删除 > 清空)。

⚠️ 删除不可撤销,会同步 iCloud。先确认备份完整再删。

## 云构建 IPA(不需要自备 Mac)

每次 push 后 GitHub Actions 自动在 macOS runner 上构建,把未签名 IPA 传到 Actions Artifacts:

1. 去仓库页面点 Actions > Build IPA > 最新一次运行。
2. 下载 `VideoWiper-unsigned-ipa`,解压得到 `VideoWiper-unsigned.ipa`。
3. 在本地用免费 Apple ID 侧载(7 天有效期,装完用完即删):
   - Fedora/ Linux:用 `iloader` 装 SideStore,再把 IPA 分享到 SideStore 安装(需 `usbmuxd`,手机上装 LocalDevVPN)。
   - Windows / macOS:用 Sideloadly 直接装。
4. 手机上打开 VideoWiper:先"请求权限并统计视频"(选完全访问),确认数量无误,再"删除相册里所有视频"(弹窗 + 手输"删除"两道确认,另有系统确认框)。

原理:CI 里 `xcodegen generate` 生成工程,`xcodebuild` 以 `CODE_SIGNING_ALLOWED=NO` 编译,`Payload/*.app` 打包成 IPA,签名由本地侧载工具用个人 Apple ID 完成。
