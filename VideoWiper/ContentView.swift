// ContentView.swift
// 功能:统计相册里所有视频,双重确认后一次性删除
// 要求 iOS 15+, Xcode 14+
import SwiftUI
import Photos

struct ContentView: View {
    @State private var authStatus: String = "未请求"
    @State private var videoCount: Int? = nil
    @State private var statusMessage: String = "点下面的按钮开始。"
    @State private var isWorking = false
    @State private var showFirstConfirm = false
    @State private var showSecondConfirm = false
    @State private var confirmText = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("相册视频清理")
                    .font(.largeTitle.bold())

                Text("权限状态: \(authStatus)")
                    .foregroundColor(.secondary)

                if let count = videoCount {
                    Text("检测到视频: \(count) 个")
                        .font(.title2.bold())
                        .foregroundColor(count > 0 ? .red : .green)
                }

                Text(statusMessage)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)

                Button("1. 请求权限并统计视频") {
                    requestAndCount()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)

                Button(role: .destructive) {
                    // 第一重确认入口
                    if videoCount ?? 0 > 0 {
                        showFirstConfirm = true
                    } else {
                        statusMessage = "没有可删的视频,先点上面的统计按钮。"
                    }
                } label: {
                    Text("2. 删除相册里所有视频")
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)

                Text("⚠️ 删除不可撤销,会同步到 iCloud。删完后去 相册 > 最近删除 里再清空一次才真正释放空间。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top)

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            // 第一重确认
            .alert("确定要删除全部视频吗?", isPresented: $showFirstConfirm) {
                Button("取消", role: .cancel) { }
                Button("继续", role: .destructive) {
                    showSecondConfirm = true
                }
            } message: {
                Text("将删除 \(videoCount ?? 0) 个视频。这一步还会触发系统的删除确认框。")
            }
            // 第二重确认:要求手动输入"删除"二字,防止误触
            .alert("最后确认:请输入\"删除\"", isPresented: $showSecondConfirm) {
                TextField("请输入 删除 二字", text: $confirmText)
                Button("取消", role: .cancel) {
                    confirmText = ""
                }
                Button("确认删除全部视频", role: .destructive) {
                    if confirmText == "删除" {
                        deleteAllVideos()
                    } else {
                        statusMessage = "输入不正确,已取消删除。"
                    }
                    confirmText = ""
                }
            } message: {
                Text("这是最后一道防线。输入\"删除\"才会真正执行。")
            }
        }
    }

    // MARK: - 权限 + 统计
    private func requestAndCount() {
        isWorking = true
        statusMessage = "正在请求权限..."
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    authStatus = "已授权(完全访问)"
                case .limited:
                    authStatus = "受限访问(只能删选中的)"
                case .denied, .restricted:
                    authStatus = "被拒绝"
                    statusMessage = "权限被拒绝,请去 设置 > 隐私 > 照片 里给本 App 完全访问权限。"
                    isWorking = false
                    return
                case .notDetermined:
                    authStatus = "未决定"
                @unknown default:
                    authStatus = "未知"
                }
                countVideos()
            }
        }
    }

    private func countVideos() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.includeHiddenAssets = false
        let videos = PHAsset.fetchAssets(with: .video, options: fetchOptions)
        videoCount = videos.countOfAssets(with: .video)
        if videos.count == 0 {
            statusMessage = "相册里没有视频,无需删除。"
        } else {
            statusMessage = "已找到 \(videos.count) 个视频。确认备份无误后再点删除。"
        }
        isWorking = false
    }

    // MARK: - 删除
    private func deleteAllVideos() {
        isWorking = true
        statusMessage = "正在删除,请在系统弹窗里点删除..."
        let videos = PHAsset.fetchAssets(with: .video, options: nil)
        guard videos.count > 0 else {
            statusMessage = "没有视频可删。"
            isWorking = false
            return
        }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(videos as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                isWorking = false
                if success {
                    statusMessage = "✅ 删除请求成功。\(videos.count) 个视频已移到\"最近删除\"。去 相册 > 最近删除 > 清空 才能释放空间。"
                    // 重新统计
                    countVideos()
                } else {
                    statusMessage = "❌ 删除失败: \(error?.localizedDescription ?? "未知错误,可能点了取消")"
                }
            }
        }
    }
}
