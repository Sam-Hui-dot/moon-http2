///|
/// Standard RFC 9113 §7 HTTP/2 32-bit error codes.
#derive(Debug, Eq, ToJson)
pub(all) enum H2ErrorCode {
  NoError
  ProtocolError
  InternalError
  FlowControlError
  SettingsTimeout
  StreamClosed
  FrameSizeError
  RefusedStream
  Cancel
  CompressionError
  ConnectError
  EnhanceYourCalm
  InadequateSecurity
  Http11Required
  UnknownCode(UInt32)
}

///|
pub extend H2ErrorCode with @debug.Debug::{to_repr}

///|
pub extend H2ErrorCode with Eq::{not_equal, equal}

///|
pub extend H2ErrorCode with @json.ToJson::{to_json}

///|
/// Convert an `H2ErrorCode` to its 32-bit RFC 9113 wire integer value.
pub fn H2ErrorCode::to_u32(self : H2ErrorCode) -> UInt32 {
  match self {
    NoError => 0x0U
    ProtocolError => 0x1U
    InternalError => 0x2U
    FlowControlError => 0x3U
    SettingsTimeout => 0x4U
    StreamClosed => 0x5U
    FrameSizeError => 0x6U
    RefusedStream => 0x7U
    Cancel => 0x8U
    CompressionError => 0x9U
    ConnectError => 0xaU
    EnhanceYourCalm => 0xbU
    InadequateSecurity => 0xcU
    Http11Required => 0xdU
    UnknownCode(v) => v
  }
}

///|
/// Decode a 32-bit RFC 9113 wire integer into an `H2ErrorCode`.
pub fn H2ErrorCode::from_u32(raw : UInt32) -> H2ErrorCode {
  match raw {
    0x0U => NoError
    0x1U => ProtocolError
    0x2U => InternalError
    0x3U => FlowControlError
    0x4U => SettingsTimeout
    0x5U => StreamClosed
    0x6U => FrameSizeError
    0x7U => RefusedStream
    0x8U => Cancel
    0x9U => CompressionError
    0xaU => ConnectError
    0xbU => EnhanceYourCalm
    0xcU => InadequateSecurity
    0xdU => Http11Required
    _ => UnknownCode(raw)
  }
}

///|
/// Human-readable canonical RFC 9113 error name.
pub fn H2ErrorCode::label(self : H2ErrorCode) -> String {
  match self {
    NoError => "NO_ERROR"
    ProtocolError => "PROTOCOL_ERROR"
    InternalError => "INTERNAL_ERROR"
    FlowControlError => "FLOW_CONTROL_ERROR"
    SettingsTimeout => "SETTINGS_TIMEOUT"
    StreamClosed => "STREAM_CLOSED"
    FrameSizeError => "FRAME_SIZE_ERROR"
    RefusedStream => "REFUSED_STREAM"
    Cancel => "CANCEL"
    CompressionError => "COMPRESSION_ERROR"
    ConnectError => "CONNECT_ERROR"
    EnhanceYourCalm => "ENHANCE_YOUR_CALM"
    InadequateSecurity => "INADEQUATE_SECURITY"
    Http11Required => "HTTP_1_1_REQUIRED"
    UnknownCode(v) => "ERROR_0x\{v}"
  }
}

///|
/// Errors raised during HTTP/2 frame parsing, HPACK coding, or protocol state transitions.
#derive(Debug, Eq)
pub(all) suberror H2Error {
  ConnectionError(H2ErrorCode, String)
  StreamError(UInt32, H2ErrorCode, String)
  CompressionError(String)
  InvalidInput(String)
}

///|
pub extend H2Error with @debug.Debug::{to_repr}

///|
pub extend H2Error with Eq::{not_equal, equal}

///|
/// Extract a concise human-readable diagnostic message from any HTTP/2 error.
pub fn error_message(error : Error) -> String {
  match error {
    ConnectionError(code, msg) => "[\{code.label()}] \{msg}"
    StreamError(sid, code, msg) => "stream #\{sid} [\{code.label()}]: \{msg}"
    CompressionError(msg) => "HPACK compression error: \{msg}"
    InvalidInput(msg) => msg
    other => other.to_string()
  }
}
