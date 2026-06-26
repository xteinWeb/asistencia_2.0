import uuid
import datetime
from typing import List, Optional
from fastapi import APIRouter, HTTPException
from database import get_db_connection
from models.schemas import (
    HorarioSyncItem, RegistroSyncItem, GenerarLltRequest, PermisoSyncItem,
    IncapacidadSyncItem, EmpleadoSyncItem, AusentismoSyncItem,
    ConvocatoriaSyncItem, ConvocatoriaEmpleadoSyncItem
)
from core.security import serialize_rows, serialize_row, serialize_value, format_datetime_for_sql

router = APIRouter(tags=["Sincronización de Datos (Kioskos)"])

# ─── HELPER FUNCTIONS ─────────────────────────────────────────────────────────

def generar_ausentismos_por_permisos(cursor):
    """Genera ausentismos automáticos basados en permisos_asistencia."""
    print("[Database] Generando ausentismos automáticos basados en permisos_asistencia...")
    try:
        cursor.execute("SELECT id, cedula_empleado, tipo, fecha_inicio, fecha_final FROM permisos_asistencia")
        permisos = cursor.fetchall() or []
        
        for p in permisos:
            cedula = p.get('cedula_empleado')
            tipo = p.get('tipo')
            f_ini = p.get('fecha_inicio')
            f_fin = p.get('fecha_final')
            
            if not cedula or not f_ini or not f_fin:
                continue
                
            if isinstance(f_ini, str):
                try:
                    dt_ini = datetime.datetime.fromisoformat(f_ini.replace(' ', 'T')).date()
                except Exception:
                    continue
            elif isinstance(f_ini, (datetime.datetime, datetime.date)):
                dt_ini = f_ini.date() if isinstance(f_ini, datetime.datetime) else f_ini
            else:
                continue
                
            if isinstance(f_fin, str):
                try:
                    dt_fin = datetime.datetime.fromisoformat(f_fin.replace(' ', 'T')).date()
                except Exception:
                    continue
            elif isinstance(f_fin, (datetime.datetime, datetime.date)):
                dt_fin = f_fin.date() if isinstance(f_fin, datetime.datetime) else f_fin
            else:
                continue
                
            curr = dt_ini
            while curr <= dt_fin:
                fecha_str = curr.strftime('%Y-%m-%d')
                
                cursor.execute(
                    "SELECT 1 FROM registros_asistencia WHERE cedula = %s AND evento = 'ENTRADA' AND fecha_hora LIKE %s",
                    (cedula, f"{fecha_str}%")
                )
                tiene_entrada = cursor.fetchone()
                
                if not tiene_entrada:
                    cursor.execute(
                        "SELECT id, sigla_ausencia FROM ausentismos WHERE cedula_empleado = %s AND fecha = %s",
                        (cedula, fecha_str)
                    )
                    existing_ausentismo = cursor.fetchone()
                    
                    if not existing_ausentismo:
                        new_id = str(uuid.uuid4()).upper()
                        cursor.execute(
                            """
                            INSERT INTO ausentismos (id, cedula_empleado, fecha, sigla_ausencia, observacion, fecha_registro_servidor)
                            VALUES (%s, %s, %s, 'PE', %s, GETDATE())
                            """,
                            (new_id, cedula, fecha_str, f"Permiso: {tipo}")
                        )
                        print(f"[Auto-Ausentismo] Creado PE para {cedula} en fecha {fecha_str}")
                    else:
                        sigla_existente = existing_ausentismo.get('sigla_ausencia') or existing_ausentismo.get('SIGLA_AUSENCIA')
                        id_existente = existing_ausentismo.get('id') or existing_ausentismo.get('ID')
                        if sigla_existente != 'PE':
                            cursor.execute(
                                "UPDATE ausentismos SET sigla_ausencia = 'PE', observacion = %s WHERE id = %s",
                                (f"Permiso: {tipo}", id_existente)
                            )
                            print(f"[Auto-Ausentismo] Actualizado a PE para {cedula} en fecha {fecha_str}")
                else:
                    cursor.execute(
                        "DELETE FROM ausentismos WHERE cedula_empleado = %s AND fecha = %s AND sigla_ausencia = 'PE'",
                        (cedula, fecha_str)
                    )
                
                curr += datetime.timedelta(days=1)
                
    except Exception as e:
        print(f"Error al generar ausentismos por permisos: {e}")

def generar_ausentismos_por_incapacidades(cursor):
    """Genera ausentismos automáticos basados en incapacidades_asistencia."""
    print("[Database] Generando ausentismos automáticos basados en incapacidades_asistencia...")
    try:
        cursor.execute("SELECT id, cedula_empleado, tipo, fecha_inicio, fecha_final FROM incapacidades_asistencia")
        incapacidades = cursor.fetchall() or []
        
        for p in incapacidades:
            cedula = p.get('cedula_empleado')
            tipo = p.get('tipo')
            f_ini = p.get('fecha_inicio')
            f_fin = p.get('fecha_final')
            
            if not cedula or not f_ini or not f_fin:
                continue
                
            if isinstance(f_ini, str):
                try:
                    dt_ini = datetime.datetime.fromisoformat(f_ini.replace(' ', 'T')).date()
                except Exception:
                    continue
            elif isinstance(f_ini, (datetime.datetime, datetime.date)):
                dt_ini = f_ini.date() if isinstance(f_ini, datetime.datetime) else f_ini
            else:
                continue
                
            if isinstance(f_fin, str):
                try:
                    dt_fin = datetime.datetime.fromisoformat(f_fin.replace(' ', 'T')).date()
                except Exception:
                    continue
            elif isinstance(f_fin, (datetime.datetime, datetime.date)):
                dt_fin = f_fin.date() if isinstance(f_fin, datetime.datetime) else f_fin
            else:
                continue
                
            curr = dt_ini
            while curr <= dt_fin:
                fecha_str = curr.strftime('%Y-%m-%d')
                
                cursor.execute(
                    "SELECT 1 FROM registros_asistencia WHERE cedula = %s AND evento = 'ENTRADA' AND fecha_hora LIKE %s",
                    (cedula, f"{fecha_str}%")
                )
                tiene_entrada = cursor.fetchone()
                
                if not tiene_entrada:
                    cursor.execute(
                        "SELECT id, sigla_ausencia FROM ausentismos WHERE cedula_empleado = %s AND fecha = %s",
                        (cedula, fecha_str)
                    )
                    existing_ausentismo = cursor.fetchone()
                    
                    sigla_target = 'EG'
                    if tipo:
                        tipo_upper = str(tipo).upper()
                        if 'ACCIDENTE' in tipo_upper:
                            sigla_target = 'AL'
                        elif 'MATERNIDAD' in tipo_upper or 'PATERNIDAD' in tipo_upper:
                            sigla_target = 'LM'
                        elif 'LICENCIA' in tipo_upper:
                            sigla_target = 'EL'
                    
                    if sigla_target not in ['EG', 'AL', 'EL', 'LM']:
                        sigla_target = 'EG'
                        
                    if not existing_ausentismo:
                        new_id = str(uuid.uuid4()).upper()
                        cursor.execute(
                            """
                            INSERT INTO ausentismos (id, cedula_empleado, fecha, sigla_ausencia, observacion, fecha_registro_servidor)
                            VALUES (%s, %s, %s, %s, %s, GETDATE())
                            """,
                            (new_id, cedula, fecha_str, sigla_target, f"Incapacidad: {tipo}")
                        )
                        print(f"[Auto-Ausentismo] Creado {sigla_target} para {cedula} en fecha {fecha_str}")
                    else:
                        sigla_existente = existing_ausentismo.get('sigla_ausencia') or existing_ausentismo.get('SIGLA_AUSENCIA')
                        id_existente = existing_ausentismo.get('id') or existing_ausentismo.get('ID')
                        if sigla_existente != sigla_target:
                            cursor.execute(
                                "UPDATE ausentismos SET sigla_ausencia = %s, observacion = %s WHERE id = %s",
                                (sigla_target, f"Incapacidad: {tipo}", id_existente)
                            )
                            print(f"[Auto-Ausentismo] Actualizado a {sigla_target} para {cedula} en fecha {fecha_str}")
                else:
                    cursor.execute(
                        "DELETE FROM ausentismos WHERE cedula_empleado = %s AND fecha = %s AND sigla_ausencia IN ('EG', 'AL', 'EL', 'LM')",
                        (cedula, fecha_str)
                    )
                
                curr += datetime.timedelta(days=1)
                
    except Exception as e:
        print(f"Error al generar ausentismos por incapacidades: {e}")


# ─── PULL ENDPOINTS (GETS) ───────────────────────────────────────────────────

@router.get(
    "/api/sync/horarios",
    summary="Descargar Horarios Master y Detalles",
    description="Devuelve la programación y rangos horarios de todos los turnos disponibles para los Kioskos."
)
def obtener_horarios():
    print("\n--- [GET /api/sync/horarios] Solicitud de sincronización ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        cursor.execute("SELECT ID_UN, ID_HORARIO, DESCRIPCION, ESTADO FROM horarios")
        horarios_rows = cursor.fetchall()
        
        cursor.execute("""
            SELECT ID_UN, ITEM, ID_HORARIO, INICIO, FINAL, 
                   LUNES, MARTES, MIERCOLES, JUEVES, VIERNES, SABADO, DOMINGO, TIPO 
            FROM itm_horarios
        """)
        items_rows = cursor.fetchall()
        conn.close()
        
        def parse_time(val):
            if val is None:
                return ""
            if isinstance(val, (datetime.datetime, datetime.time)):
                return val.strftime("%H:%M:%S")
            val_str = str(val).strip()
            if " " in val_str:
                val_str = val_str.split(" ")[-1]
            if "T" in val_str:
                val_str = val_str.split("T")[-1]
            if "." in val_str:
                val_str = val_str.split(".")[0]
            return val_str

        items_by_schedule = {}
        for item in items_rows:
            id_horario = str(item["ID_HORARIO"]).strip()
            cleaned_item = {
                "item": int(item["ITEM"]),
                "inicio": parse_time(item["INICIO"]),
                "final": parse_time(item["FINAL"]),
                "lunes": int(item["LUNES"]),
                "martes": int(item["MARTES"]),
                "miercoles": int(item["MIERCOLES"]),
                "jueves": int(item["JUEVES"]),
                "viernes": int(item["VIERNES"]),
                "sabado": int(item["SABADO"]),
                "domingo": int(item["DOMINGO"]),
                "tipo": str(item["TIPO"]).strip()
            }
            if id_horario not in items_by_schedule:
                items_by_schedule[id_horario] = []
            items_by_schedule[id_horario].append(cleaned_item)
            
        schedules_list = []
        for h in horarios_rows:
            id_horario = str(h["ID_HORARIO"]).strip()
            items = items_by_schedule.get(id_horario, [])
            items.sort(key=lambda x: x["item"])
            
            schedules_list.append({
                "id_horario": id_horario,
                "descripcion": str(h["DESCRIPCION"]).strip() if h["DESCRIPCION"] else "",
                "estado": str(h["ESTADO"]).strip() if h["ESTADO"] else "ACTIVO",
                "items": items
            })
            
        return {
            "success": True,
            "data": schedules_list
        }
    except Exception as e:
        print(f"Error en obtener_horarios: {e}")
        raise HTTPException(status_code=500, detail=f"Error al obtener horarios desde SQL Server: {e}")

@router.get(
    "/api/sync/usuarios",
    summary="Descargar Usuarios Kiosko",
    description="Devuelve los operadores, roles y credenciales válidas para iniciar sesión en los dispositivos."
)
def obtener_usuarios():
    print("\n--- [GET /api/sync/usuarios] Solicitud de Sincronización ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        cursor.execute("SELECT usuario, nombre, contrasena, rol, estado, unidad_negocio FROM usuarios_asistencia")
        rows = cursor.fetchall()
        conn.close()
        
        return {
            "success": True,
            "data": serialize_rows(rows)
        }
    except Exception as e:
        print(f"Error en obtener_usuarios: {e}")
        raise HTTPException(status_code=500, detail=f"Error al obtener usuarios desde SQL Server: {e}")

@router.get(
    "/api/sync/empleados",
    summary="Sincronizar Listado General de Empleados",
    description="Corre el cruce de estados ERP (empleados), actualiza y devuelve el listado maestro de empleados activos."
)
def obtener_empleados():
    print("\n--- [GET /api/sync/empleados] Solicitud de Sincronización ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        
        # 1. Sincronizar estados inactivos desde 'empleados' (ERP) a 'empleados_asistencia'
        cursor.execute("""
            UPDATE ea
            SET ea.estado = 'INACTIVO'
            FROM empleados_asistencia ea
            INNER JOIN empleados emp ON ea.cedula = emp.ID_EMPLEADO
            WHERE emp.ESTADO = 'INACTIVO' AND ea.estado <> 'INACTIVO'
        """)
        
        # 2. Sincronizar estados activos desde 'empleados' (ERP) a 'empleados_asistencia'
        cursor.execute("""
            UPDATE ea
            SET ea.estado = 'ACTIVO'
            FROM empleados_asistencia ea
            INNER JOIN empleados emp ON ea.cedula = emp.ID_EMPLEADO
            WHERE emp.ESTADO = 'ACTIVO' AND ea.estado <> 'ACTIVO'
        """)
        
        # 3. Insertar nuevos empleados activos en 'empleados_asistencia'
        cursor.execute("""
            INSERT INTO empleados_asistencia (cedula, nombre, estado, fecha_creacion)
            SELECT 
                emp.ID_EMPLEADO,
                LTRIM(RTRIM(
                    COALESCE(il.NOMBRE, '') + ' ' + 
                    COALESCE(il.NOMBRE2, '') + ' ' + 
                    COALESCE(il.APELLIDO, '') + ' ' + 
                    COALESCE(il.APELLIDO2, '')
                )),
                'ACTIVO',
                GETDATE()
            FROM empleados emp
            INNER JOIN IDENTIFICACIONES_LEGALES il ON emp.ID_LEGAL = il.ID_LEGAL
            WHERE COALESCE(emp.ESTADO, 'ACTIVO') = 'ACTIVO'
              AND emp.ID_EMPLEADO NOT IN (SELECT cedula FROM empleados_asistencia)
        """)
        
        # 4. Obtener la lista unificada de empleados con horarios de ITM_EMPLEADOS_TURNOS
        cursor.execute("""
            SELECT 
                COALESCE(LTRIM(RTRIM(emp.ID_EMPLEADO)), LTRIM(RTRIM(ea.cedula))) AS cedula,
                COALESCE(
                    LTRIM(RTRIM(
                        COALESCE(il.NOMBRE, '') + ' ' + 
                        COALESCE(il.NOMBRE2, '') + ' ' + 
                        COALESCE(il.APELLIDO, '') + ' ' + 
                        COALESCE(il.APELLIDO2, '')
                    )), 
                    ea.nombre, 
                    ''
                ) AS nombre,
                ea.mapa_vector_foto AS mapa_vector_foto,
                COALESCE(turn.ID_HORARIO, ea.horario_id, '') AS horario_id,
                COALESCE(ea.fecha_ini_contrato, '0') AS fecha_ini_contrato,
                COALESCE(ea.fecha_fin_contrato, '0') AS fecha_fin_contrato,
                COALESCE(emp.ESTADO, ea.estado, 'ACTIVO') AS estado,
                COALESCE(ea.sede_principal, emp.ID_UN_ITEM, '') AS sede_principal,
                ies.ID_SECCION AS id_seccion,
                COALESCE(ea.tipo, ies.ID_ACTIVIDAD, '') AS tipo,
                ea.fecha_creacion AS fecha_registro
            FROM empleados emp
            FULL OUTER JOIN empleados_asistencia ea ON LTRIM(RTRIM(emp.ID_EMPLEADO)) = LTRIM(RTRIM(ea.cedula))
            LEFT JOIN IDENTIFICACIONES_LEGALES il ON (emp.ID_LEGAL = il.ID_LEGAL OR TRY_CAST(COALESCE(emp.ID_EMPLEADO, ea.cedula) AS FLOAT) = il.ID_LEGAL)
            LEFT JOIN empleados_secciones es ON COALESCE(LTRIM(RTRIM(emp.ID_EMPLEADO)), LTRIM(RTRIM(ea.cedula))) = LTRIM(RTRIM(es.ID_EMPLEADO)) AND COALESCE(emp.ID_UN, ea.sede_principal, '00') = es.ID_UN
            LEFT JOIN (
                SELECT LTRIM(RTRIM(ID_EMPLEADO)) AS ID_EMPLEADO, ID_UN, MAX(ID_SECCION) AS ID_SECCION, MAX(ID_ACTIVIDAD) AS ID_ACTIVIDAD
                FROM itm_empleados_Secciones
                WHERE TIPO = 'PRINCIPAL'
                GROUP BY LTRIM(RTRIM(ID_EMPLEADO)), ID_UN
            ) ies ON COALESCE(LTRIM(RTRIM(emp.ID_EMPLEADO)), LTRIM(RTRIM(ea.cedula))) = ies.ID_EMPLEADO AND COALESCE(emp.ID_UN, '00') = ies.ID_UN
            LEFT JOIN (
                SELECT t.ID_EMPLEADO, MAX(t.ID_HORARIO) AS ID_HORARIO
                FROM ITM_EMPLEADOS_TURNOS t
                INNER JOIN (
                    SELECT ID_EMPLEADO, MAX(FECHA) AS MAX_FECHA
                    FROM ITM_EMPLEADOS_TURNOS
                    WHERE ESTADO = 'ACTIVO'
                    GROUP BY ID_EMPLEADO
                ) latest ON t.ID_EMPLEADO = latest.ID_EMPLEADO AND t.FECHA = latest.MAX_FECHA
                GROUP BY t.ID_EMPLEADO
            ) turn ON COALESCE(LTRIM(RTRIM(emp.ID_EMPLEADO)), LTRIM(RTRIM(ea.cedula))) = turn.ID_EMPLEADO
            WHERE COALESCE(emp.ESTADO, ea.estado, 'ACTIVO') = 'ACTIVO'
        """)
        rows = cursor.fetchall()
        conn.close()
        
        return {
            "success": True,
            "data": serialize_rows(rows)
        }
    except Exception as e:
        print(f"Error en obtener_empleados: {e}")
        raise HTTPException(status_code=500, detail=f"Error al obtener empleados desde SQL Server: {e}")

@router.get(
    "/api/sync/permisos",
    summary="Descargar Permisos",
    description="Devuelve todos los permisos registrados centralmente."
)
def obtener_permisos():
    print("\n--- [GET /api/sync/permisos] Solicitud de Sincronización ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        cursor.execute("SELECT id, usuario_registrador, cedula_empleado, fecha_hora, tipo, fecha_inicio, fecha_final, observacion FROM permisos_asistencia")
        rows = cursor.fetchall()
        conn.close()
        return {
            "success": True,
            "data": serialize_rows(rows)
        }
    except Exception as e:
        print(f"Error en obtener_permisos: {e}")
        raise HTTPException(status_code=500, detail=f"Error al obtener permisos desde SQL Server: {e}")

@router.get(
    "/api/sync/incapacidades",
    summary="Descargar Incapacidades",
    description="Devuelve todas las incapacidades registradas centralmente."
)
def obtener_incapacidades():
    print("\n--- [GET /api/sync/incapacidades] Solicitud de Sincronización ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        cursor.execute("SELECT id, usuario_registrador, cedula_empleado, fecha_hora, tipo, fecha_inicio, fecha_final, observacion FROM incapacidades_asistencia")
        rows = cursor.fetchall()
        conn.close()
        return {
            "success": True,
            "data": serialize_rows(rows)
        }
    except Exception as e:
        print(f"Error en obtener_incapacidades: {e}")
        raise HTTPException(status_code=500, detail=f"Error al obtener incapacidades desde SQL Server: {e}")

@router.get(
    "/api/sync/registros",
    summary="Descargar Registros de Asistencia",
    description="Obtiene los registros de asistencia de los últimos 30 días para sincronización local."
)
def obtener_registros():
    print("\n--- [GET /api/sync/registros] Solicitud de Sincronización (Últimos 30 días) ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        cursor.execute("""
            SELECT id, fecha_hora, cedula, evento, duracion, tipo, unidad_negocio, metodo_registro 
            FROM registros_asistencia 
            WHERE fecha_registro_servidor >= DATEADD(day, -30, GETDATE()) 
            ORDER BY fecha_hora DESC
        """)
        rows = cursor.fetchall()
        conn.close()
        return {
            "success": True,
            "data": serialize_rows(rows)
        }
    except Exception as e:
        print(f"Error en obtener_registros: {e}")
        raise HTTPException(status_code=500, detail=f"Error al obtener registros desde SQL Server: {e}")

@router.get(
    "/api/sync/ausentismos",
    summary="Descargar Ausentismos",
    description="Lanza la autogeneración por permisos/incapacidades y devuelve la lista de ausentismos."
)
def obtener_ausentismos():
    print("\n--- [GET /api/sync/ausentismos] Solicitud de Sincronización de Ausentismos ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        generar_ausentismos_por_permisos(cursor)
        generar_ausentismos_por_incapacidades(cursor)
        cursor.execute("SELECT id, cedula_empleado, fecha, sigla_ausencia, observacion FROM ausentismos")
        rows = cursor.fetchall()
        conn.close()
        return {
            "success": True,
            "data": serialize_rows(rows)
        }
    except Exception as e:
        print(f"Error en obtener_ausentismos: {e}")
        raise HTTPException(status_code=500, detail=f"Error al obtener ausentismos: {e}")

@router.get(
    "/api/sync/convocatorias",
    summary="Descargar Convocatorias",
    description="Devuelve el catálogo de programaciones y convocatorias registradas en el servidor."
)
def obtener_convocatorias():
    print("\n--- [GET /api/sync/convocatorias] Solicitud de Sincronización ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        cursor.execute("SELECT id, fecha, hora_inicio, hora_final, descripcion FROM programacion_asistencia")
        rows = cursor.fetchall()
        conn.close()
        return {
            "success": True,
            "data": serialize_rows(rows)
        }
    except Exception as e:
        print(f"Error en obtener_convocatorias: {e}")
        raise HTTPException(status_code=500, detail=f"Error al obtener convocatorias desde SQL Server: {e}")

@router.get(
    "/api/sync/convocatoria-empleados",
    summary="Descargar Empleados Convocados",
    description="Devuelve la lista de empleados asignados a las distintas convocatorias junto con su estado de asistencia."
)
def obtener_convocatoria_empleados():
    print("\n--- [GET /api/sync/convocatoria-empleados] Solicitud de Sincronización ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        cursor.execute("SELECT convocatoria_id, cedula_empleado, asistio, fecha_hora_asistencia FROM itm_programacion_asistencia")
        rows = cursor.fetchall()
        conn.close()
        return {
            "success": True,
            "data": serialize_rows(rows)
        }
    except Exception as e:
        print(f"Error en obtener_convocatoria_empleados: {e}")
        raise HTTPException(status_code=500, detail=f"Error al obtener asignaciones de convocatoria: {e}")


# ─── PUSH ENDPOINTS (POSTS & DELETES) ────────────────────────────────────────

@router.post(
    "/api/sync/registros",
    summary="Subir Marcaciones de Asistencia",
    description="Recibe los registros de entrada y salida tomados localmente por la tableta y los inserta de forma segura."
)
def sincronizar_registros(listado: List[RegistroSyncItem]):
    print(f"\n--- [POST /api/sync/registros] Sincronizando {len(listado)} registros ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        inserted = 0
        ignored = 0
        
        for r in listado:
            cursor.execute("SELECT 1 FROM empleados_asistencia WHERE cedula = %s", (r.cedula,))
            if not cursor.fetchone():
                print(f"[Sync Registros] Empleado {r.cedula} no existe centralmente. Registrando empleado básico.")
                cursor.execute(
                    "INSERT INTO empleados_asistencia (cedula, nombre, estado, fecha_creacion) VALUES (%s, %s, 'ACTIVO', GETDATE())",
                    (r.cedula, f"Empleado ({r.cedula})")
                )
            
            cursor.execute("SELECT 1 FROM registros_asistencia WHERE id = %s", (r.id,))
            if not cursor.fetchone():
                cursor.execute("""
                    INSERT INTO registros_asistencia (id, fecha_hora, cedula, evento, duracion, tipo, unidad_negocio, metodo_registro, fecha_registro_servidor)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, GETDATE())
                """, (r.id, r.fecha_hora, r.cedula, r.evento, r.duracion, r.tipo, r.unidad_negocio, r.metodo_registro))
                inserted += 1
            else:
                ignored += 1
                
        cursor_dict = conn.cursor(as_dict=True)
        generar_ausentismos_por_permisos(cursor_dict)
        generar_ausentismos_por_incapacidades(cursor_dict)
        conn.close()
        print(f"[Sync Registros] Completado. Insertados: {inserted}, Omitidos (Duplicados): {ignored}")
        return {
            "success": True,
            "message": "Sincronización de registros completada.",
            "sincronizados": inserted,
            "omitidos": ignored
        }
    except Exception as e:
        print(f"Error en sincronizar_registros: {e}")
        raise HTTPException(status_code=500, detail=f"Error al sincronizar registros en SQL Server: {e}")

@router.post(
    "/api/sync/generar-llt",
    summary="Generar Ausentismo LLT Manualmente",
    description="Procesa los retardos de una fecha dada y genera las novedades de ausentismo tipo Llegada Tarde (LLT)."
)
def generar_llt_manual(req: GenerarLltRequest):
    print(f"\n--- [POST /api/sync/generar-llt] Generando novedades LLT manuales para fecha: {req.fecha} ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        
        cursor.execute(
            "SELECT cedula, duracion FROM registros_asistencia WHERE evento = 'ENTRADA' AND tipo = 'RETARDO' AND fecha_hora LIKE %s",
            (f"{req.fecha}%",)
        )
        registros = cursor.fetchall() or []
        
        generados = 0
        actualizados = 0
        
        for r in registros:
            cedula = r.get('cedula') or r.get('CEDULA')
            duracion = r.get('duracion') or r.get('DURACION')
            
            cursor.execute(
                "SELECT id FROM ausentismos WHERE cedula_empleado = %s AND fecha = %s AND sigla_ausencia = 'LLT'",
                (cedula, req.fecha)
            )
            existing = cursor.fetchone()
            obs = f"Retardo: {duracion}" if duracion else "Retardo"
            
            if not existing:
                new_id = str(uuid.uuid4()).upper()
                cursor.execute(
                    """
                    INSERT INTO ausentismos (id, cedula_empleado, fecha, sigla_ausencia, observacion, fecha_registro_servidor)
                    VALUES (%s, %s, %s, 'LLT', %s, GETDATE())
                    """,
                    (new_id, cedula, req.fecha, obs)
                )
                generados += 1
            else:
                existing_id = existing.get('id') or existing.get('ID')
                cursor.execute(
                    "UPDATE ausentismos SET observacion = %s WHERE id = %s",
                    (obs, existing_id)
                )
                actualizados += 1
                
        conn.close()
        return {
            "success": True,
            "message": f"Procesamiento completado. Generados: {generados}, Actualizados: {actualizados}",
            "generados": generados,
            "actualizados": actualizados
        }
    except Exception as e:
        print(f"Error en generar_llt_manual: {e}")
        raise HTTPException(status_code=500, detail=f"Error al generar LLT manual: {e}")

@router.post(
    "/api/sync/permisos",
    summary="Subir Permisos",
    description="Sincroniza y guarda los permisos registrados localmente en el Kiosko."
)
def sincronizar_permisos(listado: List[PermisoSyncItem]):
    print(f"\n--- [POST /api/sync/permisos] Sincronizando {len(listado)} permisos ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        inserted = 0
        ignored = 0
        
        for p in listado:
            cursor.execute("SELECT 1 FROM empleados_asistencia WHERE cedula = %s", (p.cedula_empleado,))
            if not cursor.fetchone():
                print(f"[Sync Permisos] Empleado {p.cedula_empleado} no existe. Registrando básico.")
                cursor.execute(
                    "INSERT INTO empleados_asistencia (cedula, nombre, estado, fecha_creacion) VALUES (%s, %s, 'ACTIVO', GETDATE())",
                    (p.cedula_empleado, f"Empleado ({p.cedula_empleado})")
                )
            
            cursor.execute("SELECT 1 FROM permisos_asistencia WHERE id = %s", (p.id,))
            if not cursor.fetchone():
                cursor.execute("""
                    INSERT INTO permisos_asistencia (id, usuario_registrador, cedula_empleado, fecha_hora, tipo, fecha_inicio, fecha_final, observacion, fecha_registro_servidor)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, GETDATE())
                """, (p.id, p.usuario_registrador, p.cedula_empleado, p.fecha_hora, p.tipo, p.fecha_inicio, p.fecha_final, p.observacion))
                inserted += 1
            else:
                cursor.execute("""
                    UPDATE permisos_asistencia
                    SET usuario_registrador = %s,
                        cedula_empleado = %s,
                        fecha_hora = %s,
                        tipo = %s,
                        fecha_inicio = %s,
                        fecha_final = %s,
                        observacion = %s
                    WHERE id = %s
                """, (p.usuario_registrador, p.cedula_empleado, p.fecha_hora, p.tipo, p.fecha_inicio, p.fecha_final, p.observacion, p.id))
                ignored += 1
                
        cursor_dict = conn.cursor(as_dict=True)
        generar_ausentismos_por_permisos(cursor_dict)
        conn.close()
        print(f"[Sync Permisos] Completado. Insertados: {inserted}, Omitidos: {ignored}")
        return {
            "success": True,
            "message": "Sincronización de permisos completada.",
            "sincronizados": inserted,
            "omitidos": ignored
        }
    except Exception as e:
        print(f"Error en sincronizar_permisos: {e}")
        raise HTTPException(status_code=500, detail=f"Error al sincronizar permisos en SQL Server: {e}")

@router.post(
    "/api/sync/incapacidades",
    summary="Subir Incapacidades",
    description="Sincroniza y guarda las incapacidades registradas localmente en el Kiosko."
)
def sincronizar_incapacidades(listado: List[IncapacidadSyncItem]):
    print(f"\n--- [POST /api/sync/incapacidades] Sincronizando {len(listado)} incapacidades ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        inserted = 0
        ignored = 0
        
        for p in listado:
            cursor.execute("SELECT 1 FROM empleados_asistencia WHERE cedula = %s", (p.cedula_empleado,))
            if not cursor.fetchone():
                print(f"[Sync Incapacidades] Empleado {p.cedula_empleado} no existe. Registrando básico.")
                cursor.execute(
                    "INSERT INTO empleados_asistencia (cedula, nombre, estado, fecha_creacion) VALUES (%s, %s, 'ACTIVO', GETDATE())",
                    (p.cedula_empleado, f"Empleado ({p.cedula_empleado})")
                )
            
            cursor.execute("SELECT 1 FROM incapacidades_asistencia WHERE id = %s", (p.id,))
            if not cursor.fetchone():
                cursor.execute("""
                    INSERT INTO incapacidades_asistencia (id, usuario_registrador, cedula_empleado, fecha_hora, tipo, fecha_inicio, fecha_final, observacion, fecha_registro_servidor)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, GETDATE())
                """, (p.id, p.usuario_registrador, p.cedula_empleado, p.fecha_hora, p.tipo, p.fecha_inicio, p.fecha_final, p.observacion))
                inserted += 1
            else:
                cursor.execute("""
                    UPDATE incapacidades_asistencia
                    SET usuario_registrador = %s,
                        cedula_empleado = %s,
                        fecha_hora = %s,
                        tipo = %s,
                        fecha_inicio = %s,
                        fecha_final = %s,
                        observacion = %s
                    WHERE id = %s
                """, (p.usuario_registrador, p.cedula_empleado, p.fecha_hora, p.tipo, p.fecha_inicio, p.fecha_final, p.observacion, p.id))
                ignored += 1
                
        cursor_dict = conn.cursor(as_dict=True)
        generar_ausentismos_por_incapacidades(cursor_dict)
        conn.close()
        print(f"[Sync Incapacidades] Completado. Insertados: {inserted}, Omitidos: {ignored}")
        return {
            "success": True,
            "message": "Sincronización de incapacidades completada.",
            "sincronizados": inserted,
            "omitidos": ignored
        }
    except Exception as e:
        print(f"Error en sincronizar_incapacidades: {e}")
        raise HTTPException(status_code=500, detail=f"Error al sincronizar incapacidades en SQL Server: {e}")

@router.post(
    "/api/sync/empleados",
    summary="Subir Enrolamiento y Edición de Empleados",
    description="Sincroniza y mergea firmas biométricas y detalles de empleados modificados en el Kiosko con SQL Server."
)
def sincronizar_empleados(listado: List[EmpleadoSyncItem]):
    print(f"\n--- [POST /api/sync/empleados] Sincronizando {len(listado)} enrolamientos locales ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        processed = 0
        for emp in listado:
            query = """
            DECLARE @cedula VARCHAR(50) = %s;
            DECLARE @nombre VARCHAR(150) = %s;
            DECLARE @mapaVectorFoto VARCHAR(MAX) = %s;
            DECLARE @horarioId VARCHAR(50) = %s;
            DECLARE @fechaIniContrato VARCHAR(20) = %s;
            DECLARE @fechaFinContrato VARCHAR(20) = %s;
            DECLARE @estado VARCHAR(20) = %s;
            DECLARE @sedePrincipal VARCHAR(150) = %s;
            DECLARE @idSeccion VARCHAR(50) = %s;
            DECLARE @tipo VARCHAR(30) = %s;
            DECLARE @fechaRegistro VARCHAR(30) = %s;

            MERGE empleados_asistencia AS target
            USING (SELECT @cedula AS cedula) AS source
            ON (target.cedula = source.cedula)
            WHEN MATCHED THEN
                UPDATE SET 
                    nombre = @nombre,
                    mapa_vector_foto = COALESCE(@mapaVectorFoto, target.mapa_vector_foto),
                    horario_id = @horarioId,
                    fecha_ini_contrato = @fechaIniContrato,
                    fecha_fin_contrato = @fechaFinContrato,
                    estado = COALESCE(@estado, target.estado),
                    sede_principal = @sedePrincipal,
                    id_seccion = @idSeccion,
                    tipo = @tipo,
                    fecha_creacion = COALESCE(@fechaRegistro, target.fecha_creacion)
            WHEN NOT MATCHED THEN
                INSERT (cedula, nombre, mapa_vector_foto, horario_id, fecha_ini_contrato, fecha_fin_contrato, estado, sede_principal, id_seccion, tipo, fecha_creacion)
                VALUES (@cedula, @nombre, @mapaVectorFoto, @horarioId, @fechaIniContrato, @fechaFinContrato, @estado, @sedePrincipal, @idSeccion, @tipo, COALESCE(@fechaRegistro, GETDATE()));
            """
            
            h_id = emp.horario_id if emp.horario_id and emp.horario_id.strip() not in ("", "None") else None
            fecha_ini = emp.fecha_ini_contrato if emp.fecha_ini_contrato and emp.fecha_ini_contrato.strip() not in ("", "0", "None") else None
            fecha_fin = emp.fecha_fin_contrato if emp.fecha_fin_contrato and emp.fecha_fin_contrato.strip() not in ("", "0", "None") else None
            fecha_reg = format_datetime_for_sql(emp.fecha_registro)
            sede = emp.sede_principal if emp.sede_principal and emp.sede_principal.strip() not in ("", "None") else None
            seccion = emp.id_seccion if emp.id_seccion and emp.id_seccion.strip() not in ("", "None") else None
            tipo = emp.tipo if emp.tipo and emp.tipo.strip() not in ("", "None") else None
            estado = emp.estado if emp.estado and emp.estado.strip() not in ("", "None") else None
            
            cursor.execute(query, (
                emp.cedula,
                emp.nombre,
                emp.mapa_vector_foto,
                h_id,
                fecha_ini,
                fecha_fin,
                estado,
                sede,
                seccion,
                tipo,
                fecha_reg
            ))
            
            if emp.tipo:
                query_tipo = """
                DECLARE @cedula VARCHAR(50) = %s;
                DECLARE @tipo VARCHAR(30) = %s;

                MERGE empleados_tipo AS target
                USING (SELECT @cedula AS cedula) AS source
                ON (target.cedula = source.cedula)
                WHEN MATCHED THEN
                    UPDATE SET tipo = @tipo
                WHEN NOT MATCHED THEN
                    INSERT (cedula, tipo)
                    VALUES (@cedula, @tipo);
                """
                cursor.execute(query_tipo, (emp.cedula, emp.tipo))

            processed += 1
            
        conn.close()
        print(f"[Sync Empleados] Procesados {processed} enrolamientos biométricos.")
        return {
            "success": True,
            "message": "Sincronización de empleados/enrolamientos completada.",
            "procesados": processed
        }
    except Exception as e:
        print(f"Error en sincronizar_empleados: {e}")
        raise HTTPException(status_code=500, detail=f"Error al sincronizar enrolamientos en SQL Server: {e}")

@router.post(
    "/api/sync/horarios",
    summary="Subir Horarios de Kiosko",
    description="Sincroniza y mergea configuraciones de horarios y turnos locales."
)
def sincronizar_horarios(listado: List[HorarioSyncItem]):
    print(f"\n--- [POST /api/sync/horarios] Sincronizando {len(listado)} horarios ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        processed = 0
        for h in listado:
            query = """
            DECLARE @idHorario VARCHAR(50) = %s;
            DECLARE @horaInicio VARCHAR(10) = %s;
            DECLARE @horaFinal VARCHAR(10) = %s;
            DECLARE @tipo VARCHAR(30) = %s;
            DECLARE @dias VARCHAR(100) = %s;

            MERGE horarios_asistencia AS target
            USING (SELECT @idHorario AS id_horario) AS source
            ON (target.id_horario = source.id_horario)
            WHEN MATCHED THEN
                UPDATE SET 
                    hora_inicio = @horaInicio,
                    hora_final = @horaFinal,
                    tipo = @tipo,
                    dias = @dias
            WHEN NOT MATCHED THEN
                INSERT (id_horario, hora_inicio, hora_final, tipo, dias)
                VALUES (@idHorario, @horaInicio, @horaFinal, @tipo, @dias);
            """
            cursor.execute(query, (h.id_horario, h.hora_inicio, h.hora_final, h.tipo, h.dias))
            processed += 1
            
        conn.close()
        print(f"[Sync Horarios] Procesados {processed} horarios.")
        return {
            "success": True,
            "message": "Sincronización de horarios completada.",
            "procesados": processed
        }
    except Exception as e:
        print(f"Error en sincronizar_horarios: {e}")
        raise HTTPException(status_code=500, detail=f"Error al sincronizar horarios: {e}")

@router.delete(
    "/api/sync/empleados/{cedula}",
    summary="Inactivar/Dar de Baja Colaborador",
    description="Realiza baja lógica de un empleado (marcando estado a 'INACTIVO' tanto en cabecera como en secciones)."
)
def eliminar_empleado(cedula: str):
    print(f"\n--- [DELETE /api/sync/empleados/{cedula}] Inactivando empleado ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("UPDATE empleados_asistencia SET estado = 'INACTIVO' WHERE cedula = %s", (cedula,))
        cursor.execute("UPDATE empleados_secciones SET ESTADO = 'INACTIVO' WHERE ID_EMPLEADO = %s", (cedula,))
        conn.close()
        print(f"[Inactivar] Empleado con cédula {cedula} marcado como INACTIVO en SQL Server.")
        return {
            "success": True,
            "message": "Empleado marcado como INACTIVO con éxito en SQL Server."
        }
    except Exception as e:
        print(f"Error en eliminar_empleado: {e}")
        raise HTTPException(status_code=500, detail=f"Error al inactivar empleado en SQL Server: {e}")

@router.post(
    "/api/sync/ausentismos",
    summary="Subir Novedades de Ausentismo",
    description="Registra novedades de ausentismo (Llegadas tarde, vacaciones, etc.) capturadas localmente."
)
def sincronizar_ausentismos(listado: List[AusentismoSyncItem]):
    print(f"\n--- [POST /api/sync/ausentismos] Sincronizando {len(listado)} ausentismos locales ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        processed = 0
        for item in listado:
            cursor.execute("SELECT 1 FROM empleados_asistencia WHERE cedula = %s", (item.cedula_empleado,))
            if not cursor.fetchone():
                print(f"[Sync Ausentismos] Empleado {item.cedula_empleado} no existe. Registrando básico.")
                cursor.execute(
                    "INSERT INTO empleados_asistencia (cedula, nombre, estado, fecha_creacion) VALUES (%s, %s, 'ACTIVO', GETDATE())",
                    (item.cedula_empleado, f"Empleado ({item.cedula_empleado})")
                )
                
            query = """
            DECLARE @id VARCHAR(50) = %s;
            DECLARE @cedula_empleado VARCHAR(50) = %s;
            DECLARE @fecha VARCHAR(10) = %s;
            DECLARE @sigla_ausencia VARCHAR(10) = %s;
            DECLARE @observacion VARCHAR(500) = %s;

            MERGE ausentismos AS target
            USING (SELECT @id AS id) AS source
            ON (target.id = source.id)
            WHEN MATCHED THEN
                UPDATE SET 
                    cedula_empleado = @cedula_empleado,
                    fecha = @fecha,
                    sigla_ausencia = @sigla_ausencia,
                    observacion = @observacion
            WHEN NOT MATCHED THEN
                INSERT (id, cedula_empleado, fecha, sigla_ausencia, observacion, fecha_registro_servidor)
                VALUES (@id, @cedula_empleado, @fecha, @sigla_ausencia, @observacion, GETDATE());
            """
            cursor.execute(query, (item.id, item.cedula_empleado, item.fecha, item.sigla_ausencia, item.observacion))
            processed += 1
            
        cursor_dict = conn.cursor(as_dict=True)
        generar_ausentismos_por_permisos(cursor_dict)
        generar_ausentismos_por_incapacidades(cursor_dict)
        conn.close()
        print(f"[Sync Ausentismos] Procesados {processed} registros de ausentismo.")
        return {
            "success": True,
            "message": "Sincronización de ausentismos completada.",
            "procesados": processed
        }
    except Exception as e:
        print(f"Error en sincronizar_ausentismos: {e}")
        raise HTTPException(status_code=500, detail=f"Error al sincronizar ausentismos: {e}")

@router.delete(
    "/api/sync/ausentismos/{id}",
    summary="Eliminar Registro de Ausentismo",
    description="Elimina una novedad de ausentismo del servidor central."
)
def eliminar_ausentismo(id: str):
    print(f"\n--- [DELETE /api/sync/ausentismos/{id}] Eliminando ausentismo ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM ausentismos WHERE id = %s", (id,))
        conn.close()
        print(f"[Eliminar Ausentismo] Registro {id} eliminado de SQL Server.")
        return {
            "success": True,
            "message": "Registro de ausentismo eliminado con éxito."
        }
    except Exception as e:
        print(f"Error en eliminar_ausentismo: {e}")
        raise HTTPException(status_code=500, detail=f"Error al eliminar ausentismo en SQL Server: {e}")

@router.post(
    "/api/sync/convocatorias",
    summary="Subir Convocatorias",
    description="Sincroniza programaciones de convocatorias."
)
def sincronizar_convocatorias(listado: List[ConvocatoriaSyncItem]):
    print(f"\n--- [POST /api/sync/convocatorias] Sincronizando {len(listado)} convocatorias ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        processed = 0
        for c in listado:
            query = """
            DECLARE @id VARCHAR(50) = %s;
            DECLARE @fecha VARCHAR(10) = %s;
            DECLARE @hora_inicio VARCHAR(10) = %s;
            DECLARE @hora_final VARCHAR(10) = %s;
            DECLARE @descripcion VARCHAR(250) = %s;

            MERGE programacion_asistencia AS target
            USING (SELECT @id AS id) AS source
            ON (target.id = source.id)
            WHEN MATCHED THEN
                UPDATE SET 
                    fecha = @fecha,
                    hora_inicio = @hora_inicio,
                    hora_final = @hora_final,
                    descripcion = @descripcion
            WHEN NOT MATCHED THEN
                INSERT (id, fecha, hora_inicio, hora_final, descripcion, fecha_registro_servidor)
                VALUES (@id, @fecha, @hora_inicio, @hora_final, @descripcion, GETDATE());
            """
            cursor.execute(query, (c.id, c.fecha, c.hora_inicio, c.hora_final, c.descripcion))
            processed += 1
            
        conn.close()
        print(f"[Sync Convocatorias] Procesadas {processed} convocatorias.")
        return {
            "success": True,
            "message": "Sincronización de convocatorias completada.",
            "procesados": processed
        }
    except Exception as e:
        print(f"Error en sincronizar_convocatorias: {e}")
        raise HTTPException(status_code=500, detail=f"Error al sincronizar convocatorias: {e}")

@router.delete(
    "/api/sync/convocatorias/{id}",
    summary="Eliminar Convocatoria",
    description="Elimina la cabecera y todas las asignaciones de participantes para una convocatoria."
)
def eliminar_convocatoria(id: str):
    print(f"\n--- [DELETE /api/sync/convocatorias/{id}] Eliminando programación ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM itm_programacion_asistencia WHERE convocatoria_id = %s", (id,))
        cursor.execute("DELETE FROM programacion_asistencia WHERE id = %s", (id,))
        conn.close()
        return {"success": True, "message": "Programación eliminada con éxito."}
    except Exception as e:
        print(f"Error al eliminar convocatoria: {e}")
        raise HTTPException(status_code=500, detail=f"Error al eliminar convocatoria: {e}")

@router.post(
    "/api/sync/convocatoria-empleados",
    summary="Subir Asistencia a Convocatorias",
    description="Registra la asistencia (1 o 0) de los empleados convocados a los eventos programados."
)
def sincronizar_convocatoria_empleados(listado: List[ConvocatoriaEmpleadoSyncItem]):
    print(f"\n--- [POST /api/sync/convocatoria-empleados] Sincronizando {len(listado)} asignaciones de convocatoria ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        processed = 0
        for ce in listado:
            cursor.execute("SELECT 1 FROM empleados_asistencia WHERE cedula = %s", (ce.cedula_empleado,))
            if not cursor.fetchone():
                cursor.execute(
                    "INSERT INTO empleados_asistencia (cedula, nombre, estado, fecha_creacion) VALUES (%s, %s, 'ACTIVO', GETDATE())",
                    (ce.cedula_empleado, f"Empleado ({ce.cedula_empleado})")
                )

            cursor.execute("SELECT 1 FROM programacion_asistencia WHERE id = %s", (ce.convocatoria_id,))
            if not cursor.fetchone():
                cursor.execute(
                    "INSERT INTO programacion_asistencia (id, fecha, hora_inicio, hora_final, descripcion, fecha_registro_servidor) VALUES (%s, '2026-01-01', '08:00', '12:00', 'Convocatoria temporal', GETDATE())",
                    (ce.convocatoria_id,)
                )
                
            query = """
            DECLARE @convocatoria_id VARCHAR(50) = %s;
            DECLARE @cedula_empleado VARCHAR(50) = %s;
            DECLARE @asistio INT = %s;
            DECLARE @fecha_hora_asistencia VARCHAR(30) = %s;

            MERGE itm_programacion_asistencia AS target
            USING (SELECT @convocatoria_id AS convocatoria_id, @cedula_empleado AS cedula_empleado) AS source
            ON (target.convocatoria_id = source.convocatoria_id AND target.cedula_empleado = source.cedula_empleado)
            WHEN MATCHED THEN
                UPDATE SET 
                    asistio = @asistio,
                    fecha_hora_asistencia = @fecha_hora_asistencia
            WHEN NOT MATCHED THEN
                INSERT (convocatoria_id, cedula_empleado, asistio, fecha_hora_asistencia)
                VALUES (@convocatoria_id, @cedula_empleado, @asistio, @fecha_hora_asistencia);
            """
            cursor.execute(query, (ce.convocatoria_id, ce.cedula_empleado, ce.asistio, ce.fecha_hora_asistencia))
            processed += 1
            
        conn.close()
        print(f"[Sync Convocatorias] Procesadas {processed} asignaciones.")
        return {
            "success": True,
            "message": "Sincronización de asignaciones completada.",
            "procesados": processed
        }
    except Exception as e:
        print(f"Error en sincronizar_convocatoria_empleados: {e}")
        raise HTTPException(status_code=500, detail=f"Error al sincronizar asignaciones de convocatoria: {e}")
