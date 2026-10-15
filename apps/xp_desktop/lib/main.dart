import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/bootstrap.dart';

Future<void> main() async {
  await bootstrap(() async => App(services: await AppServices.system()));
}
