import json
import os
import platform
import re
import shutil
import socket
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "demo" / ".oracle-cache"
OUT = ROOT / "demo" / "out"
OUT.mkdir(parents=True, exist_ok=True)
CACHE.mkdir(parents=True, exist_ok=True)

H2SPEC_VER = "2.6.0"


def find_cli_bin() -> Path:
    build = ROOT / "_build" / "native" / "release" / "build" / "cmd" / "main"
    for name in ("main.exe", "main"):
        p = build / name
        if p.exists():
            return p
    subprocess.run(
        ["moon", "build", "--target", "native", "--release", "--deny-warn", "cmd/main"],
        cwd=ROOT,
        check=True,
    )
    for name in ("main.exe", "main"):
        p = build / name
        if p.exists():
            return p
    raise FileNotFoundError(f"moon-http2 CLI binary not found in {build}")


def ensure_hpack_test_case() -> Path:
    repo = CACHE / "hpack-test-case"
    if (repo / "raw-data").exists():
        return repo
    if repo.exists():
        shutil.rmtree(repo)
    subprocess.run(
        ["git", "clone", "--depth", "1", "https://github.com/http2jp/hpack-test-case.git", str(repo)],
        check=True,
    )
    return repo


def ensure_h2spec() -> Path:
    sys_name = platform.system().lower()
    if sys_name == "windows":
        exe = CACHE / "h2spec.exe"
        url = f"https://github.com/summerwind/h2spec/releases/download/v{H2SPEC_VER}/h2spec_windows_amd64.zip"
    else:
        exe = CACHE / "h2spec"
        url = f"https://github.com/summerwind/h2spec/releases/download/v{H2SPEC_VER}/h2spec_linux_amd64.tar.gz"
    if exe.exists():
        return exe
    archive = CACHE / ("h2spec.zip" if sys_name == "windows" else "h2spec.tar.gz")
    print(f"Downloading official h2spec v{H2SPEC_VER} from {url} ...")
    for attempt in range(1, 4):
        try:
            urllib.request.urlretrieve(url, archive)
            break
        except Exception:
            if attempt == 3:
                raise
            time.sleep(2)
    if sys_name == "windows":
        with zipfile.ZipFile(archive, "r") as zf:
            zf.extract("h2spec.exe", CACHE)
    else:
        with tarfile.open(archive, "r:gz") as tf:
            tf.extract("h2spec", CACHE)
        os.chmod(exe, 0o755)
    return exe


def pick_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def verify_hpack_interop(cli: Path, repo: Path) -> dict:
    impl_dirs = sorted(
        d for d in repo.iterdir()
        if d.is_dir() and not d.name.startswith(".") and d.name != "raw-data" and list(d.glob("story_*.json"))
    )
    total_stories = 0
    total_cases = 0
    total_headers = 0
    for d in impl_dirs:
        stories = sorted(d.glob("story_*.json"))
        for story in stories:
            data = json.loads(story.read_text(encoding="utf-8"))
            proc = subprocess.run(
                [str(cli), "hpack-decode-batch", str(story)],
                capture_output=True,
                text=True,
                encoding="utf-8",
                check=True,
            )
            got = json.loads(proc.stdout)
            expected = [c["headers"] for c in data["cases"]]
            if got != expected:
                raise AssertionError(f"HPACK decode mismatch in {d.name}/{story.name}")
            total_stories += 1
            total_cases += len(expected)
            total_headers += sum(len(h) for h in expected)
        print(f"HPACK_INTEROP_OK {d.name:28s} stories={len(stories)}")

    raw_stories = sorted((repo / "raw-data").glob("story_*.json"))
    rt_cases = 0
    rt_raw = 0
    rt_enc = 0
    for story in raw_stories:
        proc = subprocess.run(
            [str(cli), "hpack-roundtrip-batch", str(story)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=True,
        )
        st = json.loads(proc.stdout)
        rt_cases += st["cases"]
        rt_raw += st["raw_bytes"]
        rt_enc += st["encoded_bytes"]
    ratio = round((1.0 - rt_enc / rt_raw) * 100.0, 2) if rt_raw > 0 else 0.0
    print(f"HPACK_ROUNDTRIP_OK stories={len(raw_stories)} cases={rt_cases} {rt_raw}B -> {rt_enc}B (-{ratio}%)")
    return {
        "impls": len(impl_dirs),
        "stories": total_stories,
        "cases": total_cases,
        "headers": total_headers,
        "rt_stories": len(raw_stories),
        "rt_cases": rt_cases,
        "rt_raw": rt_raw,
        "rt_enc": rt_enc,
        "rt_saved_pct": ratio,
    }


def start_server(cli: Path, port: int) -> subprocess.Popen:
    proc = subprocess.Popen(
        [str(cli), "serve", "--port", str(port)],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    deadline = time.time() + 10.0
    while time.time() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate()
            raise RuntimeError(f"moon-http2 server exited early:\n{out}\n{err}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return proc
        except OSError:
            time.sleep(0.1)
    proc.terminate()
    raise RuntimeError("Timed out waiting for moon-http2 server to listen")


def verify_h2spec(h2spec: Path, port: int) -> dict:
    proc = subprocess.run(
        [str(h2spec), "-h", "127.0.0.1", "-p", str(port), "-S"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    out = proc.stdout + "\n" + proc.stderr
    m = re.search(r"(\d+)\s+tests,\s+(\d+)\s+passed,\s+(\d+)\s+skipped,\s+(\d+)\s+failed", out)
    if not m:
        raise RuntimeError(f"Could not parse h2spec output:\n{out}")
    total, passed, skipped, failed = map(int, m.groups())
    print(f"H2SPEC_RESULT total={total} passed={passed} skipped={skipped} failed={failed}")
    if failed != 0 or proc.returncode != 0:
        print(out)
        raise AssertionError(f"h2spec failed: {passed}/{total} passed, {failed} failed")
    return {"total": total, "passed": passed, "skipped": skipped, "failed": failed}


def verify_node_http2(port: int) -> dict:
    script = rf"""
const http2 = require('http2');
const client = http2.connect('http://127.0.0.1:{port}');
client.on('error', (e) => {{ console.error(e); process.exit(1); }});

function req(method, path, body) {{
  return new Promise((resolve, reject) => {{
    const headers = {{ ':method': method, ':path': path }};
    if (body) headers['content-length'] = Buffer.byteLength(body);
    const stream = client.request(headers);
    let status = 0;
    const chunks = [];
    stream.on('response', (h) => {{ status = h[':status']; }});
    stream.on('data', (c) => chunks.push(c));
    stream.on('end', () => resolve({{ status, body: Buffer.concat(chunks).toString('utf8') }}));
    stream.on('error', reject);
    if (body) stream.write(body);
    stream.end();
  }});
}}

async function main() {{
  const tasks = [];
  for (let i = 0; i < 40; i++) {{
    tasks.push(req('GET', '/item/' + i).then(r => {{
      if (r.status !== 200 || r.body !== 'moon-http2 ok GET /item/' + i) throw new Error('GET mismatch ' + i);
    }}));
  }}
  for (let i = 0; i < 10; i++) {{
    const payload = 'payload-' + i + '-' + 'x'.repeat(256);
    tasks.push(req('POST', '/echo/' + i, payload).then(r => {{
      if (r.status !== 200 || r.body !== payload) throw new Error('POST echo mismatch ' + i);
    }}));
  }}
  tasks.push(req('GET', '/large').then(r => {{
    if (r.status !== 200 || r.body.length !== 32768) throw new Error('large body mismatch: ' + r.body.length);
  }}));
  await Promise.all(tasks);
  await new Promise((resolve, reject) => client.ping(Buffer.from('12345678'), (err) => err ? reject(err) : resolve()));
  client.close();
  console.log(JSON.stringify({{ streams: tasks.length, ping: true }}));
}}
main().catch(e => {{ console.error(e); process.exit(1); }});
"""
    proc = subprocess.run(["node", "-e", script], capture_output=True, text=True, encoding="utf-8", check=True)
    res = json.loads(proc.stdout.strip().splitlines()[-1])
    print(f"NODE_HTTP2_OK concurrent_streams={res['streams']} ping={res['ping']}")
    return res


def main() -> None:
    cli = find_cli_bin()
    hpack_repo = ensure_hpack_test_case()
    h2spec = ensure_h2spec()

    hp = verify_hpack_interop(cli, hpack_repo)

    port = pick_free_port()
    srv = start_server(cli, port)
    try:
        hs = verify_h2spec(h2spec, port)
        nh = verify_node_http2(port)
    finally:
        srv.terminate()
        try:
            srv.wait(timeout=3)
        except subprocess.TimeoutExpired:
            srv.kill()

    summary = "\n".join([
        "## Official HTTP/2 & HPACK Differential Oracle Summary",
        "",
        f"- **Official `http2jp/hpack-test-case` cross-implementation decode**: **`{hp['impls']}` implementations / `{hp['stories']}` stories / `{hp['cases']}` header blocks / `{hp['headers']}` headers — 100% exact match**",
        f"- **Official `http2jp/hpack-test-case/raw-data` round-trip compression**: `{hp['rt_stories']}` stories / `{hp['rt_cases']}` blocks, `{hp['rt_raw']}` B -> `{hp['rt_enc']}` B (**-{hp['rt_saved_pct']}%**, 0 errors)",
        f"- **Official `summerwind/h2spec v{H2SPEC_VER}` RFC 9113 strict conformance**: **`{hs['passed']}/{hs['total']}` passed** (`{hs['skipped']}` skipped, **`{hs['failed']}` failed**)",
        f"- **Node.js `node:http2` live concurrent client interop**: **`{nh['streams']}` concurrent multiplexed streams (GET + POST echo + 32 KB chunked response) + PING — 100% PASS**",
        "",
    ])
    (OUT / "h2-oracle-summary.md").write_text(summary, encoding="utf-8")
    print(summary)


if __name__ == "__main__":
    main()
