///|
/// High-level events emitted by `H2Connection::feed` for application handlers and visualizers.
#derive(Debug, Eq)
pub(all) enum H2Event {
  SettingsUpdated(Array[SettingParam])
  RequestHeaders(
    stream_id~ : UInt32,
    headers~ : Array[HeaderField],
    end_stream~ : Bool
  )
  RequestData(stream_id~ : UInt32, data~ : Bytes, end_stream~ : Bool)
  RequestComplete(
    stream_id~ : UInt32,
    headers~ : Array[HeaderField],
    body~ : Bytes
  )
  StreamReset(stream_id~ : UInt32, code~ : H2ErrorCode)
  PingReceived(ack~ : Bool, opaque_data~ : Bytes)
  GoAwayReceived(
    last_stream_id~ : UInt32,
    code~ : H2ErrorCode,
    debug_data~ : Bytes
  )
  WindowUpdated(stream_id~ : UInt32, increment~ : UInt32)
}

///|
pub extend H2Event with @debug.Debug::{to_repr}

///|
pub extend H2Event with Eq::{not_equal, equal}

///|
/// Recorded wire frame trace entry for SVG timeline rendering and diagnostics.
#derive(Debug, Eq, ToJson)
pub(all) struct FrameTraceEntry {
  seq : Int32
  direction : String
  kind : String
  stream_id : UInt32
  payload_bytes : Int32
  detail : String
}

///|
pub extend FrameTraceEntry with @debug.Debug::{to_repr}

///|
pub extend FrameTraceEntry with Eq::{not_equal, equal}

///|
pub extend FrameTraceEntry with @json.ToJson::{to_json}

///|
/// Sans-I/O RFC 9113 HTTP/2 server connection state machine.
pub struct H2Connection {
  mut preface_checked : Bool
  recv_buf : @buffer.Buffer
  send_buf : @buffer.Buffer
  hpack_dec : HpackDecoder
  hpack_enc : HpackEncoder
  streams : Map[UInt32, H2Stream]
  mut last_remote_stream_id : UInt32
  local_max_frame_size : Int32
  mut remote_max_frame_size : Int32
  local_initial_window : Int32
  mut remote_initial_window : Int32
  local_max_concurrent_streams : Int32
  mut conn_send_window : Int32
  mut conn_recv_window : Int32
  mut conn_recv_consumed : Int32
  mut expect_continuation_stream : UInt32?
  mut continuation_end_stream : Bool
  continuation_buf : @buffer.Buffer
  mut goaway_sent : Bool
  mut closed : Bool
  trace : Array[FrameTraceEntry]
}

///|
/// Create a new Sans-I/O HTTP/2 server connection and enqueue the initial server `SETTINGS` frame.
pub fn H2Connection::new_server(
  max_concurrent_streams~ : Int32 = 128,
  initial_window_size~ : Int32 = DEFAULT_INITIAL_WINDOW_SIZE,
  max_frame_size~ : Int32 = DEFAULT_MAX_FRAME_SIZE,
) -> H2Connection {
  let conn : H2Connection = {
    preface_checked: false,
    recv_buf: @buffer.Buffer(size_hint=256),
    send_buf: @buffer.Buffer(size_hint=256),
    hpack_dec: HpackDecoder::new(),
    hpack_enc: HpackEncoder::new(),
    streams: Map([]),
    last_remote_stream_id: 0U,
    local_max_frame_size: max_frame_size,
    remote_max_frame_size: DEFAULT_MAX_FRAME_SIZE,
    local_initial_window: initial_window_size,
    remote_initial_window: DEFAULT_INITIAL_WINDOW_SIZE,
    local_max_concurrent_streams: max_concurrent_streams,
    conn_send_window: DEFAULT_INITIAL_WINDOW_SIZE,
    conn_recv_window: DEFAULT_INITIAL_WINDOW_SIZE,
    conn_recv_consumed: 0,
    expect_continuation_stream: None,
    continuation_end_stream: false,
    continuation_buf: @buffer.Buffer(size_hint=128),
    goaway_sent: false,
    closed: false,
    trace: [],
  }
  let init_settings = Settings(ack=false, params=[
    {
      id: SETTING_MAX_CONCURRENT_STREAMS,
      value: max_concurrent_streams.reinterpret_as_uint(),
    },
    {
      id: SETTING_INITIAL_WINDOW_SIZE,
      value: initial_window_size.reinterpret_as_uint(),
    },
    { id: SETTING_MAX_FRAME_SIZE, value: max_frame_size.reinterpret_as_uint(), },
  ])
  conn.queue_frame(init_settings, "initial server settings")
  conn
}

///|
fn H2Connection::record_trace(
  self : H2Connection,
  direction : String,
  frame : H2Frame,
  payload_bytes : Int32,
  detail : String,
) -> Unit {
  self.trace.push({
    seq: self.trace.length() + 1,
    direction,
    kind: frame.kind_name(),
    stream_id: frame.stream_id(),
    payload_bytes,
    detail,
  })
}

///|
fn H2Connection::queue_frame(
  self : H2Connection,
  frame : H2Frame,
  detail : String,
) -> Unit {
  let before = self.send_buf.length()
  encode_frame_into(self.send_buf, frame)
  let written = self.send_buf.length() - before
  self.record_trace("S->C", frame, written - 9, detail)
}

///|
/// Drain all pending outbound wire bytes produced by the connection.
pub fn H2Connection::take_outbound(self : H2Connection) -> Bytes {
  let out = self.send_buf.to_bytes()
  self.send_buf.reset()
  out
}

///|
/// Return whether the connection has sent `GOAWAY` and should be closed after flushing outbound bytes.
pub fn H2Connection::is_closed(self : H2Connection) -> Bool {
  self.closed
}

///|
/// Return the recorded frame timeline trace for visualization.
pub fn H2Connection::frame_trace(self : H2Connection) -> Array[FrameTraceEntry] {
  self.trace
}

///|
/// Send a `GOAWAY` frame and mark the connection closed.
pub fn H2Connection::send_goaway(
  self : H2Connection,
  code : H2ErrorCode,
  debug_msg~ : String = "",
) -> Unit {
  if !self.goaway_sent {
    self.goaway_sent = true
    self.closed = true
    self.queue_frame(
      GoAway(
        last_stream_id=self.last_remote_stream_id,
        code~,
        debug_data=ascii_to_bytes(debug_msg),
      ),
      "\{code.label()} \{debug_msg}",
    )
  }
}

///|
/// Send an HTTP/2 response (`HEADERS` + chunked `DATA` frames respecting flow-control and `MAX_FRAME_SIZE`).
pub fn H2Connection::send_response(
  self : H2Connection,
  stream_id : UInt32,
  status : Int32,
  extra_headers~ : Array[HeaderField] = [],
  body~ : Bytes = Bytes::new(0),
) -> Unit {
  let headers : Array[HeaderField] = [header_field(":status", "\{status}")]
  for h in extra_headers {
    headers.push(h)
  }
  let encoded = self.hpack_enc.encode(headers)
  let end_on_headers = body.is_empty()
  // Split header block across HEADERS + CONTINUATION if larger than remote_max_frame_size
  let max_f = self.remote_max_frame_size
  if encoded.length() <= max_f {
    self.queue_frame(
      Headers(
        stream_id~,
        end_stream=end_on_headers,
        end_headers=true,
        priority=None,
        fragment=encoded,
      ),
      ":status=\{status}",
    )
  } else {
    let mut off = 0
    let mut first = true
    while off < encoded.length() {
      let chunk_end = if off + max_f < encoded.length() {
        off + max_f
      } else {
        encoded.length()
      }
      let is_last = chunk_end == encoded.length()
      let frag = slice_bytes(encoded, off, chunk_end)
      if first {
        self.queue_frame(
          Headers(
            stream_id~,
            end_stream=end_on_headers,
            end_headers=is_last,
            priority=None,
            fragment=frag,
          ),
          ":status=\{status}",
        )
        first = false
      } else {
        self.queue_frame(
          Continuation(stream_id~, end_headers=is_last, fragment=frag),
          "continuation",
        )
      }
      off = chunk_end
    }
  }

  if !end_on_headers {
    match self.streams.get(stream_id) {
      Some(st) => {
        st.pending_body = body
        st.pending_offset = 0
        st.pending_end_stream = true
        self.flush_stream_data(st)
      }
      None => ()
    }
  } else {
    match self.streams.get(stream_id) {
      Some(st) =>
        st.state = match st.state {
          HalfClosedRemote => Closed
          Open => HalfClosedLocal
          other => other
        }
      None => ()
    }
  }
}

///|
fn H2Connection::flush_stream_data(self : H2Connection, st : H2Stream) -> Unit {
  if !st.pending_end_stream {
    return
  }
  match st.state {
    Closed => {
      st.pending_end_stream = false
      return
    }
    _ => ()
  }
  let max_f = self.remote_max_frame_size
  while st.pending_offset < st.pending_body.length() {
    let avail = if self.conn_send_window < st.send_window {
      self.conn_send_window
    } else {
      st.send_window
    }
    if avail <= 0 {
      return
    }
    let rem = st.pending_body.length() - st.pending_offset
    let mut chunk_len = if rem < avail { rem } else { avail }
    if chunk_len > max_f {
      chunk_len = max_f
    }
    let is_last = st.pending_offset + chunk_len == st.pending_body.length()
    let chunk = slice_bytes(
      st.pending_body,
      st.pending_offset,
      st.pending_offset + chunk_len,
    )
    self.conn_send_window -= chunk_len
    st.send_window -= chunk_len
    st.pending_offset += chunk_len
    self.queue_frame(
      Data(stream_id=st.id, end_stream=is_last, data=chunk, flow_len=chunk_len),
      "\{chunk_len} B",
    )
    if is_last {
      st.pending_end_stream = false
      st.state = match st.state {
        HalfClosedRemote => Closed
        Open => HalfClosedLocal
        other => other
      }
    }
  }
}

///|
fn H2Connection::flush_all_pending_data(self : H2Connection) -> Unit {
  for _, st in self.streams {
    if st.pending_end_stream {
      self.flush_stream_data(st)
    }
  }
}

///|
fn H2Connection::active_remote_streams(self : H2Connection) -> Int32 {
  let mut count = 0
  for _, st in self.streams {
    match st.state {
      Open | HalfClosedLocal | HalfClosedRemote => count += 1
      _ => ()
    }
  }
  count
}

///|
fn H2Connection::finish_header_block(
  self : H2Connection,
  stream_id : UInt32,
  block : Bytes,
  end_stream : Bool,
  events : Array[H2Event],
) -> Unit raise H2Error {
  let headers = self.hpack_dec.decode(block) catch {
    CompressionError(msg) => raise ConnectionError(CompressionError, msg)
    err => raise err
  }
  let st = match self.streams.get(stream_id) {
    Some(s) => s
    None => raise ConnectionError(InternalError, "missing stream #\{stream_id}")
  }
  let is_trailer = st.headers_received
  if is_trailer && !end_stream {
    raise StreamError(
      stream_id,
      ProtocolError,
      "trailing HEADERS frame must set END_STREAM",
    )
  }
  let cl_opt = validate_request_headers(stream_id, headers, is_trailer)
  if !is_trailer {
    st.headers_received = true
    st.req_headers = headers
    st.expected_content_length = cl_opt
  }
  events.push(RequestHeaders(stream_id~, headers~, end_stream~))
  if end_stream {
    match st.expected_content_length {
      Some(expected) if st.received_data_bytes != expected =>
        raise StreamError(
          stream_id,
          ProtocolError,
          "content-length mismatch: expected \{expected}, received \{st.received_data_bytes}",
        )
      _ => ()
    }
    st.state = match st.state {
      Open => HalfClosedRemote
      HalfClosedLocal => Closed
      other => other
    }
    events.push(
      RequestComplete(
        stream_id~,
        headers=st.req_headers,
        body=st.req_body.to_bytes(),
      ),
    )
  }
}

///|
fn H2Connection::handle_frame(
  self : H2Connection,
  frame : H2Frame,
  events : Array[H2Event],
) -> Unit raise H2Error {
  // Enforce CONTINUATION exclusivity (RFC 9113 §6.10)
  match self.expect_continuation_stream {
    Some(expected_sid) =>
      match frame {
        Continuation(stream_id~, end_headers~, fragment~) if stream_id ==
          expected_sid => {
          self.record_trace(
            "C->S",
            frame,
            fragment.length(),
            if end_headers {
              "END_HEADERS"
            } else {
              "fragment"
            },
          )
          self.continuation_buf.write_bytesview(fragment[:])
          if end_headers {
            let full = self.continuation_buf.to_bytes()
            self.continuation_buf.reset()
            let end_s = self.continuation_end_stream
            self.expect_continuation_stream = None
            self.finish_header_block(expected_sid, full, end_s, events)
          }
          return
        }
        _ =>
          raise ConnectionError(
            ProtocolError,
            "expected CONTINUATION on stream #\{expected_sid}, got \{frame.kind_name()}",
          )
      }
    None => ()
  }

  match frame {
    Settings(ack~, params~) => {
      self.record_trace(
        "C->S",
        frame,
        params.length() * 6,
        if ack {
          "ACK"
        } else {
          "\{params.length()} params"
        },
      )
      if ack {
        return
      }
      for p in params {
        match p.id {
          SETTING_HEADER_TABLE_SIZE =>
            self.hpack_enc.set_max_table_size(p.value.reinterpret_as_int())
          SETTING_ENABLE_PUSH =>
            if p.value != 0U && p.value != 1U {
              raise ConnectionError(
                ProtocolError,
                "invalid SETTINGS_ENABLE_PUSH value \{p.value}",
              )
            }
          SETTING_MAX_CONCURRENT_STREAMS => ()
          SETTING_INITIAL_WINDOW_SIZE => {
            if p.value > MAX_WINDOW_SIZE.reinterpret_as_uint() {
              raise ConnectionError(
                FlowControlError,
                "SETTINGS_INITIAL_WINDOW_SIZE exceeds 2^31 - 1",
              )
            }
            let new_win = p.value.reinterpret_as_int()
            let delta = new_win - self.remote_initial_window
            self.remote_initial_window = new_win
            for _, st in self.streams {
              match st.state {
                Open | HalfClosedRemote => {
                  let updated = st.send_window.to_int64() + delta.to_int64()
                  if updated > MAX_WINDOW_SIZE.to_int64() {
                    raise ConnectionError(
                      FlowControlError,
                      "SETTINGS_INITIAL_WINDOW_SIZE caused stream send window overflow",
                    )
                  }
                  st.send_window = updated.to_int()
                }
                _ => ()
              }
            }
          }
          SETTING_MAX_FRAME_SIZE => {
            let v = p.value.reinterpret_as_int()
            if p.value < DEFAULT_MAX_FRAME_SIZE.reinterpret_as_uint() ||
              p.value > MAX_ALLOWED_FRAME_SIZE.reinterpret_as_uint() {
              raise ConnectionError(
                ProtocolError,
                "SETTINGS_MAX_FRAME_SIZE \{p.value} out of [16384, 16777215]",
              )
            }
            self.remote_max_frame_size = v
          }
          SETTING_MAX_HEADER_LIST_SIZE => ()
          _ => () // RFC 9113 §6.5.2: ignore unknown settings
        }
      }
      self.queue_frame(Settings(ack=true, params=[]), "ACK")
      self.flush_all_pending_data()
      events.push(SettingsUpdated(params))
    }
    Ping(ack~, opaque_data~) => {
      self.record_trace("C->S", frame, 8, if ack { "ACK" } else { "echo" })
      if !ack {
        self.queue_frame(Ping(ack=true, opaque_data~), "pong")
      }
      events.push(PingReceived(ack~, opaque_data~))
    }
    GoAway(last_stream_id~, code~, debug_data~) => {
      self.record_trace("C->S", frame, 8 + debug_data.length(), code.label())
      events.push(GoAwayReceived(last_stream_id~, code~, debug_data~))
    }
    Priority(spec~, ..) =>
      self.record_trace(
        "C->S",
        frame,
        5,
        "dep=#\{spec.dependency} w=\{spec.weight}",
      )
    PushPromise(..) =>
      raise ConnectionError(
        ProtocolError,
        "client MUST NOT send PUSH_PROMISE to server",
      )
    Continuation(..) =>
      raise ConnectionError(
        ProtocolError,
        "unexpected CONTINUATION frame without preceding HEADERS",
      )
    Unknown(..) =>
      // RFC 9113 §4.1: unknown frame types MUST be ignored
      self.record_trace("C->S", frame, 0, "ignored extension")
    Headers(stream_id~, end_stream~, end_headers~, fragment~, ..) => {
      self.record_trace(
        "C->S",
        frame,
        fragment.length(),
        if end_stream {
          "END_STREAM"
        } else {
          "open"
        },
      )
      if stream_id % 2U == 0U {
        raise ConnectionError(
          ProtocolError,
          "client-initiated stream ID #\{stream_id} must be odd",
        )
      }
      match self.streams.get(stream_id) {
        Some(st) =>
          match st.state {
            Open => ()
            HalfClosedRemote =>
              raise StreamError(
                stream_id,
                StreamClosed,
                "HEADERS received on half-closed (remote) stream",
              )
            Closed =>
              raise ConnectionError(
                StreamClosed,
                "HEADERS received on closed stream #\{stream_id}",
              )
            _ =>
              raise ConnectionError(
                ProtocolError,
                "HEADERS received in invalid stream state",
              )
          }
        None => {
          if stream_id <= self.last_remote_stream_id {
            raise ConnectionError(
              ProtocolError,
              "new stream ID #\{stream_id} <= last_remote_stream_id #\{self.last_remote_stream_id}",
            )
          }
          if self.active_remote_streams() >= self.local_max_concurrent_streams {
            raise StreamError(
              stream_id,
              RefusedStream,
              "SETTINGS_MAX_CONCURRENT_STREAMS exceeded",
            )
          }
          self.last_remote_stream_id = stream_id
          self.streams.set(
            stream_id,
            H2Stream::new(
              stream_id,
              self.remote_initial_window,
              self.local_initial_window,
            ),
          )
        }
      }
      if end_headers {
        self.finish_header_block(stream_id, fragment, end_stream, events)
      } else {
        self.expect_continuation_stream = Some(stream_id)
        self.continuation_end_stream = end_stream
        self.continuation_buf.reset()
        self.continuation_buf.write_bytesview(fragment[:])
      }
    }
    Data(stream_id~, end_stream~, data~, flow_len~) => {
      self.record_trace("C->S", frame, flow_len, "\{data.length()} B")
      // Connection flow control applies to every received DATA frame (RFC 9113 §6.9.1)
      self.conn_recv_window -= flow_len
      self.conn_recv_consumed += flow_len
      if self.conn_recv_window < 0 {
        raise ConnectionError(
          FlowControlError,
          "connection receive flow-control window exceeded",
        )
      }
      if self.conn_recv_consumed >= 32768 {
        let inc = self.conn_recv_consumed.reinterpret_as_uint()
        self.conn_recv_window += self.conn_recv_consumed
        self.conn_recv_consumed = 0
        self.queue_frame(
          WindowUpdate(stream_id=0U, increment=inc),
          "+\{inc} conn",
        )
      }
      let st = match self.streams.get(stream_id) {
        Some(s) => s
        None =>
          if stream_id > self.last_remote_stream_id {
            raise ConnectionError(
              ProtocolError,
              "DATA received on idle stream #\{stream_id}",
            )
          } else {
            raise ConnectionError(
              StreamClosed,
              "DATA received on closed stream #\{stream_id}",
            )
          }
      }
      match st.state {
        Open | HalfClosedLocal => ()
        HalfClosedRemote | Closed =>
          raise StreamError(
            stream_id,
            StreamClosed,
            "DATA received on closed/half-closed stream #\{stream_id}",
          )
        _ =>
          raise ConnectionError(
            ProtocolError,
            "DATA received in invalid stream state",
          )
      }
      st.recv_window -= flow_len
      st.recv_consumed += flow_len
      if st.recv_window < 0 {
        raise StreamError(
          stream_id,
          FlowControlError,
          "stream #\{stream_id} receive window exceeded",
        )
      }
      if !end_stream && st.recv_consumed >= 32768 {
        let inc = st.recv_consumed.reinterpret_as_uint()
        st.recv_window += st.recv_consumed
        st.recv_consumed = 0
        self.queue_frame(WindowUpdate(stream_id~, increment=inc), "+\{inc}")
      }
      st.req_body.write_bytesview(data[:])
      st.received_data_bytes += data.length().to_int64()
      events.push(RequestData(stream_id~, data~, end_stream~))
      if end_stream {
        match st.expected_content_length {
          Some(expected) if st.received_data_bytes != expected =>
            raise StreamError(
              stream_id,
              ProtocolError,
              "content-length mismatch: expected \{expected}, received \{st.received_data_bytes}",
            )
          _ => ()
        }
        st.state = match st.state {
          Open => HalfClosedRemote
          HalfClosedLocal => Closed
          other => other
        }
        events.push(
          RequestComplete(
            stream_id~,
            headers=st.req_headers,
            body=st.req_body.to_bytes(),
          ),
        )
      }
    }
    RstStream(stream_id~, code~) => {
      self.record_trace("C->S", frame, 4, code.label())
      match self.streams.get(stream_id) {
        Some(st) => {
          st.state = Closed
          events.push(StreamReset(stream_id~, code~))
        }
        None =>
          if stream_id > self.last_remote_stream_id {
            raise ConnectionError(
              ProtocolError,
              "RST_STREAM received on idle stream #\{stream_id}",
            )
          } else {
            events.push(StreamReset(stream_id~, code~))
          }
      }
    }
    WindowUpdate(stream_id~, increment~) => {
      self.record_trace("C->S", frame, 4, "+\{increment}")
      if stream_id == 0U {
        let updated = self.conn_send_window.to_int64() +
          increment.reinterpret_as_int().to_int64()
        if updated > MAX_WINDOW_SIZE.to_int64() {
          raise ConnectionError(
            FlowControlError,
            "connection send window overflow",
          )
        }
        self.conn_send_window = updated.to_int()
        self.flush_all_pending_data()
      } else {
        match self.streams.get(stream_id) {
          Some(st) => {
            let updated = st.send_window.to_int64() +
              increment.reinterpret_as_int().to_int64()
            if updated > MAX_WINDOW_SIZE.to_int64() {
              raise StreamError(
                stream_id,
                FlowControlError,
                "stream #\{stream_id} send window overflow",
              )
            }
            st.send_window = updated.to_int()
            self.flush_stream_data(st)
          }
          None =>
            if stream_id > self.last_remote_stream_id {
              raise ConnectionError(
                ProtocolError,
                "WINDOW_UPDATE received on idle stream #\{stream_id}",
              )
            }
        }
      }
      events.push(WindowUpdated(stream_id~, increment~))
    }
  }
}

///|
/// Feed raw inbound wire bytes into the Sans-I/O HTTP/2 server connection.
/// Automatically queues protocol responses (`SETTINGS ACK`, `PING ACK`, `WINDOW_UPDATE`,
/// `RST_STREAM`, `GOAWAY`) and returns decoded application events.
pub fn H2Connection::feed(self : H2Connection, chunk : Bytes) -> Array[H2Event] {
  let events : Array[H2Event] = []
  if self.closed {
    return events
  }
  self.recv_buf.write_bytesview(chunk[:])
  let raw = self.recv_buf.to_bytes()
  let mut pos = 0

  if !self.preface_checked {
    let preface = ascii_to_bytes(CLIENT_PREFACE_STR)
    if raw.length() < preface.length() {
      return events
    }
    for i = 0; i < preface.length(); i = i + 1 {
      if raw[i] != preface[i] {
        self.send_goaway(ProtocolError, debug_msg="invalid client preface")
        self.recv_buf.reset()
        return events
      }
    }
    self.preface_checked = true
    pos = preface.length()
  }

  while !self.closed && pos < raw.length() {
    let decoded : (H2Frame, Int32)? = decode_frame_at(
      raw,
      pos,
      max_frame_size=self.local_max_frame_size,
    ) catch {
      ConnectionError(code, msg) => {
        self.send_goaway(code, debug_msg=msg)
        self.recv_buf.reset()
        return events
      }
      StreamError(sid, code, msg) => {
        self.queue_frame(RstStream(stream_id=sid, code~), msg)
        // Advance past malformed frame payload if complete
        if raw.length() - pos >= 9 {
          let flen = read_u24_be(raw, pos)
          pos = pos + 9 + flen
        } else {
          break
        }
        continue
      }
      err => {
        self.send_goaway(InternalError, debug_msg=error_message(err))
        self.recv_buf.reset()
        return events
      }
    }
    match decoded {
      None => break
      Some((frame, next_pos)) => {
        pos = next_pos
        self.handle_frame(frame, events) catch {
          ConnectionError(code, msg) => {
            self.send_goaway(code, debug_msg=msg)
            self.recv_buf.reset()
            return events
          }
          StreamError(sid, code, msg) => {
            match self.streams.get(sid) {
              Some(st) => st.state = Closed
              None => ()
            }
            self.queue_frame(RstStream(stream_id=sid, code~), msg)
          }
          err => {
            self.send_goaway(InternalError, debug_msg=error_message(err))
            self.recv_buf.reset()
            return events
          }
        }
      }
    }
  }

  self.recv_buf.reset()
  if pos < raw.length() {
    self.recv_buf.write_bytesview(raw[pos:raw.length()])
  }
  events
}
