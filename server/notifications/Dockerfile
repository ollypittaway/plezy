FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
ARG INSTALL_FIREBASE=true
RUN if [ "$INSTALL_FIREBASE" = false ]; then sed -i '/^firebase-admin==/d' requirements.txt; fi \
    && pip install --no-cache-dir -r requirements.txt && useradd --system --uid 10001 panel && install -d -o panel /data
COPY app.py viewer_settings.py index.html panel.css panel.js ./
USER panel
ENV DATA_DIR=/data PORT=8080
EXPOSE 8080
CMD ["python", "app.py"]
