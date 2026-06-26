FROM python:3.10-slim

# Evitar que Python escriba archivos pyc y hacer buffer de salida
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV DEEPFACE_HOME=/app

WORKDIR /app

# Instalar librerías gráficas esenciales del sistema requeridas por OpenCV (libGL y libgthread)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Copiar requirements e instalar dependencias usando wheels precompilados de alta estabilidad.
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copiar y ejecutar el script de precalentamiento biométrico tolerante a fallos
COPY prewarm.py .
RUN python prewarm.py && rm prewarm.py

# Copiar el código fuente modularizado
COPY database.py main.py ./
COPY core/ ./core/
COPY models/ ./models/
COPY routers/ ./routers/
COPY services/ ./services/

# Crear carpeta de caras temporales y ajustar permisos
RUN mkdir -p temp_faces && chmod 777 temp_faces

EXPOSE 5000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "5000"]
