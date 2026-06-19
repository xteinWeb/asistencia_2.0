import sys
import os

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from database import get_db_connection

def run_migration():
    print("Iniciando migración para agregar 'metodo_registro' a registros_asistencia...")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Agregar columna metodo_registro si no existe
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
        print("Migración de columna 'metodo_registro' completada con éxito.")
        
        # Verificar la tabla
        cursor.execute("SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'registros_asistencia'")
        columns = cursor.fetchall()
        for col in columns:
            if col[0].lower() == 'metodo_registro':
                print(f"Verificado - Columna encontrada: {col[0]} ({col[1]})")
                
        conn.close()
    except Exception as e:
        print(f"Error ejecutando migración: {e}")
        sys.exit(1)

if __name__ == "__main__":
    run_migration()
