import 'package:flutter/widgets.dart';

import 'core/di/service_locator.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupDependencies();
  runApp(const QuranApp());
}
