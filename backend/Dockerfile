FROM node:20-alpine
WORKDIR /app

# Install deps first (cached layer)
COPY package*.json ./
RUN npm ci --omit=dev

COPY . .

EXPOSE 3000
CMD ["node", "server.js"]
