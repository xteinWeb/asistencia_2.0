import pymssql
import json
import math

DB_SERVER = "190.85.54.78"
DB_USER = "sa"
DB_PASSWORD = "sql2025DEVadmin"
DB_DATABASE = "ARTDECOM"
DB_PORT = 9788

def euclidean_distance(v1, v2):
    if len(v1) != len(v2):
        return -1
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(v1, v2)))

def compare():
    try:
        conn = pymssql.connect(
            server=DB_SERVER,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            database=DB_DATABASE,
            autocommit=True
        )
        cursor = conn.cursor()
        
        # Obtener vector de Orlando (1140865692) y Juan Jose (1042244228)
        cursor.execute("SELECT cedula, nombre, mapa_vector_foto FROM empleados_asistencia WHERE cedula IN ('1140865692', '1042244228')")
        rows = cursor.fetchall()
        
        data = {}
        for row in rows:
            cedula, nombre, vector_str = row
            if vector_str:
                data[cedula] = (nombre, json.loads(vector_str))
                
        if len(data) < 2:
            print("Error: No se encontraron los vectores de ambos empleados en la base de datos.")
            for ced, val in data.items():
                print(f"Encontrado: {val[0]} ({ced})")
            return
            
        name1, v1 = data['1140865692']
        name2, v2 = data['1042244228']
        
        dist = euclidean_distance(v1, v2)
        print("\n=== COMPARACIÓN DE VECTORES EN SQL SERVER ===")
        print(f"Empleado 1: {name1} (1140865692) - Dimensiones: {len(v1)}")
        print(f"Empleado 2: {name2} (1042244228) - Dimensiones: {len(v2)}")
        print(f"Distancia Euclidiana L2 en base de datos: {dist:.4f}")
        
        # Calcular similitud equivalente en escala del Tótem (con umbral 0.6)
        if dist <= 0:
            sim = 100.0
        elif dist >= 0.6:
            sim = 0.0
        else:
            sim = (1 - dist / 0.6) * 100
        print(f"Similitud calculada (con umbral 0.6): {sim:.2f}%")
        
        conn.close()
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    compare()
