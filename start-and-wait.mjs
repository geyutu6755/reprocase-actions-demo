// Starts the demo site and waits until it actually answers (no fixed sleep).
import { spawn } from 'node:child_process';
const child = spawn(process.execPath, ['server.mjs', 'site'], { stdio: 'ignore', detached: false });
process.on('exit', () => { try { child.kill(); } catch {} });
for (let i = 0; i < 40; i++) {
  try {
    const res = await fetch('http://127.0.0.1:4173/');
    if (res.ok) { console.log('site ready'); process.exit(0); }
  } catch {}
  await new Promise((r) => setTimeout(r, 250));
}
console.error('site did not become ready');
process.exit(1);
