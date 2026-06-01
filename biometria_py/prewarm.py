import numpy as np
import traceback

try:
    print("[Pre-warm] Cargando modelo Facenet y descargando pesos si es necesario...")
    from deepface import DeepFace
    
    # Intentar ejecutar una representación dummy para pre-descargar y cargar el modelo Facenet
    DeepFace.represent(
        img_path=np.zeros((160, 160, 3), dtype=np.uint8),
        model_name='Facenet',
        enforce_detection=False
    )
    print("[Pre-warm] ¡PRE-WARMING BIOMÉTRICO COMPLETADO CON ÉXITO!")
except Exception as e:
    print("\n=== [Pre-warm] ADVERTENCIA: ERROR EN PRE-WARMING BIOMÉTRICO ===")
    traceback.print_exc()
    print("El contenedor continuará construyéndose, pero el modelo se descargará al iniciar en caliente.")
    print("=============================================================\n")
