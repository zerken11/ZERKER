FROM node:18-bullseye

# Install build tools for better-sqlite3
RUN apt-get update && apt-get install -y \
    python3 make g++ \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY . .

EXPOSE 3000
CMD ["npm", "start"]

