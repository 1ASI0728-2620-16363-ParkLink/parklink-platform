import { randomBytes } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
const secret=()=>randomBytes(24).toString('hex');
const lines=['# Generated for local development only. Never commit.',`JWT_SECRET=${secret()}`,`RABBITMQ_PASSWORD=${secret()}`,`OPENCODE_SERVER_PASSWORD=${secret()}`];
for(const name of ['IDENTITY','SUPPLY','DISCOVERY','RESERVATION','PAYMENT','NOTIFICATION','AGENT','AUDIT'])lines.push(`${name}_DB_PASSWORD=${secret()}`);
await writeFile(new URL('../.env',import.meta.url),lines.join('\n')+'\n',{flag:'wx',mode:0o600});
console.log('Created .env with unique local credentials. Existing files are never overwritten.');
