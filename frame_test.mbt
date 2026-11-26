///|
test "rfc9113: frame roundtrip for all standard frame types" {
  let frames : Array[@moon-http2.H2Frame] = [
    Data(
      stream_id=1U,
      end_stream=true,
      data=@moon-http2.ascii_to_bytes("hello"),
      flow_len=5,
    ),
    Headers(
      stream_id=3U,
      end_stream=false,
      end_headers=true,
      priority=Some({ exclusive: true, dependency: 1U, weight: 16, }),
      fragment=@moon-http2.hex_to_bytes("8286418a089d5c0b8170dc780f03"),
    ),
    Priority(stream_id=5U, spec={
      exclusive: false,
      dependency: 3U,
      weight: 64,
    }),
    RstStream(stream_id=3U, code=Cancel),
    Settings(ack=false, params=[
      { id: @moon-http2.SETTING_MAX_CONCURRENT_STREAMS, value: 100U, },
      { id: @moon-http2.SETTING_INITIAL_WINDOW_SIZE, value: 65535U, },
    ]),
    Settings(ack=true, params=[]),
    Ping(ack=false, opaque_data=@moon-http2.ascii_to_bytes("12345678")),
    GoAway(
      last_stream_id=5U,
      code=NoError,
      debug_data=@moon-http2.ascii_to_bytes("bye"),
    ),
    WindowUpdate(stream_id=1U, increment=4096U),
    Continuation(
      stream_id=3U,
      end_headers=true,
      fragment=@moon-http2.hex_to_bytes("82"),
    ),
  ]
  for f in frames {
    let wire = @moon-http2.encode_frame(f)
    let decoded = @moon-http2.decode_frame_at(wire, 0)
    match decoded {
      Some((f2, next)) => {
        assert_eq(next, wire.length())
        assert_eq(f2, f)
      }
      None => abort("expected decoded frame")
    }
  }
}

///|
test "rfc9113: full server handshake, request/response, ping, and svg timeline" {
  let conn = @moon-http2.H2Connection::new_server()
  let init_out = conn.take_outbound()
  let init_frames = @moon-http2.decode_frames(init_out)
  assert_eq(init_frames.length(), 1)
  assert_eq(init_frames[0].kind_name(), "SETTINGS")

  let enc = @moon-http2.HpackEncoder::new()
  let hdr_block = enc.encode([
    @moon-http2.header_field(":method", "GET"),
    @moon-http2.header_field(":scheme", "http"),
    @moon-http2.header_field(":path", "/hello"),
    @moon-http2.header_field(":authority", "localhost"),
  ])
  let req_buf = @buffer.Buffer()
  req_buf.write_bytesview(
    @moon-http2.ascii_to_bytes(@moon-http2.CLIENT_PREFACE_STR)[:],
  )
  @moon-http2.encode_frame_into(req_buf, Settings(ack=false, params=[]))
  @moon-http2.encode_frame_into(
    req_buf,
    Headers(
      stream_id=1U,
      end_stream=true,
      end_headers=true,
      priority=None,
      fragment=hdr_block,
    ),
  )
  @moon-http2.encode_frame_into(
    req_buf,
    Ping(ack=false, opaque_data=@moon-http2.ascii_to_bytes("abcdefgh")),
  )

  let events = conn.feed(req_buf.to_bytes())
  let mut saw_complete = false
  let mut saw_ping = false
  for ev in events {
    match ev {
      RequestComplete(stream_id=1U, ..) => saw_complete = true
      PingReceived(ack=false, ..) => saw_ping = true
      _ => ()
    }
  }
  assert_true(saw_complete)
  assert_true(saw_ping)

  conn.send_response(
    1U,
    200,
    extra_headers=[@moon-http2.header_field("content-type", "text/plain")],
    body=@moon-http2.ascii_to_bytes("ok"),
  )
  let resp_frames = @moon-http2.decode_frames(conn.take_outbound())
  assert_eq(resp_frames.length(), 4)
  assert_eq(resp_frames[0].kind_name(), "SETTINGS(ACK)")
  assert_eq(resp_frames[1].kind_name(), "PING(ACK)")
  assert_eq(resp_frames[2].kind_name(), "HEADERS")
  assert_eq(resp_frames[3].kind_name(), "DATA")
  let svg = @moon-http2.render_timeline_svg(conn.frame_trace())
  assert_true(svg.contains("moon-http2-timeline"))
}
