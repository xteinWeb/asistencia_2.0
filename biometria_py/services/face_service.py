import os
import shutil
import numpy as np
from fastapi import UploadFile, HTTPException
from deepface import DeepFace
from core.config import TEMP_DIR
from core.security import l2_normalize

def prewarm_model():
    """Precarga y compila el modelo de reconocimiento facial (ArcFace) con una imagen dummy."""
    print("Precargando modelo de Reconocimiento Facial (ArcFace + MediaPipe)...")
    try:
        dummy_img = np.zeros((160, 160, 3), dtype=np.uint8)
        # Precalentamos tanto el representador (ArcFace) como el detector (MediaPipe)
        DeepFace.represent(img_path=dummy_img, model_name="ArcFace", detector_backend="mediapipe", enforce_detection=False)
        print("¡Modelo ArcFace y detector MediaPipe cargados correctamente en memoria y listos!")
    except Exception as e:
        print(f"Error al precargar el modelo: {e}")

async def process_face_image(face: UploadFile, cedula: str = None) -> list:
    """Procesa una imagen subida, detecta el rostro, genera su firma biométrica y la normaliza."""
    os.makedirs(TEMP_DIR, exist_ok=True)
    PERM_DIR = "fotos_empleados"
    os.makedirs(PERM_DIR, exist_ok=True)
    
    temp_file_path = os.path.join(TEMP_DIR, face.filename)
    try:
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(face.file, buffer)
            
        representations = DeepFace.represent(
            img_path=temp_file_path,
            model_name="ArcFace",
            detector_backend="mediapipe",
            enforce_detection=True,
            align=True
        )
        
        if not representations or len(representations) == 0:
            raise HTTPException(status_code=400, detail="No se detectó ningún rostro en la imagen.")
            
        selected_representation = representations[0]
        if len(representations) > 1:
            print(f"[Biometría] Se detectaron {len(representations)} rostros en la imagen. Seleccionando el rostro de mayor tamaño...")
            representations.sort(
                key=lambda r: r["facial_area"]["w"] * r["facial_area"]["h"], 
                reverse=True
            )
            selected_representation = representations[0]
            
        if cedula and cedula.strip() != "":
            clean_cedula = "".join(c for c in cedula if c.isalnum() or c in ('-', '_')).strip()
            perm_file_path = os.path.join(PERM_DIR, f"{clean_cedula}.jpg")
            shutil.copy(temp_file_path, perm_file_path)
            print(f"[Biometría] Foto permanente de empleado guardada con éxito en: {perm_file_path}")
            
        raw_embedding = selected_representation["embedding"]
        embedding = l2_normalize(raw_embedding)
        
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)
            
        print(f"¡Éxito! Vector facial generado correctamente. Dimensiones: {len(embedding)}")
        return embedding
        
    except Exception as e:
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)
            
        error_msg = str(e)
        print(f"Error procesando rostro: {error_msg}")
        if "Face could not be detected" in error_msg:
            raise HTTPException(
                status_code=400, 
                detail="No se detectó ningún rostro en la imagen. Asegúrese de mirar a la cámara y contar con buena iluminación."
            )
        raise HTTPException(
            status_code=500, 
            detail=f"Error interno en el procesamiento biométrico: {error_msg}"
        )
