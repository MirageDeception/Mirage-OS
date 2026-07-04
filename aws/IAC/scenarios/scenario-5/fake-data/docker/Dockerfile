FROM python:3.11-slim
WORKDIR /app
COPY .env /app/.env
RUN mkdir -p /app/config /root/.aws
COPY config/secrets.json /app/config/secrets.json
COPY aws-credentials /root/.aws/credentials
CMD ["python", "-m", "http.server", "8080"]
