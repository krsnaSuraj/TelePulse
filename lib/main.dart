import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/app_meta.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppMeta.init();
  runApp(
    const ProviderScope(
      child: TelePulseApp(),
    ),
  );
}
