#!/bin/bash

# 0. 定义 APK 文件名（全局变量）
APK_FILE="blhx_9.5.11_0427_1_20250506_095207_d4e3f.apk"
DECOMPILED_DIR="decompiled_azurlane"  # 反编译后的目录名

# 1. 下载依赖工具（apkeep 和 apktool）
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

# 2. 检查本地 APK 文件是否存在
if [ ! -f "$APK_FILE" ]; then
    echo "❌ 错误：未找到 APK 文件！请确认仓库根目录存在 $APK_FILE"
    exit 1
fi

# 3. 反编译 APK
echo "=== 开始反编译 ==="
java -jar apktool.jar d "$APK_FILE" -o "$DECOMPILED_DIR" || {
    echo "❌ 反编译失败！请检查 APK 文件是否完整。"
    exit 1
}

# 4. 复制 apktool.yml 到反编译目录（必须提前创建此文件！）
cp apktool.yml "$DECOMPILED_DIR/"

# 5. 注入 Perseus
if [ ! -d "Perseus" ]; then
    git clone https://github.com/Egoistically/Perseus
fi
cp -r Perseus/. "$DECOMPILED_DIR/lib/"

# 6. 动态查找 UnityPlayerActivity.smali
UNITY_ACTIVITY=$(find "$DECOMPILED_DIR" -name "UnityPlayerActivity.smali" | head -1)
if [ -z "$UNITY_ACTIVITY" ]; then
    echo "❌ 错误：未找到 UnityPlayerActivity.smali！"
    exit 1
fi

# 7. 修改 smali 代码（核心注入）
sed -i "1i\\# Perseus Injection" "$UNITY_ACTIVITY"

# 8. 重新构建 APK
echo "=== 开始构建修改后的 APK ==="
java -jar apktool.jar b "$DECOMPILED_DIR" -o "build/${APK_FILE%.apk}.patched.apk" || {
    echo "❌ 构建失败！检查反编译目录是否存在错误。"
    exit 1
}

# 9. 设置版本号（简化版，直接使用日期）
echo "PERSEUS_VERSION=$(date +%Y%m%d)" >> $GITHUB_ENV