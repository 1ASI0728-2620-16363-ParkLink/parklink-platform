FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
COPY apps/owner-dashboard ./apps/owner-dashboard
RUN npm ci --workspace=@parklink/owner-dashboard --include-workspace-root
ARG VITE_API_URL=http://localhost:3000
ENV VITE_API_URL=$VITE_API_URL
RUN npm run build -w @parklink/owner-dashboard
FROM nginxinc/nginx-unprivileged:1.28-alpine
COPY --from=build /app/apps/owner-dashboard/dist /usr/share/nginx/html
EXPOSE 8080
