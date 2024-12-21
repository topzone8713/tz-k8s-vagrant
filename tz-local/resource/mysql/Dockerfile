FROM python:3.8

RUN apt-get update && apt-get install -y curl
RUN pip3 install awscli

WORKDIR /app

COPY run.sh .

RUN chmod 777 /app/run.sh

ENTRYPOINT ["/bin/sh", "/app/run.sh"]
