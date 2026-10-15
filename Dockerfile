# Dockerfile
# Imagen base: Python 3.11 mínima (slim = sin paquetes innecesarios)
FROM python:3.11-slim

# Variables de entorno para Python en contenedor
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

# Directorio de trabajo dentro del contenedor
WORKDIR /app

# Instalar dependencias del sistema necesarias para psycopg2
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev gcc \
    && rm -rf /var/lib/apt/lists/*

# Copiar e instalar dependencias Python primero (aprovecha caché de Docker)
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# Copiar el código fuente
COPY . .

# Recolectar archivos estáticos durante el build
RUN python manage.py collectstatic --no-input \
    --settings=core.settings \
    || echo "collectstatic con settings base"

# Exponer el puerto
EXPOSE $PORT

# Comando por defecto: iniciar Gunicorn
CMD gunicorn core.wsgi \
    --bind 0.0.0.0:$PORT \
    --workers 2 \
    --timeout 120 \
    --log-file -
2.3 Crear docker-compose.yml
Permite simular el entorno de producción localmente con PostgreSQL y Redis.

# docker-compose.yml
# Uso: docker-compose up --build
# Requiere Docker Desktop instalado en la PC

version: '3.9'

services:

  # ── Base de datos PostgreSQL ────────────────────────────────────────
  db:
    image: postgres:15-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB:       erp_db
      POSTGRES_USER:     erp_user
      POSTGRES_PASSWORD: erp_pass_local
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U erp_user -d erp_db"]
      interval: 5s
      timeout: 5s
      retries: 5

  # ── Cache Redis (preparado para Celery en W16) ─────────────────────
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    ports:
      - "6379:6379"

  # ── Aplicación Django ───────────────────────────────────────────────
  web:
    build: .
    restart: unless-stopped
    command: >
      sh -c "python manage.py migrate &&
             python manage.py collectstatic --no-input &&
             gunicorn core.wsgi --bind 0.0.0.0:8000 --workers 2 --log-file -"
    volumes:
      - .:/app
      - static_volume:/app/staticfiles
      - media_volume:/app/media
    ports:
      - "8000:8000"
    depends_on:
      db:
        condition: service_healthy
    environment:
      DJANGO_SETTINGS_MODULE: core.settings_prod
      SECRET_KEY:             dev-clave-docker-no-usar-en-produccion
      DEBUG:                  "False"
      DATABASE_URL:           postgres://erp_user:erp_pass_local@db:5432/erp_db
      REDIS_URL:              redis://redis:6379/0
      ALLOWED_HOSTS:          localhost,127.0.0.1

volumes:
  postgres_data:
  static_volume:
  media_volume: