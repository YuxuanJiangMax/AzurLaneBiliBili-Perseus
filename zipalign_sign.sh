#!/bin/bash
set -e  # 任何命令失败立即终止脚本

# 定义路径和文件名
INPUT_APK="build/com.bilibili.AzurLane.patched.apk"  # 与 patch_perseus.sh 的输出一致
ALIGNED_APK="build/com.bilibili.AzurLane.aligned.apk"
SIGNED_APK="build/com.bilibili.AzurLane.signed.apk"

# ---------------------------
# 1. 检查输入文件是否存在
# ---------------------------
if [ ! -f "$INPUT_APK" ]; then
    echo "❌ 错误：未找到 APK 文件！路径：$INPUT_APK"
    exit 1
fi

# ---------------------------
# 2. 执行 Zipalign 对齐
# ---------------------------
echo "=== 开始 Zipalign 对齐 ==="
zipalign -v -p 4 "$INPUT_APK" "$ALIGNED_APK" || {
    echo "❌ Zipalign 失败！"
    exit 1
}

# ---------------------------
# 3. 执行 APK 签名
# ---------------------------
echo "=== 开始 APK 签名 ==="
apksigner sign \
  --ks your-keystore.jks \                  # 替换为你的密钥库文件名
  --ks-pass pass:"$KEYSTORE_PASSWORD" \     # 从环境变量读取密码
  --out "$SIGNED_APK" \
  "$ALIGNED_APK" || {
    echo "❌ 签名失败！"
    exit 1
}

# ---------------------------
# 4. 清理中间文件（可选）
# ---------------------------
rm "$ALIGNED_APK"

echo "✅ 签名完成！输出文件：$SIGNED_APK"