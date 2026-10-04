import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/core/constants/app_constants.dart';
import 'package:frontend/data/finance_api.dart';
import 'package:frontend/data/finance_store.dart';
import 'package:frontend/data/secure_vault.dart';
import 'package:frontend/screens/app_shell.dart';
import 'package:frontend/screens/onboarding/login_screen.dart';
import 'package:frontend/shared/themes/app_theme.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  final store = await FinanceStore.load(
    api: HttpFinanceApi(),
    vault: FlutterSecureVault(),
  );
  runApp(MyApp(store: store));
}

class MyApp extends StatelessWidget {
  const MyApp({required this.store, super.key});

  final FinanceStore store;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<FinanceStore>.value(
      value: store,
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: store.isSignedIn ? const MainShell() : const LoginScreen(),
      ),
    );
  }
}
