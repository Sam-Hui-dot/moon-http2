///|
fn hex_to_bytes(hex : String) -> Bytes {
  let clean : Array[Int32] = []
  for ch in hex {
    let c = ch.to_int()
    if c >= 48 && c <= 57 {
      clean.push(c - 48)
    } else if c >= 97 && c <= 102 {
      clean.push(c - 87)
    } else if c >= 65 && c <= 70 {
      clean.push(c - 55)
    }
  }
  let buf = @buffer.Buffer()
  for i = 0; i + 1 < clean.length(); i = i + 2 {
    buf.write_byte(((clean[i] << 4) | clean[i + 1]).to_byte())
  }
  buf.to_bytes()
}

///|
test "rfc 7541 appendix c.4 stateful huffman request sequence" {
  let dec = @moon-http2.HpackDecoder::new()
  // C.4.1 First Request
  let req1 = hex_to_bytes("8286 8441 8cf1 e3c2 e5f2 3a6b a0ab 90f4 ff")
  let h1 = dec.decode(req1)
  assert_eq(h1.length(), 4)
  assert_eq(h1[0], @moon-http2.header_field(":method", "GET"))
  assert_eq(h1[1], @moon-http2.header_field(":scheme", "http"))
  assert_eq(h1[2], @moon-http2.header_field(":path", "/"))
  assert_eq(h1[3], @moon-http2.header_field(":authority", "www.example.com"))
  assert_eq(dec.table.size(), 57)

  // C.4.2 Second Request (reuses dynamic entry :authority)
  let req2 = hex_to_bytes("8286 84be 5886 a8eb 1064 9cbf")
  let h2 = dec.decode(req2)
  assert_eq(h2[3], @moon-http2.header_field(":authority", "www.example.com"))
  assert_eq(h2[4], @moon-http2.header_field("cache-control", "no-cache"))
  assert_eq(dec.table.size(), 110)

  // C.4.3 Third Request
  let req3 = hex_to_bytes(
    "8287 85bf 4088 25a8 49e9 5ba9 7d7f 8925 a849 e95b b8e8 b4bf",
  )
  let h3 = dec.decode(req3)
  assert_eq(h3[1], @moon-http2.header_field(":scheme", "https"))
  assert_eq(h3[2], @moon-http2.header_field(":path", "/index.html"))
  assert_eq(h3[4], @moon-http2.header_field("custom-key", "custom-value"))
  assert_eq(dec.table.size(), 164)
}

///|
test "rfc 7541 appendix c.6 response eviction with size limit" {
  let dec = @moon-http2.HpackDecoder::new(max_table_size=256)
  dec.set_max_table_size_limit(256)
  let r1 = hex_to_bytes(
    "4882 6402 5885 aec3 771a 4b61 96d0 7abe 9410 54d4 44a8 2005 9504 0b81 66e0 82a6 2d1b ff6e 919d 29ad 1718 63c7 8f0b 97c8 e9ae 82ae 43d3",
  )
  let h1 = dec.decode(r1)
  assert_eq(h1[0], @moon-http2.header_field(":status", "302"))
  assert_eq(
    h1[3],
    @moon-http2.header_field("location", "https://www.example.com"),
  )
  assert_eq(dec.table.size(), 222)

  let r2 = hex_to_bytes("4883 640e ffc1 c0bf")
  let h2 = dec.decode(r2)
  assert_eq(h2[0], @moon-http2.header_field(":status", "307"))
  assert_eq(h2[1], @moon-http2.header_field("cache-control", "private"))
  assert_eq(
    h2[3],
    @moon-http2.header_field("location", "https://www.example.com"),
  )
  assert_eq(dec.table.size(), 222)
}

///|
test "hpack encoder roundtrip and strict huffman error checks" {
  let enc = @moon-http2.HpackEncoder::new()
  let dec = @moon-http2.HpackDecoder::new()
  let hs = [
    @moon-http2.header_field(":status", "200"),
    @moon-http2.header_field("content-type", "application/json"),
    @moon-http2.header_field("x-secret", "tok-999", sensitive=true),
  ]
  let w1 = enc.encode(hs)
  let d1 = dec.decode(w1)
  assert_eq(d1, hs)
  // Second pass reuses dynamic table for content-type and keeps sensitive unindexed
  let w2 = enc.encode(hs)
  assert_true(w2.length() < w1.length())
  let d2 = dec.decode(w2)
  assert_eq(d2, hs)

  // Invalid Huffman padding (zero-padded) must fail with CompressionError
  let zero_pad = try {
    let _ = @moon-http2.huffman_decode(b"\x04")
    false
  } catch {
    _ => true
  }
  assert_true(zero_pad)

  // Padding longer than 7 bits (0xff = 8 ones) must fail
  let long_pad = try {
    let _ = @moon-http2.huffman_decode(b"\xff")
    false
  } catch {
    _ => true
  }
  assert_true(long_pad)

  // EOS symbol (30 ones) must fail
  let eos_sym = try {
    let _ = @moon-http2.huffman_decode(b"\xff\xff\xff\xff")
    false
  } catch {
    _ => true
  }
  assert_true(eos_sym)
}
