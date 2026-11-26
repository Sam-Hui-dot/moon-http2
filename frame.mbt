///|
/// Standard RFC 9113 §3.5 HTTP/2 client connection preface (24 bytes).
pub const CLIENT_PREFACE_STR : String = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

///|
pub const DEFAULT_INITIAL_WINDOW_SIZE : Int32 = 65535

///|
pub const DEFAULT_MAX_FRAME_SIZE : Int32 = 16384

///|
pub const MAX_ALLOWED_FRAME_SIZE : Int32 = 16777215

///|
pub const MAX_WINDOW_SIZE : Int32 = 2147483647

///|
/// RFC 9113 frame flag bitmasks.
pub const FLAG_END_STREAM : Byte = b'\x01'

///|
pub const FLAG_ACK : Byte = b'\x01'

///|
pub const FLAG_END_HEADERS : Byte = b'\x04'

///|
pub const FLAG_PADDED : Byte = b'\x08'

///|
pub const FLAG_PRIORITY : Byte = b'\x20'

///|
/// RFC 9113 §6.5.2 SETTINGS parameter identifiers.
pub const SETTING_HEADER_TABLE_SIZE : UInt16 = 0x1

///|
pub const SETTING_ENABLE_PUSH : UInt16 = 0x2

///|
pub const SETTING_MAX_CONCURRENT_STREAMS : UInt16 = 0x3

///|
pub const SETTING_INITIAL_WINDOW_SIZE : UInt16 = 0x4

///|
pub const SETTING_MAX_FRAME_SIZE : UInt16 = 0x5

///|
pub const SETTING_MAX_HEADER_LIST_SIZE : UInt16 = 0x6

///|
/// Parsed priority metadata from a `HEADERS` (with `PRIORITY` flag) or `PRIORITY` frame.
#derive(Debug, Eq, ToJson)
pub(all) struct PrioritySpec {
  exclusive : Bool
  dependency : UInt32
  weight : Int32
}

///|
pub extend PrioritySpec with @debug.Debug::{to_repr}

///|
pub extend PrioritySpec with Eq::{not_equal, equal}

///|
pub extend PrioritySpec with @json.ToJson::{to_json}

///|
/// Single key-value parameter inside a `SETTINGS` frame.
#derive(Debug, Eq, ToJson)
pub(all) struct SettingParam {
  id : UInt16
  value : UInt32
}

///|
pub extend SettingParam with @debug.Debug::{to_repr}

///|
pub extend SettingParam with Eq::{not_equal, equal}

///|
pub extend SettingParam with @json.ToJson::{to_json}

///|
/// Decoded RFC 9113 HTTP/2 frame covering all 10 standard frame types plus unknown extension frames.
#derive(Debug, Eq)
pub(all) enum H2Frame {
  Data(
    stream_id~ : UInt32,
    end_stream~ : Bool,
    data~ : Bytes,
    flow_len~ : Int32
  )
  Headers(
    stream_id~ : UInt32,
    end_stream~ : Bool,
    end_headers~ : Bool,
    priority~ : PrioritySpec?,
    fragment~ : Bytes
  )
  Priority(stream_id~ : UInt32, spec~ : PrioritySpec)
  RstStream(stream_id~ : UInt32, code~ : H2ErrorCode)
  Settings(ack~ : Bool, params~ : Array[SettingParam])
  PushPromise(
    stream_id~ : UInt32,
    promised_stream_id~ : UInt32,
    end_headers~ : Bool,
    fragment~ : Bytes
  )
  Ping(ack~ : Bool, opaque_data~ : Bytes)
  GoAway(last_stream_id~ : UInt32, code~ : H2ErrorCode, debug_data~ : Bytes)
  WindowUpdate(stream_id~ : UInt32, increment~ : UInt32)
  Continuation(stream_id~ : UInt32, end_headers~ : Bool, fragment~ : Bytes)
  Unknown(
    frame_type~ : Byte,
    flags~ : Byte,
    stream_id~ : UInt32,
    payload~ : Bytes
  )
}

///|
pub extend H2Frame with @debug.Debug::{to_repr}

///|
pub extend H2Frame with Eq::{not_equal, equal}

///|
/// Return the canonical RFC 9113 name of an `H2Frame`.
pub fn H2Frame::kind_name(self : H2Frame) -> String {
  match self {
    Data(..) => "DATA"
    Headers(..) => "HEADERS"
    Priority(..) => "PRIORITY"
    RstStream(..) => "RST_STREAM"
    Settings(ack~, ..) => if ack { "SETTINGS(ACK)" } else { "SETTINGS" }
    PushPromise(..) => "PUSH_PROMISE"
    Ping(ack~, ..) => if ack { "PING(ACK)" } else { "PING" }
    GoAway(..) => "GOAWAY"
    WindowUpdate(..) => "WINDOW_UPDATE"
    Continuation(..) => "CONTINUATION"
    Unknown(frame_type~, ..) => "UNKNOWN(0x\{frame_type.to_int()})"
  }
}

///|
/// Return the stream identifier associated with an `H2Frame`.
pub fn H2Frame::stream_id(self : H2Frame) -> UInt32 {
  match self {
    Data(stream_id~, ..)
    | Headers(stream_id~, ..)
    | Priority(stream_id~, ..)
    | RstStream(stream_id~, ..)
    | PushPromise(stream_id~, ..)
    | WindowUpdate(stream_id~, ..)
    | Continuation(stream_id~, ..)
    | Unknown(stream_id~, ..) => stream_id
    Settings(..) | Ping(..) | GoAway(..) => 0U
  }
}

///|
fn read_u16_be(bs : Bytes, off : Int32) -> UInt16 {
  let b0 = bs[off].to_int()
  let b1 = bs[off + 1].to_int()
  ((b0 << 8) | b1).to_uint16()
}

///|
fn read_u24_be(bs : Bytes, off : Int32) -> Int32 {
  let b0 = bs[off].to_int()
  let b1 = bs[off + 1].to_int()
  let b2 = bs[off + 2].to_int()
  (b0 << 16) | (b1 << 8) | b2
}

///|
fn read_u32_be(bs : Bytes, off : Int32) -> UInt32 {
  let b0 = bs[off].to_int().reinterpret_as_uint()
  let b1 = bs[off + 1].to_int().reinterpret_as_uint()
  let b2 = bs[off + 2].to_int().reinterpret_as_uint()
  let b3 = bs[off + 3].to_int().reinterpret_as_uint()
  (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
}

///|
fn write_u16_be(buf : @buffer.Buffer, v : UInt16) -> Unit {
  let n = v.to_int()
  buf.write_byte(((n >> 8) & 0xff).to_byte())
  buf.write_byte((n & 0xff).to_byte())
}

///|
fn write_u24_be(buf : @buffer.Buffer, v : Int32) -> Unit {
  buf.write_byte(((v >> 16) & 0xff).to_byte())
  buf.write_byte(((v >> 8) & 0xff).to_byte())
  buf.write_byte((v & 0xff).to_byte())
}

///|
fn write_u32_be(buf : @buffer.Buffer, v : UInt32) -> Unit {
  buf.write_byte(((v >> 24) & 0xffU).reinterpret_as_int().to_byte())
  buf.write_byte(((v >> 16) & 0xffU).reinterpret_as_int().to_byte())
  buf.write_byte(((v >> 8) & 0xffU).reinterpret_as_int().to_byte())
  buf.write_byte((v & 0xffU).reinterpret_as_int().to_byte())
}

///|
/// Convert an ASCII string into raw `Bytes`.
pub fn ascii_to_bytes(s : String) -> Bytes {
  let buf = @buffer.Buffer(size_hint=s.length())
  for ch in s {
    buf.write_byte((ch.to_int() & 0xff).to_byte())
  }
  buf.to_bytes()
}

///|
fn hex_nibble(ch : Char) -> Int32? {
  let c = ch.to_int()
  if c >= '0'.to_int() && c <= '9'.to_int() {
    Some(c - '0'.to_int())
  } else if c >= 'a'.to_int() && c <= 'f'.to_int() {
    Some(c - 'a'.to_int() + 10)
  } else if c >= 'A'.to_int() && c <= 'F'.to_int() {
    Some(c - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
/// Decode a hexadecimal string (ignoring whitespace) into raw `Bytes`.
pub fn hex_to_bytes(hex : String) -> Bytes raise H2Error {
  let nibbles : Array[Int32] = []
  for ch in hex {
    if ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t' {
      continue
    }
    match hex_nibble(ch) {
      Some(v) => nibbles.push(v)
      None => raise InvalidInput("invalid hex character '\{ch}'")
    }
  }
  if nibbles.length() % 2 != 0 {
    raise InvalidInput("hex input must have even number of digits")
  }
  let buf = @buffer.Buffer(size_hint=nibbles.length() / 2)
  let mut i = 0
  while i < nibbles.length() {
    buf.write_byte(((nibbles[i] << 4) | nibbles[i + 1]).to_byte())
    i += 2
  }
  buf.to_bytes()
}

///|
/// Encode raw `Bytes` into a lowercase hexadecimal string.
pub fn bytes_to_hex(bs : Bytes) -> String {
  let digits = "0123456789abcdef"
  let sb = StringBuilder()
  for i = 0; i < bs.length(); i = i + 1 {
    let b = bs[i].to_int()
    sb.write_char(digits[(b >> 4) & 0xf].to_int().unsafe_to_char())
    sb.write_char(digits[b & 0xf].to_int().unsafe_to_char())
  }
  sb.to_string()
}

///|
fn slice_bytes(bs : Bytes, start : Int32, end : Int32) -> Bytes {
  if end <= start {
    return Bytes::new(0)
  }
  let buf = @buffer.Buffer(size_hint=end - start)
  buf.write_bytesview(bs[start:end])
  buf.to_bytes()
}

///|
/// Encode the 9-byte HTTP/2 frame header plus payload into `buf`.
pub fn encode_frame_into(buf : @buffer.Buffer, frame : H2Frame) -> Unit {
  match frame {
    Data(stream_id~, end_stream~, data~, ..) => {
      let flags : Byte = if end_stream { FLAG_END_STREAM } else { b'\x00' }
      write_u24_be(buf, data.length())
      buf.write_byte(b'\x00')
      buf.write_byte(flags)
      write_u32_be(buf, stream_id & 0x7fffffffU)
      buf.write_bytesview(data[:])
    }
    Headers(stream_id~, end_stream~, end_headers~, priority~, fragment~) => {
      let mut flags = 0
      if end_stream {
        flags = flags | FLAG_END_STREAM.to_int()
      }
      if end_headers {
        flags = flags | FLAG_END_HEADERS.to_int()
      }
      let extra = match priority {
        Some(_) => {
          flags = flags | FLAG_PRIORITY.to_int()
          5
        }
        None => 0
      }
      write_u24_be(buf, fragment.length() + extra)
      buf.write_byte(b'\x01')
      buf.write_byte(flags.to_byte())
      write_u32_be(buf, stream_id & 0x7fffffffU)
      match priority {
        Some(spec) => {
          let dep = if spec.exclusive {
            (spec.dependency & 0x7fffffffU) | 0x80000000U
          } else {
            spec.dependency & 0x7fffffffU
          }
          write_u32_be(buf, dep)
          buf.write_byte(((spec.weight - 1) & 0xff).to_byte())
        }
        None => ()
      }
      buf.write_bytesview(fragment[:])
    }
    Priority(stream_id~, spec~) => {
      write_u24_be(buf, 5)
      buf.write_byte(b'\x02')
      buf.write_byte(b'\x00')
      write_u32_be(buf, stream_id & 0x7fffffffU)
      let dep = if spec.exclusive {
        (spec.dependency & 0x7fffffffU) | 0x80000000U
      } else {
        spec.dependency & 0x7fffffffU
      }
      write_u32_be(buf, dep)
      buf.write_byte(((spec.weight - 1) & 0xff).to_byte())
    }
    RstStream(stream_id~, code~) => {
      write_u24_be(buf, 4)
      buf.write_byte(b'\x03')
      buf.write_byte(b'\x00')
      write_u32_be(buf, stream_id & 0x7fffffffU)
      write_u32_be(buf, code.to_u32())
    }
    Settings(ack~, params~) => {
      let flags : Byte = if ack { FLAG_ACK } else { b'\x00' }
      let len = if ack { 0 } else { params.length() * 6 }
      write_u24_be(buf, len)
      buf.write_byte(b'\x04')
      buf.write_byte(flags)
      write_u32_be(buf, 0U)
      if !ack {
        for p in params {
          write_u16_be(buf, p.id)
          write_u32_be(buf, p.value)
        }
      }
    }
    PushPromise(stream_id~, promised_stream_id~, end_headers~, fragment~) => {
      let flags : Byte = if end_headers { FLAG_END_HEADERS } else { b'\x00' }
      write_u24_be(buf, 4 + fragment.length())
      buf.write_byte(b'\x05')
      buf.write_byte(flags)
      write_u32_be(buf, stream_id & 0x7fffffffU)
      write_u32_be(buf, promised_stream_id & 0x7fffffffU)
      buf.write_bytesview(fragment[:])
    }
    Ping(ack~, opaque_data~) => {
      let flags : Byte = if ack { FLAG_ACK } else { b'\x00' }
      write_u24_be(buf, 8)
      buf.write_byte(b'\x06')
      buf.write_byte(flags)
      write_u32_be(buf, 0U)
      for i = 0; i < 8; i = i + 1 {
        if i < opaque_data.length() {
          buf.write_byte(opaque_data[i])
        } else {
          buf.write_byte(b'\x00')
        }
      }
    }
    GoAway(last_stream_id~, code~, debug_data~) => {
      write_u24_be(buf, 8 + debug_data.length())
      buf.write_byte(b'\x07')
      buf.write_byte(b'\x00')
      write_u32_be(buf, 0U)
      write_u32_be(buf, last_stream_id & 0x7fffffffU)
      write_u32_be(buf, code.to_u32())
      buf.write_bytesview(debug_data[:])
    }
    WindowUpdate(stream_id~, increment~) => {
      write_u24_be(buf, 4)
      buf.write_byte(b'\x08')
      buf.write_byte(b'\x00')
      write_u32_be(buf, stream_id & 0x7fffffffU)
      write_u32_be(buf, increment & 0x7fffffffU)
    }
    Continuation(stream_id~, end_headers~, fragment~) => {
      let flags : Byte = if end_headers { FLAG_END_HEADERS } else { b'\x00' }
      write_u24_be(buf, fragment.length())
      buf.write_byte(b'\x09')
      buf.write_byte(flags)
      write_u32_be(buf, stream_id & 0x7fffffffU)
      buf.write_bytesview(fragment[:])
    }
    Unknown(frame_type~, flags~, stream_id~, payload~) => {
      write_u24_be(buf, payload.length())
      buf.write_byte(frame_type)
      buf.write_byte(flags)
      write_u32_be(buf, stream_id & 0x7fffffffU)
      buf.write_bytesview(payload[:])
    }
  }
}

///|
/// Encode a single `H2Frame` to wire bytes.
pub fn encode_frame(frame : H2Frame) -> Bytes {
  let buf = @buffer.Buffer(size_hint=32)
  encode_frame_into(buf, frame)
  buf.to_bytes()
}

///|
/// Try to decode one HTTP/2 frame starting at `offset` in `buf`.
/// Returns `None` if fewer than `9 + payload_length` bytes are available.
/// Enforces all RFC 9113 §4 / §6 structural length, stream ID, flag, and padding rules.
pub fn decode_frame_at(
  buf : Bytes,
  offset : Int32,
  max_frame_size~ : Int32 = DEFAULT_MAX_FRAME_SIZE,
) -> (H2Frame, Int32)? raise H2Error {
  let avail = buf.length() - offset
  if avail < 9 {
    return None
  }
  let length = read_u24_be(buf, offset)
  let ftype = buf[offset + 3]
  let flags = buf[offset + 4]
  let stream_id = read_u32_be(buf, offset + 5) & 0x7fffffffU

  if length > max_frame_size {
    raise ConnectionError(
      FrameSizeError,
      "frame length \{length} exceeds SETTINGS_MAX_FRAME_SIZE (\{max_frame_size})",
    )
  }
  if avail < 9 + length {
    return None
  }

  let pstart = offset + 9
  let pend = pstart + length
  let next_off = pend

  match ftype {
    // 0x0 DATA
    b'\x00' => {
      if stream_id == 0U {
        raise ConnectionError(ProtocolError, "DATA frame with stream_id 0")
      }
      let end_stream = (flags.to_int() & FLAG_END_STREAM.to_int()) != 0
      let padded = (flags.to_int() & FLAG_PADDED.to_int()) != 0
      let mut dstart = pstart
      let mut dend = pend
      if padded {
        if length < 1 {
          raise ConnectionError(
            ProtocolError,
            "padded DATA frame missing Pad Length byte",
          )
        }
        let pad_len = buf[dstart].to_int()
        dstart += 1
        if pad_len >= length {
          raise ConnectionError(
            ProtocolError,
            "DATA frame pad length \{pad_len} >= payload length \{length}",
          )
        }
        dend = pend - pad_len
      }
      Some(
        (
          Data(
            stream_id~,
            end_stream~,
            data=slice_bytes(buf, dstart, dend),
            flow_len=length,
          ),
          next_off,
        ),
      )
    }
    // 0x1 HEADERS
    b'\x01' => {
      if stream_id == 0U {
        raise ConnectionError(ProtocolError, "HEADERS frame with stream_id 0")
      }
      let end_stream = (flags.to_int() & FLAG_END_STREAM.to_int()) != 0
      let end_headers = (flags.to_int() & FLAG_END_HEADERS.to_int()) != 0
      let padded = (flags.to_int() & FLAG_PADDED.to_int()) != 0
      let has_priority = (flags.to_int() & FLAG_PRIORITY.to_int()) != 0
      let mut pos = pstart
      let mut pad_len = 0
      if padded {
        if pos >= pend {
          raise ConnectionError(
            ProtocolError,
            "padded HEADERS frame missing Pad Length byte",
          )
        }
        pad_len = buf[pos].to_int()
        pos += 1
      }
      let priority : PrioritySpec? = if has_priority {
        if pos + 5 > pend {
          raise ConnectionError(
            FrameSizeError,
            "HEADERS frame with PRIORITY flag too short",
          )
        }
        let raw_dep = read_u32_be(buf, pos)
        let exclusive = (raw_dep & 0x80000000U) != 0U
        let dependency = raw_dep & 0x7fffffffU
        let weight = buf[pos + 4].to_int() + 1
        pos += 5
        if dependency == stream_id {
          raise StreamError(
            stream_id,
            ProtocolError,
            "HEADERS PRIORITY cannot depend on itself",
          )
        }
        Some({ exclusive, dependency, weight, })
      } else {
        None
      }
      if pos + pad_len > pend {
        raise ConnectionError(
          ProtocolError,
          "HEADERS frame padding exceeds remaining payload",
        )
      }
      let frag = slice_bytes(buf, pos, pend - pad_len)
      Some(
        (
          Headers(
            stream_id~,
            end_stream~,
            end_headers~,
            priority~,
            fragment=frag,
          ),
          next_off,
        ),
      )
    }
    // 0x2 PRIORITY
    b'\x02' => {
      if stream_id == 0U {
        raise ConnectionError(ProtocolError, "PRIORITY frame with stream_id 0")
      }
      if length != 5 {
        raise StreamError(
          stream_id,
          FrameSizeError,
          "PRIORITY frame length must be 5, got \{length}",
        )
      }
      let raw_dep = read_u32_be(buf, pstart)
      let exclusive = (raw_dep & 0x80000000U) != 0U
      let dependency = raw_dep & 0x7fffffffU
      let weight = buf[pstart + 4].to_int() + 1
      if dependency == stream_id {
        raise StreamError(
          stream_id,
          ProtocolError,
          "PRIORITY frame cannot depend on itself",
        )
      }
      Some(
        (
          Priority(stream_id~, spec={ exclusive, dependency, weight, }),
          next_off,
        ),
      )
    }
    // 0x3 RST_STREAM
    b'\x03' => {
      if stream_id == 0U {
        raise ConnectionError(
          ProtocolError,
          "RST_STREAM frame with stream_id 0",
        )
      }
      if length != 4 {
        raise ConnectionError(
          FrameSizeError,
          "RST_STREAM frame length must be 4, got \{length}",
        )
      }
      let code = H2ErrorCode::from_u32(read_u32_be(buf, pstart))
      Some((RstStream(stream_id~, code~), next_off))
    }
    // 0x4 SETTINGS
    b'\x04' => {
      if stream_id != 0U {
        raise ConnectionError(
          ProtocolError,
          "SETTINGS frame must have stream_id 0",
        )
      }
      let ack = (flags.to_int() & FLAG_ACK.to_int()) != 0
      if ack {
        if length != 0 {
          raise ConnectionError(
            FrameSizeError,
            "SETTINGS ACK frame must have length 0, got \{length}",
          )
        }
        return Some((Settings(ack=true, params=[]), next_off))
      }
      if length % 6 != 0 {
        raise ConnectionError(
          FrameSizeError,
          "SETTINGS frame length must be a multiple of 6, got \{length}",
        )
      }
      let params : Array[SettingParam] = []
      let mut pos = pstart
      while pos < pend {
        let id = read_u16_be(buf, pos)
        let value = read_u32_be(buf, pos + 2)
        params.push({ id, value, })
        pos += 6
      }
      Some((Settings(ack=false, params~), next_off))
    }
    // 0x5 PUSH_PROMISE
    b'\x05' => {
      if stream_id == 0U {
        raise ConnectionError(
          ProtocolError,
          "PUSH_PROMISE frame with stream_id 0",
        )
      }
      let end_headers = (flags.to_int() & FLAG_END_HEADERS.to_int()) != 0
      let padded = (flags.to_int() & FLAG_PADDED.to_int()) != 0
      let mut pos = pstart
      let mut pad_len = 0
      if padded {
        if pos >= pend {
          raise ConnectionError(
            ProtocolError,
            "padded PUSH_PROMISE missing Pad Length",
          )
        }
        pad_len = buf[pos].to_int()
        pos += 1
      }
      if pos + 4 > pend {
        raise ConnectionError(
          FrameSizeError,
          "PUSH_PROMISE frame missing promised stream ID",
        )
      }
      let promised = read_u32_be(buf, pos) & 0x7fffffffU
      pos += 4
      if promised == 0U {
        raise ConnectionError(
          ProtocolError,
          "PUSH_PROMISE promised stream ID cannot be 0",
        )
      }
      if pos + pad_len > pend {
        raise ConnectionError(
          ProtocolError,
          "PUSH_PROMISE padding exceeds payload",
        )
      }
      let frag = slice_bytes(buf, pos, pend - pad_len)
      Some(
        (
          PushPromise(
            stream_id~,
            promised_stream_id=promised,
            end_headers~,
            fragment=frag,
          ),
          next_off,
        ),
      )
    }
    // 0x6 PING
    b'\x06' => {
      if stream_id != 0U {
        raise ConnectionError(ProtocolError, "PING frame must have stream_id 0")
      }
      if length != 8 {
        raise ConnectionError(
          FrameSizeError,
          "PING frame length must be 8, got \{length}",
        )
      }
      let ack = (flags.to_int() & FLAG_ACK.to_int()) != 0
      Some((Ping(ack~, opaque_data=slice_bytes(buf, pstart, pend)), next_off))
    }
    // 0x7 GOAWAY
    b'\x07' => {
      if stream_id != 0U {
        raise ConnectionError(
          ProtocolError,
          "GOAWAY frame must have stream_id 0",
        )
      }
      if length < 8 {
        raise ConnectionError(
          FrameSizeError,
          "GOAWAY frame length must be >= 8, got \{length}",
        )
      }
      let last_stream_id = read_u32_be(buf, pstart) & 0x7fffffffU
      let code = H2ErrorCode::from_u32(read_u32_be(buf, pstart + 4))
      let debug_data = slice_bytes(buf, pstart + 8, pend)
      Some((GoAway(last_stream_id~, code~, debug_data~), next_off))
    }
    // 0x8 WINDOW_UPDATE
    b'\x08' => {
      if length != 4 {
        raise ConnectionError(
          FrameSizeError,
          "WINDOW_UPDATE frame length must be 4, got \{length}",
        )
      }
      let inc = read_u32_be(buf, pstart) & 0x7fffffffU
      if inc == 0U {
        if stream_id == 0U {
          raise ConnectionError(
            ProtocolError,
            "WINDOW_UPDATE increment on connection cannot be 0",
          )
        } else {
          raise StreamError(
            stream_id,
            ProtocolError,
            "WINDOW_UPDATE increment on stream cannot be 0",
          )
        }
      }
      Some((WindowUpdate(stream_id~, increment=inc), next_off))
    }
    // 0x9 CONTINUATION
    b'\x09' => {
      if stream_id == 0U {
        raise ConnectionError(
          ProtocolError,
          "CONTINUATION frame with stream_id 0",
        )
      }
      let end_headers = (flags.to_int() & FLAG_END_HEADERS.to_int()) != 0
      Some(
        (
          Continuation(
            stream_id~,
            end_headers~,
            fragment=slice_bytes(buf, pstart, pend),
          ),
          next_off,
        ),
      )
    }
    // Unknown extension frame (RFC 9113 §4.1: ignore outside CONTINUATION)
    _ =>
      Some(
        (
          Unknown(
            frame_type=ftype,
            flags~,
            stream_id~,
            payload=slice_bytes(buf, pstart, pend),
          ),
          next_off,
        ),
      )
  }
}

///|
/// Decode all complete HTTP/2 frames from a raw byte buffer (optionally skipping a leading client preface).
pub fn decode_frames(
  raw : Bytes,
  max_frame_size~ : Int32 = DEFAULT_MAX_FRAME_SIZE,
) -> Array[H2Frame] raise H2Error {
  let frames : Array[H2Frame] = []
  let mut pos = 0
  let preface = ascii_to_bytes(CLIENT_PREFACE_STR)
  if raw.length() >= preface.length() {
    let mut is_preface = true
    for i = 0; i < preface.length(); i = i + 1 {
      if raw[i] != preface[i] {
        is_preface = false
        break
      }
    }
    if is_preface {
      pos = preface.length()
    }
  }
  while pos < raw.length() {
    match decode_frame_at(raw, pos, max_frame_size~) {
      Some((f, next_pos)) => {
        frames.push(f)
        pos = next_pos
      }
      None => break
    }
  }
  frames
}
