# UI 优化更新日志

## 2026-10-21 - 自定义背景适配与课程表视图优化

### 1. 设置页面自定义背景适配优化

**问题描述：**
- 使用自定义背景图片时，设置页面的文字与背景发生撞色，导致可读性差
- 缺少视觉层次，内容与背景混在一起

**解决方案：**
- 为设置页面内容添加半透明背景容器（85% 不透明度）
- 应用毛玻璃效果（BackdropFilter）增强视觉分层
- 添加圆角边框（20px 圆角）和阴影效果
- 添加半透明边框提升层次感
- 仅在启用自定义背景时应用，无背景时保持原样式

**修改文件：**
- `lib/pages/settings_page.dart`

**技术细节：**
```dart
// 当有自定义背景时，内容被包裹在半透明容器中
Container(
  margin: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: surface.withValues(alpha: 0.85),  // 85% 不透明度
    borderRadius: BorderRadius.circular(20),
    border: Border.all(...),
    boxShadow: [...],
  ),
  child: ClipRRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),  // 毛玻璃效果
      child: ListView(...),
    ),
  ),
)
```

### 2. 课程表视图切换方式优化

**问题描述：**
- 原有的大胶囊切换按钮（周视图/日视图）占用屏幕空间过大
- 影响课程表内容的显示区域

**解决方案：**
- 移除顶部的大胶囊 SegmentedButton
- 在 AppBar 右侧添加紧凑的图标切换按钮
- 点击图标即可在周视图和日视图之间切换
- 图标会根据当前视图动态变化：
  - 周视图时显示日视图图标（view_agenda_outlined）
  - 日视图时显示周视图图标（calendar_view_week_outlined）
- 添加 tooltip 提示当前操作

**修改文件：**
- `lib/pages/timetable_page.dart`

**技术细节：**
```dart
// AppBar 中添加切换按钮
actions: [
  if (hasTimetable)
    IconButton(
      tooltip: _dailyView ? '切换到周视图' : '切换到日视图',
      icon: Icon(
        _dailyView
          ? Icons.calendar_view_week_outlined
          : Icons.view_agenda_outlined,
      ),
      onPressed: () => setState(() => _dailyView = !_dailyView),
    ),
  // ... 其他按钮
]

// 移除了原来的 SegmentedButton 组件
```

### 优化效果

**设置页面：**
- ✅ 文字在任何背景上都清晰可读
- ✅ 内容与背景有明确的视觉层次
- ✅ 毛玻璃效果提升视觉美感
- ✅ 无自定义背景时保持原有简洁样式

**课程表页面：**
- ✅ 节省约 60-80px 的垂直空间
- ✅ 切换操作更便捷（AppBar 右上角触手可及）
- ✅ 视图切换图标更直观
- ✅ 界面更加简洁

### 测试状态

- ✅ Flutter analyze 通过
- ✅ Debug APK 构建成功
- ✅ 无语法错误
- ✅ 与现有功能兼容

### 截图对比

请参考 `img_debug` 目录下的微信图片：
- 微信图片_20261021214009_71_76.jpg - 设置页面优化前
- 微信图片_20261021214010_72_76.jpg - 课程表周视图优化前
- 微信图片_20261021214011_73_76.jpg - 课程表日视图优化前

### 后续建议

如果需要进一步优化，可以考虑：
1. 为其他页面（如通知、作业等）也添加类似的背景适配
2. 提供自定义背景亮度调节选项
3. 自动检测背景亮度，动态调整文字颜色
4. 为卡片组件添加半透明背景选项
