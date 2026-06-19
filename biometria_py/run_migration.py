import sys
import os

# Agrega la carpeta actual al path de python
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from database import get_db_connection

def run_migration():
    print("Iniciando migración manual para SQL Server...")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 1. Crear tabla incapacidades_asistencia
        print("Creando tabla 'incapacidades_asistencia'...")
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
        print("Tabla 'incapacidades_asistencia' creada/verificada.")
        
        # 2. Verificar estructura
        cursor.execute("SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'incapacidades_asistencia'")
        columns = cursor.fetchall()
        print("Columnas de incapacidades_asistencia:")
        for col in columns:
            print(f" - {col[0]}: {col[1]}")
            
        conn.close()
        print("Migración completada con éxito.")
    except Exception as e:
        print(f"Error durante la migración: {e}")
        sys.exit(1)

if __name__ == "__main__":
    run_migration()
