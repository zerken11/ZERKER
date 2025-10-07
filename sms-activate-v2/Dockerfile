FROM node:22-bullseye

# Install build deps for better-sqlite3
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-dev build-essential libsqlite3-dev ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --production --no-audit --no-fund

# Copy application
COPY . .

EXPOSE 3000
CMD ["node", "backend/index.js"]
