#!/bin/bash

# 胶囊通知测试脚本
# 通过ADB logcat查看通知是否正常工作

echo "=========================================="
echo "  荣耀胶囊通知测试"
echo "=========================================="
echo ""

# 检查设备连接
echo "1. 检查设备连接..."
if ! adb devices | grep -q "device$"; then
    echo "❌ 未检测到设备，请确保手机已通过ADB连接"
    exit 1
fi
echo "✅ 设备已连接"
echo ""

# 检查应用是否安装
echo "2. 检查应用..."
if ! adb shell pm list packages | grep -q "com.example.smart_hunan_agri"; then
    echo "❌ 应用未安装"
    exit 1
fi
echo "✅ 应用已安装"
echo ""

# 获取设备信息
echo "3. 设备信息："
MANUFACTURER=$(adb shell getprop ro.product.manufacturer)
MODEL=$(adb shell getprop ro.product.model)
SDK=$(adb shell getprop ro.build.version.sdk)
echo "   制造商: $MANUFACTURER"
echo "   型号: $MODEL"
echo "   Android SDK: $SDK"
echo ""

# 检查通知权限
echo "4. 检查通知权限..."
NOTIF_PERM=$(adb shell dumpsys notification | grep -A 1 "com.example.smart_hunan_agri" | grep "allowed=true")
if [ -z "$NOTIF_PERM" ]; then
    echo "⚠️  通知权限可能未授予"
    echo "   请在应用中手动授予通知权限"
else
    echo "✅ 通知权限已授予"
fi
echo ""

# 启动应用
echo "5. 启动应用..."
adb shell am start -n com.example.smart_hunan_agri/.MainActivity > /dev/null 2>&1
sleep 2
echo "✅ 应用已启动"
echo ""

echo "=========================================="
echo "  测试说明"
echo "=========================================="
echo ""
echo "请在手机上进行以下操作："
echo ""
echo "1. 进入【设置】"
echo "2. 找到【通知设置】区域"
echo "3. 点击【胶囊通知】（新增功能）"
echo "4. 启用任意类型（如课程提醒）"
echo "5. 点击【发送测试通知】"
echo "6. 下拉通知栏查看效果"
echo ""
echo "如果你的设备支持灵动岛："
echo "- 屏幕顶部会显示胶囊形式"
echo "- 轻触可查看详情"
echo "- 会有动态进度显示"
echo ""
echo "=========================================="
echo "  实时日志监控"
echo "=========================================="
echo ""
echo "按 Ctrl+C 停止监控"
echo ""

# 开始监控日志
adb logcat -c
adb logcat | grep -i --line-buffered -E "Capsule|UnifiedCapsule|Notification|honor.magic"
