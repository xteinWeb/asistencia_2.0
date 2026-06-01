import os
import shutil
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from deepface import DeepFace
import numpy as np

app = FastAPI(title="Edge Biometrics Service", version="1.0.0")

# Habilitar CORS para los Kioskos de Flutter
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

TEMP_DIR = "temp_faces"
os.makedirs(TEMP_DIR, exist_ok=True)

# Precargar y compilar el modelo al iniciar para que la primera marcación sea instantánea
@app.on_event("startup")
def startup_event():
    print("Precargando modelo de Reconocimiento Facial (Facenet)...")
    try:
        # Ejecutamos una representación dummy con una imagen vacía de 160x160 para forzar la carga y compilación
        dummy_img = np.zeros((160, 160, 3), dtype=np.uint8)
        DeepFace.represent(img_path=dummy_img, model_name="Facenet", enforce_detection=False)
        print("¡Modelo Facenet cargado correctamente en memoria y listo para inferencia offline!")
    except Exception as e:
        print(f"Error al precargar el modelo: {e}")

@app.post("/api/asistencia/nuevoEmpleado")
@app.post("/api/asistencia/compararRostro")
async def generar_vector(face: UploadFile = File(...)):
    print(f"\n--- [Generar Vector Python] Petición recibida para archivo: {face.filename} ---")
    
    # Guardar temporalmente la imagen subida
    temp_file_path = os.path.join(TEMP_DIR, face.filename)
    try:
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(face.file, buffer)
            
        # Extraer vector de 128 floats usando DeepFace con el modelo Facenet
        # OpenCV es el backend de detección de caras estándar más rápido en CPU
        # align=True alinea automáticamente el rostro para máxima precisión biométrica
        representations = DeepFace.represent(
            img_path=temp_file_path,
            model_name="Facenet",
            detector_backend="opencv",
            enforce_detection=True,
            align=True
        )
        
        if not representations or len(representations) == 0:
            raise HTTPException(status_code=400, detail="No se detectó ningún rostro en la imagen.")
            
        if len(representations) > 1:
            raise HTTPException(status_code=400, detail="Se detectó más de un rostro en la imagen. Tome una foto individual.")
            
        # Obtener el vector de 128 flotantes
        embedding = representations[0]["embedding"]
        
        # Eliminar archivo temporal
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)
            
        print(f"¡Éxito! Vector facial generado correctamente. Dimensiones: {len(embedding)}")
        return {
            "success": True,
            "message": "Vector facial generado correctamente con Python DeepFace (Facenet).",
            "vector": embedding,
            "dimensiones": len(embedding)
        }
        
    except Exception as e:
        # Asegurar limpieza del archivo temporal en caso de error
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)
            
        error_msg = str(e)
        print(f"Error procesando rostro: {error_msg}")
        if "Face could not be detected" in error_msg:
            raise HTTPException(status_code=400, detail="No se detectó ningún rostro en la imagen. Asegúrese de mirar a la cámara y contar con buena iluminación.")
        raise HTTPException(status_code=500, detail=f"Error interno en el procesamiento biométrico: {error_msg}")

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "biometria_py", "model": "Facenet"}
