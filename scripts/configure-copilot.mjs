import {randomBytes} from 'node:crypto';
import {readFile,appendFile} from 'node:fs/promises';
const env=new URL('../.env',import.meta.url),content=await readFile(env,'utf8');
if(!/^OPENCODE_SERVER_PASSWORD=/m.test(content))await appendFile(env,`\n# Isolated application runtime; unrelated to your personal OpenCode installation.\nOPENCODE_SERVER_PASSWORD=${randomBytes(32).toString('hex')}\n`,{mode:0o600});
console.log('Isolated OpenCode service authentication configured. Existing credentials were preserved; no secrets are printed.');
