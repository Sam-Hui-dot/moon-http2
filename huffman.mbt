///|
/// RFC 7541 Appendix B canonical Huffman codes for octets 0..255.
let huffman_codes : FixedArray[UInt32] = [
  0x1ff8U, 0x7fffd8U, 0xfffffe2U, 0xfffffe3U, 0xfffffe4U, 0xfffffe5U, 0xfffffe6U,
  0xfffffe7U, 0xfffffe8U, 0xffffeaU, 0x3ffffffcU, 0xfffffe9U, 0xfffffeaU, 0x3ffffffdU,
  0xfffffebU, 0xfffffecU, 0xfffffedU, 0xfffffeeU, 0xfffffefU, 0xffffff0U, 0xffffff1U,
  0xffffff2U, 0x3ffffffeU, 0xffffff3U, 0xffffff4U, 0xffffff5U, 0xffffff6U, 0xffffff7U,
  0xffffff8U, 0xffffff9U, 0xffffffaU, 0xffffffbU, 0x14U, 0x3f8U, 0x3f9U, 0xffaU,
  0x1ff9U, 0x15U, 0xf8U, 0x7faU, 0x3faU, 0x3fbU, 0xf9U, 0x7fbU, 0xfaU, 0x16U, 0x17U,
  0x18U, 0x0U, 0x1U, 0x2U, 0x19U, 0x1aU, 0x1bU, 0x1cU, 0x1dU, 0x1eU, 0x1fU, 0x5cU,
  0xfbU, 0x7ffcU, 0x20U, 0xffbU, 0x3fcU, 0x1ffaU, 0x21U, 0x5dU, 0x5eU, 0x5fU, 0x60U,
  0x61U, 0x62U, 0x63U, 0x64U, 0x65U, 0x66U, 0x67U, 0x68U, 0x69U, 0x6aU, 0x6bU, 0x6cU,
  0x6dU, 0x6eU, 0x6fU, 0x70U, 0x71U, 0x72U, 0xfcU, 0x73U, 0xfdU, 0x1ffbU, 0x7fff0U,
  0x1ffcU, 0x3ffcU, 0x22U, 0x7ffdU, 0x3U, 0x23U, 0x4U, 0x24U, 0x5U, 0x25U, 0x26U,
  0x27U, 0x6U, 0x74U, 0x75U, 0x28U, 0x29U, 0x2aU, 0x7U, 0x2bU, 0x76U, 0x2cU, 0x8U,
  0x9U, 0x2dU, 0x77U, 0x78U, 0x79U, 0x7aU, 0x7bU, 0x7ffeU, 0x7fcU, 0x3ffdU, 0x1ffdU,
  0xffffffcU, 0xfffe6U, 0x3fffd2U, 0xfffe7U, 0xfffe8U, 0x3fffd3U, 0x3fffd4U, 0x3fffd5U,
  0x7fffd9U, 0x3fffd6U, 0x7fffdaU, 0x7fffdbU, 0x7fffdcU, 0x7fffddU, 0x7fffdeU, 0xffffebU,
  0x7fffdfU, 0xffffecU, 0xffffedU, 0x3fffd7U, 0x7fffe0U, 0xffffeeU, 0x7fffe1U, 0x7fffe2U,
  0x7fffe3U, 0x7fffe4U, 0x1fffdcU, 0x3fffd8U, 0x7fffe5U, 0x3fffd9U, 0x7fffe6U, 0x7fffe7U,
  0xffffefU, 0x3fffdaU, 0x1fffddU, 0xfffe9U, 0x3fffdbU, 0x3fffdcU, 0x7fffe8U, 0x7fffe9U,
  0x1fffdeU, 0x7fffeaU, 0x3fffddU, 0x3fffdeU, 0xfffff0U, 0x1fffdfU, 0x3fffdfU, 0x7fffebU,
  0x7fffecU, 0x1fffe0U, 0x1fffe1U, 0x3fffe0U, 0x1fffe2U, 0x7fffedU, 0x3fffe1U, 0x7fffeeU,
  0x7fffefU, 0xfffeaU, 0x3fffe2U, 0x3fffe3U, 0x3fffe4U, 0x7ffff0U, 0x3fffe5U, 0x3fffe6U,
  0x7ffff1U, 0x3ffffe0U, 0x3ffffe1U, 0xfffebU, 0x7fff1U, 0x3fffe7U, 0x7ffff2U, 0x3fffe8U,
  0x1ffffecU, 0x3ffffe2U, 0x3ffffe3U, 0x3ffffe4U, 0x7ffffdeU, 0x7ffffdfU, 0x3ffffe5U,
  0xfffff1U, 0x1ffffedU, 0x7fff2U, 0x1fffe3U, 0x3ffffe6U, 0x7ffffe0U, 0x7ffffe1U,
  0x3ffffe7U, 0x7ffffe2U, 0xfffff2U, 0x1fffe4U, 0x1fffe5U, 0x3ffffe8U, 0x3ffffe9U,
  0xffffffdU, 0x7ffffe3U, 0x7ffffe4U, 0x7ffffe5U, 0xfffecU, 0xfffff3U, 0xfffedU,
  0x1fffe6U, 0x3fffe9U, 0x1fffe7U, 0x1fffe8U, 0x7ffff3U, 0x3fffeaU, 0x3fffebU, 0x1ffffeeU,
  0x1ffffefU, 0xfffff4U, 0xfffff5U, 0x3ffffeaU, 0x7ffff4U, 0x3ffffebU, 0x7ffffe6U,
  0x3ffffecU, 0x3ffffedU, 0x7ffffe7U, 0x7ffffe8U, 0x7ffffe9U, 0x7ffffeaU, 0x7ffffebU,
  0xffffffeU, 0x7ffffecU, 0x7ffffedU, 0x7ffffeeU, 0x7ffffefU, 0x7fffff0U, 0x3ffffeeU,
]

///|
/// RFC 7541 Appendix B Huffman code bit lengths for octets 0..255.
let huffman_lens : FixedArray[Int32] = [
  13, 23, 28, 28, 28, 28, 28, 28, 28, 24, 30, 28, 28, 30, 28, 28, 28, 28, 28, 28,
  28, 28, 30, 28, 28, 28, 28, 28, 28, 28, 28, 28, 6, 10, 10, 12, 13, 6, 8, 11, 10,
  10, 8, 11, 8, 6, 6, 6, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 7, 8, 15, 6, 12, 10, 13, 6,
  7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 7, 8, 13,
  19, 13, 14, 6, 15, 5, 6, 5, 6, 5, 6, 6, 6, 5, 7, 7, 6, 6, 6, 5, 6, 7, 6, 5, 5,
  6, 7, 7, 7, 7, 7, 15, 11, 14, 13, 28, 20, 22, 20, 20, 22, 22, 22, 23, 22, 23, 23,
  23, 23, 23, 24, 23, 24, 24, 22, 23, 24, 23, 23, 23, 23, 21, 22, 23, 22, 23, 23,
  24, 22, 21, 20, 22, 22, 23, 23, 21, 23, 22, 22, 24, 21, 22, 23, 23, 21, 21, 22,
  21, 23, 22, 23, 23, 20, 22, 22, 22, 23, 22, 22, 23, 26, 26, 20, 19, 22, 23, 22,
  25, 26, 26, 26, 27, 27, 26, 24, 25, 19, 21, 26, 27, 27, 26, 27, 24, 21, 21, 26,
  26, 28, 27, 27, 27, 20, 24, 20, 21, 22, 21, 21, 23, 22, 22, 25, 25, 24, 24, 26,
  23, 26, 27, 26, 26, 27, 27, 27, 27, 27, 28, 27, 27, 27, 27, 27, 26,
]

///|
priv struct HuffmanTrie {
  left : Array[Int32]
  right : Array[Int32]
  sym : Array[Int32]
}

///|
fn build_huffman_trie() -> HuffmanTrie {
  let left : Array[Int32] = [-1]
  let right : Array[Int32] = [-1]
  let sym : Array[Int32] = [-1]

  fn insert_code(code : UInt32, bits : Int32, s : Int32) -> Unit {
    let mut node = 0
    for b = bits - 1; b >= 0; b = b - 1 {
      let bit = (code >> b) & 1U
      if bit == 0U {
        if left[node] == -1 {
          left[node] = left.length()
          left.push(-1)
          right.push(-1)
          sym.push(-1)
        }
        node = left[node]
      } else {
        if right[node] == -1 {
          right[node] = left.length()
          left.push(-1)
          right.push(-1)
          sym.push(-1)
        }
        node = right[node]
      }
    }
    sym[node] = s
  }

  for i = 0; i < 256; i = i + 1 {
    insert_code(huffman_codes[i], huffman_lens[i], i)
  }
  // EOS symbol 256: 30 ones (0x3fffffff)
  insert_code(0x3fffffffU, 30, 256)
  { left, right, sym, }
}

///|
let huffman_trie : HuffmanTrie = build_huffman_trie()

///|
/// Return the exact Huffman-encoded byte length of raw octets without allocating output.
pub fn huffman_encoded_len(data : Bytes) -> Int32 {
  let mut bits = 0
  for i = 0; i < data.length(); i = i + 1 {
    bits += huffman_lens[data[i].to_int()]
  }
  (bits + 7) / 8
}

///|
/// Encode raw octets using the RFC 7541 Appendix B static Huffman code and EOS padding.
pub fn huffman_encode(data : Bytes) -> Bytes {
  let buf = @buffer.Buffer()
  let mut cur : UInt64 = 0UL
  let mut nbits = 0
  for i = 0; i < data.length(); i = i + 1 {
    let b = data[i].to_int()
    let code = huffman_codes[b].to_uint64()
    let clen = huffman_lens[b]
    cur = (cur << clen) | code
    nbits += clen
    while nbits >= 8 {
      nbits -= 8
      buf.write_byte(((cur >> nbits) & 0xffUL).to_byte())
    }
  }
  if nbits > 0 {
    let pad = 8 - nbits
    let final_byte = ((cur << pad) | ((1UL << pad) - 1UL)) & 0xffUL
    buf.write_byte(final_byte.to_byte())
  }
  buf.to_bytes()
}

///|
/// Decode RFC 7541 Huffman-encoded octets strictly enforcing §5.2 padding and EOS rules.
pub fn huffman_decode(data : Bytes) -> Bytes raise H2Error {
  let buf = @buffer.Buffer()
  let mut node = 0
  let mut pending_bits = 0
  let mut pending_val = 0U
  for i = 0; i < data.length(); i = i + 1 {
    let byte_val = data[i].to_int()
    for shift = 7; shift >= 0; shift = shift - 1 {
      let bit = (byte_val >> shift) & 1
      node = if bit == 0 {
        huffman_trie.left[node]
      } else {
        huffman_trie.right[node]
      }
      if node < 0 {
        raise CompressionError("invalid Huffman code prefix")
      }
      pending_bits += 1
      pending_val = (pending_val << 1) | bit.reinterpret_as_uint()
      let s = huffman_trie.sym[node]
      if s >= 0 {
        if s == 256 {
          raise CompressionError("EOS symbol encountered in Huffman data")
        }
        buf.write_byte(s.to_byte())
        node = 0
        pending_bits = 0
        pending_val = 0U
      }
    }
  }
  if pending_bits > 7 {
    raise CompressionError(
      "Huffman EOS padding exceeds 7 bits (\{pending_bits} bits)",
    )
  }
  if pending_bits > 0 {
    let expected = (1U << pending_bits) - 1U
    if pending_val != expected {
      raise CompressionError("Huffman EOS padding contains zero bit")
    }
  }
  buf.to_bytes()
}
