from pydantic import BaseModel, Field
from typing import Optional, List

class RegistroSyncItem(BaseModel):
    id: str = Field(..., description="ID único del registro de asistencia")
    fecha_hora: str = Field(..., description="Fecha y hora del registro en formato ISO (e.g. YYYY-MM-DD HH:MM:SS)")
    cedula: str = Field(..., description="Cédula del empleado")
    evento: str = Field(..., description="Tipo de evento: ENTRADA o SALIDA")
    duracion: Optional[str] = Field(None, description="Duración si aplica")
    tipo: str = Field(..., description="Tipo de registro: NORMAL, RETARDO, etc.")
    unidad_negocio: str = Field(..., description="ID o código de la unidad de negocio")
    metodo_registro: Optional[str] = Field('FACIAL', description="Método de registro (por ejemplo, FACIAL, MANUAL)")

class GenerarLltRequest(BaseModel):
    fecha: str = Field(..., description="Fecha para la cual generar LLT (YYYY-MM-DD)")

class PermisoSyncItem(BaseModel):
    id: str = Field(..., description="ID único del permiso")
    usuario_registrador: str = Field(..., description="Usuario que registró el permiso")
    cedula_empleado: str = Field(..., description="Cédula del empleado")
    fecha_hora: str = Field(..., description="Fecha y hora de registro del permiso")
    tipo: str = Field(..., description="Tipo de permiso")
    fecha_inicio: str = Field(..., description="Fecha de inicio del permiso")
    fecha_final: str = Field(..., description="Fecha de finalización del permiso")
    observacion: Optional[str] = Field(None, description="Observaciones opcionales")

class IncapacidadSyncItem(BaseModel):
    id: str = Field(..., description="ID de la incapacidad")
    usuario_registrador: str = Field(..., description="Usuario que registró la incapacidad")
    cedula_empleado: str = Field(..., description="Cédula del empleado")
    fecha_hora: str = Field(..., description="Fecha y hora de registro de la incapacidad")
    tipo: str = Field(..., description="Tipo de incapacidad")
    fecha_inicio: str = Field(..., description="Fecha de inicio")
    fecha_final: str = Field(..., description="Fecha de finalización")
    observacion: Optional[str] = Field(None, description="Observaciones opcionales")

class EmpleadoSyncItem(BaseModel):
    cedula: str = Field(..., description="Cédula del empleado")
    nombre: str = Field(..., description="Nombre completo del empleado")
    mapa_vector_foto: Optional[str] = Field(None, description="Vector biométrico serializado en JSON (128 flotantes)")
    horario_id: Optional[str] = Field(None, description="ID del horario asignado")
    fecha_ini_contrato: Optional[str] = Field(None, description="Fecha de inicio de contrato")
    fecha_fin_contrato: Optional[str] = Field(None, description="Fecha de fin de contrato (nulo si indefinido)")
    estado: Optional[str] = Field('ACTIVO', description="Estado del empleado: ACTIVO o INACTIVO")
    sede_principal: Optional[str] = Field(None, description="Sede principal asignada")
    id_seccion: Optional[str] = Field(None, description="Sección asignada")
    tipo: Optional[str] = Field(None, description="Tipo de empleado: OPERATIVO, ADMINISTRATIVO, LIDER")
    fecha_registro: Optional[str] = Field(None, description="Fecha de registro en la app")

class HorarioSyncItem(BaseModel):
    id_horario: str = Field(..., description="ID del horario")
    hora_inicio: str = Field(..., description="Hora de inicio (HH:MM:SS)")
    hora_final: str = Field(..., description="Hora de salida (HH:MM:SS)")
    tipo: str = Field(..., description="Tipo de horario")
    dias: str = Field(..., description="Días laborables aplicables (separados por comas)")

class AusentismoSyncItem(BaseModel):
    id: str = Field(..., description="ID del ausentismo")
    cedula_empleado: str = Field(..., description="Cédula del empleado")
    fecha: str = Field(..., description="Fecha del ausentismo (YYYY-MM-DD)")
    sigla_ausencia: str = Field(..., description="Sigla identificadora de la ausencia")
    observacion: Optional[str] = Field(None, description="Observaciones opcionales")

class ConvocatoriaSyncItem(BaseModel):
    id: str = Field(..., description="ID de la convocatoria")
    fecha: str = Field(..., description="Fecha de la convocatoria (YYYY-MM-DD)")
    hora_inicio: str = Field(..., description="Hora de inicio de la convocatoria")
    hora_final: str = Field(..., description="Hora de finalización")
    descripcion: str = Field(..., description="Descripción o motivo de la convocatoria")

class ConvocatoriaEmpleadoSyncItem(BaseModel):
    convocatoria_id: str = Field(..., description="ID de la convocatoria")
    cedula_empleado: str = Field(..., description="Cédula del empleado convocado")
    asistio: int = Field(..., description="Indicador de asistencia: 1 si asistió, 0 si no")
    fecha_hora_asistencia: Optional[str] = Field(None, description="Fecha y hora de registro de asistencia")
