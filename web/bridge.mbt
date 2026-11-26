///|
fn json_err(err : Error) -> String {
  Json::object({
    "ok": @json.ToJson::to_json(false),
    "error": @json.ToJson::to_json(@h2.error_message(err)),
  }).stringify()
}

///|
/// Analyze a raw hexadecimal HTTP/2 client wire stream through `H2Connection::new_server()`,
/// returning decoded frames, trace, outbound server frames, and native SVG timeline.
pub fn analyze_hex_json(hex_stream : String) -> String {
  try {
    let raw = @h2.hex_to_bytes(hex_stream)
    let conn = @h2.H2Connection::new_server()
    let _ = conn.take_outbound()
    let events = conn.feed(raw)
    let mut completed = 0
    for ev in events {
      match ev {
        RequestComplete(stream_id~, headers~, body~) => {
          completed += 1
          let mut path = "/"
          for h in headers {
            if h.name == ":path" {
              path = h.value
            }
          }
          let resp = if !body.is_empty() {
            body
          } else {
            @h2.ascii_to_bytes("ok \{path}")
          }
          conn.send_response(
            stream_id,
            200,
            extra_headers=[@h2.header_field("content-type", "text/plain")],
            body=resp,
          )
        }
        _ => ()
      }
    }
    let outbound = conn.take_outbound()
    let trace = conn.frame_trace()
    Json::object({
      "ok": @json.ToJson::to_json(true),
      "closed": @json.ToJson::to_json(conn.is_closed()),
      "completed_requests": @json.ToJson::to_json(completed),
      "outbound_hex": @json.ToJson::to_json(@h2.bytes_to_hex(outbound)),
      "trace": @json.ToJson::to_json(trace),
      "timeline_svg": @json.ToJson::to_json(@h2.render_timeline_svg(trace)),
      "markdown": @json.ToJson::to_json(@h2.render_trace_markdown(trace)),
    }).stringify()
  } catch {
    err => json_err(err)
  }
}

///|
/// Encode a sequence of header blocks with HPACK (Huffman + Dynamic Table) and decode them back,
/// returning per-request hex, compression stats, and native SVG chart.
pub fn hpack_demo_json(requests_json : String) -> String {
  try {
    let parsed = @json.parse(requests_json)
    let enc = @h2.HpackEncoder::new(use_huffman=true)
    let dec = @h2.HpackDecoder::new()
    let stats : Array[@h2.HpackSampleStat] = []
    let blocks : Array[Json] = []
    match parsed {
      Array(reqs) =>
        for idx = 0; idx < reqs.length(); idx = idx + 1 {
          let hdrs : Array[@h2.HeaderField] = []
          let mut raw_len = 0
          match reqs[idx] {
            Array(pairs) =>
              for p in pairs {
                match p {
                  Array([String(k), String(v)]) => {
                    hdrs.push(@h2.header_field(k, v))
                    raw_len += k.length() + v.length()
                  }
                  _ => ()
                }
              }
            _ => ()
          }
          let wire = enc.encode(hdrs)
          let back = dec.decode(wire)
          stats.push({
            request_index: idx + 1,
            raw_bytes: raw_len,
            encoded_bytes: wire.length(),
            dynamic_entries: enc.table.len(),
            dynamic_bytes: enc.table.size(),
          })
          blocks.push(
            Json::object({
              "hex": @json.ToJson::to_json(@h2.bytes_to_hex(wire)),
              "encoded_bytes": @json.ToJson::to_json(wire.length()),
              "raw_bytes": @json.ToJson::to_json(raw_len),
              "decoded": @json.ToJson::to_json(back),
            }),
          )
        }
      _ => abort("expected JSON array of requests")
    }
    Json::object({
      "ok": @json.ToJson::to_json(true),
      "blocks": Json::array(blocks),
      "stats": @json.ToJson::to_json(stats),
      "hpack_svg": @json.ToJson::to_json(@h2.render_hpack_svg(stats)),
    }).stringify()
  } catch {
    err => json_err(err)
  }
}

///|
/// Build a canonical multi-stream HTTP/2 client wire scenario in hex for browser presets.
pub fn build_preset_hex(scenario : String) -> String {
  let enc = @h2.HpackEncoder::new(use_huffman=true)
  let buf = @buffer.Buffer(size_hint=256)
  buf.write_bytesview(@h2.ascii_to_bytes(@h2.CLIENT_PREFACE_STR)[:])
  @h2.encode_frame_into(buf, Settings(ack=false, params=[]))
  match scenario {
    "protocol_error" => {
      // Invalid even client stream ID -> triggers GOAWAY PROTOCOL_ERROR
      let h = enc.encode([
        @h2.header_field(":method", "GET"),
        @h2.header_field(":scheme", "http"),
        @h2.header_field(":path", "/bad-even-stream"),
        @h2.header_field(":authority", "example.org"),
      ])
      @h2.encode_frame_into(
        buf,
        Headers(
          stream_id=2U,
          end_stream=true,
          end_headers=true,
          priority=None,
          fragment=h,
        ),
      )
    }
    "continuation" => {
      let h = enc.encode([
        @h2.header_field(":method", "GET"),
        @h2.header_field(":scheme", "https"),
        @h2.header_field(":path", "/api/v1/items"),
        @h2.header_field(":authority", "api.moonbit.dev"),
        @h2.header_field("x-trace-id", "trace-99482716-abcd"),
      ])
      let mid = h.length() / 2
      let b1 = @buffer.Buffer()
      b1.write_bytesview(h[0:mid])
      let b2 = @buffer.Buffer()
      b2.write_bytesview(h[mid:h.length()])
      @h2.encode_frame_into(
        buf,
        Headers(
          stream_id=1U,
          end_stream=true,
          end_headers=false,
          priority=None,
          fragment=b1.to_bytes(),
        ),
      )
      @h2.encode_frame_into(
        buf,
        Continuation(stream_id=1U, end_headers=true, fragment=b2.to_bytes()),
      )
    }
    _ => {
      // Multiplexed 3-stream RPC + POST body + PING
      let h1 = enc.encode([
        @h2.header_field(":method", "GET"),
        @h2.header_field(":scheme", "https"),
        @h2.header_field(":path", "/users/42"),
        @h2.header_field(":authority", "api.moonbit.dev"),
      ])
      let h3 = enc.encode([
        @h2.header_field(":method", "POST"),
        @h2.header_field(":scheme", "https"),
        @h2.header_field(":path", "/echo"),
        @h2.header_field(":authority", "api.moonbit.dev"),
        @h2.header_field("content-length", "18"),
      ])
      let h5 = enc.encode([
        @h2.header_field(":method", "GET"),
        @h2.header_field(":scheme", "https"),
        @h2.header_field(":path", "/healthz"),
        @h2.header_field(":authority", "api.moonbit.dev"),
      ])
      @h2.encode_frame_into(
        buf,
        Headers(
          stream_id=1U,
          end_stream=true,
          end_headers=true,
          priority=None,
          fragment=h1,
        ),
      )
      @h2.encode_frame_into(
        buf,
        Headers(
          stream_id=3U,
          end_stream=false,
          end_headers=true,
          priority=None,
          fragment=h3,
        ),
      )
      @h2.encode_frame_into(
        buf,
        Data(
          stream_id=3U,
          end_stream=true,
          data=@h2.ascii_to_bytes("{\"hello\":\"moonh2\"}"),
          flow_len=18,
        ),
      )
      @h2.encode_frame_into(
        buf,
        Headers(
          stream_id=5U,
          end_stream=true,
          end_headers=true,
          priority=None,
          fragment=h5,
        ),
      )
      @h2.encode_frame_into(
        buf,
        Ping(ack=false, opaque_data=@h2.ascii_to_bytes("moonping")),
      )
    }
  }
  @h2.bytes_to_hex(buf.to_bytes())
}

///|
extern "js" fn register_browser_api(
  analyze_fn : (String) -> String,
  hpack_fn : (String) -> String,
  preset_fn : (String) -> String,
) -> Unit =
  #|(analyzeFn, hpackFn, presetFn) => {
  #|  globalThis.MoonHttp2 = {
  #|    analyzeHex: (hex) => JSON.parse(analyzeFn(hex)),
  #|    hpackDemo: (reqs) => JSON.parse(hpackFn(JSON.stringify(reqs))),
  #|    buildPresetHex: (name) => presetFn(name),
  #|  };
  #|}

///|
fn main {
  register_browser_api(analyze_hex_json, hpack_demo_json, build_preset_hex)
}
