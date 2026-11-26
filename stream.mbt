///|
/// RFC 9113 §5.1 7-state HTTP/2 stream lifecycle.
#derive(Debug, Eq, ToJson)
pub(all) enum StreamState {
  Idle
  ReservedLocal
  ReservedRemote
  Open
  HalfClosedLocal
  HalfClosedRemote
  Closed
}

///|
pub extend StreamState with @debug.Debug::{to_repr}

///|
pub extend StreamState with Eq::{not_equal, equal}

///|
pub extend StreamState with @json.ToJson::{to_json}

///|
/// Per-stream state tracked by an `H2Connection`.
pub struct H2Stream {
  id : UInt32
  mut state : StreamState
  mut send_window : Int32
  mut recv_window : Int32
  mut recv_consumed : Int32
  mut expected_content_length : Int64?
  mut received_data_bytes : Int64
  mut headers_received : Bool
  mut req_headers : Array[HeaderField]
  req_body : @buffer.Buffer
  mut pending_body : Bytes
  mut pending_offset : Int32
  mut pending_end_stream : Bool
}

///|
fn H2Stream::new(
  id : UInt32,
  send_window : Int32,
  recv_window : Int32,
) -> H2Stream {
  {
    id,
    state: Open,
    send_window,
    recv_window,
    recv_consumed: 0,
    expected_content_length: None,
    received_data_bytes: 0L,
    headers_received: false,
    req_headers: [],
    req_body: @buffer.Buffer(size_hint=64),
    pending_body: Bytes::new(0),
    pending_offset: 0,
    pending_end_stream: false,
  }
}

///|
/// Validate RFC 9113 §8.1–§8.3 HTTP/2 request header block semantics.
/// Returns `Some(content_length)` if a valid `content-length` header is present.
pub fn validate_request_headers(
  stream_id : UInt32,
  headers : Array[HeaderField],
  is_trailer : Bool,
) -> Int64? raise H2Error {
  let mut seen_regular = false
  let mut seen_method = false
  let mut seen_scheme = false
  let mut seen_path = false
  let mut seen_authority = false
  let mut is_connect = false
  let mut content_len : Int64? = None

  for h in headers {
    let name = h.name
    let value = h.value
    if name.is_empty() {
      raise StreamError(stream_id, ProtocolError, "empty header field name")
    }
    // RFC 9113 §8.2.1: header field names MUST be lowercase ASCII
    for ch in name {
      let c = ch.to_int()
      if c >= 'A'.to_int() && c <= 'Z'.to_int() {
        raise StreamError(
          stream_id,
          ProtocolError,
          "uppercase character in header name '\{name}'",
        )
      }
      if c <= 0x20 || c >= 0x7f {
        raise StreamError(
          stream_id,
          ProtocolError,
          "invalid character in header name '\{name}'",
        )
      }
    }

    if name.has_prefix(":") {
      if is_trailer {
        raise StreamError(
          stream_id,
          ProtocolError,
          "pseudo-header '\{name}' not allowed in trailers",
        )
      }
      if seen_regular {
        raise StreamError(
          stream_id,
          ProtocolError,
          "pseudo-header '\{name}' appeared after regular header",
        )
      }
      match name {
        ":method" => {
          if seen_method || value.is_empty() {
            raise StreamError(
              stream_id,
              ProtocolError,
              "duplicate or empty :method pseudo-header",
            )
          }
          seen_method = true
          if value == "CONNECT" {
            is_connect = true
          }
        }
        ":scheme" => {
          if seen_scheme || value.is_empty() {
            raise StreamError(
              stream_id,
              ProtocolError,
              "duplicate or empty :scheme pseudo-header",
            )
          }
          seen_scheme = true
        }
        ":path" => {
          if seen_path || value.is_empty() {
            raise StreamError(
              stream_id,
              ProtocolError,
              "duplicate or empty :path pseudo-header",
            )
          }
          seen_path = true
        }
        ":authority" => {
          if seen_authority {
            raise StreamError(
              stream_id,
              ProtocolError,
              "duplicate :authority pseudo-header",
            )
          }
          seen_authority = true
        }
        _ =>
          raise StreamError(
            stream_id,
            ProtocolError,
            "unknown or forbidden request pseudo-header '\{name}'",
          )
      }
    } else {
      seen_regular = true
      // RFC 9113 §8.2.2: connection-specific header fields MUST NOT be used
      match name {
        "connection"
        | "keep-alive"
        | "proxy-connection"
        | "transfer-encoding"
        | "upgrade" =>
          raise StreamError(
            stream_id,
            ProtocolError,
            "forbidden connection-specific header '\{name}'",
          )
        "te" =>
          if value != "trailers" {
            raise StreamError(
              stream_id,
              ProtocolError,
              "TE header value must be 'trailers', got '\{value}'",
            )
          }
        "content-length" => {
          let parsed = parse_nonneg_i64(value)
          match parsed {
            Some(n) =>
              match content_len {
                Some(prev) if prev != n =>
                  raise StreamError(
                    stream_id,
                    ProtocolError,
                    "conflicting content-length headers",
                  )
                _ => content_len = Some(n)
              }
            None =>
              raise StreamError(
                stream_id,
                ProtocolError,
                "invalid content-length header '\{value}'",
              )
          }
        }
        _ => ()
      }
    }
  }

  if !is_trailer {
    if !seen_method {
      raise StreamError(
        stream_id,
        ProtocolError,
        "missing :method pseudo-header",
      )
    }
    if is_connect {
      if seen_scheme || seen_path || !seen_authority {
        raise StreamError(
          stream_id,
          ProtocolError,
          "CONNECT request must include :authority and omit :scheme/:path",
        )
      }
    } else if !seen_scheme || !seen_path {
      raise StreamError(
        stream_id,
        ProtocolError,
        "request missing required :scheme or :path pseudo-header",
      )
    }
  }
  content_len
}

///|
fn parse_nonneg_i64(s : String) -> Int64? {
  if s.is_empty() {
    return None
  }
  let mut acc = 0L
  for ch in s {
    let c = ch.to_int()
    if c < '0'.to_int() || c > '9'.to_int() {
      return None
    }
    acc = acc * 10L + (c - '0'.to_int()).to_int64()
  }
  Some(acc)
}
