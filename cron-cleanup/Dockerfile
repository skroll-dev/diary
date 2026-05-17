FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

# Cloud Run Job: Prozess läuft bis Fertigstellung, kein dauerhafter Server
CMD ["python", "-m", "app.main"]
