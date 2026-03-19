# 选择特定版本的 slim 基础镜像，减少体积并锁定环境
FROM python:3.11-slim

# 设置环境变量，防止 Python 生成 .pyc 文件并确保日志即时输出
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# 设置工作目录
WORKDIR /app

# 先建用户
RUN adduser --disabled-password --gecos '' appuser

# Python 依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install "fastapi[standard]" playwright

# 系统依赖（root）
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
RUN playwright install-deps chromium && rm -rf /var/lib/apt/lists/*
RUN playwright install-deps chromium && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* /usr/share/lintian/* && \
    rm -rf /usr/share/locale/*

USER appuser
ENV PLAYWRIGHT_BROWSERS_PATH=/home/appuser/pw-browsers
RUN playwright install chromium

# 复制代码时直接 chown
USER root
COPY --chown=appuser:appuser . /app
RUN mkdir -p /app/media && chown appuser:appuser /app/media
USER appuser

CMD ["python", "run.py"]