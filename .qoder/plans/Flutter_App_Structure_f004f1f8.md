# Flutter App - Estructura Completa

## Modelos de datos (extraídos del diagrama)

### SQLite local (BD Dispositivo)
- **empleados**: cedula, nombre, mapa_vector_foto (JSON array 128 floats), horario_id, fecha_ini_contrato, fecha_fin_contrato
- **horarios**: id_horario, hora_inicio, hora_final, tipo (LABORAL/ALMUERZO/DESCANSO), dias (L,M,M,J,V,S,D)
- **registros**: id, fecha_hora, cedula, evento (ENTRADA/SALIDA), duracion, tipo (LABORAL/PERMISO/ALMUERZO/RETARDO/EXTRAS), unidad_negocio, sincronizado (bool)
- **usuarios**: usuario, nombre, contrasena, rol, estado, unidad_negocio
- **permisos**: id, usuario_registrador, cedula_empleado, fecha_hora, tipo (CITA_MEDICA/PERSONAL/LABORAL/TRASLADO/FIN_CONTRATO), fecha_inicio, fecha_final, sincronizado (bool)
- **configuracion**: clave, valor (url_api, frecuencia_sync, unidad_negocio, etc.)

---

## Task 1: Configurar pubspec.yaml con dependencias

Agregar a `lib/../pubspec.yaml`:
```yaml
dependencies:
  sqflite: ^2.3.3          # SQLite local
  sqflite_common_ffi: ^2.3.3  # SQLite en Desktop (Windows/Linux)
  http: ^1.2.2             # HTTP cliente para API
  camera: ^0.11.0          # Cámara para captura de foto
  google_mlkit_face_detection: ^0.11.0  # Detección facial offline
  connectivity_plus: ^6.0.5  # Verificar conexión
  path_provider: ^2.1.4    # Rutas del sistema
  provider: ^6.1.2         # Gestión de estado
  shared_preferences: ^2.3.2  # Config simple
  intl: ^0.19.0            # Formateo de fechas
  image: ^4.2.0            # Procesamiento de imágenes
  flutter_secure_storage: ^9.2.2  # Almacenamiento seguro JWT
  go_router: ^14.3.0       # Navegación
  window_size: # Desktop window control
```

---

## Task 2: Estructura de carpetas (Atomic Design)

```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── constants/
│   │   ├── api_constants.dart       # URLs del backend Node.js
│   │   ├── db_constants.dart        # Nombres de tablas SQLite
│   │   └── app_constants.dart       # Umbrales, timeouts, etc.
│   ├── theme/
│   │   ├── app_colors.dart
│   │   ├── app_text_styles.dart
│   │   └── app_theme.dart
│   ├── routes/
│   │   └── app_router.dart          # GoRouter config
│   └── utils/
│       ├── date_utils.dart
│       ├── face_matcher.dart        # Comparación local de vectores
│       └── horario_validator.dart   # Valida horario → Retardo/Normal/Salida/Almuerzo
├── data/
│   ├── datasources/
│   │   ├── local/
│   │   │   └── database_helper.dart  # Inicialización SQLite + CRUD
│   │   └── remote/
│   │       └── api_service.dart      # HTTP calls al Node.js
│   ├── models/
│   │   ├── empleado_model.dart
│   │   ├── horario_model.dart
│   │   ├── registro_model.dart
│   │   ├── usuario_model.dart
│   │   ├── permiso_model.dart
│   │   └── configuracion_model.dart
│   └── repositories/
│       ├── empleado_repository.dart
│       ├── registro_repository.dart
│       ├── permiso_repository.dart
│       └── sincronizacion_repository.dart
├── domain/
│   ├── entities/
│   │   ├── empleado.dart
│   │   ├── horario.dart
│   │   ├── registro.dart
│   │   ├── usuario.dart
│   │   └── permiso.dart
│   └── usecases/
│       ├── registrar_empleado_usecase.dart   # Online: llama API → guarda local
│       ├── marcar_asistencia_usecase.dart    # Offline: face match → valida horario → registra
│       ├── registrar_permiso_usecase.dart
│       └── sincronizar_usecase.dart          # Sube registros no sincronizados
├── presentation/
│   ├── atoms/
│   │   ├── buttons/
│   │   │   ├── primary_button.dart
│   │   │   └── icon_button_atom.dart
│   │   ├── inputs/
│   │   │   ├── text_field_atom.dart
│   │   │   └── dropdown_atom.dart
│   │   ├── text/
│   │   │   ├── heading_text.dart
│   │   │   └── body_text.dart
│   │   ├── indicators/
│   │   │   ├── loading_indicator.dart
│   │   │   └── status_badge.dart
│   │   └── avatar/
│   │       └── face_avatar.dart
│   ├── molecules/
│   │   ├── employee_card.dart         # Tarjeta de empleado con foto y estado
│   │   ├── attendance_record_tile.dart # Fila de registro de asistencia
│   │   ├── camera_preview_widget.dart  # Preview cámara + overlay detección
│   │   ├── face_scan_widget.dart       # Widget completo de escaneo facial
│   │   ├── time_display.dart           # Reloj en tiempo real
│   │   ├── horario_badge.dart          # Badge de tipo: RETARDO/NORMAL/etc.
│   │   └── form_field_group.dart       # Label + input agrupados
│   ├── organisms/
│   │   ├── login_form.dart
│   │   ├── employee_registration_form.dart  # Form completo registro empleado
│   │   ├── attendance_list.dart             # Lista de registros del día
│   │   ├── employee_list.dart
│   │   ├── permission_form.dart             # Form de permisos
│   │   ├── sync_status_panel.dart           # Panel estado sincronización
│   │   └── main_navigation.dart             # Navegación lateral/inferior
│   ├── templates/
│   │   ├── auth_template.dart          # Layout para login
│   │   ├── dashboard_template.dart     # Layout principal con nav
│   │   ├── kiosk_template.dart         # Layout modo kiosco (totem)
│   │   └── admin_template.dart         # Layout administración
│   └── pages/
│       ├── splash/
│       │   └── splash_page.dart         # Inicialización + carga modelos ML
│       ├── login/
│       │   └── login_page.dart
│       ├── home/
│       │   └── home_page.dart           # Dashboard principal
│       ├── asistencia/
│       │   └── asistencia_page.dart     # Pantalla de marcado (modo kiosco)
│       ├── empleados/
│       │   ├── empleados_list_page.dart
│       │   └── empleado_detail_page.dart
│       ├── registro_empleado/
│       │   └── registro_empleado_page.dart  # Registro online con foto
│       ├── historial/
│       │   └── historial_page.dart
│       ├── horarios/
│       │   └── horarios_page.dart
│       ├── permisos/
│       │   └── permisos_page.dart
│       └── configuracion/
│           └── configuracion_page.dart      # URL API, sincronización, unidad negocio
└── services/
    ├── sync_service.dart        # Servicio background de sincronización periódica
    ├── face_recognition_service.dart  # ML Kit + comparación local de vectores
    └── connectivity_service.dart      # Monitor de conectividad
```

---

## Task 3: database_helper.dart

Crear todas las tablas SQLite con los campos del diagrama. Método `initDB()` que crea las 6 tablas. Incluir métodos de inserción, actualización, consulta y marcado de `sincronizado = false/true`.

---

## Task 4: Modelos y entidades

Un modelo por cada tabla (con `fromMap`, `toMap`, `fromJson`, `toJson`).

---

## Task 5: face_matcher.dart

Comparación local de vectores (distancia euclidiana en Dart) para marcar asistencia **offline** sin llamar a la API:
```dart
double euclideanDistance(List<double> v1, List<double> v2)
bool isMatch(List<double> stored, List<double> detected, {double threshold = 0.6})
```

---

## Task 6: horario_validator.dart

Lógica del diagrama de flujo:
- Si tipo LABORAL → validar horario → determinar: Retardo / Normal / Salida / Almuerzo
- Si hay permiso autorizado → Registrar con tipo PERMISO
- Si no tiene permiso → No registrar

---

## Task 7: Páginas principales (esqueleto)

Crear páginas con estructura básica:
- `splash_page.dart` - carga inicial, verifica DB, carga config
- `login_page.dart` - autenticación local con usuarios de SQLite
- `asistencia_page.dart` - pantalla principal del totem (cámara, reloj, resultado)
- `configuracion_page.dart` - URL API, frecuencia sync

---

## Task 8: main.dart y app.dart

Configurar:
- `sqflite_common_ffi` para Desktop en `main.dart`
- `MaterialApp` con tema, rutas GoRouter
- Provider para gestión de estado
- Detección de plataforma Android vs Desktop para ajustar UI

---

## Notas de arquitectura

- **Sincronización**: Los registros se guardan con `sincronizado = 0`. Un `SyncService` periódico sube los pendientes al servidor Node.js.
- **Reconocimiento offline**: Los vectores faciales (128 floats) se almacenan en SQLite como JSON. `face_matcher.dart` compara en Dart sin llamar a la API.
- **Registro de empleado**: Requiere internet. Llama a `POST /api/asistencia/nuevoEmpleado` → guarda empleado + vector en SQLite local.
- **Desktop vs Android**: `main.dart` detecta la plataforma e inicializa `sqflite_common_ffi` solo en Desktop/Windows.
