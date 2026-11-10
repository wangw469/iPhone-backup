// ContentView.swift
// 功能:
//  1. 统计相册里所有视频,双重确认后一次性删除
//  2. 删除个人收藏以外的所有照片(保留标了 ❤️ 的),双重确认后执行
// 要求 iOS 15+, Xcode 14+
import SwiftUI
import Photos

/// 删除目标:视频 / 非收藏照片,两类删除共用两道确认框
private enum DeleteTarget {
    case videos
    case unFavoritedPhotos
}

struct ContentView: View {
    @State private var authStatus: String = "未请求"
    @State private var videoCount: Int? = nil
    @State private var totalPhotoCount: Int? = nil
    @State private var favPhotoCount: Int? = nil
    @State private var deletablePhotoCount: Int? = nil
    @State private var statusMessage: String = "点下面的按钮开始。"
    @State private var isWorking = false
    @State private var pendingTarget: DeleteTarget? = nil
    @State private var showFirstConfirm = false
    @State private var showSecondConfirm = false
    @State private var confirmText = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Text("相册清理")
                        .font(.largeTitle.bold())

                    Text("权限状态: \(authStatus)")
                        .foregroundColor(.secondary)

                    if let count = videoCount {
                        Text("视频: \(count) 个")
                            .font(.title3.bold())
                            .foregroundColor(count > 0 ? .red : .green)
                    }

                    if let total = totalPhotoCount,
                       let fav = favPhotoCount,
                       let del = deletablePhotoCount {
                        Text("照片共 \(total) 张,其中个人收藏 \(fav) 张,可删除 \(del) 张")
                            .font(.title3.bold())
                            .foregroundColor(del > 0 ? .red : .green)
                            .multilineTextAlignment(.center)
                    }

                    Text(statusMessage)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)

                    Button("1. 请求权限并统计") {
                        requestAndCount()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)

                    Button(role: .destructive) {
                        if videoCount ?? 0 > 0 {
                            pendingTarget = .videos
                            showFirstConfirm = true
                        } else {
                            statusMessage = "没有可删的视频,先点上面的统计按钮。"
                        }
                    } label: {
                        Text("2. 删除相册里所有视频")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)

                    Button(role: .destructive) {
                        if deletablePhotoCount ?? 0 > 0 {
                            pendingTarget = .unFavoritedPhotos
                            showFirstConfirm = true
                        } else {
                            statusMessage = "没有可删的照片(可能全是收藏,或先点统计按钮)。"
                        }
                    } label: {
                        Text("3. 删除个人收藏以外的所有照片")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)

                    Text("⚠️ 删除不可撤销,会同步到 iCloud。照片删除只保留标了 ❤️ 个人收藏 的,其余全删。删完后去 相册 > 最近删除 里再清空一次才真正释放空间。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            // 第一重确认
            .alert(firstConfirmTitle, isPresented: $showFirstConfirm) {
                Button("取消", role: .cancel) {
                    pendingTarget = nil
                }
                Button("继续", role: .destructive) {
                    showSecondConfirm = true
                }
            } message: {
                Text(firstConfirmMessage)
            }
            // 第二重确认:要求手动输入"删除"二字,防止误触
            .alert("最后确认:请输入\"删除\"", isPresented: $showSecondConfirm) {
                TextField("请输入 删除 二字", text: $confirmText)
                Button("取消", role: .cancel) {
                    confirmText = ""
                    pendingTarget = nil
                }
                Button("确认删除", role: .destructive) {
                    if confirmText == "删除", let target = pendingTarget {
                        switch target {
                        case .videos:
                            deleteAllVideos()
                        case .unFavoritedPhotos:
                            deleteUnfavoritedPhotos()
                        }
                    } else {
                        statusMessage = "输入不正确,已取消删除。"
                    }
                    confirmText = ""
                    pendingTarget = nil
                }
            } message: {
                Text("这是最后一道防线。输入\"删除\"才会真正执行,之后系统还会再弹一次确认框。")
            }
        }
    }

    // MARK: - 确认框文案
    private var firstConfirmTitle: String {
        switch pendingTarget {
        case .videos:
            return "确定要删除全部视频吗?"
        case .unFavoritedPhotos:
            return "确定删除非收藏的全部照片吗?"
        case nil:
            return "确定吗?"
        }
    }

    private var firstConfirmMessage: String {
        switch pendingTarget {
        case .videos:
            return "将删除 \(videoCount ?? 0) 个视频。这一步还会触发系统的删除确认框。"
        case .unFavoritedPhotos:
            return "将删除 \(deletablePhotoCount ?? 0) 张照片,保留 \(favPhotoCount ?? 0) 张个人收藏。这一步还会触发系统的删除确认框。"
        case nil:
            return ""
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
                countAll()
            }
        }
    }

    private func countAll() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.includeHiddenAssets = false
        let videos = PHAsset.fetchAssets(with: .video, options: fetchOptions)
        videoCount = videos.count

        let photos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        var fav = 0
        photos.enumerateObjects { asset, _, _ in
            if asset.isFavorite {
                fav += 1
            }
        }
        totalPhotoCount = photos.count
        favPhotoCount = fav
        deletablePhotoCount = photos.count - fav

        if videos.count == 0 && photos.count == 0 {
            statusMessage = "相册里没有视频和照片,无需删除。"
        } else {
            statusMessage = "已找到 \(videos.count) 个视频、\(photos.count) 张照片(收藏 \(fav) 张)。确认备份无误后再点删除。"
        }
        isWorking = false
    }

    // MARK: - 删除视频
    private func deleteAllVideos() {
        isWorking = true
        statusMessage = "正在删除视频,请在系统弹窗里点删除..."
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
                    countAll()
                } else {
                    statusMessage = "❌ 删除失败: \(error?.localizedDescription ?? "未知错误,可能点了取消")"
                }
            }
        }
    }

    // MARK: - 删除非收藏照片(保留个人收藏)
    private func deleteUnfavoritedPhotos() {
        isWorking = true
        statusMessage = "正在收集非收藏照片..."
        let photos = PHAsset.fetchAssets(with: .image, options: nil)
        var toDelete: [PHAsset] = []
        var fav = 0
        photos.enumerateObjects { asset, _, _ in
            if asset.isFavorite {
                fav += 1
            } else {
                toDelete.append(asset)
            }
        }
        guard !toDelete.isEmpty else {
            statusMessage = "没有可删的照片(\(fav) 张全是个人收藏)。"
            isWorking = false
            return
        }
        statusMessage = "正在删除 \(toDelete.count) 张照片,请在系统弹窗里点删除..."
        let assetsToDelete = toDelete as NSArray
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assetsToDelete)
        }) { success, error in
            DispatchQueue.main.async {
                isWorking = false
                if success {
                    statusMessage = "✅ 删除请求成功。\(toDelete.count) 张照片已移到\"最近删除\",保留了 \(fav) 张个人收藏。去 相册 > 最近删除 > 清空 才能释放空间。"
                    countAll()
                } else {
                    statusMessage = "❌ 删除失败: \(error?.localizedDescription ?? "未知错误,可能点了取消")"
                }
            }
        }
    }
}
