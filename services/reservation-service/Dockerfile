FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
COPY packages ./packages
COPY services/reservation-service ./services/reservation-service
RUN npm ci --workspace=@parklink/contracts --workspace=@parklink/runtime --workspace=@parklink/reservation-service --include-workspace-root
RUN npm run build:shared && npm run build -w @parklink/reservation-service && npm prune --omit=dev
FROM node:22-alpine
WORKDIR /app
COPY --from=build --chown=node:node /app /app
USER node
WORKDIR /app/services/reservation-service
EXPOSE 3000
HEALTHCHECK CMD node -e "fetch('http://localhost:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node","dist/main.js"]
