import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/routes/app_router.dart';
import '../../../data/datasources/local/database_helper.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  String _status = 'Iniciando...';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final db = DatabaseHelper();

      if (!kIsWeb) {
        setState(() => _status = 'Inicializando base de datos...');
        await db.database;
      }

      setState(() => _status = 'Cargando configuración...');
      await db.getConfig('url_api');

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final usuario = prefs.getString('auth_usuario');

      if (mounted) {
        if (token != null && usuario != null) {
          context.go(AppRoutes.asistencia);
        } else {
          context.go(AppRoutes.login);
        }
      }
    } catch (e) {
      setState(() => _status = 'Error al inicializar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1565C0),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fingerprint, size: 80, color: Colors.white),
            const SizedBox(height: 24),
            const Text(
              'Control de Asistencia',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Reconocimiento Facial',
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              _status,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
