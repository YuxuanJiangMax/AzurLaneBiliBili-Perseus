#!/bin/bash

# 定义关键路径和参数
APK_FILE="blhx_9.5.11_0427_1_20250506_095207_d4e3f.apk"  # 仓库中的 APK 文件名
DECOMPILED_DIR="decompiled_azurlane"  # 反编译后的目录名

# 1. 下载依赖工具（apkeep 和 apktool）
get_artifact_download_url() {
    curl -s "https://api.github.com/repos/$1/releases/latest" | jq -r '.assets[] | select(.name | contains("'"$2"'")).browser_download_url'
}

# 定义 Apktool 2.11.1 的下载链接（确保版本兼容性）
APKTOOL_URL="https://github.com/iBotPeaches/Apktool/releases/download/v2.11.1/apktool_2.11.1.jar"

artifacts=(
    "apkeep:EFForg/apkeep:apkeep-x86_64-unknown-linux-gnu"
    "apktool.jar::$APKTOOL_URL"  # 直接指定 Apktool 2.11.1 的链接
)

for entry in "${artifacts[@]}"; do
    IFS=':' read -r name repo pattern <<< "$entry"
    if [ ! -f "$name" ]; then
        echo "下载工具: $name"
        if [[ "$name" == "apktool.jar" ]]; then
            wget -O "$name" "$APKTOOL_URL"
        else
            url=$(get_artifact_download_url "$repo" "$pattern")
            wget -O "$name" "$url"
        fi
        chmod +x "$name"
    fi
done

# 2. 检查本地 APK 文件是否存在
echo "=== 检查本地 APK 文件 ==="
if [ ! -f "$APK_FILE" ]; then
    echo "❌ 错误：未找到 APK 文件！请确认仓库根目录存在 $APK_FILE"
    exit 1
elif ! unzip -tq "$APK_FILE"; then
    echo "❌ 错误：APK 文件已损坏！请重新上传。"
    exit 1
else
    echo "✅ APK 文件验证通过！"
fi

# 3. 反编译 APK（使用 Apktool 2.11.1）
echo "=== 开始反编译 ==="
java -jar apktool.jar d -f "$APK_FILE" -o "$DECOMPILED_DIR" || {
    echo "❌ 反编译失败！可能原因："
    echo "1. APK 文件加密或结构特殊"
    echo "2. Apktool 版本不兼容（当前版本：2.11.1）"
    exit 1
}

# 4. 注入 Perseus
if [ ! -d "Perseus" ]; then
    git clone https://github.com/Egoistically/Perseus
fi
cp -r Perseus/. "$DECOMPILED_DIR/lib/"

# 5. 动态查找并修改 smali 代码
UNITY_ACTIVITY=$(find "$DECOMPILED_DIR" -name "UnityPlayerActivity.smali" | head -1)
if [ -z "$UNITY_ACTIVITY" ]; then
    echo "❌ 错误：未找到 UnityPlayerActivity.smali！"
    exit 1
fi

# 注入 Perseus 初始化代码
sed -i "1i\\# Perseus Injection" "$UNITY_ACTIVITY"
sed -i "/onCreate/a \\
    const-string v0, \"Perseus\"\n\\
    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V\n\\
    invoke-static {p0}, Lcom/unity3d/player/UnityPlayerActivity;->init(Landroid/content/Context;)V" "$UNITY_ACTIVITY"

# 6. 重新构建 APK
echo "=== 构建修改后的 APK ==="
java -jar apktool.jar b "$DECOMPILED_DIR" -o "build/${APK_FILE%.apk}.patched.apk" || {
    echo "❌ 构建失败！可能原因："
    echo "1. smali 代码语法错误"
    echo "2. 资源文件缺失"
    exit 1
}

# 7. 自动提取版本号（从 APK 元数据）
VERSION=$(./apkeep -a com.bilibili.AzurLane -l | grep -oP 'versionName=\K[^ ]+')
echo "PERSEUS_VERSION=$VERSION" >> $GITHUB_ENV

echo "✅ 构建完成！输出文件：build/${APK_FILE%.apk}.patched.apk"