import os

DB_SERVER = os.getenv("DB_SERVER", "190.85.54.78")
DB_PORT = os.getenv("DB_PORT", "1433")
DB_USER = os.getenv("DB_USER", "sa")
DB_PASSWORD = os.getenv("DB_PASSWORD", "ADMadm1234")
DB_DATABASE = os.getenv("DB_DATABASE", "ARTDECON")
TEMP_DIR = os.getenv("TEMP_DIR", "temp_faces")
