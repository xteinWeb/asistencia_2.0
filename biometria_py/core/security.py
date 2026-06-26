import uuid
import datetime
import math

def serialize_value(val):
    """Serializa tipos especiales de SQL Server (UUID, Datetime) a JSON seguro."""
    if isinstance(val, uuid.UUID):
        return str(val).upper()
    elif isinstance(val, (datetime.datetime, datetime.date)):
        return val.isoformat()
    return val

def serialize_row(row):
    """Serializa una fila del cursor (como diccionario) a JSON seguro."""
    if not row:
        return row
    return {k: serialize_value(v) for k, v in row.items()}

def serialize_rows(rows):
    """Serializa un listado de filas a JSON seguro."""
    if not rows:
        return []
    return [serialize_row(r) for r in rows]

def l2_normalize(vector):
    """Normalización L2 para asegurar que los vectores residan en una esfera unitaria."""
    sq_sum = sum(x**2 for x in vector)
    norm = math.sqrt(sq_sum)
    if norm == 0:
        return vector
    return [x / norm for x in vector]

def format_datetime_for_sql(val_str):
    """Sanitiza y formatea una fecha ISO (con microsegundos) a formato compatible con SQL Server DATETIME."""
    if not val_str:
        return None
    val_str = str(val_str).strip()
    if val_str in ("", "0", "None"):
        return None
    val_str = val_str.replace('T', ' ')
    if '.' in val_str:
        parts = val_str.split('.')
        date_time_part = parts[0]
        frac_part = parts[1]
        frac_digits = "".join(c for c in frac_part if c.isdigit())[:3]
        if frac_digits:
            return f"{date_time_part}.{frac_digits}"
        else:
            return date_time_part
    return val_str
