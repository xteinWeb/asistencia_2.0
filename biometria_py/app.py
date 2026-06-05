import os
import shutil
from typing import List, Optional
from fastapi import FastAPI, File, UploadFile, HTTPException, Depends, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from deepface import DeepFace
import numpy as np
import uuid
import datetime
import math

# Importar la conexión nativa a SQL Server
from database import get_db_connection

app = FastAPI(
    title="Edge Biometrics & Business Unified Backend",
    version="2.0.0",
    description="Backend unificado en Python FastAPI y Docker para Biometría y Sincronización de Kioskos."
)

# Habilitar CORS para los Kioskos de Flutter
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

TEMP_DIR = "temp_faces"
os.makedirs(TEMP_DIR, exist_ok=True)

# Helper para serializar tipos especiales de SQL Server (UUID, Datetime) a JSON seguro
def serialize_value(val):
    if isinstance(val, uuid.UUID):
        return str(val).upper()
    elif isinstance(val, (datetime.datetime, datetime.date)):
        return val.isoformat()
    return val

def serialize_row(row):
    if not row:
        return row
    return {k: serialize_value(v) for k, v in row.items()}

def serialize_rows(rows):
    if not rows:
        return []
    return [serialize_row(r) for r in rows]

# Normalización L2 para asegurar que los vectores residan en una esfera unitaria.
# Esto reduce la distancia euclidiana entre el mismo rostro de ~4.0 a ~0.34,
# logrando compatibilidad perfecta con el umbral estricto de 0.6 de la tableta de Flutter.
def l2_normalize(vector):
    sq_sum = sum(x**2 for x in vector)
    norm = math.sqrt(sq_sum)
    if norm == 0:
        return vector
    return [x / norm for x in vector]

# Precargar y compilar el modelo al iniciar para que la primera marcación sea instantánea
@app.on_event("startup")
def startup_event():
    print("Precargando modelo de Reconocimiento Facial (Facenet)...")
    try:
        # Ejecutamos una representación dummy con una imagen vacía de 160x160 para forzar la carga y compilación
        dummy_img = np.zeros((160, 160, 3), dtype=np.uint8)
        DeepFace.represent(img_path=dummy_img, model_name="Facenet", enforce_detection=False)
        print("¡Modelo Facenet cargado correctamente en memoria y listo para inferencia offline!")
    except Exception as e:
        print(f"Error al precargar el modelo: {e}")

    # Sembrar administrador por defecto en SQL Server si la tabla está vacía
    print("Verificando administrador por defecto en base de datos central...")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 1. Asegurar que la tabla exista (crearla si por alguna razón no existe)
        try:
            cursor.execute("""
                IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='usuarios_asistencia' AND xtype='U')
                CREATE TABLE usuarios_asistencia (
                    usuario VARCHAR(50) PRIMARY KEY,
                    nombre VARCHAR(150) NOT NULL,
                    contrasena VARCHAR(150) NOT NULL,
                    rol VARCHAR(50) NOT NULL,
                    estado VARCHAR(20) NOT NULL DEFAULT 'ACTIVO',
                    unidad_negocio VARCHAR(100) NOT NULL DEFAULT ''
                )
            """)
        except Exception as te:
            print(f"Nota al verificar/crear tabla usuarios_asistencia: {te}")

        # 2. Asegurar que 'admin' exista con la contraseña admin123, rol ADMIN y estado ACTIVO
        print("[Database] Asegurando usuario 'admin'...")
        cursor.execute("SELECT 1 FROM usuarios_asistencia WHERE usuario = %s", ('admin',))
        if cursor.fetchone():
            cursor.execute("""
                UPDATE usuarios_asistencia 
                SET nombre = %s, contrasena = %s, rol = %s, estado = %s, unidad_negocio = %s
                WHERE usuario = %s
            """, ('Administrador', 'admin123', 'ADMIN', 'ACTIVO', 'Principal', 'admin'))
            print("[Database] Usuario 'admin' verificado/actualizado con éxito.")
        else:
            cursor.execute("""
                INSERT INTO usuarios_asistencia (usuario, nombre, contrasena, rol, estado, unidad_negocio)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, ('admin', 'Administrador', 'admin123', 'ADMIN', 'ACTIVO', 'Principal'))
            print("[Database] Usuario 'admin' registrado con éxito.")

        # 3. Asegurar que 'galapa' exista con contraseña galapa2025, rol OPERADOR, unidad_negocio pl03 y estado ACTIVO
        print("[Database] Asegurando usuario 'galapa'...")
        cursor.execute("SELECT 1 FROM usuarios_asistencia WHERE usuario = %s", ('galapa',))
        if cursor.fetchone():
            cursor.execute("""
                UPDATE usuarios_asistencia 
                SET nombre = %s, contrasena = %s, rol = %s, estado = %s, unidad_negocio = %s
                WHERE usuario = %s
            """, ('Usuario Galapa', 'galapa2025', 'OPERADOR', 'ACTIVO', 'pl03', 'galapa'))
            print("[Database] Usuario 'galapa' verificado/actualizado con éxito.")
        else:
            cursor.execute("""
                INSERT INTO usuarios_asistencia (usuario, nombre, contrasena, rol, estado, unidad_negocio)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, ('galapa', 'Usuario Galapa', 'galapa2025', 'OPERADOR', 'ACTIVO', 'pl03'))
            print("[Database] Usuario 'galapa' registrado con éxito.")

        # Asegurar columnas de sede y sección en la tabla empleados_asistencia
        print("[Database] Asegurando columnas 'sede_principal' e 'id_seccion' in 'empleados_asistencia'...")
        try:
            cursor.execute("ALTER TABLE empleados_asistencia ADD sede_principal VARCHAR(150)")
            print("[Database] Columna 'sede_principal' agregada con éxito.")
        except Exception as e:
            # Ya existe la columna u otro error esperado
            pass
            
        try:
            cursor.execute("ALTER TABLE empleados_asistencia ADD id_seccion VARCHAR(50)")
            print("[Database] Columna 'id_seccion' agregada con éxito.")
        except Exception as e:
            # Ya existe la columna u otro error esperado
            pass

        try:
            cursor.execute("ALTER TABLE empleados_asistencia ADD tipo VARCHAR(30)")
            print("[Database] Columna 'tipo' agregada con éxito a 'empleados_asistencia'.")
        except Exception as e:
            # Ya existe la columna u otro error esperado
            pass

        # Asegurar tabla empleados_tipo
        print("[Database] Asegurando tabla 'empleados_tipo'...")
        try:
            cursor.execute("""
                IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='empleados_tipo' AND xtype='U')
                CREATE TABLE empleados_tipo (
                    cedula VARCHAR(50) PRIMARY KEY,
                    tipo VARCHAR(30) NOT NULL CHECK (tipo IN ('OPERATIVO', 'ADMINISTRATIVO')),
                    FOREIGN KEY (cedula) REFERENCES empleados_asistencia(cedula) ON DELETE CASCADE
                )
            """)
            print("[Database] Tabla 'empleados_tipo' asegurada con éxito.")
        except Exception as e:
            print(f"Error al verificar/crear tabla empleados_tipo: {e}")

        # Asegurar tabla tipo_ausencia
        print("[Database] Asegurando tabla 'tipo_ausencia'...")
        try:
            cursor.execute("""
                IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='tipo_ausencia' AND xtype='U')
                CREATE TABLE tipo_ausencia (
                    sigla VARCHAR(10) PRIMARY KEY,
                    nombre VARCHAR(150) NOT NULL
                )
            """)
            print("[Database] Tabla 'tipo_ausencia' asegurada con éxito.")
            
            # Sembrar tipos de ausencia iniciales si la tabla está vacía
            cursor.execute("SELECT COUNT(*) FROM tipo_ausencia")
            row = cursor.fetchone()
            total = 0
            if row:
                if isinstance(row, dict):
                    total = row.get('total', 0)
                else:
                    total = row[0]
            if total == 0:
                print("[Database] Sembrando datos iniciales en 'tipo_ausencia'...")
                tipos = [
                    ('EG', 'INCAPACIDAD POR ENFERMEDAD GENERAL'),
                    ('AL', 'INCAPACIDAD POR ACCIDENTE LABORAL'),
                    ('EL', 'ENFERMEDAD LABORAL'),
                    ('SC', 'FALTA SIN JUSTA CAUSA'),
                    ('SU', 'SUSPENCIÓN'),
                    ('LIC', 'LICENICIA'),
                    ('LLT', 'LLEGADA TARDE'),
                    ('PE', 'PERMISO'),
                    ('LU', 'LICENCIA POR LUTO'),
                    ('LM', 'LICENCIA DE MATERNIDAD'),
                    ('VAC', 'VACACIONES'),
                    ('AISL', 'AISLAMIENO'),
                    ('DV', 'DEVOLUCIÓN'),
                    ('TFE', 'TRABAJO POR FURA DE LA EMPRESA')
                ]
                for sigla, nombre in tipos:
                    cursor.execute("INSERT INTO tipo_ausencia (sigla, nombre) VALUES (%s, %s)", (sigla, nombre))
                print("[Database] Datos iniciales de 'tipo_ausencia' sembrados.")
        except Exception as e:
            print(f"Error al verificar/crear/sembrar tabla tipo_ausencia: {e}")

        # Asegurar tabla ausentismos
        print("[Database] Asegurando tabla 'ausentismos'...")
        try:
            cursor.execute("""
                IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='ausentismos' AND xtype='U')
                CREATE TABLE ausentismos (
                    id VARCHAR(50) PRIMARY KEY,
                    cedula_empleado VARCHAR(50) NOT NULL,
                    fecha VARCHAR(10) NOT NULL,
                    sigla_ausencia VARCHAR(10) NOT NULL,
                    fecha_registro_servidor DATETIME DEFAULT GETDATE(),
                    FOREIGN KEY (cedula_empleado) REFERENCES empleados_asistencia(cedula) ON DELETE CASCADE,
                    FOREIGN KEY (sigla_ausencia) REFERENCES tipo_ausencia(sigla)
                )
            """)
            print("[Database] Tabla 'ausentismos' asegurada con éxito.")
        except Exception as e:
            print(f"Error al verificar/crear tabla ausentismos: {e}")
            
        # Asegurar columna 'observacion' en 'permisos_asistencia'
        print("[Database] Asegurando columna 'observacion' en 'permisos_asistencia'...")
        try:
            cursor.execute("ALTER TABLE permisos_asistencia ADD observacion VARCHAR(500)")
            print("[Database] Columna 'observacion' agregada con éxito.")
        except Exception:
            pass

        # Asegurar columna 'observacion' en 'ausentismos'
        print("[Database] Asegurando columna 'observacion' en 'ausentismos'...")
        try:
            cursor.execute("ALTER TABLE ausentismos ADD observacion VARCHAR(500)")
            print("[Database] Columna 'observacion' agregada con éxito a 'ausentismos'.")
        except Exception:
            pass

        conn.close()
    except Exception as e:
        print(f"Error al verificar/sembrar usuarios por defecto en SQL Server: {e}")

# ==============================================================================
# 1. ENDPOINTS BIOMÉTRICOS
# ==============================================================================

@app.post("/api/asistencia/nuevoEmpleado")
@app.post("/api/asistencia/compararRostro")
async def generar_vector(
    face: UploadFile = File(...),
    cedula: Optional[str] = Form(None)
):
    print(f"\n--- [Generar Vector Python] Petición recibida para archivo: {face.filename}, Cédula: {cedula} ---")
    
    # Asegurar directorios
    os.makedirs(TEMP_DIR, exist_ok=True)
    PERM_DIR = "fotos_empleados"
    os.makedirs(PERM_DIR, exist_ok=True)
    
    # Guardar temporalmente la imagen subida
    temp_file_path = os.path.join(TEMP_DIR, face.filename)
    try:
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(face.file, buffer)
            
        # Extraer vector de 128 floats usando DeepFace con el modelo Facenet
        # OpenCV es el backend de detección de caras estándar más rápido en CPU
        # align=True alinea automáticamente el rostro para máxima precisión biométrica
        representations = DeepFace.represent(
            img_path=temp_file_path,
            model_name="Facenet",
            detector_backend="opencv",
            enforce_detection=True,
            align=True
        )
        
        if not representations or len(representations) == 0:
            raise HTTPException(status_code=400, detail="No se detectó ningún rostro en la imagen.")
            
        # Si se detecta más de un rostro (personas de fondo o falsos positivos de OpenCV por sombras/ropa),
        # seleccionamos de forma inteligente la cara de mayor tamaño, que garantiza ser la del empleado
        # situado directamente en frente de la cámara del Tótem.
        selected_representation = representations[0]
        if len(representations) > 1:
            print(f"[Biometría] Se detectaron {len(representations)} rostros en la imagen. Seleccionando el rostro de mayor tamaño...")
            # Ordenar por área de la cara (w * h) en orden descendente y tomar el más grande
            representations.sort(
                key=lambda r: r["facial_area"]["w"] * r["facial_area"]["h"], 
                reverse=True
            )
            selected_representation = representations[0]
            
        # Si se proporciona la cédula del empleado, guardamos la foto de forma permanente
        if cedula and cedula.strip() != "":
            # Limpiar la cédula para que sea un nombre de archivo seguro
            clean_cedula = "".join(c for c in cedula if c.isalnum() or c in ('-', '_')).strip()
            perm_file_path = os.path.join(PERM_DIR, f"{clean_cedula}.jpg")
            shutil.copy(temp_file_path, perm_file_path)
            print(f"[Biometría] Foto permanente de empleado guardada con éxito en: {perm_file_path}")
            
        # Obtener el vector de 128 flotantes y aplicar Normalización L2
        raw_embedding = selected_representation["embedding"]
        embedding = l2_normalize(raw_embedding)
        
        # Eliminar archivo temporal
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)
            
        print(f"¡Éxito! Vector facial generado correctamente. Dimensiones: {len(embedding)}")
        return {
            "success": True,
            "message": "Vector facial generado correctamente con Python DeepFace (Facenet).",
            "vector": embedding,
            "dimensiones": len(embedding)
        }
        
    except Exception as e:
        # Asegurar limpieza del archivo temporal en caso de error
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)
            
        error_msg = str(e)
        print(f"Error procesando rostro: {error_msg}")
        if "Face could not be detected" in error_msg:
            raise HTTPException(status_code=400, detail="No se detectó ningún rostro en la imagen. Asegúrese de mirar a la cámara y contar con buena iluminación.")
        raise HTTPException(status_code=500, detail=f"Error interno en el procesamiento biométrico: {error_msg}")


# ==============================================================================
# 2. MODELOS PYDANTIC PARA SINCRONIZACIÓN
# ==============================================================================

class RegistroSyncItem(BaseModel):
    id: str
    fecha_hora: str
    cedula: str
    evento: str
    duracion: Optional[str] = None
    tipo: str
    unidad_negocio: str

class GenerarLltRequest(BaseModel):
    fecha: str

class PermisoSyncItem(BaseModel):
    id: str
    usuario_registrador: str
    cedula_empleado: str
    fecha_hora: str
    tipo: str
    fecha_inicio: str
    fecha_final: str
    observacion: Optional[str] = None

class EmpleadoSyncItem(BaseModel):
    cedula: str
    nombre: str
    mapa_vector_foto: Optional[str] = None
    horario_id: Optional[str] = None
    fecha_ini_contrato: Optional[str] = None
    fecha_fin_contrato: Optional[str] = None
    estado: Optional[str] = 'ACTIVO'
    sede_principal: Optional[str] = None
    id_seccion: Optional[str] = None
    tipo: Optional[str] = None

class HorarioSyncItem(BaseModel):
    id_horario: str
    hora_inicio: str
    hora_final: str
    tipo: str
    dias: str

class AusentismoSyncItem(BaseModel):
    id: str
    cedula_empleado: str
    fecha: str
    sigla_ausencia: str
    observacion: Optional[str] = None


# ==============================================================================
# 3. ENDPOINTS DE SINCRONIZACIÓN (PULL - DESCARGAS)
# ==============================================================================

@app.get("/api/sync/horarios")
def obtener_horarios():
    print("\n--- [GET /api/sync/horarios] Solicitud de sincronización ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        # Fetch master schedules
        cursor.execute("SELECT ID_UN, ID_HORARIO, DESCRIPCION, ESTADO FROM horarios")
        horarios_rows = cursor.fetchall()
        
        # Fetch schedule items/segments
        cursor.execute("""
            SELECT ID_UN, ITEM, ID_HORARIO, INICIO, FINAL, 
                   LUNES, MARTES, MIERCOLES, JUEVES, VIERNES, SABADO, DOMINGO, TIPO 
            FROM itm_horarios
        """)
        items_rows = cursor.fetchall()
        conn.close()
        
        # Helper to format datetime/time to HH:MM:SS
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

        # Group items by schedule
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
            
        # Structure the schedules list
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

@app.get("/api/sync/usuarios")
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

@app.get("/api/sync/empleados")
def obtener_empleados():
    print("\n--- [GET /api/sync/empleados] Solicitud de Sincronización ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        cursor.execute("""
            SELECT e.cedula, e.nombre, e.mapa_vector_foto, e.horario_id, e.fecha_ini_contrato, e.fecha_fin_contrato, e.estado, e.sede_principal, e.id_seccion, COALESCE(e.tipo, et.tipo) AS tipo 
            FROM empleados_asistencia e
            LEFT JOIN empleados_tipo et ON e.cedula = et.cedula
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

@app.get("/api/sync/permisos")
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

@app.get("/api/sync/registros")
def obtener_registros():
    print("\n--- [GET /api/sync/registros] Solicitud de Sincronización (Últimos 30 días) ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        # Consulta idéntica de últimos 30 días optimizada
        cursor.execute("""
            SELECT id, fecha_hora, cedula, evento, duracion, tipo, unidad_negocio 
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


# ==============================================================================
# 4. ENDPOINTS DE SINCRONIZACIÓN (PUSH - SUBIDAS)
# ==============================================================================

@app.post("/api/sync/registros")
def sincronizar_registros(listado: List[RegistroSyncItem]):
    print(f"\n--- [POST /api/sync/registros] Sincronizando {len(listado)} registros ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        inserted = 0
        ignored = 0
        
        for r in listado:
            # 1. Asegurar integridad referencial: crear empleado básico si no existe en empleados_asistencia
            cursor.execute("SELECT 1 FROM empleados_asistencia WHERE cedula = %s", (r.cedula,))
            if not cursor.fetchone():
                print(f"[Sync Registros] Empleado {r.cedula} no existe centralmente. Registrando empleado básico.")
                cursor.execute(
                    "INSERT INTO empleados_asistencia (cedula, nombre, estado, fecha_creacion) VALUES (%s, %s, 'ACTIVO', GETDATE())",
                    (r.cedula, f"Empleado ({r.cedula})")
                )
            
            # 2. Insertar registro si no existe
            cursor.execute("SELECT 1 FROM registros_asistencia WHERE id = %s", (r.id,))
            if not cursor.fetchone():
                cursor.execute("""
                    INSERT INTO registros_asistencia (id, fecha_hora, cedula, evento, duracion, tipo, unidad_negocio, fecha_registro_servidor)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, GETDATE())
                """, (r.id, r.fecha_hora, r.cedula, r.evento, r.duracion, r.tipo, r.unidad_negocio))
                inserted += 1
            else:
                ignored += 1
                
        # Generar ausentismos por permisos para limpiar registros de faltas
        cursor_dict = conn.cursor(as_dict=True)
        generar_ausentismos_por_permisos(cursor_dict)
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

@app.post("/api/sync/generar-llt")
def generar_llt_manual(req: GenerarLltRequest):
    print(f"\n--- [POST /api/sync/generar-llt] Generando novedades LLT manuales para fecha: {req.fecha} ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        
        # 1. Obtener todos los registros de entrada con retardo para esa fecha
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
            
            # Verificar si existe novedad LLT
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

@app.post("/api/sync/permisos")
def sincronizar_permisos(listado: List[PermisoSyncItem]):
    print(f"\n--- [POST /api/sync/permisos] Sincronizando {len(listado)} permisos ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        inserted = 0
        ignored = 0
        
        for p in listado:
            # 1. Asegurar integridad referencial: crear empleado básico si no existe
            cursor.execute("SELECT 1 FROM empleados_asistencia WHERE cedula = %s", (p.cedula_empleado,))
            if not cursor.fetchone():
                print(f"[Sync Permisos] Empleado {p.cedula_empleado} no existe. Registrando básico.")
                cursor.execute(
                    "INSERT INTO empleados_asistencia (cedula, nombre, estado, fecha_creacion) VALUES (%s, %s, 'ACTIVO', GETDATE())",
                    (p.cedula_empleado, f"Empleado ({p.cedula_empleado})")
                )
            
            # 2. Insertar o actualizar permiso
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
                
        # Generar ausentismos por permisos inmediatamente
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

@app.post("/api/sync/empleados")
def sincronizar_empleados(listado: List[EmpleadoSyncItem]):
    print(f"\n--- [POST /api/sync/empleados] Sincronizando {len(listado)} enrolamientos locales ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        processed = 0
        
        for emp in listado:
            # Declaración de variables y ejecución de MERGE seguro de SQL Server
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
                    tipo = @tipo
            WHEN NOT MATCHED THEN
                INSERT (cedula, nombre, mapa_vector_foto, horario_id, fecha_ini_contrato, fecha_fin_contrato, estado, sede_principal, id_seccion, tipo, fecha_creacion)
                VALUES (@cedula, @nombre, @mapaVectorFoto, @horarioId, @fechaIniContrato, @fechaFinContrato, @estado, @sedePrincipal, @idSeccion, @tipo, GETDATE());
            """
            
            # Convertir horario_id a None si está vacío
            h_id = emp.horario_id if emp.horario_id and emp.horario_id.strip() != "" else None
            
            cursor.execute(query, (
                emp.cedula,
                emp.nombre,
                emp.mapa_vector_foto,
                h_id,
                emp.fecha_ini_contrato,
                emp.fecha_fin_contrato,
                emp.estado,
                emp.sede_principal,
                emp.id_seccion,
                emp.tipo
            ))
            
            # MERGE para empleados_tipo
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

@app.post("/api/sync/horarios")
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
            
            cursor.execute(query, (
                h.id_horario,
                h.hora_inicio,
                h.hora_final,
                h.tipo,
                h.dias
            ))
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
        raise HTTPException(status_code=500, detail=f"Error al sincronizar horarios en SQL Server: {e}")


# ==============================================================================
# 5. ELIMINACIÓN DE EMPLEADO (SOFT-DELETE)
# ==============================================================================

@app.delete("/api/sync/empleados/{cedula}")
def eliminar_empleado(cedula: str):
    print(f"\n--- [DELETE /api/sync/empleados/{cedula}] Inactivando empleado ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("UPDATE empleados_asistencia SET estado = 'INACTIVO' WHERE cedula = %s", (cedula,))
        conn.close()
        
        print(f"[Inactivar] Empleado con cédula {cedula} marcado como INACTIVO en SQL Server.")
        return {
            "success": True,
            "message": "Empleado marcado como INACTIVO con éxito en SQL Server."
        }
    except Exception as e:
        print(f"Error en eliminar_empleado: {e}")
        raise HTTPException(status_code=500, detail=f"Error al inactivar empleado en SQL Server: {e}")


# ==============================================================================
# 6. MONITOREO DE SALUD (HEALTHCHECK)
# ==============================================================================

@app.get("/health")
async def health_check():
    # Comprobar salud y conexión de base de datos
    db_ok = False
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.fetchone()
        conn.close()
        db_ok = True
    except Exception as e:
        print(f"[Healthcheck] Error de conexión a DB: {e}")
        
    return {
        "status": "healthy",
        "service": "biometria_py",
        "model": "Facenet",
        "database_connected": db_ok
    }

@app.get("/api/secciones")
def obtener_todas_secciones():
    print("\n--- [GET /api/secciones] Obtener secciones tipo proceso ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        cursor.execute("SELECT ID_SECCION, DESCRIPCION FROM secciones WHERE tipo = 'proceso'")
        rows = cursor.fetchall()
        conn.close()
        
        # Estandarizar claves a minúsculas
        data = []
        for r in rows:
            data.append({
                "id_seccion": serialize_value(r.get('ID_SECCION') or r.get('id_seccion')),
                "descripcion": serialize_value(r.get('DESCRIPCION') or r.get('descripcion'))
            })
            
        return {
            "success": True,
            "data": data
        }
    except Exception as e:
        print(f"Error en obtener_todas_secciones: {e}")
        raise HTTPException(status_code=500, detail=f"Error al obtener secciones desde SQL Server: {e}")

def generar_ausentismos_por_permisos(cursor):
    print("[Database] Generando ausentismos automáticos basados en permisos_asistencia...")
    try:
        # 1. Obtener todos los permisos
        cursor.execute("SELECT id, cedula_empleado, tipo, fecha_inicio, fecha_final FROM permisos_asistencia")
        permisos = cursor.fetchall() or []
        
        for p in permisos:
            cedula = p.get('cedula_empleado')
            tipo = p.get('tipo')
            f_ini = p.get('fecha_inicio')
            f_fin = p.get('fecha_final')
            
            if not cedula or not f_ini or not f_fin:
                continue
                
            # Convertir a datetime.date
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
                
            # Generar todas las fechas en el rango (inclusive)
            curr = dt_ini
            while curr <= dt_fin:
                fecha_str = curr.strftime('%Y-%m-%d')
                
                # Check 1: ¿Tiene entrada en registros_asistencia para esta fecha?
                cursor.execute(
                    "SELECT 1 FROM registros_asistencia WHERE cedula = %s AND evento = 'ENTRADA' AND fecha_hora LIKE %s",
                    (cedula, f"{fecha_str}%")
                )
                tiene_entrada = cursor.fetchone()
                
                if not tiene_entrada:
                    # Check 2: ¿Tiene ya un ausentismo en la tabla ausentismos?
                    cursor.execute(
                        "SELECT id, sigla_ausencia FROM ausentismos WHERE cedula_empleado = %s AND fecha = %s",
                        (cedula, fecha_str)
                    )
                    existing_ausentismo = cursor.fetchone()
                    
                    if not existing_ausentismo:
                        # Crear ausentismo
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
                    # Si tiene entrada pero existe un ausentismo 'PE', lo eliminamos
                    cursor.execute(
                        "DELETE FROM ausentismos WHERE cedula_empleado = %s AND fecha = %s AND sigla_ausencia = 'PE'",
                        (cedula, fecha_str)
                    )
                
                curr += datetime.timedelta(days=1)
                
    except Exception as e:
        print(f"Error al generar ausentismos por permisos: {e}")


# ==============================================================================
# 7. ENDPOINTS DE AUSENTISMO
# ==============================================================================

@app.get("/api/tipos-ausencia")
def obtener_tipos_ausencia():
    print("\n--- [GET /api/tipos-ausencia] Obtener tipos de ausencia ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        cursor.execute("SELECT VALOR1 as sigla, VALOR2 as nombre FROM ITM_DOMINIOS WHERE ID_DOMINIO = 'AUSENCIAS' ORDER BY VALOR2 ASC")
        rows = cursor.fetchall()
        conn.close()
        return {
            "success": True,
            "data": serialize_rows(rows)
        }
    except Exception as e:
        print(f"Error en obtener_tipos_ausencia: {e}")
        raise HTTPException(status_code=500, detail=f"Error al obtener tipos de ausencia: {e}")

@app.get("/api/sync/ausentismos")
def obtener_ausentismos():
    print("\n--- [GET /api/sync/ausentismos] Solicitud de Sincronización de Ausentismos ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        generar_ausentismos_por_permisos(cursor)
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

@app.post("/api/sync/ausentismos")
def sincronizar_ausentismos(listado: List[AusentismoSyncItem]):
    print(f"\n--- [POST /api/sync/ausentismos] Sincronizando {len(listado)} ausentismos locales ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        processed = 0
        for item in listado:
            # Asegurar integridad referencial: crear empleado básico si no existe
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
            
        # Generar ausentismos por permisos para mantener la base de datos limpia y consistente
        cursor_dict = conn.cursor(as_dict=True)
        generar_ausentismos_por_permisos(cursor_dict)
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

@app.delete("/api/sync/ausentismos/{id}")
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
