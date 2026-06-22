import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/auth_service.dart';

/// Página de login con usuario, contraseña y empresa (API externa)
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usuarioController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _empresaSeleccionada;
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _cargandoEmpresas = false;

  // Lista de empresas disponibles (se carga dinámicamente)
  List<Map<String, String>> _empresas = [];
  String idAs = '';
  String? _error;

  @override
  void dispose() {
    _usuarioController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Validar credenciales de usuario mediante la API externa
  Future<void> _iniciarSesion() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      String authResult = await login(
        usuario: _usuarioController.text.trim(),
        contra: _passwordController.text.trim(),
        empresa: _empresaSeleccionada!,
        idAs: idAs,
      );

      if (authResult == '') {
        // Redirigir siempre a la pantalla Home (menú principal administrativo) por defecto
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          context.go(AppRoutes.home);
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = authResult;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error de conexión: $e';
        });
      }
    }
  }

  /// Función que se ejecuta cada vez que cambia el texto del usuario
  void _onUsuarioCambiado(String usuario) {
    _cargarEmpresasPorUsuario(usuario);
  }

  /// Cargar empresas desde API cuando el usuario escribe
  Future<void> _cargarEmpresasPorUsuario(String usuario) async {
    if (usuario.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _empresas = [];
          _empresaSeleccionada = null;
          _cargandoEmpresas = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _cargandoEmpresas = true;
        _empresaSeleccionada = null;
      });
    }

    try {
      Object resultado = await getEmpresa(usuario: usuario);
      if (resultado is List<Map<String, String>>) {
        if (mounted) {
          setState(() {
            _empresas = resultado;
            _cargandoEmpresas = false;
          });
        }
        print('Empresas cargadas: $resultado');
      } else {
        print('Error cargando empresas: $resultado');
        if (mounted) {
          setState(() {
            _empresas = [];
            _cargandoEmpresas = false;
          });
        }
      }
    } catch (e) {
      print('Error cargando empresas: $e');
      if (mounted) {
        setState(() {
          _empresas = [];
          _cargandoEmpresas = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 600;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade800,
              Colors.blue.shade600,
              Colors.blue.shade400,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isWide ? 460 : double.infinity,
                ),
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            Icons.fingerprint_rounded,
                            size: 72,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Control de Asistencia',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ingresa tus credenciales para continuar',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),

                          // Campo Usuario
                          TextFormField(
                            controller: _usuarioController,
                            keyboardType: TextInputType.text,
                            onChanged: _onUsuarioCambiado,
                            decoration: const InputDecoration(
                              labelText: 'Usuario',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'El usuario es obligatorio';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),

                          // Campo Contraseña
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            keyboardType: TextInputType.visiblePassword,
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'La contraseña es obligatoria';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),

                          // Dropdown de Empresa
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _empresaSeleccionada,
                            hint: _cargandoEmpresas
                                ? const Text('Cargando empresas...')
                                : Text(
                                    _empresas.isEmpty
                                        ? 'Ingresa tu usuario primero'
                                        : 'Selecciona una empresa',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            items: _empresas.map((empresa) {
                              return DropdownMenuItem<String>(
                                value: empresa['ID'],
                                child: Container(
                                  constraints: const BoxConstraints(
                                    maxWidth: 300,
                                  ),
                                  child: Text(
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    empresa['EMPRESA'] ?? '',
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              setState(() {
                                _empresaSeleccionada = newValue;
                                if (newValue != null) {
                                  final selected = _empresas.firstWhere(
                                    (empresa) => empresa['ID'] == newValue,
                                  );
                                  idAs = selected['ID_AS'] ?? '';
                                }
                              });
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Selecciona una empresa';
                              }
                              return null;
                            },
                          ),

                          if (_cargandoEmpresas) ...[
                            const SizedBox(height: 8),
                            const LinearProgressIndicator(),
                          ],

                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 28),

                          ElevatedButton(
                            onPressed: _isLoading ? null : _iniciarSesion,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Iniciar Sesión',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
