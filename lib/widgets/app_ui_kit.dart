import 'package:flutter/material.dart';
import 'app_motion.dart';

/// ---------------------------------------------------------------------------
/// 设计系统 Tokens (参考 TDesign 4/8px 阶梯规范 & Forui 极简现代美学)
/// ---------------------------------------------------------------------------

class AppSpacing {
  const AppSpacing._();
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
}

class AppRadius {
  const AppRadius._();
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double full = 999.0;

  static const BorderRadius roundedXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius roundedSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius roundedMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius roundedLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius roundedXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius roundedFull = BorderRadius.all(Radius.circular(full));
}

/// ---------------------------------------------------------------------------
/// AppCard: 现代极简卡片 (参考 Forui FCard 与 TDesign TDCard)
/// 去除厚重 AI 味毛玻璃，采用极细 1px 微妙边框与克制浅层投影
/// ---------------------------------------------------------------------------

enum AppCardVariant {
  /// 细描边扁平风格 (Forui 经典风格)
  outlined,
  /// 浅色填充微投影风格 (TDesign 经典卡片)
  elevated,
  /// 纯填充风格 (Secondary / Tonal)
  filled,
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.variant = AppCardVariant.outlined,
    this.onTap,
    this.borderRadius,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final AppCardVariant variant;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? AppRadius.roundedLg;

    Color bg;
    Border? border;
    List<BoxShadow>? shadows;

    switch (variant) {
      case AppCardVariant.outlined:
        bg = color ?? (isDark ? colors.surfaceContainerLow : colors.surface);
        border = Border.all(
          color: borderColor ?? colors.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.7),
          width: 1.0,
        );
        shadows = isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ];
        break;
      case AppCardVariant.elevated:
        bg = color ?? (isDark ? colors.surfaceContainer : colors.surface);
        border = Border.all(
          color: borderColor ?? colors.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.5),
          width: 1.0,
        );
        shadows = [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ];
        break;
      case AppCardVariant.filled:
        bg = color ?? colors.surfaceContainerHighest.withValues(alpha: 0.45);
        border = null;
        shadows = null;
        break;
    }

    Widget content = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: border,
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      content = AppPressable(
        onTap: onTap,
        borderRadius: radius,
        child: content,
      );
    }

    return content;
  }
}

/// ---------------------------------------------------------------------------
/// AppBadge: 状态徽章 / 标签 (参考 TDesign TDTag 与 Forui FBadge)
/// ---------------------------------------------------------------------------

enum AppBadgeVariant {
  primary,
  secondary,
  success,
  warning,
  error,
  neutral,
}

class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.icon,
    this.variant = AppBadgeVariant.neutral,
    this.hasDot = false,
  });

  final String label;
  final IconData? icon;
  final AppBadgeVariant variant;
  final bool hasDot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    Color fg;
    Color bg;

    switch (variant) {
      case AppBadgeVariant.primary:
        fg = colors.primary;
        bg = colors.primary.withValues(alpha: 0.10);
        break;
      case AppBadgeVariant.secondary:
        fg = colors.secondary;
        bg = colors.secondary.withValues(alpha: 0.10);
        break;
      case AppBadgeVariant.success:
        fg = const Color(0xFF07C160);
        bg = const Color(0xFF07C160).withValues(alpha: 0.12);
        break;
      case AppBadgeVariant.warning:
        fg = const Color(0xFFE88A1A);
        bg = const Color(0xFFE88A1A).withValues(alpha: 0.12);
        break;
      case AppBadgeVariant.error:
        fg = colors.error;
        bg = colors.error.withValues(alpha: 0.10);
        break;
      case AppBadgeVariant.neutral:
        fg = colors.onSurfaceVariant;
        bg = colors.surfaceContainerHighest.withValues(alpha: 0.65);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.roundedSm,
        border: Border.all(
          color: fg.withValues(alpha: 0.16),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (hasDot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: fg,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
          ] else if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 3.5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.15,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// AppCellGroup & AppCell: 列表分组 (参考 TDesign TDCellGroup / iOS 清爽分组列表)
/// 替代原先无规范嵌套和滥用毛玻璃的分类卡片
/// ---------------------------------------------------------------------------

class AppCellGroup extends StatelessWidget {
  const AppCellGroup({
    super.key,
    this.title,
    required this.cells,
    this.margin = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.xs,
    ),
  });

  final String? title;
  final List<AppCell> cells;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                bottom: AppSpacing.sm,
              ),
              child: Text(
                title!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
          AppCard(
            padding: EdgeInsets.zero,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: cells.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                thickness: 0.7,
                indent: 56,
                endIndent: 0,
                color: colors.outlineVariant.withValues(alpha: 0.35),
              ),
              itemBuilder: (context, index) => cells[index],
            ),
          ),
        ],
      ),
    );
  }
}

class AppCell extends StatelessWidget {
  const AppCell({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.badge,
    this.trailing,
    this.onTap,
    this.showArrow = true,
  });

  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? badge;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? colors.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: effectiveIconColor.withValues(alpha: 0.08),
                    borderRadius: AppRadius.roundedMd,
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      size: 20,
                      color: effectiveIconColor,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          badge!,
                        ],
                      ],
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                          height: 1.25,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ],
              if (showArrow) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.45),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// AppServiceItem: 现代方圆图标服务入口 (参考 TDesign 宫格导航规范)
/// 拒绝单一且幼稚的圆形大底色泡泡
/// ---------------------------------------------------------------------------

class AppServiceItem extends StatelessWidget {
  const AppServiceItem({
    super.key,
    required this.icon,
    required this.label,
    this.badge,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AppPressable(
      onTap: onTap,
      borderRadius: AppRadius.roundedMd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: AppRadius.roundedMd,
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    size: 22,
                    color: colors.onSurface,
                  ),
                ),
              ),
              if (badge != null)
                Positioned(
                  top: -4,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: colors.error,
                      borderRadius: AppRadius.roundedFull,
                    ),
                    constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs + 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.onSurface.withValues(alpha: 0.88),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
