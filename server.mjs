// Minimal static server for the demo site (real 404s, no SPA fallback).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.argv[2] || 'site');
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png' };

http.createServer((req, res) => {
  const urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  let filePath = path.normalize(path.join(root, urlPath));
  if (!filePath.startsWith(root)) { res.writeHead(403); res.end(); return; }
  let stat = fs.statSync(filePath, { throwIfNoEntry: false });
  if (stat?.isDirectory()) { filePath = path.join(filePath, 'index.html'); stat = fs.statSync(filePath, { throwIfNoEntry: false }); }
  if (!stat) { res.writeHead(404, { 'Content-Type': 'text/plain' }); res.end('404'); return; }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(filePath)] ?? 'application/octet-stream' });
  fs.createReadStream(filePath).pipe(res);
}).listen(process.env.PORT || 4173, '127.0.0.1', () => console.log('demo site ready'));
