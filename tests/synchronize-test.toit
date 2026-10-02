// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import expect show *
import io show BIG-ENDIAN
import net
import net.udp
import ntp

main:
  // Every response is generated locally; no public NTP server is contacted.
  network := net.open
  try:
    for leap := 0; leap < 3; leap++:
      for stratum := 1; stratum <= 15; stratum++:
        result := exchange network --leap=leap --stratum=stratum
        expect-not-null result
        expect (result.accuracy >= (Duration --us=0))
        expected := Time.parse "2024-01-01T00:00:00Z"
        adjusted := Time.now + result.adjustment
        expect ((expected.to adjusted).in-us.abs <= 2_000_000)

    print "Rejecting unsynchronized leap indicator"
    expect-null (exchange network --leap=3)
    for stratum := 0; stratum < 256; stratum++:
      if 1 <= stratum <= 15: continue
      print "Rejecting stratum $stratum"
      expect-null (exchange network --stratum=stratum)

    print "Rejecting missing timestamps"
    expect-null (exchange network --zero-receive)
    expect-null (exchange network --zero-transmit)
    expect-null (exchange network --zero-receive --zero-transmit)
    expect-null (exchange network --bad-marker)
    expect-null (exchange network --version=3)
    expect-null (exchange network --mode=3)
    expect-null (exchange network --reversed-timestamps)
    expect-null (exchange network --size=47)
    expect-null (exchange network --size=0)
    expect-null (exchange network --no-reply)
    expect-not network.is-closed
  finally:
    network.close

exchange network/net.Interface -> ntp.Result?
    --leap/int=0
    --stratum/int=1
    --version/int=4
    --mode/int=4
    --size/int=48
    --zero-receive/bool=false
    --zero-transmit/bool=false
    --bad-marker/bool=false
    --reversed-timestamps/bool=false
    --reply/bool=true:
  socket := network.udp-open --port=0
  try:
    results := with-timeout (Duration --s=5):
      Task.group [
        ::
          request := socket.receive
          expect-equals 48 request.data.size
          expect-equals 0x23 request.data[0]
          response := ByteArray 48
          response[0] = (leap << 6) | (version << 3) | mode
          response[1] = stratum
          marker := BIG-ENDIAN.int64 request.data 40
          BIG-ENDIAN.put-int64 response 24 (bad-marker ? marker ^ 1 : marker)
          // 2024-01-01, expressed in seconds since 1900.
          if not zero-receive:
            BIG-ENDIAN.put-uint32 response 32 (reversed-timestamps ? 3_913_056_001 : 3_913_056_000)
          if not zero-transmit:
            BIG-ENDIAN.put-uint32 response 40 3_913_056_000
          if reply:
            socket.send (udp.Datagram (response.copy 0 size) request.address)
          null,
        ::
          ntp.synchronize --network=network --server="127.0.0.1"
              --port=socket.local-address.port
              --max-rtt=(Duration --ms=200),
      ]
    return results[1]
  finally:
    socket.close
