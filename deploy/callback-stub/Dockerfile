# Day 0 Applink callback stub (plan A0.1). Standard library only.
# Render's lamp-api builds this until render.yaml (A1.4) points it at backend/.
FROM python:3.12-slim
RUN useradd --create-home --uid 10001 app
WORKDIR /app
COPY stub.py .
USER app
ENV PYTHONUNBUFFERED=1
EXPOSE 8000
CMD ["python", "stub.py"]
