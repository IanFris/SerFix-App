import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shimmer/shimmer.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';

class SerfixAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SerfixAppBar({
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(AppSpacing.appBarHeight);

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppSpacing.x2),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
        ),
      );
}

class SerfixPrimaryButton extends StatefulWidget {
  const SerfixPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expand;

  @override
  State<SerfixPrimaryButton> createState() => _SerfixPrimaryButtonState();
}

class _SerfixPrimaryButtonState extends State<SerfixPrimaryButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;
    final button = Listener(
      onPointerDown: enabled ? (_) => setState(() => _isPressed = true) : null,
      onPointerUp: enabled ? (_) => setState(() => _isPressed = false) : null,
      onPointerCancel:
          enabled ? (_) => setState(() => _isPressed = false) : null,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: SizedBox(
          height: AppSpacing.buttonHeight,
          width: widget.expand ? double.infinity : null,
          child: FilledButton(
            onPressed: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    widget.onPressed!();
                  }
                : null,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: widget.isLoading
                  ? SizedBox(
                      key: ValueKey('loading'),
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : Row(
                      key: const ValueKey('label'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, size: 19),
                          const SizedBox(width: AppSpacing.x2),
                        ],
                        Text(widget.label),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );

    return button;
  }
}

class SerfixStatusBadge extends StatelessWidget {
  const SerfixStatusBadge({
    required this.label,
    required this.color,
    this.icon,
    super.key,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        constraints:
            const BoxConstraints(minHeight: AppSpacing.statusBadgeHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x3,
          vertical: AppSpacing.x1,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: AppSpacing.x1),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      );
}

class SerfixServiceCard extends StatelessWidget {
  const SerfixServiceCard({
    required this.title,
    required this.description,
    required this.priceLabel,
    required this.icon,
    required this.onTap,
    this.rating,
    super.key,
  });

  final String title;
  final String description;
  final String priceLabel;
  final IconData icon;
  final VoidCallback onTap;
  final String? rating;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final borderColor = Theme.of(context).brightness == Brightness.light
        ? AppColors.neutral200
        : AppColors.darkBorder;
    return Semantics(
      button: true,
      label: '$title, $description, mulai $priceLabel',
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: borderColor),
            ),
            padding: const EdgeInsets.all(AppSpacing.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: AppSpacing.serviceIconBox,
                      height: AppSpacing.serviceIconBox,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      child: Icon(icon, color: colors.primary, size: 24),
                    ),
                    const Spacer(),
                    if (rating != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: AppSpacing.iconSmall,
                            color: AppColors.warning,
                          ),
                          Text(
                            rating!,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x3),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Text(
                  priceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SerfixBottomNavItem {
  const SerfixBottomNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class SerfixBottomNavigation extends StatelessWidget {
  const SerfixBottomNavigation({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<SerfixBottomNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final borderColor = Theme.of(context).brightness == Brightness.light
        ? AppColors.neutral200
        : AppColors.darkBorder;
    final unselectedColor = Theme.of(context).brightness == Brightness.light
        ? AppColors.neutral500
        : AppColors.neutral300;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        AppSpacing.x4,
        AppSpacing.x2,
        AppSpacing.x4,
        AppSpacing.x3,
      ),
      child: Container(
        height: AppSpacing.bottomNavigationHeight,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          children: List.generate(items.length, (index) {
            final item = items[index];
            final selected = selectedIndex == index;
            final color = selected ? colors.primary : unselectedColor;
            return Expanded(
              child: Semantics(
                button: true,
                selected: selected,
                label: item.label,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSelected(index);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.x1,
                      vertical: AppSpacing.x2,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.primary.withValues(alpha: 0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          selected ? item.selectedIcon : item.icon,
                          size: AppSpacing.iconMedium,
                          color: color,
                        ),
                        const SizedBox(height: AppSpacing.x1),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: color,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class SerfixEmptyState extends StatelessWidget {
  const SerfixEmptyState({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  static const _illustration = '''
<svg xmlns="http://www.w3.org/2000/svg" width="160" height="128" viewBox="0 0 160 128" fill="none">
  <rect x="34" y="18" width="92" height="72" rx="14" fill="#EAF1F3"/>
  <path d="M47 41h66M54 55h52M61 69h38" stroke="#126B78" stroke-width="4" stroke-linecap="round"/>
  <path d="M58 103c7-8 13-8 20 0s13 8 20 0 13-8 20 0" stroke="#55D6C2" stroke-width="4" stroke-linecap="round"/>
  <circle cx="126" cy="27" r="13" fill="#55D6C2"/>
  <path d="m120 27 4 4 8-9" stroke="#10272E" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.string(
                _illustration,
                width: AppSpacing.emptyIllustrationWidth,
                height: AppSpacing.emptyIllustrationHeight,
                semanticsLabel: 'Ilustrasi layanan SerFix kosong',
              ),
              const SizedBox(height: AppSpacing.x4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.72),
                    ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.x4),
                TextButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      );
}

class SerfixSkeleton extends StatelessWidget {
  const SerfixSkeleton({
    this.height = 16,
    this.width,
    this.radius = AppSpacing.radiusSm,
    super.key,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
        baseColor: Theme.of(context).brightness == Brightness.light
            ? AppColors.neutral100
            : AppColors.darkBorder,
        highlightColor: Theme.of(context).brightness == Brightness.light
            ? Colors.white
            : AppColors.darkSurface,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light
                ? AppColors.neutral100
                : AppColors.darkBorder,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      );
}

class SerfixBottomSheetFrame extends StatelessWidget {
  const SerfixBottomSheetFrame({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.x4),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: AppSpacing.dragHandleWidth,
                  height: AppSpacing.dragHandleHeight,
                  decoration: BoxDecoration(
                    color: AppColors.neutral300,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
              child,
            ],
          ),
        ),
      );
}

class SerfixInputField extends StatelessWidget {
  const SerfixInputField({
    required this.label,
    this.hint,
    this.controller,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
    this.prefixIcon,
    super.key,
  });

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final Widget? prefixIcon;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: prefixIcon,
          alignLabelWithHint: maxLines > 1,
        ),
      );
}
