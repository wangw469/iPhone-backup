#!/usr/bin/env bash
# iPhone USB 照片备份到 /data/photos
# 适用: Linux + iPhone 数据线直连
# 依赖: libimobiledevice-utils, ifuse, rsync (失败自动回退到 gphoto2)
set -euo pipefail

DEST="${DEST:-/data/photos}"
MOUNT="${MOUNT:-/tmp/iphone-mnt}"
LOG="${LOG:-/tmp/iphone-backup-$(date +%Y%m%d-%H%M%S).log}"

info() { echo "[INFO] $*" | tee -a "$LOG"; }
err() { echo "[ERROR] $*" | tee -a "$LOG" >&2; }

need_root_for_apt=0
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    SUDO=""
    need_root_for_apt=1
  fi
else
  SUDO=""
fi

info "目标目录: $DEST"
info "挂载点: $MOUNT"

# 1. 建目录 + 修归属
if [ ! -d "$DEST" ]; then
  info "创建 $DEST"
  if [ -n "${SUDO:-}" ]; then
    $SUDO mkdir -p "$DEST"
  else
    mkdir -p "$DEST" || { err "建不了 $DEST, 需要 root/sudo"; exit 1; }
  fi
fi
# DEST 可能是之前 sudo 建的 root:root，非 root 写不进去 -> 就是你这次
# mkdir/mkstemp Permission denied + chgrp Operation not permitted 的原因
if [ ! -w "$DEST" ]; then
  info "修复 $DEST 归属为 $(id -u):$(id -g)"
  if [ -n "${SUDO:-}" ]; then
    $SUDO chown -R "$(id -u):$(id -g)" "$DEST"
  else
    err "$DEST 不可写且无 sudo，请手动执行: chown -R $(id -u):$(id -g) $DEST"
    ls -ld "$DEST" | tee -a "$LOG"
    exit 1
  fi
fi
touch "$DEST/.write-test" && rm -f "$DEST/.write-test" || { err "$DEST 仍不可写: $(ls -ld "$DEST")"; exit 1; }

# 2. 检查依赖
missing=()
for cmd in idevicepair ifuse rsync; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done

if [ "${#missing[@]}" -gt 0 ]; then
  info "缺依赖: ${missing[*]}, 尝试安装..."
  if command -v apt-get >/dev/null 2>&1; then
    ${SUDO:-} apt-get update && ${SUDO:-} apt-get install -y libimobiledevice-utils ifuse rsync gphoto2 fuse3
  elif command -v dnf >/dev/null 2>&1; then
    ${SUDO:-} dnf install -y libimobiledevice-utils ifuse rsync gphoto2 fuse
  elif command -v pacman >/dev/null 2>&1; then
    ${SUDO:-} pacman -Sy --noconfirm libimobiledevice ifuse rsync gphoto2
  else
    err "装不了依赖，请手动安装: libimobiledevice-utils ifuse rsync gphoto2"
    exit 1
  fi
fi

# 3. 检查 USB 是否认到 iPhone
info "检查 USB 设备..."
if command -v lsusb >/dev/null 2>&1; then
  lsusb | grep -i "apple" | tee -a "$LOG" || info "lsusb 没看到 Apple 设备，换线/换口再试 (仍可继续试配对)"
fi
idevice_id -l | tee -a "$LOG" || true

# 4. 配对 (iPhone 上点“信任”)
info "配对 iPhone (手机上必须点 信任，输入锁屏密码)..."
idevicepair pair | tee -a "$LOG"
idevicepair validate | tee -a "$LOG" || { err "配对验证失败，重拔插重试"; exit 1; }

cleanup() {
  if mountpoint -q "$MOUNT" 2>/dev/null; then
    info "卸载 $MOUNT"
    fusermount3 -u "$MOUNT" 2>/dev/null || fusermount -u "$MOUNT" 2>/dev/null || ${SUDO:-} umount "$MOUNT" || true
  fi
}
trap cleanup EXIT

# 注意: 残留的 stale ifuse 挂载会导致 mkdir/stat 报 Input/output error
# 所以必须先卸载，再 mkdir
if mountpoint -q "$MOUNT" 2>/dev/null; then
  info "$MOUNT 已挂载，先卸载"
  fusermount3 -u "$MOUNT" 2>/dev/null || fusermount -u "$MOUNT" 2>/dev/null || ${SUDO:-} umount "$MOUNT" || true
else
  # stale FUSE 但 mountpoint 检测失败时也尝试强卸一次 (EIO 情况)
  fusermount3 -u "$MOUNT" 2>/dev/null || fusermount -u "$MOUNT" 2>/dev/null || true
fi

mkdir -p "$MOUNT"
# ifuse 必须由当前用户挂载，挂载点属主不对会挂载失败
if [ "$(id -u)" -ne 0 ] && [ ! -w "$MOUNT" ]; then
  ${SUDO:-} chown -R "$(id -u):$(id -g)" "$MOUNT" || true
fi

# 5. 挂载，优先 ifuse
MOUNT_OK=0
info "尝试 ifuse 挂载..."
if ifuse "$MOUNT" 2>&1 | tee -a "$LOG"; then
  sleep 1
  if mountpoint -q "$MOUNT" 2>/dev/null; then
    MOUNT_OK=1
    info "挂载成功"
    ls "$MOUNT" | tee -a "$LOG"
    ls "$MOUNT/DCIM" 2>&1 | head -20 | tee -a "$LOG" || true
  fi
fi

if [ "$MOUNT_OK" -eq 1 ]; then
  SRC="$MOUNT/DCIM"
  if [ ! -d "$SRC" ]; then
    # 有些 iOS 版本目录结构不同，找一下
    info "没找到 DCIM，实际内容:"
    find "$MOUNT" -maxdepth 3 -type d | tee -a "$LOG"
    # 尝试 PhotoData 或直接全量 rsync
    if [ -d "$MOUNT/PhotoData" ]; then
      SRC="$MOUNT/PhotoData"
    else
      SRC="$MOUNT"
    fi
  fi
  info "从 $SRC 同步到 $DEST (增量，跳过已存在)..."
  # --ignore-existing: 已存在的不覆盖，保证增量; -a 保留时间戳
  # 非 root 用 -a 会尝试 chgrp/chown 报 Operation not permitted，加 --no-o --no-g 避开
  if [ "$(id -u)" -eq 0 ]; then
    rsync -avh --progress --ignore-existing "$SRC/" "$DEST/" | tee -a "$LOG"
  else
    rsync -avh --no-o --no-g --progress --ignore-existing "$SRC/" "$DEST/" | tee -a "$LOG"
  fi
  info "完成。统计:"
  find "$DEST" -type f | wc -l | tee -a "$LOG"
  du -sh "$DEST" | tee -a "$LOG"
  exit 0
fi

# 6. 回退: gphoto2
err "ifuse 挂载失败，回退到 gphoto2 ..."
info "gphoto2 --auto-detect:"
gphoto2 --auto-detect | tee -a "$LOG" || true
info "开始下载全部照片到 $DEST ..."
# --get-all-files 会把 DCIM 全拉下来，已存在的不重复占空间由 gphoto2 跳过提示处理
cd "$DEST"
gphoto2 --get-all-files --skip-existing 2>&1 | tee -a "$LOG"
info "gphoto2 完成。统计:"
find "$DEST" -type f | wc -l | tee -a "$LOG"
du -sh "$DEST" | tee -a "$LOG"
