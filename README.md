# moon-http2

[![Live Browser Workbench](https://img.shields.io/badge/Live%20Demo-GitHub%20Pages%20(Zero%20Upload)-047857?style=for-the-badge)](https://sam-hui-dot.github.io/moon-http2/)
[![CI](https://github.com/Sam-Hui-dot/moon-http2/actions/workflows/ci.yml/badge.svg)](https://github.com/Sam-Hui-dot/moon-http2/actions/workflows/ci.yml)
[![Mooncakes](https://img.shields.io/badge/mooncakes-Sam--Hui--dot%2Fmoon--http2%400.1.0-orange)](https://mooncakes.io/docs/Sam-Hui-dot/moon-http2%400.1.0)

Pure-MoonBit **Sans-I/O RFC 9113 HTTP/2 & RFC 7541 HPACK protocol engine**, native async `h2c` server, native SVG frame-timeline / HPACK compression visualizer, and zero-upload browser workbench.

- **Zero third-party dependencies** in the root Sans-I/O library (`Sam-Hui-dot/moon-http2`), verified across all four MoonBit targets (`wasm`, `wasm-gc`, `js`, `native`) with `--deny-warn`.
- **147 / 147 official `summerwind/h2spec v2.6.0` RFC 9113 conformance tests PASS** (0 skipped, 0 failed) against the live native `h2c` server.
- **14 / 14 official `http2jp/hpack-test-case` cross-implementation decode suites PASS** (`446` stories / `47,142` header blocks / `548,382` headers, 100% exact match) plus `raw-data` round-trip compression (`1,162,372 B -> 361,250 B`, `-68.92%`).
- **Node.js v24 `node:http2` live concurrent interop PASS** (`51` concurrent multiplexed streams including 40 GETs, 10 POST echoes, 32 KB window-chunked response, and PING).
- **Zero-Upload Browser Workbench**: [https://sam-hui-dot.github.io/moon-http2/](https://sam-hui-dot.github.io/moon-http2/).

## Verified External Oracle Results (`demo/verify_h2.py`)

| External Oracle | Scope | Result |
| --- | --- | --- |
| **`summerwind/h2spec v2.6.0`** (`-S` strict mode) | All RFC 9113 framing, stream states, flow control, HPACK, HTTP semantics | **`147 / 147` PASS** (0 skipped, 0 failed) |
| **`http2jp/hpack-test-case`** (cross-impl decode) | `14` implementations (`nghttp2`, `go-hpack`, `haskell-http2-*`, `node-http2`, `python-hpack`, `swift-nio`) | **`446` stories / `47,142` blocks / `548,382` headers — 100% exact** |
| **`http2jp/hpack-test-case/raw-data`** (round-trip) | `32` stories / `3,384` blocks encoded with Huffman + dynamic table and decoded back | **`1,162,372 B -> 361,250 B` (-68.92%, 0 errors)** |
| **Node.js `node:http2`** (live TCP `h2c`) | 40 GET + 10 POST echo + 32 KB chunked response + PING | **`51 / 51` concurrent streams PASS** |

## Architecture (`0.1.0`)

- **RFC 7541 HPACK (`huffman.mbt`, `hpack.mbt`)**: Complete Appendix B 257-symbol canonical Huffman table with strict §5.2 padding/EOS rejection, 61-entry static table, FIFO dynamic table (`name + value + 32` octets), prefixed integers, and all 5 header field representations.
- **RFC 9113 Wire Framing (`frame.mbt`, `error.mbt`)**: All 10 standard frame types (`DATA`, `HEADERS`, `PRIORITY`, `RST_STREAM`, `SETTINGS`, `PUSH_PROMISE`, `PING`, `GOAWAY`, `WINDOW_UPDATE`, `CONTINUATION`) plus unknown extension frame handling and strict length/flag/padding validation.
- **Sans-I/O Multiplexing & Flow Control (`stream.mbt`, `connection.mbt`)**: 7-state stream lifecycle, pseudo-header & connection-header validation, `content-length` verification, connection + per-stream send/receive flow-control windows (including negative-window tracking on `SETTINGS_INITIAL_WINDOW_SIZE` shrinkage and automatic `WINDOW_UPDATE` replenishment), `CONTINUATION` exclusivity, and `SETTINGS_MAX_CONCURRENT_STREAMS` enforcement.
- **Visualization & Reports (`viz.mbt`, `report.mbt`)**: Native SVG client-server frame sequence timeline (`render_timeline_svg`), HPACK compression progression chart (`render_hpack_svg`), and text/Markdown/JSON reports.

## Quick Start

### 1. MoonBit Library (`wasm` / `wasm-gc` / `js` / `native`)

```powershell
moon add Sam-Hui-dot/moon-http2@0.1.0
```

```moonbit
let conn = @moon-http2.H2Connection::new_server()
let server_settings = conn.take_outbound()
let events = conn.feed(client_wire_bytes)
for ev in events {
  match ev {
    RequestComplete(stream_id~, ..) =>
      conn.send_response(
        stream_id,
        200,
        extra_headers=[@moon-http2.header_field("content-type", "text/plain")],
        body=@moon-http2.ascii_to_bytes("hello from moon-http2"),
      )
    _ => ()
  }
}
let reply_bytes = conn.take_outbound()
let svg = @moon-http2.render_timeline_svg(conn.frame_trace())
```

### 2. Native `h2c` Server & Verification

```powershell
# Run 4-target unit tests
moon test --target wasm --deny-warn .
moon test --target wasm-gc --deny-warn .
moon test --target js --deny-warn .
moon test --target native --deny-warn .

# Build native CLI and run live h2c server
moon build --target native --release --deny-warn cmd/main
./_build/native/release/build/cmd/main/main serve --port 8080

# Run all 3 external Oracles (http2jp/hpack-test-case + h2spec v2.6.0 + node:http2)
python demo/verify_h2.py

# Build zero-upload browser workbench
python demo/build_web.py
```
