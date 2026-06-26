import os
import json
import requests
from database import get_db_connection

def migrar_fotos_a_arcface_via_api():
    # Directorio de fotos descargadas
    FOTOS_DIR = "fotos_empleados"
    API_URL = "http://192.168.11.46:8085/api/asistencia/compararRostro"
    
    if not os.path.exists(FOTOS_DIR):
        print(f"Error: La carpeta '{FOTOS_DIR}' no existe localmente.")
        return

    # Buscar todas las fotos .jpg en el directorio
    archivos = [f for f in os.listdir(FOTOS_DIR) if f.lower().endswith(".jpg")]
    
    if not archivos:
        print(f"No se encontraron fotos en la carpeta '{FOTOS_DIR}'.")
        return

    print(f"=== INICIANDO MIGRACION BIOMETRICA VIA API (ArcFace 512d) ===")
    print(f"Se encontraron {len(archivos)} fotos para procesar.")
    print(f"Usando API de procesamiento en: {API_URL}")
    print("Estableciendo conexion con la base de datos central...")
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        print("Conexion establecida con exito!")
    except Exception as e:
        print(f"Error al conectar a la base de datos: {e}")
        return

    exitosos = 0
    fallidos = 0

    # Procesar cada foto
    for idx, archivo in enumerate(archivos, 1):
        cedula = os.path.splitext(archivo)[0]
        ruta_completa = os.path.join(FOTOS_DIR, archivo)
        
        # Ignorar archivos temporales o de prueba
        if cedula.lower() in ("test_temp", "temp", "face"):
            print(f"[{idx}/{len(archivos)}] Saltando archivo de prueba: {archivo}")
            continue

        print(f"\n[{idx}/{len(archivos)}] Procesando Cedula: {cedula} (Archivo: {archivo})...")
        
        try:
            # 1. Verificar si el empleado existe en la base de datos
            cursor.execute("SELECT nombre FROM empleados_asistencia WHERE cedula = %s", (cedula,))
            row = cursor.fetchone()
            if not row:
                print(f"  [WARNING] Advertencia: El empleado con cedula '{cedula}' no existe en la tabla empleados_asistencia. Se omitira.")
                fallidos += 1
                continue
                
            nombre_empleado = row[0]
            print(f"  Empleado: {nombre_empleado}")

            # 2. Generar embedding enviando la foto al backend
            with open(ruta_completa, "rb") as img_file:
                files = {"face": (archivo, img_file, "image/jpeg")}
                data = {"cedula": cedula}
                response = requests.post(API_URL, files=files, data=data, timeout=30)
            
            if response.status_code != 200:
                raise Exception(f"Error de la API (Status {response.status_code}): {response.text}")
                
            res_json = response.json()
            if not res_json.get("success"):
                raise Exception(f"API no reporto exito: {res_json.get('message')}")
                
            embedding_normalizado = res_json["vector"]

            # 3. Convertir el vector a formato JSON de texto para guardarlo en la columna VARCHAR(MAX)
            vector_json = json.dumps(embedding_normalizado)

            # 4. Actualizar la base de datos
            cursor.execute(
                "UPDATE empleados_asistencia SET mapa_vector_foto = %s WHERE cedula = %s",
                (vector_json, cedula)
            )
            conn.commit()
            print(f"  [OK] Exito! Vector ArcFace de {len(embedding_normalizado)} dimensiones actualizado en la base de datos.")
            exitosos += 1

        except Exception as e:
            conn.rollback()
            print(f"  [ERROR] Error al procesar '{archivo}': {e}")
            fallidos += 1

    conn.close()
    print(f"\n=== MIGRACION FINALIZADA ===")
    print(f"Procesados con éxito: {exitosos}")
    print(f"Fallidos u omitidos: {fallidos}")

if __name__ == "__main__":
    migrar_fotos_a_arcface_via_api()
