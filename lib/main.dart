import 'package:flutter/material.dart';

import 'db.dart';
import 'notifications.dart';
import 'ui/budget.dart';
import 'ui/dashboard.dart';
import 'ui/loans.dart';
import 'ui/more.dart';
import 'ui/tasks.dart';

final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

Future<void> loadTheme() async {
  final v = await AppDb.instance.getSetting('dark');
  themeMode.value = v == '1' ? ThemeMode.dark : ThemeMode.light;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDb.instance;
  await db.open();
  await loadTheme();
  await Notifier.init();
  db.version.addListener(() {
    loadTheme();
    Notifier.rescheduleAll(db);
  });
  Notifier.rescheduleAll(db);
  runApp(const PdmApp());
}

class PdmApp extends StatefulWidget {
  const PdmApp({super.key});
  @override
  State<PdmApp> createState() => _PdmAppState();
}

class _PdmAppState extends State<PdmApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Notifier.rescheduleAll(AppDb.instance);
    }
  }

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00897B), brightness: b),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Personal Daily Manager',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const Shell(),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;
  static const _pages = <Widget>[
    DashboardPage(),
    TasksPage(),
    BudgetPage(),
    LoansPage(),
    MorePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _i, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (i) => setState(() => _i = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: 'Tasks'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Budget'),
          NavigationDestination(icon: Icon(Icons.handshake_outlined), selectedIcon: Icon(Icons.handshake), label: 'Udhaar'),
          NavigationDestination(icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
