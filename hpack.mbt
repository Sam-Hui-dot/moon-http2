///|
/// Single HTTP/2 header field `(name, value)` with optional HPACK never-index sensitivity flag.
#derive(Debug, Eq, ToJson)
pub(all) struct HeaderField {
  name : String
  value : String
  sensitive : Bool
}

///|
pub extend HeaderField with @debug.Debug::{to_repr}

///|
pub extend HeaderField with Eq::{not_equal, equal}

///|
pub extend HeaderField with @json.ToJson::{to_json}

///|
/// Construct a `HeaderField`.
pub fn header_field(
  name : String,
  value : String,
  sensitive~ : Bool = false,
) -> HeaderField {
  { name, value, sensitive, }
}

///|
/// RFC 7541 Appendix A 61-entry immutable static header table (0-based array matching 1..61 indices).
let hpack_static_table : FixedArray[(String, String)] = [
  (":authority", ""),
  (":method", "GET"),
  (":method", "POST"),
  (":path", "/"),
  (":path", "/index.html"),
  (":scheme", "http"),
  (":scheme", "https"),
  (":status", "200"),
  (":status", "204"),
  (":status", "206"),
  (":status", "304"),
  (":status", "400"),
  (":status", "404"),
  (":status", "500"),
  ("accept-charset", ""),
  ("accept-encoding", "gzip, deflate"),
  ("accept-language", ""),
  ("accept-ranges", ""),
  ("accept", ""),
  ("access-control-allow-origin", ""),
  ("age", ""),
  ("allow", ""),
  ("authorization", ""),
  ("cache-control", ""),
  ("content-disposition", ""),
  ("content-encoding", ""),
  ("content-language", ""),
  ("content-length", ""),
  ("content-location", ""),
  ("content-range", ""),
  ("content-type", ""),
  ("cookie", ""),
  ("date", ""),
  ("etag", ""),
  ("expect", ""),
  ("expires", ""),
  ("from", ""),
  ("host", ""),
  ("if-match", ""),
  ("if-modified-since", ""),
  ("if-none-match", ""),
  ("if-range", ""),
  ("if-unmodified-since", ""),
  ("last-modified", ""),
  ("link", ""),
  ("location", ""),
  ("max-forwards", ""),
  ("proxy-authenticate", ""),
  ("proxy-authorization", ""),
  ("range", ""),
  ("referer", ""),
  ("refresh", ""),
  ("retry-after", ""),
  ("server", ""),
  ("set-cookie", ""),
  ("strict-transport-security", ""),
  ("transfer-encoding", ""),
  ("user-agent", ""),
  ("vary", ""),
  ("via", ""),
  ("www-authenticate", ""),
]

///|
/// Raw UTF-8/ISO-8859-1 byte extraction for ASCII-compatible HTTP header strings.
fn str_to_ascii_bytes(s : String) -> Bytes {
  let buf = @buffer.Buffer()
  for ch in s {
    let code = ch.to_int()
    if code <= 0x7f {
      buf.write_byte(code.to_byte())
    } else if code <= 0xff && code < 0x800 {
      buf.write_byte(code.to_byte())
    } else if code < 0x800 {
      buf.write_byte((0xc0 | (code >> 6)).to_byte())
      buf.write_byte((0x80 | (code & 0x3f)).to_byte())
    } else if code < 0x10000 {
      buf.write_byte((0xe0 | (code >> 12)).to_byte())
      buf.write_byte((0x80 | ((code >> 6) & 0x3f)).to_byte())
      buf.write_byte((0x80 | (code & 0x3f)).to_byte())
    } else {
      buf.write_byte((0xf0 | (code >> 18)).to_byte())
      buf.write_byte((0x80 | ((code >> 12) & 0x3f)).to_byte())
      buf.write_byte((0x80 | ((code >> 6) & 0x3f)).to_byte())
      buf.write_byte((0x80 | (code & 0x3f)).to_byte())
    }
  }
  buf.to_bytes()
}

///|
/// Convert raw octets into a MoonBit `String` preserving each single-byte octet (`0x00..0xff`).
fn raw_bytes_to_string(b : Bytes) -> String {
  let sb = StringBuilder()
  for i = 0; i < b.length(); i = i + 1 {
    sb.write_char(Int32::unsafe_to_char(b[i].to_int()))
  }
  sb.to_string()
}

///|
fn entry_hpack_size(name : String, value : String) -> Int32 {
  str_to_ascii_bytes(name).length() + str_to_ascii_bytes(value).length() + 32
}

///|
/// HPACK FIFO dynamic header table with RFC 7541 §4.1 byte-size accounting (`name + value + 32`).
pub struct DynamicTable {
  mut entries : Array[(String, String)]
  mut size_bytes : Int32
  mut max_size : Int32
}

///|
/// Create an empty HPACK dynamic table bounded by `max_size` bytes (default `4096`).
pub fn DynamicTable::new(max_size~ : Int32 = 4096) -> DynamicTable {
  { entries: [], size_bytes: 0, max_size, }
}

///|
/// Current dynamic table size in RFC 7541 octets.
pub fn DynamicTable::size(self : DynamicTable) -> Int32 {
  self.size_bytes
}

///|
/// Current number of entries in the dynamic table.
pub fn DynamicTable::len(self : DynamicTable) -> Int32 {
  self.entries.length()
}

///|
/// Current maximum capacity of the dynamic table in octets.
pub fn DynamicTable::max_capacity(self : DynamicTable) -> Int32 {
  self.max_size
}

///|
/// Update the dynamic table max capacity and evict oldest entries until `size_bytes <= new_max`.
pub fn DynamicTable::set_max_size(self : DynamicTable, new_max : Int32) -> Unit {
  self.max_size = if new_max < 0 { 0 } else { new_max }
  self.evict_to_fit(self.max_size)
}

///|
fn DynamicTable::evict_to_fit(self : DynamicTable, limit : Int32) -> Unit {
  while self.size_bytes > limit && !self.entries.is_empty() {
    match self.entries.pop() {
      Some((n, v)) => self.size_bytes -= entry_hpack_size(n, v)
      None => break
    }
  }
}

///|
/// Insert a new `(name, value)` at dynamic index 1, evicting old entries as needed per RFC 7541 §4.4.
pub fn DynamicTable::insert(
  self : DynamicTable,
  name : String,
  value : String,
) -> Unit {
  let sz = entry_hpack_size(name, value)
  if sz > self.max_size {
    self.entries = []
    self.size_bytes = 0
    return
  }
  self.evict_to_fit(self.max_size - sz)
  let next : Array[(String, String)] = Array::make(
    self.entries.length() + 1,
    (name, value),
  )
  for i = 0; i < self.entries.length(); i = i + 1 {
    next[i + 1] = self.entries[i]
  }
  self.entries = next
  self.size_bytes += sz
}

///|
/// Retrieve a copy of all current dynamic entries in newest-first order (`index 62..`).
pub fn DynamicTable::snapshot(self : DynamicTable) -> Array[(String, String)] {
  self.entries.copy()
}

///|
fn lookup_index(
  dyn_tbl : DynamicTable,
  idx : Int32,
) -> (String, String) raise H2Error {
  if idx <= 0 {
    raise CompressionError("HPACK index 0 is invalid")
  }
  if idx <= 61 {
    return hpack_static_table[idx - 1]
  }
  let dyn_idx = idx - 62
  if dyn_idx >= dyn_tbl.entries.length() {
    raise CompressionError("HPACK dynamic table index \{idx} out of bounds")
  }
  dyn_tbl.entries[dyn_idx]
}

///|
fn encode_prefixed_int(
  buf : @buffer.Buffer,
  first_byte_prefix : Int32,
  prefix_bits : Int32,
  value : Int32,
) -> Unit {
  let max_prefix = (1 << prefix_bits) - 1
  if value < max_prefix {
    buf.write_byte((first_byte_prefix | value).to_byte())
    return
  }
  buf.write_byte((first_byte_prefix | max_prefix).to_byte())
  let mut rem = value - max_prefix
  while rem >= 128 {
    buf.write_byte(((rem & 0x7f) | 0x80).to_byte())
    rem = rem >> 7
  }
  buf.write_byte(rem.to_byte())
}

///|
fn decode_prefixed_int(
  data : Bytes,
  pos : Int32,
  prefix_bits : Int32,
) -> (Int32, Int32) raise H2Error {
  if pos >= data.length() {
    raise CompressionError("truncated HPACK integer")
  }
  let mask = (1 << prefix_bits) - 1
  let first = data[pos].to_int() & mask
  let mut p = pos + 1
  if first < mask {
    return (first, p)
  }
  let mut val : Int64 = first.to_int64()
  let mut shift = 0
  while true {
    if p >= data.length() {
      raise CompressionError("truncated HPACK multi-byte integer")
    }
    let b = data[p].to_int()
    p += 1
    if shift >= 28 {
      raise CompressionError("HPACK integer overflow")
    }
    val += (b & 0x7f).to_int64() << shift
    if val > 0x7fffffffL {
      raise CompressionError("HPACK integer exceeds 31-bit limit")
    }
    if (b & 0x80) == 0 {
      break
    }
    shift += 7
  }
  (val.to_int(), p)
}

///|
fn encode_hpack_string(
  buf : @buffer.Buffer,
  raw : Bytes,
  use_huffman : Bool,
) -> Unit {
  if use_huffman {
    let enc = huffman_encode(raw)
    encode_prefixed_int(buf, 0x80, 7, enc.length())
    buf.write_bytesview(enc[:])
  } else {
    encode_prefixed_int(buf, 0x00, 7, raw.length())
    buf.write_bytesview(raw[:])
  }
}

///|
fn decode_hpack_string(
  data : Bytes,
  pos : Int32,
) -> (String, Int32) raise H2Error {
  if pos >= data.length() {
    raise CompressionError("truncated HPACK string length")
  }
  let is_huff = (data[pos].to_int() & 0x80) != 0
  let (slen, start) = decode_prefixed_int(data, pos, 7)
  if slen < 0 || start + slen > data.length() {
    raise CompressionError("truncated HPACK string payload")
  }
  let slice_buf = @buffer.Buffer()
  for i = 0; i < slen; i = i + 1 {
    slice_buf.write_byte(data[start + i])
  }
  let raw = slice_buf.to_bytes()
  let decoded = if is_huff { huffman_decode(raw) } else { raw }
  (raw_bytes_to_string(decoded), start + slen)
}

///|
/// Stateful RFC 7541 HPACK decoder enforcing `SETTINGS_HEADER_TABLE_SIZE` and block-start table updates.
pub struct HpackDecoder {
  table : DynamicTable
  mut max_allowed_table_size : Int32
}

///|
/// Create a new `HpackDecoder` with `max_allowed_table_size` (default `4096`).
pub fn HpackDecoder::new(max_table_size~ : Int32 = 4096) -> HpackDecoder {
  {
    table: DynamicTable::new(max_size=max_table_size),
    max_allowed_table_size: max_table_size,
  }
}

///|
/// Update the HTTP/2 `SETTINGS_HEADER_TABLE_SIZE` ceiling enforced during decoding.
pub fn HpackDecoder::set_max_table_size_limit(
  self : HpackDecoder,
  limit : Int32,
) -> Unit {
  self.max_allowed_table_size = limit
  if self.table.max_size > limit {
    self.table.set_max_size(limit)
  }
}

///|
/// Decode a complete HPACK header block fragment into an ordered array of `HeaderField`s.
pub fn HpackDecoder::decode(
  self : HpackDecoder,
  block : Bytes,
) -> Array[HeaderField] raise H2Error {
  let headers : Array[HeaderField] = []
  let mut pos = 0
  let mut allow_table_size_update = true

  while pos < block.length() {
    let b = block[pos].to_int()
    if (b & 0x80) != 0 {
      // 6.1 Indexed Header Field
      allow_table_size_update = false
      let (idx, next_pos) = decode_prefixed_int(block, pos, 7)
      let (name, value) = lookup_index(self.table, idx)
      headers.push({ name, value, sensitive: false, })
      pos = next_pos
    } else if (b & 0x40) != 0 {
      // 6.2.1 Literal Header Field with Incremental Indexing
      allow_table_size_update = false
      let (name_idx, after_idx) = decode_prefixed_int(block, pos, 6)
      let (name, after_name) = if name_idx == 0 {
        decode_hpack_string(block, after_idx)
      } else {
        let (n, _) = lookup_index(self.table, name_idx)
        (n, after_idx)
      }
      let (value, after_val) = decode_hpack_string(block, after_name)
      self.table.insert(name, value)
      headers.push({ name, value, sensitive: false, })
      pos = after_val
    } else if (b & 0x20) != 0 {
      // 6.3 Dynamic Table Size Update (must appear before any header representations per §4.2)
      if !allow_table_size_update {
        raise CompressionError(
          "dynamic table size update must occur at beginning of header block",
        )
      }
      let (new_sz, next_pos) = decode_prefixed_int(block, pos, 5)
      if new_sz > self.max_allowed_table_size {
        raise CompressionError(
          "dynamic table size update \{new_sz} exceeds SETTINGS_HEADER_TABLE_SIZE \{self.max_allowed_table_size}",
        )
      }
      self.table.set_max_size(new_sz)
      pos = next_pos
    } else {
      // 6.2.2 Without Indexing (0000xxxx) or 6.2.3 Never Indexed (0001xxxx)
      allow_table_size_update = false
      let never_index = (b & 0x10) != 0
      let (name_idx, after_idx) = decode_prefixed_int(block, pos, 4)
      let (name, after_name) = if name_idx == 0 {
        decode_hpack_string(block, after_idx)
      } else {
        let (n, _) = lookup_index(self.table, name_idx)
        (n, after_idx)
      }
      let (value, after_val) = decode_hpack_string(block, after_name)
      headers.push({ name, value, sensitive: never_index, })
      pos = after_val
    }
  }
  headers
}

///|
/// Stateful RFC 7541 HPACK encoder with automatic static/dynamic lookup and Huffman compression.
pub struct HpackEncoder {
  table : DynamicTable
  mut pending_size_update : Int32?
  use_huffman : Bool
}

///|
/// Create a new `HpackEncoder` with initial table size `max_size` (default `4096`).
pub fn HpackEncoder::new(
  max_size~ : Int32 = 4096,
  use_huffman~ : Bool = true,
) -> HpackEncoder {
  {
    table: DynamicTable::new(max_size~),
    pending_size_update: None,
    use_huffman,
  }
}

///|
/// Apply a peer `SETTINGS_HEADER_TABLE_SIZE` update to be emitted at the start of the next block.
pub fn HpackEncoder::set_max_table_size(
  self : HpackEncoder,
  new_max : Int32,
) -> Unit {
  if new_max != self.table.max_size {
    self.table.set_max_size(new_max)
    self.pending_size_update = Some(new_max)
  }
}

///|
fn find_best_match(
  dyn_tbl : DynamicTable,
  name : String,
  value : String,
) -> (Int32, Bool) {
  let mut name_only_idx = 0
  for i = 0; i < 61; i = i + 1 {
    let (sn, sv) = hpack_static_table[i]
    if sn == name {
      if sv == value {
        return (i + 1, true)
      }
      if name_only_idx == 0 {
        name_only_idx = i + 1
      }
    }
  }
  for i = 0; i < dyn_tbl.entries.length(); i = i + 1 {
    let (dn, dv) = dyn_tbl.entries[i]
    if dn == name {
      if dv == value {
        return (62 + i, true)
      }
      if name_only_idx == 0 {
        name_only_idx = 62 + i
      }
    }
  }
  (name_only_idx, false)
}

///|
/// Encode a list of header fields into an HPACK header block fragment.
pub fn HpackEncoder::encode(
  self : HpackEncoder,
  headers : Array[HeaderField],
) -> Bytes {
  let buf = @buffer.Buffer()
  match self.pending_size_update {
    Some(sz) => {
      encode_prefixed_int(buf, 0x20, 5, sz)
      self.pending_size_update = None
    }
    None => ()
  }
  for h in headers {
    let (idx, full_match) = find_best_match(self.table, h.name, h.value)
    if full_match && !h.sensitive {
      encode_prefixed_int(buf, 0x80, 7, idx)
      continue
    }
    let val_bytes = str_to_ascii_bytes(h.value)
    let val_huff = self.use_huffman &&
      huffman_encoded_len(val_bytes) < val_bytes.length()
    if h.sensitive {
      encode_prefixed_int(buf, 0x10, 4, idx)
      if idx == 0 {
        let name_bytes = str_to_ascii_bytes(h.name)
        let name_huff = self.use_huffman &&
          huffman_encoded_len(name_bytes) < name_bytes.length()
        encode_hpack_string(buf, name_bytes, name_huff)
      }
      encode_hpack_string(buf, val_bytes, val_huff)
    } else {
      let sz = entry_hpack_size(h.name, h.value)
      if sz <= self.table.max_size {
        encode_prefixed_int(buf, 0x40, 6, idx)
        if idx == 0 {
          let name_bytes = str_to_ascii_bytes(h.name)
          let name_huff = self.use_huffman &&
            huffman_encoded_len(name_bytes) < name_bytes.length()
          encode_hpack_string(buf, name_bytes, name_huff)
        }
        encode_hpack_string(buf, val_bytes, val_huff)
        self.table.insert(h.name, h.value)
      } else {
        encode_prefixed_int(buf, 0x00, 4, idx)
        if idx == 0 {
          let name_bytes = str_to_ascii_bytes(h.name)
          let name_huff = self.use_huffman &&
            huffman_encoded_len(name_bytes) < name_bytes.length()
          encode_hpack_string(buf, name_bytes, name_huff)
        }
        encode_hpack_string(buf, val_bytes, val_huff)
      }
    }
  }
  buf.to_bytes()
}
