FROM nextcloud

RUN echo "deb [allow-insecure=yes] http://repo.delellis.com.ar stretch main" > /etc/apt/sources.list.d/20-pdlib.list \
    && apt-get update \
    && apt-get install -y gpsbabel tesseract-ocr tesseract-ocr-all php7.0-pdlib
