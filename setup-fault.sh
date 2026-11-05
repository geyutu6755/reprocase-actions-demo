#!/bin/bash
set -euo pipefail
mkdir -p site
cat > site/fault-page.html << 'PAGE'
<!doctype html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Fault</title></head>
<body>
<p>Fault page</p>
<img src="./missing-fault-asset.png" alt="x" width="10" height="10">
<script>
document.addEventListener("DOMContentLoaded",function(){throw new Error("VerificationFault: setup fault")});
</script>
</body>
</html>
PAGE
node -e "
const fs = require('fs');
let t = fs.readFileSync('site/index.html', 'utf8');
if (!t.includes('fault-page.html')) {
  t = t.replace('</main>', '<p><a href=\"./fault-page.html\">Fault page</a></p></main>');
  fs.writeFileSync('site/index.html', t);
}
"
echo "fault page injected"
