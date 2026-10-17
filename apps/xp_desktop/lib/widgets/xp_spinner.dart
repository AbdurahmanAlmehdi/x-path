import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/xp_clock.dart';

/// An icon that turns: the running arc once per `motion.duration.spin`, or
/// the reconnecting arrows once per `motion.duration.pulse` ([slow]).
///
/// Under Reduce Motion it stands still (Status, "Running treatment"), and
/// while the app is not in front (`XpClock.isLive`).
class XpSpinner extends StatefulWidget {
  const new({
    required this.icon,
    required this.size,
    required this.color,
    this.slow = false,
    super.key,
  });

  final IconData icon;
  final double size;
  final Color color;

  /// Turns at the pulse speed instead of the spin speed.
  final bool slow;

  @override
  State<XpSpinner> createState() => _XpSpinnerState();
}

class _XpSpinnerState extends State<XpSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = context.xpMotion;
    final still =
        MediaQuery.disableAnimationsOf(context) || !XpClock.isLive(context);
    _controller.duration = widget.slow
        ? motion.durationPulse
        : motion.durationSpin;
    if (still) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _controller,
    child: Icon(widget.icon, size: widget.size, color: widget.color),
  );
}
