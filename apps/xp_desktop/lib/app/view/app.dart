import 'package:material_ui/material_ui.dart';

class App extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XPath',
      theme: ThemeData(useMaterial3: true),
      home: const Scaffold(body: Center(child: Text('XPath'))),
    );
  }
}
