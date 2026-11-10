# syntax=docker/dockerfile:1
# 本地文档预览服务的容器配置，仅供阅读示例。
ARG PYTHON_VERSION=3.12
FROM python:${PYTHON_VERSION}-slim AS runtime

WORKDIR /workspace
ENV PYTHONUNBUFFERED=1
COPY . /workspace
EXPOSE 8000
CMD ["python", "-m", "http.server", "8000"]
