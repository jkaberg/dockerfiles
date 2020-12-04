FROM linuxserver/nextcloud
RUN apk update \
    && apk upgrade \
    && apk add tesseract-ocr

ADD https://github.com/tesseract-ocr/tessdata/raw/master/eng.traineddata /usr/share/tessdata/eng.traineddata
ADD https://github.com/tesseract-ocr/tessdata/raw/master/nor.traineddata /usr/share/tessdata/nor.traineddata
