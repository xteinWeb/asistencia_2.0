import os
import sys
import shutil
import json
import csv
import math
from deepface import DeepFace
from database import get_db_connection

# Directorios de trabajo
INPUT_DIR = "fotos_registro_masivo"
PROCESSED_DIR = os.path.join(INPUT_DIR, "procesados")
PERM_DIR = "fotos_empleados"
CSV_FILE = "empleados_registro.csv"

def l2_normalize(vector):
    sq_sum = sum(x**2 for x in vector)
    norm = math.sqrt(sq_sum)
    if norm == 0:
        return vector
    return [x / norm for x in vector]

def detect_delimiter(file_path):
    """Detecta si el archivo CSV usa coma (,) o punto y coma (;)"""
    with open(file_path, "r", encoding="utf-8-sig") as f:
        first_line = f.readline()
        if ";" in first_line:
            return ";"
        return ","

def process_bulk_registration():
    # Asegurar directorios
    os.makedirs(INPUT_DIR, exist_ok=True)
    os.makedirs(PROCESSED_DIR, exist_ok=True)
    os.makedirs(PERM_DIR, exist_ok=True)

    print("=============================================================")
    print("      REGISTRO MASIVO DE EMPLEADOS Y VECTORES FACIALES")
    print("=============================================================")
    print(f"\nUsted puede realizar el registro usando dos métodos:\n")
    print(f"MÉTODO A (Recomendado): Crear un archivo Excel y guardarlo como CSV con el nombre:")
    print(f"   => {CSV_FILE} (en la carpeta biometria_py)")
    print("\n   Columnas requeridas en el CSV:")
    print("   cedula;nombre;tipo;fecha_inicio;fecha_fin;horario_id;id_seccion;sede_principal;foto")
    print("   - tipo: OPERATIVO o ADMINISTRATIVO")
    print("   - foto: El nombre del archivo dentro de 'fotos_registro_masivo' (ej: juan.jpg)")
    print("\nMÉTODO B: Sin CSV. Solo coloque las fotos en la carpeta:")
    print(f"   => {os.path.abspath(INPUT_DIR)}")
    print("   Con el nombre: [cedula]_[Nombre Completo].jpg")
    print("=============================================================\n")

    # Detectar qué método se usará
    csv_path = CSV_FILE
    use_csv = os.path.exists(csv_path)
    
    employees_to_process = []

    if use_csv:
        print(f"Se detectó el archivo '{CSV_FILE}'. Leyendo datos...")
        delimiter = detect_delimiter(csv_path)
        try:
            with open(csv_path, "r", encoding="utf-8-sig") as f:
                reader = csv.DictReader(f, delimiter=delimiter)
                for row in reader:
                    # Limpiar llaves y valores
                    clean_row = {k.strip().lower(): v.strip() for k, v in row.items() if k}
                    
                    cedula = clean_row.get("cedula", "")
                    nombre = clean_row.get("nombre", "")
                    foto = clean_row.get("foto", "")
                    
                    if not cedula or not nombre or not foto:
                        print(f"[Omitido] Fila sin datos esenciales (cédula, nombre o foto): {row}")
                        continue
                        
                    employees_to_process.append({
                        "cedula": cedula,
                        "nombre": nombre,
                        "tipo": clean_row.get("tipo", "OPERATIVO").upper(),
                        "fecha_inicio": clean_row.get("fecha_inicio", None) or None,
                        "fecha_fin": clean_row.get("fecha_fin", None) or None,
                        "horario_id": clean_row.get("horario_id", "01"),
                        "id_seccion": clean_row.get("id_seccion", None) or None,
                        "sede_principal": clean_row.get("sede_principal", None) or None,
                        "foto_filename": foto
                    })
            print(f"Se cargaron {len(employees_to_process)} empleados desde el CSV.\n")
        except Exception as e:
            print(f"Error al leer el archivo CSV: {e}")
            return
    else:
        print(f"No se encontró '{CSV_FILE}'. Escaneando fotos en la carpeta '{INPUT_DIR}'...")
        valid_extensions = (".jpg", ".jpeg", ".png")
        photo_files = [f for f in os.listdir(INPUT_DIR) if f.lower().endswith(valid_extensions)]

        if not photo_files:
            print("No se encontraron fotos para procesar.")
            print("Coloque fotos en 'fotos_registro_masivo' o configure 'empleados_registro.csv'.")
            return

        print(f"Se detectaron {len(photo_files)} fotos en la carpeta.\n")
        for file_name in photo_files:
            base_name, ext = os.path.splitext(file_name)
            cedula = ""
            nombre = ""
            
            if "_" in base_name:
                parts = base_name.split("_", 1)
                cedula = parts[0].strip()
                nombre = parts[1].strip()
            else:
                cedula = base_name.strip()
                nombre = input(f"Ingrese el nombre para la cédula {cedula} (Dejar vacío para 'Empleado {cedula}'): ").strip()
                if not nombre:
                    nombre = f"Empleado {cedula}"
                    
            employees_to_process.append({
                "cedula": cedula,
                "nombre": nombre,
                "tipo": "OPERATIVO",
                "fecha_inicio": None,
                "fecha_fin": None,
                "horario_id": "01",
                "id_seccion": None,
                "sede_principal": None,
                "foto_filename": file_name
            })

    if not employees_to_process:
        print("No hay empleados listos para procesar.")
        return

    # Conexión a Base de Datos Central
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
    except Exception as e:
        print(f"Error al conectar a la base de datos: {e}")
        return

    success_count = 0
    fail_count = 0

    for emp in employees_to_process:
        file_name = emp["foto_filename"]
        file_path = os.path.join(INPUT_DIR, file_name)
        
        print(f"\nProcesando empleado: {emp['nombre']} (C.C. {emp['cedula']})...")

        if not os.path.exists(file_path):
            print(f"[ERROR] No se encontró la foto '{file_name}' en la carpeta '{INPUT_DIR}'.")
            fail_count += 1
            continue

        try:
            # Generar Vector Facial usando DeepFace (Facenet)
            print(f"[DeepFace] Analizando rostro en la foto '{file_name}'...")
            representations = DeepFace.represent(
                img_path=file_path,
                model_name="Facenet",
                detector_backend="opencv",
                enforce_detection=True,
                align=True
            )

            if not representations:
                print(f"[ERROR] No se detectó ningún rostro en la imagen {file_name}.")
                fail_count += 1
                continue

            # Seleccionar rostro principal (el de mayor tamaño)
            representations.sort(
                key=lambda r: r["facial_area"]["w"] * r["facial_area"]["h"], 
                reverse=True
            )
            selected_rep = representations[0]
            raw_embedding = selected_rep["embedding"]
            embedding = l2_normalize(raw_embedding)
            embedding_json = json.dumps(embedding)

            # Insertar/Actualizar en base de datos central (SQL Server) con metadatos completos
            print(f"[DB] Registrando en SQL Server...")
            
            query = """
            DECLARE @cedula VARCHAR(50) = %s;
            DECLARE @nombre VARCHAR(150) = %s;
            DECLARE @mapaVectorFoto VARCHAR(MAX) = %s;
            DECLARE @horarioId VARCHAR(50) = %s;
            DECLARE @fechaIniContrato VARCHAR(20) = %s;
            DECLARE @fechaFinContrato VARCHAR(20) = %s;
            DECLARE @estado VARCHAR(20) = 'ACTIVO';
            DECLARE @sedePrincipal VARCHAR(150) = %s;
            DECLARE @idSeccion VARCHAR(50) = %s;
            DECLARE @tipo VARCHAR(30) = %s;

            MERGE empleados_asistencia AS target
            USING (SELECT @cedula AS cedula) AS source
            ON (target.cedula = source.cedula)
            WHEN MATCHED THEN
                UPDATE SET 
                    nombre = @nombre,
                    mapa_vector_foto = @mapaVectorFoto,
                    horario_id = @horarioId,
                    fecha_ini_contrato = @fechaIniContrato,
                    fecha_fin_contrato = @fechaFinContrato,
                    sede_principal = @sedePrincipal,
                    id_seccion = @idSeccion,
                    tipo = @tipo
            WHEN NOT MATCHED THEN
                INSERT (cedula, nombre, mapa_vector_foto, horario_id, fecha_ini_contrato, fecha_fin_contrato, estado, sede_principal, id_seccion, tipo, fecha_creacion)
                VALUES (@cedula, @nombre, @mapaVectorFoto, @horarioId, @fechaIniContrato, @fechaFinContrato, @estado, @sedePrincipal, @idSeccion, @tipo, GETDATE());
            """
            
            cursor.execute(query, (
                emp["cedula"],
                emp["nombre"],
                embedding_json,
                emp["horario_id"],
                emp["fecha_inicio"],
                emp["fecha_fin"],
                emp["sede_principal"],
                emp["id_seccion"],
                emp["tipo"]
            ))
            
            # Guardar foto permanentemente con el nombre de su cédula
            perm_photo_path = os.path.join(PERM_DIR, f"{emp['cedula']}.jpg")
            shutil.copy(file_path, perm_photo_path)
            
            # Mover archivo de entrada a la carpeta de procesados
            dest_processed_path = os.path.join(PROCESSED_DIR, file_name)
            if os.path.exists(dest_processed_path):
                os.remove(dest_processed_path)
            shutil.move(file_path, dest_processed_path)

            print(f"¡Éxito! Empleado {emp['nombre']} registrado correctamente.")
            success_count += 1

        except Exception as ex:
            print(f"[ERROR] Error al procesar {file_name}: {ex}")
            fail_count += 1

    # Cerrar recursos
    cursor.close()
    conn.close()

    print("\n=============================================================")
    print("                    RESUMEN DE PROCESO")
    print("=============================================================")
    print(f"Registrados con éxito: {success_count}")
    print(f"Errores/Omitidos:     {fail_count}")
    print("=============================================================\n")

if __name__ == "__main__":
    process_bulk_registration()
