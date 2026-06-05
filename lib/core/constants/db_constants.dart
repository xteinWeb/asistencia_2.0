class DbConstants {
  static const String dbName = 'asistencia_empleados.db';
  static const int dbVersion = 10;


  // Table names
  static const String tableEmpleados = 'empleados';
  static const String tableHorarios = 'horarios';
  static const String tableRegistros = 'registros';
  static const String tableUsuarios = 'usuarios';
  static const String tablePermisos = 'permisos';
  static const String tableConfiguracion = 'configuracion';

  // Empleados columns
  static const String colCedula = 'cedula';
  static const String colNombre = 'nombre';
  static const String colMapaVectorFoto = 'mapa_vector_foto';
  static const String colHorarioId = 'horario_id';
  static const String colFechaIniContrato = 'fecha_ini_contrato';
  static const String colFechaFinContrato = 'fecha_fin_contrato';

  // Horarios columns
  static const String colIdHorario = 'id_horario';
  static const String colHoraInicio = 'hora_inicio';
  static const String colHoraFinal = 'hora_final';
  static const String colTipo = 'tipo';
  static const String colDias = 'dias';

  // Registros columns
  static const String colId = 'id';
  static const String colFechaHora = 'fecha_hora';
  static const String colEvento = 'evento';
  static const String colDuracion = 'duracion';
  static const String colUnidadNegocio = 'unidad_negocio';
  static const String colSincronizado = 'sincronizado';

  // Usuarios columns
  static const String colUsuario = 'usuario';
  static const String colContrasena = 'contrasena';
  static const String colRol = 'rol';
  static const String colEstado = 'estado';

  // Permisos columns
  static const String colUsuarioRegistrador = 'usuario_registrador';
  static const String colCedulaEmpleado = 'cedula_empleado';
  static const String colFechaInicio = 'fecha_inicio';
  static const String colFechaFinal = 'fecha_final';

  // Configuracion columns
  static const String colClave = 'clave';
  static const String colValor = 'valor';

  // Config keys
  static const String cfgUrlApi = 'url_api';
  static const String cfgFrecuenciaSync = 'frecuencia_sync';
  static const String cfgUnidadNegocio = 'unidad_negocio';
  static const String cfgUmbralFacial = 'umbral_facial';
  static const String cfgPermitirManual = 'permitir_manual';
}
