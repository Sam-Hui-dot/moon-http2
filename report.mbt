///|
/// Format a frame timeline trace as concise human-readable text.
pub fn render_trace_text(entries : Array[FrameTraceEntry]) -> String {
  let sb = StringBuilder()
  sb.write_string("moon-http2 frame trace (\{entries.length()} frames)\n")
  for e in entries {
    sb.write_string(
      "  #\{e.seq} [\{e.direction}] \{e.kind} stream=\{e.stream_id} len=\{e.payload_bytes}B \{e.detail}\n",
    )
  }
  sb.to_string()
}

///|
/// Format a frame timeline trace as a GitHub-flavored Markdown table.
pub fn render_trace_markdown(entries : Array[FrameTraceEntry]) -> String {
  let sb = StringBuilder()
  sb.write_string("| Seq | Dir | Frame | Stream | Bytes | Detail |\n")
  sb.write_string("| ---: | :---: | --- | ---: | ---: | --- |\n")
  for e in entries {
    sb.write_string(
      "| \{e.seq} | \{e.direction} | `\{e.kind}` | \{e.stream_id} | \{e.payload_bytes} | \{e.detail} |\n",
    )
  }
  sb.to_string()
}
