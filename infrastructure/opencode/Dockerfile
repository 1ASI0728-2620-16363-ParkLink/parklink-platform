FROM node:22-alpine
RUN npm install --global opencode-ai@1.19.5 && npm cache clean --force
RUN mkdir -p /workspace /home/node/.local/share /home/node/.cache /home/node/.config && chown -R node:node /workspace /home/node
USER node
WORKDIR /workspace
ENV HOME=/home/node
ENV OPENCODE_DISABLE_DEFAULT_PLUGINS=true
ENV OPENCODE_DISABLE_AUTOUPDATE=true
ENV OPENCODE_DISABLE_SHARE=true
EXPOSE 4096
HEALTHCHECK --interval=10s --start-period=40s CMD node -e "fetch('http://localhost:4096/global/health',{headers:{Authorization:'Basic '+Buffer.from('opencode:'+process.env.OPENCODE_SERVER_PASSWORD).toString('base64')}}).then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["opencode","serve","--hostname=0.0.0.0","--port=4096"]
