from fastapi import APIRouter, HTTPException
from database import get_db_connection
from core.security import serialize_value, serialize_rows

router = APIRouter(tags=["Catálogos & Tablas de Apoyo"])

@router.get(
    "/api/secciones",
    summary="Obtener todas las secciones",
    description="Devuelve el catálogo de secciones con tipo 'proceso' definidas en el sistema de producción."
)
def obtener_todas_secciones():
    print("\n--- [GET /api/secciones] Obtener secciones tipo proceso ---")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        cursor.execute("SELECT ID_SECCION, DESCRIPCION FROM secciones WHERE tipo = 'proceso'")
        rows = cursor.fetchall()
        conn.close()
        
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

@router.get(
    "/api/tipos-ausencia",
    summary="Obtener tipos de ausencia",
    description="Devuelve la lista de tipos y siglas de ausencia autorizadas en el sistema central."
)
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
