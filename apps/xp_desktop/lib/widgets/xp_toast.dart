import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/toast/cubit/toast_cubit.dart';
import 'package:xp_desktop/widgets/xp_button.dart';

/// [child] with the toasts of the `ToastCubit` above it, bottom right
/// (`surface.overlay`, `elevation.2`), newest at the bottom.
class XpToastHost extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: child),
      Positioned(
        right: 16,
        bottom: 16,
        child: BlocBuilder<ToastCubit, ToastState>(
          builder: (context, state) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final toast in state.toasts)
                Padding(
                  key: ValueKey(('toast', toast.id)),
                  padding: const EdgeInsets.only(top: 8),
                  child: XpToast(toast: toast),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// One toast: its message, its action, and a close button.
class XpToast extends StatelessWidget {
  const new({required this.toast, super.key});

  final Toast toast;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final cubit = context.read<ToastCubit>();
    final action = toast.action;
    return Semantics(
      liveRegion: true,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        decoration: BoxDecoration(
          color: colors.surfaceOverlay,
          borderRadius: BorderRadius.circular(context.xpRadii.lg),
          border: Border.all(color: colors.borderDefault),
          boxShadow: context.xpElevation.elevation2,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  toast.message,
                  style: context.xpType.body.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: 8),
                XpButton(
                  label: action,
                  kind: XpButtonKind.tertiary,
                  size: XpButtonSize.small,
                  onPressed: () => cubit.act(toast.id),
                ),
              ],
              const SizedBox(width: 4),
              Tooltip(
                message: context.l10n.toastDismiss,
                child: InkWell(
                  onTap: () => cubit.dismiss(toast.id),
                  borderRadius: BorderRadius.circular(context.xpRadii.md),
                  child: SizedBox.square(
                    dimension: context.xpSizes.controlSm,
                    child: Icon(
                      PhosphorIconsRegular.x,
                      size: context.xpSizes.iconSm,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
