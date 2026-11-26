import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"


def main() -> None:
    cmd = ["moon", "build", "--target", "js", "--release", "--deny-warn", "web"]
    print("Running:", " ".join(cmd))
    subprocess.run(cmd, cwd=ROOT, check=True)

    built_js = ROOT / "_build" / "js" / "release" / "build" / "web" / "web.js"
    if not built_js.exists():
        raise FileNotFoundError(f"Expected JS build artifact not found: {built_js}")

    DOCS.mkdir(parents=True, exist_ok=True)
    target_js = DOCS / "moon-http2.js"
    shutil.copy2(built_js, target_js)
    print(f"Copied {built_js} -> {target_js} ({target_js.stat().st_size} bytes)")

    smoke = r"""
require('./docs/moon-http2.js');
const H2 = globalThis.MoonHttp2;
for (const name of ['multiplex', 'continuation', 'protocol_error']) {
  const hex = H2.buildPresetHex(name);
  const res = H2.analyzeHex(hex);
  if (!res.ok) throw new Error('analyzeHex failed for ' + name + ': ' + res.error);
  if (!res.timeline_svg.includes('moon-http2-timeline')) throw new Error('missing timeline svg');
  console.log('WEB_SMOKE_OK', name, 'frames=' + res.trace.length, 'closed=' + res.closed, 'reqs=' + res.completed_requests);
}
const hp = H2.hpackDemo([
  [[':method','GET'],[':scheme','https'],[':path','/api/v1/orders'],[':authority','shop.example.com'],['authorization','Bearer tok_demo_001']],
  [[':method','GET'],[':scheme','https'],[':path','/api/v1/orders'],[':authority','shop.example.com'],['authorization','Bearer tok_demo_001'],['cache-control','no-cache']],
  [[':method','POST'],[':scheme','https'],[':path','/api/v1/orders'],[':authority','shop.example.com'],['authorization','Bearer tok_demo_001']],
]);
if (!hp.ok || !hp.hpack_svg.includes('moon-http2-hpack')) throw new Error('hpackDemo failed');
console.log('WEB_HPACK_OK', hp.stats.map(s => `${s.raw_bytes}->${s.encoded_bytes}`).join(', '));
"""
    subprocess.run(["node", "-e", smoke], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
