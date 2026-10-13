import 'dart:io';

import 'package:xpd/xpd.dart';

void main(List<String> args) {
  exitCode = runXpd(args, out: stdout, err: stderr);
}
