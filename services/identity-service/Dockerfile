FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
COPY packages ./packages
COPY services/identity-service ./services/identity-service
RUN npm ci --workspace=@parklink/contracts --workspace=@parklink/runtime --workspace=@parklink/identity-service --include-workspace-root
RUN npm run build:shared && npm run build -w @parklink/identity-service && npm prune --omit=dev
FROM node:22-alpine
WORKDIR /app
COPY --from=build --chown=node:node /app /app
USER node
WORKDIR /app/services/identity-service
EXPOSE 3000
HEALTHCHECK CMD node -e "fetch('http://localhost:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node","dist/main.js"]
