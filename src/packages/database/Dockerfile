FROM node:18-slim

WORKDIR /app
COPY package.json .
COPY src ./src
COPY migrations ./migrations

RUN npm install --production

CMD ["node", "src/migrate.js"] 