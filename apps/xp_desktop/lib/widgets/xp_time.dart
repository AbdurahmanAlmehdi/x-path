import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/widgets/xp_clock.dart';
import 'package:xp_desktop/widgets/xp_format.dart';

/// When something happened, as a list shows it: the time of day for the
/// last day, else a date and time ([formatWhen]); the tooltip says it in
/// full ([formatAbsolute]).
class XpTime extends StatelessWidget {
  const new(this.time, {this.style, super.key});

  final DateTime time;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: formatAbsolute(time),
    child: Text(formatWhen(time, XpClock.now(context)), style: style),
  );
}
