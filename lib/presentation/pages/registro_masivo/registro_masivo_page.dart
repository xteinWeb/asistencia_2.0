import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/constants/db_constants.dart';
import '../../../core/constants/api_constants.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../data/models/empleado_model.dart';

class RegistroMasivoPage extends StatefulWidget {
  const RegistroMasivoPage({super.key});

  @override
  State<RegistroMasivoPage> createState() => _RegistroMasivoPageState();
}

class _RegistroMasivoPageState extends State<RegistroMasivoPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
  PlatformFile? _csvFile;
  List<PlatformFile> _selectedPhotos = [];
  List<Map<String, dynamic>> _parsedEmployees = [];
  
  bool _isProcessing = false;
  double _progress = 0.0;
  int _currentIndex = 0;
  List<String> _processLogs = [];
  final ScrollController _logScrollController = ScrollController();

  int _successCount = 0;
  int _failCount = 0;

  // Step indicator
  int _currentStep = 0; // 0: Select, 1: Preview, 2: Process

  Future<void> _pickCSVFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _csvFile = result.files.first;
          _parsedEmployees.clear();
          if (_currentStep == 1) _currentStep = 0;
        });
        await _parseCSV();
      }
    } catch (e) {
      _showSnackBar('Error al seleccionar CSV: $e', isError: true);
    }
  }

  Future<void> _pickPhotos() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedPhotos = result.files;
        });
        _matchPhotos();
      }
    } catch (e) {
      _showSnackBar('Error al seleccionar fotos: $e', isError: true);
    }
  }

  String _decodeBytes(List<int> bytes) {
    try {
      return const Utf8Decoder().convert(bytes);
    } catch (_) {
      try {
        return const Latin1Decoder().convert(bytes);
      } catch (_) {
        return String.fromCharCodes(bytes);
      }
    }
  }

  Future<void> _parseCSV() async {
    if (_csvFile == null) return;
    
    try {
      List<int> bytes;
      if (kIsWeb) {
        bytes = _csvFile!.bytes!;
      } else {
        bytes = await File(_csvFile!.path!).readAsBytes();
      }

      final csvString = _decodeBytes(bytes);
      final delimiter = csvString.contains(';') ? ';' : ',';

      final List<List<dynamic>> csvRows = Csv(
        fieldDelimiter: delimiter,
        autoDetect: false,
        dynamicTyping: false,
      ).decode(csvString);

      if (csvRows.isEmpty) {
        _showSnackBar('El archivo CSV está vacío.', isError: true);
        return;
      }

      final headers = csvRows.first.map((h) => h.toString().trim().toLowerCase()).toList();
      
      final List<Map<String, dynamic>> tempEmployees = [];
      
      for (int i = 1; i < csvRows.length; i++) {
        final row = csvRows[i];
        if (row.length < headers.length) continue;

        final Map<String, dynamic> empData = {};
        for (int j = 0; j < headers.length; j++) {
          empData[headers[j]] = row[j].toString().trim();
        }

        final cedula = empData['cedula'] ?? '';
        final nombre = empData['nombre'] ?? '';
        final foto = empData['foto'] ?? '';

        if (cedula.isEmpty || nombre.isEmpty) continue;

        tempEmployees.add({
          'cedula': cedula,
          'nombre': nombre,
          'tipo': empData['tipo'] ?? 'OPERATIVO',
          'fecha_inicio': empData['fecha_inicio'] ?? '',
          'fecha_fin': empData['fecha_fin'] ?? '',
          'horario_id': empData['horario_id'] ?? '01',
          'id_seccion': empData['id_seccion'] ?? '',
          'sede_principal': empData['sede_principal'] ?? '',
          'foto_filename': foto,
          'matched_photo': null,
          'status': 'Falta Foto',
        });
      }

      setState(() {
        _parsedEmployees = tempEmployees;
        if (_parsedEmployees.isNotEmpty) {
          _currentStep = 1; // Avanzar a vista previa
        }
      });

      _matchPhotos();
    } catch (e) {
      _showSnackBar('Error al procesar el archivo CSV: $e', isError: true);
    }
  }

  void _matchPhotos() {
    if (_parsedEmployees.isEmpty || _selectedPhotos.isEmpty) return;

    setState(() {
      for (var emp in _parsedEmployees) {
        final fotoName = emp['foto_filename'].toString().toLowerCase();
        final cedula = emp['cedula'].toString().toLowerCase();

        PlatformFile? matched;
        for (var file in _selectedPhotos) {
          final fileName = file.name.toLowerCase();
          final nameWithoutExt = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
          
          if (fileName == fotoName || nameWithoutExt == fotoName || fileName == '$cedula.jpg' || nameWithoutExt == cedula) {
            matched = file;
            break;
          }
        }

        if (matched != null) {
          emp['matched_photo'] = matched;
          emp['status'] = 'Listo';
        } else {
          emp['matched_photo'] = null;
          emp['status'] = 'Falta Foto';
        }
      }
    });
  }

  void _addLog(String log) {
    setState(() {
      _processLogs.add('[${DateFormat('HH:mm:ss').format(DateTime.now())}] $log');
    });
    // Auto scroll log to bottom
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startImport() async {
    final readyList = _parsedEmployees.where((e) => e['matched_photo'] != null).toList();
    if (readyList.isEmpty) {
      _showSnackBar('No hay empleados listos para importar (todos requieren foto).', isError: true);
      return;
    }

    final baseUrl = await _dbHelper.getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;

    setState(() {
      _isProcessing = true;
      _currentStep = 2; // Avanzar a procesamiento
      _progress = 0.0;
      _currentIndex = 0;
      _processLogs.clear();
      _successCount = 0;
      _failCount = 0;
    });

    _addLog('Iniciando importación masiva de ${readyList.length} empleados...');

    for (int i = 0; i < readyList.length; i++) {
      final emp = readyList[i];
      final PlatformFile photoFile = emp['matched_photo'];

      setState(() {
        _currentIndex = i + 1;
        _progress = (i + 1) / readyList.length;
      });

      _addLog('Procesando (${i + 1}/${readyList.length}): ${emp['nombre']} (C.C. ${emp['cedula']})...');

      try {
        // Step A: Generar Vector Facial mediante el Endpoint de Python
        _addLog('Generando firma facial en el servidor...');
        final vectorUri = Uri.parse('$baseUrl/api/biometria/vector');
        final request = http.MultipartRequest('POST', vectorUri);
        
        request.fields['cedula'] = emp['cedula'];
        
        if (kIsWeb) {
          request.files.add(http.MultipartFile.fromBytes(
            'face',
            photoFile.bytes!,
            filename: photoFile.name,
          ));
        } else {
          request.files.add(await http.MultipartFile.fromPath(
            'face',
            photoFile.path!,
          ));
        }

        final streamedResponse = await request.send().timeout(const Duration(seconds: 15));
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode != 200) {
          final errBody = jsonDecode(response.body);
          throw Exception(errBody['detail'] ?? 'Error de procesamiento');
        }

        final responseData = jsonDecode(response.body);
        final List<dynamic> rawVector = responseData['vector'];
        final List<double> vector = rawVector.map((v) => double.parse(v.toString())).toList();

        _addLog('Firma facial generada con éxito (Dim: ${vector.length}). Guardando empleado...');

        // Step B: Guardar empleado en base de datos central/local
        final nuevoEmpleado = EmpleadoModel(
          cedula: emp['cedula'],
          nombre: emp['nombre'],
          mapaVectorFoto: vector,
          horarioId: emp['horario_id'],
          fechaIniContrato: emp['fecha_inicio'].toString().isNotEmpty ? emp['fecha_inicio'] : null,
          fechaFinContrato: emp['fecha_fin'].toString().isNotEmpty ? emp['fecha_fin'] : null,
          sincronizado: kIsWeb ? true : false, // Sincronizado en la nube de inmediato si está en Web
          estado: 'ACTIVO',
          sedePrincipal: emp['sede_principal'].toString().isNotEmpty ? emp['sede_principal'] : null,
          idSeccion: emp['id_seccion'].toString().isNotEmpty ? emp['id_seccion'] : null,
          tipo: emp['tipo'].toString().isNotEmpty ? emp['tipo'] : 'OPERATIVO',
          fechaRegistro: DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
        );

        final result = await _dbHelper.insertEmpleado(nuevoEmpleado);

        if (result > 0) {
          _addLog('¡Éxito! ${emp['nombre']} registrado correctamente.');
          _successCount++;
        } else {
          throw Exception('Fallo al guardar en base de datos.');
        }

      } catch (e) {
        _addLog('[ERROR] Falló el registro de ${emp['nombre']}: $e');
        _failCount++;
      }
    }

    setState(() {
      _isProcessing = false;
    });

    _addLog('Proceso finalizado. Correctos: $_successCount | Errores: $_failCount');
    _showSummaryDialog();
  }

  void _showSummaryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.assignment_turned_in_outlined, color: AppColors.primary, size: 28),
            SizedBox(width: 8),
            Text('Resumen de Importación'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('El procesamiento de registro masivo ha finalizado.'),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success, size: 20),
                const SizedBox(width: 8),
                Text('Registrados con éxito: $_successCount', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.cancel, color: AppColors.error, size: 20),
                const SizedBox(width: 8),
                Text('Errores / Omitidos: $_failCount', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            if (!kIsWeb) ...[
              const SizedBox(height: 16),
              const Text(
                'Nota: Recuerde realizar una sincronización manual en la pantalla principal para descargar los nuevos registros a la base de datos local SQLite.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
              )
            ]
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.go(AppRoutes.empleados);
            },
            child: const Text('Volver a Empleados'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importación Masiva de Colaboradores'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isProcessing ? null : () => context.go(AppRoutes.empleados),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Step Navigation Header
            _buildStepIndicator(),
            const SizedBox(height: 20),

            // Main Wizard steps
            Expanded(
              child: _buildCurrentStepView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStepNode(0, 'Cargar Archivos', Icons.upload_file),
            const Icon(Icons.arrow_forward, size: 16, color: AppColors.textDisabled),
            _buildStepNode(1, 'Vista Previa', Icons.preview),
            const Icon(Icons.arrow_forward, size: 16, color: AppColors.textDisabled),
            _buildStepNode(2, 'Procesamiento', Icons.biotech),
          ],
        ),
      ),
    );
  }

  Widget _buildStepNode(int stepIndex, String title, IconData icon) {
    final isActive = _currentStep == stepIndex;
    final isDone = _currentStep > stepIndex;
    
    Color color = AppColors.textDisabled;
    if (isActive) {
      color = AppColors.primary;
    } else if (isDone) {
      color = AppColors.success;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 0:
        return _buildSelectFilesView();
      case 1:
        return _buildPreviewView();
      case 2:
        return _buildProcessingView();
      default:
        return _buildSelectFilesView();
    }
  }

  Widget _buildSelectFilesView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Instrucciones de Carga',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  '1. Prepare un archivo CSV delimitado por comas (,) o punto y coma (;) con las siguientes columnas:\n'
                  '   cedula;nombre;tipo;fecha_inicio;fecha_fin;horario_id;id_seccion;sede_principal;foto\n\n'
                  '2. El campo "foto" debe contener el nombre de la foto de la persona (ej. juan.jpg).\n\n'
                  '3. Suba el archivo CSV y luego seleccione las fotos asociadas.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),

                // CSV Picker
                OutlinedButton.icon(
                  onPressed: _pickCSVFile,
                  icon: Icon(_csvFile != null ? Icons.check_circle : Icons.insert_drive_file, 
                    color: _csvFile != null ? AppColors.success : AppColors.primary),
                  label: Text(_csvFile != null ? _csvFile!.name : 'Seleccionar Archivo CSV',
                    style: TextStyle(color: _csvFile != null ? AppColors.success : AppColors.primary)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: _csvFile != null ? AppColors.success : AppColors.primary),
                  ),
                ),
                const SizedBox(height: 16),

                // Photos Picker
                OutlinedButton.icon(
                  onPressed: _pickPhotos,
                  icon: Icon(_selectedPhotos.isNotEmpty ? Icons.photo_library : Icons.add_a_photo,
                    color: _selectedPhotos.isNotEmpty ? AppColors.success : AppColors.primary),
                  label: Text(_selectedPhotos.isNotEmpty 
                      ? '${_selectedPhotos.length} fotos seleccionadas'
                      : 'Seleccionar Fotos de Empleados'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewView() {
    final matchedCount = _parsedEmployees.where((e) => e['matched_photo'] != null).length;
    final missingCount = _parsedEmployees.length - matchedCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary Card
        Card(
          elevation: 2,
          color: AppColors.primary.withOpacity(0.05),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryText('Total en CSV', '${_parsedEmployees.length}', Colors.black),
                _buildSummaryText('Fotos Listas', '$matchedCount', AppColors.success),
                _buildSummaryText('Faltan Fotos', '$missingCount', AppColors.error),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Grid List Table
        Expanded(
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Scrollbar(
                child: ListView.builder(
                  itemCount: _parsedEmployees.length,
                  itemBuilder: (context, index) {
                    final emp = _parsedEmployees[index];
                    final isMatched = emp['matched_photo'] != null;

                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: isMatched ? AppColors.success.withOpacity(0.1) : AppColors.error.withOpacity(0.1),
                        child: Icon(
                          isMatched ? Icons.image : Icons.broken_image,
                          color: isMatched ? AppColors.success : AppColors.error,
                        ),
                      ),
                      title: Text(emp['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('C.C. ${emp['cedula']} | Foto asignada: ${emp['foto_filename']}'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isMatched ? AppColors.success.withOpacity(0.2) : AppColors.error.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isMatched ? 'Listo' : 'Falta Foto',
                          style: TextStyle(
                            color: isMatched ? AppColors.success : AppColors.error,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Action Buttons Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _currentStep = 0;
                });
              },
              child: const Text('Volver a Cargar'),
            ),
            ElevatedButton.icon(
              onPressed: matchedCount > 0 ? _startImport : null,
              icon: const Icon(Icons.play_circle_outline),
              label: Text('Iniciar Registro Masivo ($matchedCount)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildSummaryText(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildProcessingView() {
    final readyList = _parsedEmployees.where((e) => e['matched_photo'] != null).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Progress Card
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                Text(
                  _isProcessing
                      ? 'Procesando Empleado $_currentIndex de ${readyList.length}'
                      : 'Procesamiento Terminado',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _progress,
                  minHeight: 10,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
                const SizedBox(height: 8),
                Text('${(_progress * 100).toStringAsFixed(0)}% Completado',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        const Text(
          'Consola de Procesamiento',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),

        // Console Log Output
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade800),
            ),
            child: Scrollbar(
              thumbVisibility: true,
              child: ListView.builder(
                controller: _logScrollController,
                itemCount: _processLogs.length,
                itemBuilder: (context, index) {
                  final log = _processLogs[index];
                  Color logColor = Colors.greenAccent;
                  if (log.contains('[ERROR]')) {
                    logColor = Colors.redAccent;
                  } else if (log.contains('Iniciando') || log.contains('finalizado')) {
                    logColor = Colors.yellowAccent;
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Text(
                      log,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: logColor,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
