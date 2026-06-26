import os
import pymssql

# Credenciales por defecto para base de datos central '00' (ARTDECOM)
DB_SERVER = os.getenv("DB_SERVER", "190.85.54.78")
DB_USER = os.getenv("DB_USER", "sa")
DB_PASSWORD = os.getenv("DB_PASSWORD", "sql2025DEVadmin")
DB_DATABASE = os.getenv("DB_DATABASE", "ARTDECOM")
DB_PORT = int(os.getenv("DB_PORT", "9788"))

def get_db_connection():
    """
    Retorna una conexión activa a SQL Server central.
    Habilita autocommit de forma predeterminada para simplificar las transacciones.
    """
    try:
        print(f"[Database] Conectando a {DB_SERVER}:{DB_PORT}/{DB_DATABASE} con usuario {DB_USER}...")
        conn = pymssql.connect(
            server=DB_SERVER,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            database=DB_DATABASE,
            autocommit=True
        )
        return conn
    except Exception as e:
        print(f"[Database] ERROR de conexión a SQL Server: {e}")
        raise e
