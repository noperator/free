FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    wget \
    parallel \
    nodejs \
    npm \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g wrangler

RUN curl -fsSLO https://github.com/aptible/supercronic/releases/download/v0.2.41/supercronic-linux-amd64 && \
    chmod +x supercronic-linux-amd64 && \
    mv supercronic-linux-amd64 /usr/local/bin/supercronic

WORKDIR /app

COPY requirements.txt .
RUN python3 -m venv venv && \
    ./venv/bin/pip install --no-cache-dir -r requirements.txt

COPY main.py deploy.sh ./
RUN chmod +x deploy.sh

RUN mkdir -p deploy cal

# Create crontab
RUN echo "*/5 * * * * /app/deploy.sh" > /app/crontab

CMD ["supercronic", "/app/crontab"]
