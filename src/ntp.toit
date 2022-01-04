// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import binary show BIG_ENDIAN
import net

NTP_DEFAULT_SERVER_HOSTNAME /string   ::= "pool.ntp.org"
NTP_DEFAULT_SERVER_PORT     /int      ::= 123
NTP_DEFAULT_MAX_RTT         /Duration ::= Duration --s=2

class Result:
  adjustment/Duration ::= ?
  accuracy/Duration ::= ?
  constructor .adjustment .accuracy:

synchronize -> Result?
    --network/net.Interface?=null
    --server/string=NTP_DEFAULT_SERVER_HOSTNAME
    --port/int=NTP_DEFAULT_SERVER_PORT
    --max_rtt/Duration=NTP_DEFAULT_MAX_RTT:
  outgoing ::= Packet_.outgoing
  effective_network := network ? network : net.open
  socket := effective_network.udp_open
  try:
    ips := effective_network.resolve server
    socket.connect
      net.SocketAddress
        ips[0]
        port

    marker ::= (random << 32) | random
    outgoing.marker = marker

    transmit ::= Time.monotonic_us
    socket.write outgoing.bytes

    catch: with_timeout max_rtt:
      data ::= socket.read
      received ::= Time.monotonic_us
      now ::= Time.now

      round_trip ::= Duration --us=(received - transmit)
      incoming ::= Packet_.incoming data
      t1 ::= now - round_trip  // Validated through the marker.
      t2 ::= incoming.receive_timestamp
      t3 ::= incoming.transmit_timestamp
      t4 ::= now

      // Drop invalid or too delayed packets.
      if incoming.marker != marker or incoming.version != VERSION_ or incoming.mode != MODE_SERVER_ or
          round_trip > max_rtt or t2 > t3:
        return null

      // If we've received a Kiss-o'-Death packet, we can't use the result.
      if incoming.stratum == 0:
        return null

      // Computed accuracy is the round trip time minus the (often neglible) processing time.
      d ::= round_trip - (t2.to t3)

      // Compute the adjustment and return the synchronization result.
      c ::= ((t1.to t2) + (t4.to t3)) / 2
      return Result c d

  finally:
    socket.close
    if effective_network != network: effective_network.close
  return null

// --------------------------------------------------------------------------------------------------------

LEAP_INDICATOR_NO_WARNING_ ::= 0
LEAP_INDICATOR_PLUS_ONE_   ::= 1
LEAP_INDICATOR_MINUS_ONE_  ::= 2
LEAP_INDICATOR_RESERVED_   ::= 3

VERSION_                   ::= 4

MODE_CLIENT_               ::= 3
MODE_SERVER_               ::= 4

class Packet_:
  bytes/ByteArray ::= ?

  constructor.outgoing:
    bytes = ByteArray DATAGRAM_SIZE
    bytes[0] = (LEAP_INDICATOR_NO_WARNING_ << LEAP_INDICATOR_SHIFT) | (VERSION_ << VERSION_SHIFT) | MODE_CLIENT_

  constructor.incoming .bytes:

  // Code warning of impending leap-second to be inserted at the end of the last day of the current month.
  leap_indicator -> int: return (bytes[0] & LEAP_INDICATOR_MASK) >> LEAP_INDICATOR_SHIFT

  // 3-bit integer representing the NTP version number, currently 4
  version -> int: return (bytes[0] & VERSION_MASK) >> VERSION_SHIFT

  // 3-bit integer representing the mode.
  mode -> int: return (bytes[0] & MODE_MASK)

  // 8-bit integer representing the stratum. If it is zero, the packet is a Kiss-o'-Death
  // packet that must be discarded.
  stratum -> int: return bytes[1]

  // Local time at which the request arrived at the service host.
  receive_timestamp -> Time: return get_timestamp_ 32

  // Local time at which the reply departed the service host for the client host.
  transmit_timestamp -> Time: return get_timestamp_ 40

  // Instead of passing an actual timestamp in the transmit field, we use a random
  // marker. The server side doesn't need to know anything about our perception
  // of time to be able to give us meaningful time updates.
  marker -> int: return BIG_ENDIAN.int64 bytes 24         // Stored in incoming originate timestamp field
  marker= value/int: BIG_ENDIAN.put_int64 bytes 40 value  // Stored in outgoing transmit timestamp field.

  // Helper functions for getting and settings timestamps.
  get_timestamp_ offset/int -> Time:
    seconds ::= (BIG_ENDIAN.uint32 bytes offset) - TIME_SECONDS_ADJUSTMENT
    ns ::= (BIG_ENDIAN.uint32 bytes offset + 4) * Duration.NANOSECONDS_PER_SECOND / (1 << 32)
    return Time.epoch --s=seconds --ns=ns

  // Private parts.
  static DATAGRAM_SIZE           ::= 4 * 4 + 4 * 8
  static LEAP_INDICATOR_MASK     ::= 0b11000000
  static VERSION_MASK            ::= 0b00111000
  static MODE_MASK               ::= 0b00000111
  static LEAP_INDICATOR_SHIFT    ::= 6
  static VERSION_SHIFT           ::= 3

  static TIME_SECONDS_ADJUSTMENT ::= 2_208_988_800  // Seconds from 1900 to 1970.
