# syntax=docker/dockerfile:1
# Example container configuration for a local document server.
ARG PYTHON_VERSION=3.12
FROM python:${PYTHON_VERSION}-slim AS runtime

WORKDIR /workspace
ENV PYTHONUNBUFFERED=1
COPY . /workspace
EXPOSE 8000
CMD ["python", "-m", "http.server", "8000"]
