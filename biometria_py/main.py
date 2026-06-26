import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from database import get_db_connection
from services.face_service import prewarm_model
from routers import health, secciones, asistencia, sync

# Inicialización de la aplicación FastAPI con ruta de Swagger personalizada en /apidocs
app = FastAPI(
    title="Edge Biometrics & Business Unified Backend",
    version="2.0.0",
    description="Backend unificado en Python FastAPI y Docker para Biometría y Sincronización de Kioskos.",
    docs_url="/apidocs",
    redoc_url=None
)

# Habilitar CORS para los Kioskos de Flutter
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Registrar Routers Modulares
app.include_router(health.router)
app.include_router(secciones.router)
app.include_router(asistencia.router)
app.include_router(sync.router)

def verify_and_seed_db():
    """Verifica y asegura la estructura de todas las tablas en la base de datos central y siembra registros básicos."""
    print("Verificando administrador y tablas por defecto en base de datos central...")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 1. Asegurar tabla horarios_asistencia
        print("[Database] Asegurando tabla 'horarios_asistencia'...")
        try:
            cursor.execute("""
                IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='horarios_asistencia' AND xtype='U')
                CREATE TABLE horarios_asistencia (
                    id_horario VARCHAR(50) PRIMARY KEY,
                    hora_inicio VARCHAR(10) NOT NULL,
                    hora_final VARCHAR(10) NOT NULL,
                    tipo VARCHAR(30) NOT NULL,
                    dias VARCHAR(100) NOT NULL,
                    fecha_creacion DATETIME NOT NULL DEFAULT GETDATE()
                )
            """)
            print("[Database] Tabla 'horarios_asistencia' asegurada con éxito.")
        except Exception as e:
            print(f"Nota al verificar/crear tabla horarios_asistencia: {e}")

        # 2. Asegurar tabla empleados_asistencia
        print("[Database] Asegurando tabla 'empleados_asistencia'...")
        try:
            cursor.execute("""
                IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='empleados_asistencia' AND xtype='U')
                CREATE TABLE empleados_asistencia (
                    cedula VARCHAR(50) PRIMARY KEY,
                    nombre VARCHAR(150) NOT NULL,
                    mapa_vector_foto VARCHAR(MAX) NULL,
                    horario_id VARCHAR(50) NULL,
                    fecha_ini_contrato VARCHAR(20) NULL,
                    fecha_fin_contrato VARCHAR(20) NULL,
                    estado VARCHAR(20) NULL DEFAULT 'ACTIVO',
                    sede_principal VARCHAR(150) NULL,
                    id_seccion VARCHAR(50) NULL,
                    tipo VARCHAR(30) NULL,
                    fecha_creacion DATETIME NOT NULL DEFAULT GETDATE()
                )
            """)
            print("[Database] Tabla 'empleados_asistencia' asegurada con éxito.")
        except Exception as e:
            print(f"Nota al verificar/crear tabla empleados_asistencia: {e}")

        # 3. Asegurar tabla registros_asistencia
        print("[Database] Asegurando tabla 'registros_asistencia'...")
        try:
            cursor.execute("""
                IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='registros_asistencia' AND xtype='U')
                CREATE TABLE registros_asistencia (
                    id VARCHAR(50) PRIMARY KEY,
                    fecha_hora VARCHAR(30) NOT NULL,
                    cedula VARCHAR(50) NOT NULL FOREIGN KEY REFERENCES empleados_asistencia(cedula) ON DELETE CASCADE,
                    evento VARCHAR(30) NOT NULL,
                    duracion VARCHAR(50) NULL,
                    tipo VARCHAR(30) NOT NULL,
                    unidad_negocio VARCHAR(100) NOT NULL,
                    metodo_registro VARCHAR(50) NOT NULL DEFAULT 'FACIAL',
                    fecha_registro_servidor DATETIME NOT NULL DEFAULT GETDATE()
                )
            """)
            print("[Database] Tabla 'registros_asistencia' asegurada con éxito.")
        except Exception as e:
            print(f"Nota al verificar/crear tabla registros_asistencia: {e}")

        # 4. Asegurar tabla permisos_asistencia
        print("[Database] Asegurando tabla 'permisos_asistencia'...")
        try:
            cursor.execute("""
                IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='permisos_asistencia' AND xtype='U')
                CREATE TABLE permisos_asistencia (
                    id VARCHAR(50) PRIMARY KEY,
                    usuario_registrador VARCHAR(50) NOT NULL,
                    cedula_empleado VARCHAR(50) NOT NULL FOREIGN KEY REFERENCES empleados_asistencia(cedula) ON DELETE CASCADE,
                    fecha_hora VARCHAR(30) NOT NULL,
                    tipo VARCHAR(50) NOT NULL,
                    fecha_inicio VARCHAR(20) NOT NULL,
                    fecha_final VARCHAR(20) NOT NULL,
                    observacion VARCHAR(500) NULL,
                    fecha_registro_servidor DATETIME NOT NULL DEFAULT GETDATE()
                )
            """)
            print("[Database] Tabla 'permisos_asistencia' asegurada con éxito.")
        except Exception as e:
            print(f"Nota al verificar/crear tabla permisos_asistencia: {e}")

        # 5. Asegurar tabla usuarios_asistencia
        print("[Database] Asegurando tabla 'usuarios_asistencia'...")
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
            print("[Database] Tabla 'usuarios_asistencia' asegurada con éxito.")
        except Exception as te:
            print(f"Nota al verificar/crear tabla usuarios_asistencia: {te}")

        # 6. Asegurar que 'admin' exista
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

        # 7. Asegurar que 'galapa' exista
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

        # Columnas fallback para empleados_asistencia
        try:
            cursor.execute("ALTER TABLE empleados_asistencia ADD sede_principal VARCHAR(150)")
        except Exception:
            pass
        try:
            cursor.execute("ALTER TABLE empleados_asistencia ADD id_seccion VARCHAR(50)")
        except Exception:
            pass
        try:
            cursor.execute("ALTER TABLE empleados_asistencia ADD tipo VARCHAR(30)")
        except Exception:
            pass

        # Asegurar tabla empleados_tipo
        print("[Database] Asegurando tabla 'empleados_tipo'...")
        try:
            cursor.execute("""
                IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='empleados_tipo' AND xtype='U')
                CREATE TABLE empleados_tipo (
                    cedula VARCHAR(50) PRIMARY KEY,
                    tipo VARCHAR(30) NOT NULL,
                    FOREIGN KEY (cedula) REFERENCES empleados_asistencia(cedula) ON DELETE CASCADE
                )
            """)
            print("[Database] Tabla 'empleados_tipo' asegurada con éxito.")
            
            # Remover restricciones CHECK restrictivas anteriores si existen
            cursor.execute("""
                DECLARE @sql NVARCHAR(MAX) = '';
                SELECT @sql += 'ALTER TABLE empleados_tipo DROP CONSTRAINT ' + name + ';'
                FROM sys.check_constraints
                WHERE parent_object_id = OBJECT_ID('empleados_tipo');
                IF @sql <> ''
                    EXEC sp_executesql @sql;
            """)
            print("[Database] Restricciones CHECK anteriores removidas de 'empleados_tipo'.")
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
            
            cursor.execute("SELECT COUNT(*) FROM tipo_ausencia")
            row = cursor.fetchone()
            total = row[0] if row else 0
            if total == 0:
                print("[Database] Sembrando datos iniciales en 'tipo_ausencia'...")
                tipos = [('EG', 'INCAPACIDAD'), ('AL', 'ACCIDENTE'), ('SC', 'FALTA'), ('VAC', 'VACACIONES')]
                for sigla, nombre in tipos:
                    cursor.execute("INSERT INTO tipo_ausencia (sigla, nombre) VALUES (%s, %s)", (sigla, nombre))
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
            
        # Columnas fallback
        try:
            cursor.execute("ALTER TABLE permisos_asistencia ADD observacion VARCHAR(500)")
        except Exception:
            pass
        try:
            cursor.execute("ALTER TABLE ausentismos ADD observacion VARCHAR(500)")
        except Exception:
            pass

        # Asegurar tabla incapacidades_asistencia
        print("[Database] Asegurando tabla 'incapacidades_asistencia'...")
        try:
            cursor.execute("""
                IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='incapacidades_asistencia' AND xtype='U')
                CREATE TABLE incapacidades_asistencia (
                    id VARCHAR(50) PRIMARY KEY,
                    usuario_registrador VARCHAR(50) NOT NULL,
                    cedula_empleado VARCHAR(50) NOT NULL,
                    fecha_hora VARCHAR(30) NOT NULL,
                    tipo VARCHAR(50) NOT NULL,
                    fecha_inicio VARCHAR(30) NOT NULL,
                    fecha_final VARCHAR(30) NOT NULL,
                    observacion VARCHAR(500),
                    fecha_registro_servidor DATETIME DEFAULT GETDATE(),
                    FOREIGN KEY (cedula_empleado) REFERENCES empleados_asistencia(cedula) ON DELETE CASCADE
                )
            """)
            print("[Database] Tabla 'incapacidades_asistencia' asegurada con éxito.")
        except Exception as e:
            print(f"Error al verificar/crear tabla incapacidades_asistencia: {e}")

        # Asegurar tabla programacion_asistencia
        print("[Database] Asegurando tabla 'programacion_asistencia'...")
        try:
            cursor.execute("""
                IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='programacion_asistencia' AND xtype='U')
                CREATE TABLE programacion_asistencia (
                    id VARCHAR(50) PRIMARY KEY,
                    fecha VARCHAR(10) NOT NULL,
                    hora_inicio VARCHAR(10) NOT NULL,
                    hora_final VARCHAR(10) NOT NULL,
                    descripcion VARCHAR(250) NOT NULL,
                    fecha_registro_servidor DATETIME DEFAULT GETDATE()
                )
            """)
            print("[Database] Tabla 'programacion_asistencia' asegurada con éxito.")
        except Exception as e:
            print(f"Error al verificar/crear tabla programacion_asistencia: {e}")

        # Asegurar tabla itm_programacion_asistencia
        print("[Database] Asegurando tabla 'itm_programacion_asistencia'...")
        try:
            cursor.execute("""
                IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='itm_programacion_asistencia' AND xtype='U')
                CREATE TABLE itm_programacion_asistencia (
                    convocatoria_id VARCHAR(50) NOT NULL,
                    cedula_empleado VARCHAR(50) NOT NULL,
                    asistio INT NOT NULL DEFAULT 0,
                    fecha_hora_asistencia VARCHAR(30),
                    PRIMARY KEY (convocatoria_id, cedula_empleado),
                    FOREIGN KEY (convocatoria_id) REFERENCES programacion_asistencia(id) ON DELETE CASCADE,
                    FOREIGN KEY (cedula_empleado) REFERENCES empleados_asistencia(cedula) ON DELETE CASCADE
                )
            """)
            print("[Database] Tabla 'itm_programacion_asistencia' asegurada con éxito.")
        except Exception as e:
            print(f"Error al verificar/crear tabla itm_programacion_asistencia: {e}")

        # Asegurar columna metodo_registro en la tabla registros_asistencia si no existe
        print("[Database] Asegurando columna 'metodo_registro' en 'registros_asistencia'...")
        try:
            cursor.execute("""
                IF NOT EXISTS (
                    SELECT * FROM sys.columns 
                    WHERE object_id = OBJECT_ID('registros_asistencia') 
                    AND name = 'metodo_registro'
                )
                BEGIN
                    ALTER TABLE registros_asistencia ADD metodo_registro VARCHAR(50) DEFAULT 'FACIAL' WITH VALUES;
                END
            """)
            print("[Database] Columna 'metodo_registro' agregada/verificada en 'registros_asistencia'.")
        except Exception as e:
            print(f"Error al verificar/agregar columna metodo_registro: {e}")

        conn.close()
    except Exception as e:
        print(f"Error al verificar/sembrar usuarios por defecto en SQL Server: {e}")

@app.on_event("startup")
def startup_event():
    # Pre-cargar modelo DeepFace Facenet
    prewarm_model()
    # Ejecutar la verificación y siembra de tablas
    verify_and_seed_db()
