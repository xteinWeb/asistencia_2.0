FROM python:3.10-slim

# Evitar que Python escriba archivos pyc y hacer buffer de salida
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV DEEPFACE_HOME=/app

WORKDIR /app

# Instalar dependencias esenciales del sistema para OpenCV y DeepFace
RUN apt-get update && apt-get install -y --no-install-recommends \
    g++ \
    libgl1-mesa-glx \
    libglib2.0-0 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copiar requirements y hacer la instalación de librerías
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Pre-descargar el modelo biométrico Facenet en tiempo de compilación (docker build)
# Esto asegura que la imagen sea 100% autocontenida y funcione sin internet en la sucursal.
# DeepFace descargará los pesos de Facenet y los almacenará en /app/.deepface/weights/
RUN python -c "from deepface import DeepFace; import numpy as np; DeepFace.represent(img_path=np.zeros((160, 160, 3), dtype=np.uint8), model_name='Facenet', enforce_detection=False)"

# Copiar el código fuente
COPY app.py .

# Crear carpeta de caras temporales y ajustar permisos
RUN mkdir -p temp_faces && chmod 777 temp_faces

EXPOSE 5000

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "5000"]
