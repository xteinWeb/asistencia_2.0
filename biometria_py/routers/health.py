from fastapi import APIRouter
from database import get_db_connection

router = APIRouter(tags=["Health & Status"])

@router.get(
    "/health",
    summary="Monitoreo de Salud",
    description="Verifica que el servicio de la API esté activo y comprueba la conexión en tiempo real con la base de datos SQL Server."
)
async def health_check():
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
