from fastapi import APIRouter, File, UploadFile, Form
from typing import Optional
from services.face_service import process_face_image

router = APIRouter(tags=["Biometría & Reconocimiento Facial"])

@router.post(
    "/api/asistencia/nuevoEmpleado",
    summary="Registrar / Generar Vector Facial para Nuevo Empleado",
    description="Recibe la foto del rostro del empleado, detecta y alinea la cara y genera el vector de 128 flotantes normalizado. Si se especifica la cédula, guarda la foto permanentemente."
)
@router.post(
    "/api/asistencia/compararRostro",
    summary="Generar Vector Facial para Verificación de Marcaciones",
    description="Recibe una foto tomada por el Tótem y extrae su vector biométrico para que la tableta compare contra su SQLite local."
)
async def generar_vector(
    face: UploadFile = File(..., description="Archivo de imagen del rostro"),
    cedula: Optional[str] = Form(None, description="Cédula del empleado para guardar la foto permanentemente (opcional)")
):
    import time
    start_time = time.time()
    print(f"\n--- [Generar Vector Python] Petición recibida para archivo: {face.filename}, Cédula: {cedula} ---")
    embedding = await process_face_image(face, cedula)
    elapsed = time.time() - start_time
    print(f"[Generar Vector Python] Éxito: Vector generado en {elapsed:.4f} segundos.")
    return {
        "success": True,
        "message": "Vector facial generado correctamente con Python DeepFace (ArcFace).",
        "vector": embedding,
        "dimensiones": len(embedding)
    }
