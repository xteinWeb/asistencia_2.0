import os
import json
import numpy as np
from deepface import DeepFace
from database import get_db_connection
from core.security import l2_normalize

def migrar_fotos_a_arcface():
    # Directorio de fotos descargadas
    FOTOS_DIR = "fotos_empleados"
    
    if not os.path.exists(FOTOS_DIR):
        print(f"Error: La carpeta '{FOTOS_DIR}' no existe localmente.")
        return

    # Buscar todas las fotos .jpg en el directorio
    archivos = [f for f in os.listdir(FOTOS_DIR) if f.lower().endswith(".jpg")]
    
    if not archivos:
        print(f"No se encontraron fotos en la carpeta '{FOTOS_DIR}'.")
        return

    print(f"=== INICIANDO MIGRACIÓN BIOMÉTRICA (ArcFace 512d) ===")
    print(f"Se encontraron {len(archivos)} fotos para procesar.")
    print("Estableciendo conexión con la base de datos de desarrollo...")
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        print("¡Conexión establecida con éxito!")
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

        print(f"\n[{idx}/{len(archivos)}] Procesando Cédula: {cedula} (Archivo: {archivo})...")
        
        try:
            # 1. Verificar si el empleado existe en la base de datos
            cursor.execute("SELECT nombre FROM empleados_asistencia WHERE cedula = %s", (cedula,))
            row = cursor.fetchone()
            if not row:
                print(f"  ⚠️ Advertencia: El empleado con cédula '{cedula}' no existe en la tabla empleados_asistencia. Se omitirá.")
                fallidos += 1
                continue
                
            nombre_empleado = row[0]
            print(f"  Empleado: {nombre_empleado}")

            # 2. Generar embedding usando ArcFace y MediaPipe
            representations = DeepFace.represent(
                img_path=ruta_completa,
                model_name="ArcFace",
                detector_backend="mediapipe",
                enforce_detection=True,
                align=True
            )

            if not representations:
                raise Exception("No se detectó ningún rostro en la imagen.")

            # Obtener el primer rostro y normalizar
            raw_embedding = representations[0]["embedding"]
            embedding_normalizado = l2_normalize(raw_embedding)

            # 3. Convertir el vector a formato JSON de texto para guardarlo en la columna VARCHAR(MAX)
            vector_json = json.dumps(embedding_normalizado)

            # 4. Actualizar la base de datos
            cursor.execute(
                "UPDATE empleados_asistencia SET mapa_vector_foto = %s WHERE cedula = %s",
                (vector_json, cedula)
            )
            conn.commit()
            print(f"  ✅ ¡Éxito! Vector ArcFace de 512 dimensiones actualizado en la base de datos.")
            exitosos += 1

        except Exception as e:
            conn.rollback()
            print(f"  ❌ Error al procesar '{archivo}': {e}")
            fallidos += 1

    conn.close()
    print(f"\n=== MIGRACIÓN FINALIZADA ===")
    print(f"Procesados con éxito: {exitosos}")
    print(f"Fallidos u omitidos: {fallidos}")

if __name__ == "__main__":
    migrar_fotos_a_arcface()
