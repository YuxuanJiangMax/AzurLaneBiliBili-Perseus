#!/bin/bash

# 定义关键路径和参数
MEGA_LINK="https://mega.nz/file/W9ZnAQRB#_GQjD82cL8H4PFpyPP-D8aMAQuWnZvBeH2jEbCafKS0"  # 替换为你的 Mega 直链
APK_FILE="blhx_9.5.11_0427_1_20250506_095207_d4e3f.apk"  # APK 文件名（与 Mega 文件一致）
DECOMPILED_DIR="decompiled_azurlane"  # 反编译后的目录名

# 1. 安装 megatools（仅限 GitHub Actions）
if [ -n "$GITHUB_ACTIONS" ]; then
    echo "=== 在 GitHub Actions 中安装 megatools ==="
    sudo apt-get update
    sudo apt-get install -y megatools
fi

# 2. 下载依赖工具（apkeep 和 apktool）
get_artifact_download_url() {
    curl -s "https://api.github.com/repos/$1/releases/latest" | jq -r '.assets[] | select(.name | contains("'"$2"'")).browser_download_url'
}

artifacts=(
    "apkeep:EFForg/apkeep:apkeep-x86_64-unknown-linux-gnu"
    "apktool.jar:iBotPeaches/Apktool:apktool"
)

for entry in "${artifacts[@]}"; do
    IFS=':' read -r name repo pattern <<< "$entry"
    if [ ! -f "$name" ]; then
        echo "下载工具: $name"
        url=$(get_artifact_download_url "$repo" "$pattern")
        wget -O "$name" "$url"
    fi
done
chmod +x apkeep apktool.jar

# 3. 从 Mega 下载 APK（含重试机制）
echo "=== 从 Mega 下载 APK ==="
MAX_RETRIES=3
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "尝试下载（第 $((RETRY_COUNT+1)) 次）"
    megatools dl "$MEGA_LINK" --path ./ --no-progress -o "$APK_FILE"
    
    if [ $? -eq 0 ] && [ -f "$APK_FILE" ]; then
        echo "✅ APK 下载成功！"
        break
    else
        echo "❌ 下载失败，正在重试..."
        RETRY_COUNT=$((RETRY_COUNT+1))
        sleep 10
    fi
done

# 检查文件完整性
if [ ! -f "$APK_FILE" ]; then
    echo "❌ 错误：APK 文件未下载成功！"
    exit 1
elif ! unzip -tq "$APK_FILE"; then
    echo "❌ 错误：APK 文件已损坏！请检查 Mega 链接。"
    exit 1
fi

# 4. 反编译 APK
echo "=== 开始反编译 ==="
java -jar apktool.jar d -f "$APK_FILE" -o "$DECOMPILED_DIR" || {
    echo "❌ 反编译失败！可能原因："
    echo "1. APK 文件不兼容当前 Apktool 版本"
    echo "2. APK 加密或已被修改"
    exit 1
}

# 5. 注入 Perseus
if [ ! -d "Perseus" ]; then
    git clone https://github.com/Egoistically/Perseus
fi
cp -r Perseus/. "$DECOMPILED_DIR/lib/"

# 6. 动态查找并修改 smali 代码
UNITY_ACTIVITY=$(find "$DECOMPILED_DIR" -name "UnityPlayerActivity.smali" | head -1)
if [ -z "$UNITY_ACTIVITY" ]; then
    echo "❌ 错误：未找到 UnityPlayerActivity.smali！"
    exit 1
fi

sed -i "1i\\# Perseus Injection" "$UNITY_ACTIVITY"

# 7. 重新构建 APK
echo "=== 构建修改后的 APK ==="
java -jar apktool.jar b "$DECOMPILED_DIR" -o "build/${APK_FILE%.apk}.patched.apk" || {
    echo "❌ 构建失败！检查反编译目录。"
    exit 1
}

# 8. 生成版本号（示例）
echo "PERSEUS_VERSION=$(date +%Y%m%d)" >> $GITHUB_ENV