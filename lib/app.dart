import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/datasources/local/database_helper.dart';
import 'services/connectivity_service.dart';
import 'services/sync_service.dart';

import 'core/theme/theme_provider.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final DatabaseHelper _db;
  late final ConnectivityService _connectivity;
  late final SyncService _syncService;

  @override
  void initState() {
    super.initState();
    _db = DatabaseHelper();
    _connectivity = ConnectivityService();
    _syncService = SyncService(db: _db, connectivity: _connectivity);

    // Iniciar la sincronización periódica en segundo plano
    _syncService.startPeriodicSync();
  }

  @override
  void dispose() {
    _syncService.stopSync();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<DatabaseHelper>.value(value: _db),
        Provider<ConnectivityService>.value(value: _connectivity),
        Provider<SyncService>.value(value: _syncService),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp.router(
            title: 'Tótem Control de Asistencia',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            routerConfig: appRouter,
          );
        },
      ),
    );
  }
}
