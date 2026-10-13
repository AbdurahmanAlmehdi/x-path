import 'package:flutter/widgets.dart';

/// The whole app: one line of text that says which flavor it is.
class BuildApp extends StatelessWidget {
  const BuildApp({required this.flavor, super.key});

  final String flavor;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: Text('build_app $flavor')),
  );
}
