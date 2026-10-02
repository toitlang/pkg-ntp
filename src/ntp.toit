// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import io show BIG-ENDIAN
import net
import net.udp

NTP-DEFAULT-SERVER-HOSTNAME /string   ::= "pool.ntp.org"
NTP-DEFAULT-SERVER-PORT     /int      ::= 123
NTP-DEFAULT-MAX-RTT         /Duration ::= Duration --s=2

class Result:
  adjustment/Duration ::= ?
  accuracy/Duration ::= ?
  constructor .adjustment .accuracy:

synchronize -> Result?
    --network/net.Interface?=null
    --server/string=NTP-DEFAULT-SERVER-HOSTNAME
    --port/int=NTP-DEFAULT-SERVER-PORT
    --max-rtt/Duration=NTP-DEFAULT-MAX-RTT:
  outgoing ::= Packet_.outgoing
  effective-network := network ? network : net.open
  socket/udp.Socket? := null
  try:
    socket = effective-network.udp-open
    ips := effective-network.resolve server
    socket.connect
      net.SocketAddress
        ips[0]
        port

    marker ::= (random << 32) | random
    outgoing.marker = marker

    transmit ::= Time.monotonic-us
    socket.write outgoing.bytes

    catch: with-timeout max-rtt:
      data ::= socket.read
      received ::= Time.monotonic-us
      now ::= Time.now

      if not data or data.size < Packet_.DATAGRAM-SIZE:
        return null

      round-trip ::= Duration --us=(received - transmit)
      incoming ::= Packet_.incoming data
      t1 ::= now - round-trip  // Validated through the marker.
      t2 ::= incoming.receive-timestamp
      t3 ::= incoming.transmit-timestamp
      t4 ::= now

      // Drop invalid or too delayed packets.
      if incoming.marker != marker or incoming.version != VERSION_ or incoming.mode != MODE-SERVER_ or
          round-trip > max-rtt or t2 > t3:
        return null

      // Reject Kiss-o'-Death replies, unsynchronized clocks, and missing timestamps.
      if incoming.leap-indicator == LEAP-INDICATOR-UNSYNCHRONIZED_ or
          incoming.stratum == 0 or incoming.stratum >= 16 or not incoming.has-timestamps:
        return null

      // Computed accuracy is the round trip time minus the (often neglible) processing time.
      d ::= round-trip - (t2.to t3)

      // Compute the adjustment and return the synchronization result.
      c ::= ((t1.to t2) + (t4.to t3)) / 2
      return Result c d

  finally:
    try:
      if socket: socket.close
    finally:
      if effective-network != network: effective-network.close
  return null

// --------------------------------------------------------------------------------------------------------

LEAP-INDICATOR-NO-WARNING_ ::= 0
LEAP-INDICATOR-PLUS-ONE_   ::= 1
LEAP-INDICATOR-MINUS-ONE_  ::= 2
LEAP-INDICATOR-UNSYNCHRONIZED_ ::= 3

VERSION_                   ::= 4

MODE-CLIENT_               ::= 3
MODE-SERVER_               ::= 4

class Packet_:
  bytes/ByteArray ::= ?

  constructor.outgoing:
    bytes = ByteArray DATAGRAM-SIZE
    bytes[0] = (LEAP-INDICATOR-NO-WARNING_ << LEAP-INDICATOR-SHIFT) | (VERSION_ << VERSION-SHIFT) | MODE-CLIENT_

  constructor.incoming .bytes:

  // Code warning of impending leap-second to be inserted at the end of the last day of the current month.
  leap-indicator -> int: return (bytes[0] & LEAP-INDICATOR-MASK) >> LEAP-INDICATOR-SHIFT

  // 3-bit integer representing the NTP version number, currently 4
  version -> int: return (bytes[0] & VERSION-MASK) >> VERSION-SHIFT

  // 3-bit integer representing the mode.
  mode -> int: return (bytes[0] & MODE-MASK)

  // 8-bit integer representing the stratum. If it is zero, the packet is a Kiss-o'-Death
  // packet that must be discarded.
  stratum -> int: return bytes[1]

  // Local time at which the request arrived at the service host.
  receive-timestamp -> Time: return get-timestamp_ 32

  // Local time at which the reply departed the service host for the client host.
  transmit-timestamp -> Time: return get-timestamp_ 40

  // A zero timestamp denotes unknown or unsynchronized time.
  has-timestamps -> bool:
    return (BIG-ENDIAN.int64 bytes 32) != 0 and (BIG-ENDIAN.int64 bytes 40) != 0

  // Instead of passing an actual timestamp in the transmit field, we use a random
  // marker. The server side doesn't need to know anything about our perception
  // of time to be able to give us meaningful time updates.
  marker -> int: return BIG-ENDIAN.int64 bytes 24         // Stored in incoming originate timestamp field
  marker= value/int: BIG-ENDIAN.put-int64 bytes 40 value  // Stored in outgoing transmit timestamp field.

  // Helper functions for getting and settings timestamps.
  get-timestamp_ offset/int -> Time:
    seconds ::= (BIG-ENDIAN.uint32 bytes offset) - TIME-SECONDS-ADJUSTMENT
    ns ::= (BIG-ENDIAN.uint32 bytes offset + 4) * Duration.NANOSECONDS-PER-SECOND / (1 << 32)
    return Time.epoch --s=seconds --ns=ns

  // Private parts.
  static DATAGRAM-SIZE           ::= 4 * 4 + 4 * 8
  static LEAP-INDICATOR-MASK     ::= 0b11000000
  static VERSION-MASK            ::= 0b00111000
  static MODE-MASK               ::= 0b00000111
  static LEAP-INDICATOR-SHIFT    ::= 6
  static VERSION-SHIFT           ::= 3

  static TIME-SECONDS-ADJUSTMENT ::= 2_208_988_800  // Seconds from 1900 to 1970.
