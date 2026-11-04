// Starts the demo site DETACHED so it survives this step (GitHub Actions job
// steps share the runner, so later steps can scan localhost:4173), waits
// until it answers, then exits leaving the server running.
import { spawn } from 'node:child_process';
const child = spawn(process.execPath, ['server.mjs', 'site'], {
  stdio: 'ignore',
  detached: true
});
child.unref();
for (let i = 0; i < 40; i++) {
  try {
    const res = await fetch('http://127.0.0.1:4173/');
    if (res.ok) { console.log('site ready (detached server kept alive for later steps)'); process.exit(0); }
  } catch {}
  await new Promise((r) => setTimeout(r, 250));
}
console.error('site did not become ready');
process.exit(1);
