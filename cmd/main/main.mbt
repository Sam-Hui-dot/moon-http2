///|
fn parse_int_arg(s : String, fallback : Int32) -> Int32 {
  let mut acc = 0
  let mut any = false
  for ch in s {
    let c = ch.to_int()
    if c >= '0'.to_int() && c <= '9'.to_int() {
      acc = acc * 10 + (c - '0'.to_int())
      any = true
    } else {
      return fallback
    }
  }
  if any {
    acc
  } else {
    fallback
  }
}

///|
fn headers_to_json(headers : Array[@h2.HeaderField]) -> Json {
  let arr : Array[Json] = []
  for h in headers {
    let obj : Map[String, Json] = Map([])
    obj.set(h.name, @json.ToJson::to_json(h.value))
    arr.push(Json::object(obj))
  }
  Json::array(arr)
}

///|
async fn cmd_hpack_decode_batch(path : String) -> Unit {
  let txt = @fs.read_file(path).text()
  let parsed = @json.parse(txt)
  let cases = match parsed {
    Object(m) =>
      match m.get("cases") {
        Some(Array(arr)) => arr
        _ => abort("missing 'cases' array in HPACK test file")
      }
    _ => abort("expected JSON object in HPACK test file")
  }
  let dec = @h2.HpackDecoder::new()
  let results : Array[Json] = []
  for c in cases {
    match c {
      Object(cm) => {
        match cm.get("header_table_size") {
          Some(Number(n, ..)) => dec.set_max_table_size_limit(n.to_int())
          _ => ()
        }
        let wire_hex = match cm.get("wire") {
          Some(String(s)) => s
          _ => abort("missing 'wire' hex in HPACK case")
        }
        let wire = @h2.hex_to_bytes(wire_hex)
        let hdrs = dec.decode(wire)
        results.push(headers_to_json(hdrs))
      }
      _ => abort("expected JSON object in cases")
    }
  }
  println(Json::array(results).stringify())
}

///|
async fn cmd_hpack_roundtrip_batch(path : String) -> Unit {
  let txt = @fs.read_file(path).text()
  let parsed = @json.parse(txt)
  let cases = match parsed {
    Object(m) =>
      match m.get("cases") {
        Some(Array(arr)) => arr
        _ => abort("missing 'cases' array")
      }
    _ => abort("expected JSON object")
  }
  let enc = @h2.HpackEncoder::new(use_huffman=true)
  let dec = @h2.HpackDecoder::new()
  let mut raw_total = 0
  let mut enc_total = 0
  let mut count = 0
  for c in cases {
    match c {
      Object(cm) => {
        let hdrs : Array[@h2.HeaderField] = []
        match cm.get("headers") {
          Some(Array(harr)) =>
            for item in harr {
              match item {
                Object(hm) =>
                  for k, v in hm {
                    match v {
                      String(sv) => {
                        hdrs.push(@h2.header_field(k, sv))
                        raw_total += k.length() + sv.length()
                      }
                      _ => ()
                    }
                  }
                _ => ()
              }
            }
          _ => ()
        }
        let wire = enc.encode(hdrs)
        enc_total += wire.length()
        let back = dec.decode(wire)
        if back.length() != hdrs.length() {
          abort("HPACK roundtrip header count mismatch at case #\{count}")
        }
        for i = 0; i < hdrs.length(); i = i + 1 {
          if back[i].name != hdrs[i].name || back[i].value != hdrs[i].value {
            abort("HPACK roundtrip mismatch at case #\{count} header #\{i}")
          }
        }
        count += 1
      }
      _ => ()
    }
  }
  println(
    Json::object({
      "cases": @json.ToJson::to_json(count),
      "raw_bytes": @json.ToJson::to_json(raw_total),
      "encoded_bytes": @json.ToJson::to_json(enc_total),
    }).stringify(),
  )
}

///|
async fn handle_h2c_client(sock : @socket.Tcp) -> Unit {
  defer sock.close()
  let conn = @h2.H2Connection::new_server()
  let init_out = conn.take_outbound()
  if !init_out.is_empty() {
    sock.write(init_out)
  }
  while !conn.is_closed() {
    let chunk_opt = sock.read_some(max_len=16384) catch { _ => None }
    match chunk_opt {
      None => break
      Some(chunk) => {
        if chunk.is_empty() {
          break
        }
        let events = conn.feed(chunk)
        for ev in events {
          match ev {
            RequestComplete(stream_id~, headers~, body~) => {
              let mut path = "/"
              let mut meth = "GET"
              for h in headers {
                if h.name == ":path" {
                  path = h.value
                } else if h.name == ":method" {
                  meth = h.value
                }
              }
              let resp_body = if !body.is_empty() {
                body
              } else if path == "/large" {
                let sb = StringBuilder()
                for _i = 0; _i < 1024; _i = _i + 1 {
                  sb.write_string("0123456789abcdef0123456789abcdef")
                }
                @h2.ascii_to_bytes(sb.to_string())
              } else {
                @h2.ascii_to_bytes("moon-http2 ok \{meth} \{path}")
              }
              let cl = "\{resp_body.length()}"
              conn.send_response(
                stream_id,
                200,
                extra_headers=[
                  @h2.header_field("content-type", "text/plain"),
                  @h2.header_field("content-length", cl),
                  @h2.header_field("server", "moon-http2/0.1.0"),
                ],
                body=resp_body,
              )
            }
            _ => ()
          }
        }
        let out = conn.take_outbound()
        if !out.is_empty() {
          sock.write(out) catch {
            _ => break
          }
        }
        if conn.is_closed() {
          @async.sleep(20)
          break
        }
      }
    }
  }
}

///|
async fn cmd_serve(port : Int32) -> Unit {
  let addr = @socket.Addr::parse("127.0.0.1:\{port}")
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  println("MOON_HTTP2_LISTENING 127.0.0.1:\{port}")
  server.run_forever(allow_failure=true, (sock, _peer) => {
    handle_h2c_client(sock)
  })
}

///|
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    println(
      "Usage: moon-http2 <serve --port N | hpack-decode-batch FILE | hpack-roundtrip-batch FILE | decode-hex HEX>",
    )
    return
  }
  match args[1] {
    "serve" => {
      let mut port = 8080
      for i = 2; i + 1 < args.length(); i = i + 1 {
        if args[i] == "--port" {
          port = parse_int_arg(args[i + 1], 8080)
        }
      }
      cmd_serve(port)
    }
    "hpack-decode-batch" => {
      if args.length() < 3 {
        abort("missing JSON file path")
      }
      cmd_hpack_decode_batch(args[2])
    }
    "hpack-roundtrip-batch" => {
      if args.length() < 3 {
        abort("missing JSON file path")
      }
      cmd_hpack_roundtrip_batch(args[2])
    }
    "decode-hex" => {
      if args.length() < 3 {
        abort("missing hex payload")
      }
      let conn = @h2.H2Connection::new_server()
      let _ = conn.take_outbound()
      let _ = conn.feed(@h2.hex_to_bytes(args[2]))
      println(@h2.render_trace_text(conn.frame_trace()))
    }
    other => abort("unknown command: \{other}")
  }
}
