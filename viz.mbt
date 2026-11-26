///|
fn esc_svg(s : String) -> String {
  let sb = StringBuilder()
  for ch in s {
    match ch {
      '&' => sb.write_string("&amp;")
      '<' => sb.write_string("&lt;")
      '>' => sb.write_string("&gt;")
      '"' => sb.write_string("&quot;")
      _ => sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
fn stream_color(sid : UInt32, kind : String) -> String {
  if kind == "GOAWAY" || kind == "RST_STREAM" {
    return "#f43f5e"
  }
  if sid == 0U {
    return "#38bdf8"
  }
  match sid / 2U % 5U {
    0U => "#34d399"
    1U => "#a78bfa"
    2U => "#fbbf24"
    3U => "#fb7185"
    _ => "#60a5fa"
  }
}

///|
/// Render an HTTP/2 connection's recorded frame exchange as a native SVG sequence timeline.
pub fn render_timeline_svg(entries : Array[FrameTraceEntry]) -> String {
  let max_rows = if entries.length() > 48 { 48 } else { entries.length() }
  let row_h = 30
  let top_h = 68
  let height = top_h + max_rows * row_h + 36
  let width = 760
  let left_x = 130
  let right_x = 630

  let sb = StringBuilder()
  sb.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" class=\"moon-http2-timeline\" viewBox=\"0 0 \{width} \{height}\" width=\"\{width}\" height=\"\{height}\">",
  )
  sb.write_string(
    "<rect width=\"100%\" height=\"100%\" fill=\"#0b1120\" rx=\"10\"/>",
  )
  sb.write_string(
    "<text x=\"24\" y=\"28\" fill=\"#f8fafc\" font-family=\"ui-monospace,monospace\" font-size=\"14\" font-weight=\"700\">moon-http2 Frame Timeline (\{entries.length()} frames)</text>",
  )
  sb.write_string(
    "<rect x=\"75\" y=\"38\" width=\"110\" height=\"22\" rx=\"5\" fill=\"#1e293b\" stroke=\"#38bdf8\"/><text x=\"130\" y=\"53\" text-anchor=\"middle\" fill=\"#e2e8f0\" font-family=\"ui-monospace,monospace\" font-size=\"11\">Client</text>",
  )
  sb.write_string(
    "<rect x=\"575\" y=\"38\" width=\"110\" height=\"22\" rx=\"5\" fill=\"#1e293b\" stroke=\"#34d399\"/><text x=\"630\" y=\"53\" text-anchor=\"middle\" fill=\"#e2e8f0\" font-family=\"ui-monospace,monospace\" font-size=\"11\">Server</text>",
  )
  sb.write_string(
    "<line x1=\"\{left_x}\" y1=\"60\" x2=\"\{left_x}\" y2=\"\{height - 16}\" stroke=\"#334155\" stroke-dasharray=\"4 4\"/>",
  )
  sb.write_string(
    "<line x1=\"\{right_x}\" y1=\"60\" x2=\"\{right_x}\" y2=\"\{height - 16}\" stroke=\"#334155\" stroke-dasharray=\"4 4\"/>",
  )

  for i = 0; i < max_rows; i = i + 1 {
    let e = entries[i]
    let y = top_h + i * row_h + 18
    let color = stream_color(e.stream_id, e.kind)
    let is_c2s = e.direction == "C->S"
    let x1 = if is_c2s { left_x + 4 } else { right_x - 4 }
    let x2 = if is_c2s { right_x - 8 } else { left_x + 8 }
    sb.write_string(
      "<line x1=\"\{x1}\" y1=\"\{y}\" x2=\"\{x2}\" y2=\"\{y}\" stroke=\"\{color}\" stroke-width=\"2\"/>",
    )
    if is_c2s {
      sb.write_string(
        "<polygon points=\"\{x2},\{y - 4} \{x2 + 7},\{y} \{x2},\{y + 4}\" fill=\"\{color}\"/>",
      )
    } else {
      sb.write_string(
        "<polygon points=\"\{x2},\{y - 4} \{x2 - 7},\{y} \{x2},\{y + 4}\" fill=\"\{color}\"/>",
      )
    }
    let label = esc_svg(
      "#\{e.seq} \{e.kind} [s=\{e.stream_id}] (\{e.payload_bytes}B) \{e.detail}",
    )
    sb.write_string(
      "<text x=\"380\" y=\"\{y - 5}\" text-anchor=\"middle\" fill=\"#e2e8f0\" font-family=\"ui-monospace,monospace\" font-size=\"10.5\">\{label}</text>",
    )
  }
  sb.write_string("</svg>")
  sb.to_string()
}

///|
/// Per-request HPACK compression statistics entry for SVG visualization.
#derive(Debug, Eq, ToJson)
pub(all) struct HpackSampleStat {
  request_index : Int32
  raw_bytes : Int32
  encoded_bytes : Int32
  dynamic_entries : Int32
  dynamic_bytes : Int32
}

///|
pub extend HpackSampleStat with @debug.Debug::{to_repr}

///|
pub extend HpackSampleStat with Eq::{not_equal, equal}

///|
pub extend HpackSampleStat with @json.ToJson::{to_json}

///|
/// Render HPACK compression ratio progression across consecutive requests as a native SVG chart.
pub fn render_hpack_svg(stats : Array[HpackSampleStat]) -> String {
  let width = 720
  let row_h = 34
  let top_h = 54
  let height = top_h + stats.length() * row_h + 28
  let mut max_raw = 1
  for st in stats {
    if st.raw_bytes > max_raw {
      max_raw = st.raw_bytes
    }
  }
  let bar_max = 420
  let sb = StringBuilder()
  sb.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" class=\"moon-http2-hpack\" viewBox=\"0 0 \{width} \{height}\" width=\"\{width}\" height=\"\{height}\">",
  )
  sb.write_string(
    "<rect width=\"100%\" height=\"100%\" fill=\"#0b1120\" rx=\"10\"/>",
  )
  sb.write_string(
    "<text x=\"20\" y=\"28\" fill=\"#f8fafc\" font-family=\"ui-monospace,monospace\" font-size=\"13.5\" font-weight=\"700\">HPACK Dynamic Table + Huffman Compression</text>",
  )
  for i = 0; i < stats.length(); i = i + 1 {
    let st = stats[i]
    let y = top_h + i * row_h
    let w_raw = st.raw_bytes * bar_max / max_raw
    let w_enc = st.encoded_bytes * bar_max / max_raw
    let saved_pct = if st.raw_bytes > 0 {
      (st.raw_bytes - st.encoded_bytes) * 100 / st.raw_bytes
    } else {
      0
    }
    sb.write_string(
      "<text x=\"20\" y=\"\{y + 15}\" fill=\"#cbd5e1\" font-family=\"ui-monospace,monospace\" font-size=\"11\">Req #\{st.request_index}</text>",
    )
    sb.write_string(
      "<rect x=\"84\" y=\"\{y + 3}\" width=\"\{w_raw}\" height=\"10\" rx=\"3\" fill=\"#334155\"/>",
    )
    sb.write_string(
      "<rect x=\"84\" y=\"\{y + 15}\" width=\"\{w_enc}\" height=\"10\" rx=\"3\" fill=\"#10b981\"/>",
    )
    sb.write_string(
      "<text x=\"516\" y=\"\{y + 17}\" fill=\"#e2e8f0\" font-family=\"ui-monospace,monospace\" font-size=\"10.5\">\{st.raw_bytes}B -&gt; \{st.encoded_bytes}B (-\{saved_pct}%) [dyn=\{st.dynamic_entries}]</text>",
    )
  }
  sb.write_string("</svg>")
  sb.to_string()
}
