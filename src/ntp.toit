// Copyright (C) 2021 Toitware ApS. All rights reserved.

import binary show BIG_ENDIAN
import net

NTP_SERVER_HOSTNAME_   ::= "pool.ntp.org"
NTP_SERVER_PORT_       ::= 123
NTP_MAX_ROUND_TRIP_    ::= Duration --s=2

class Result:
  adjustment/Duration ::= ?
  accuracy/Duration ::= ?
  constructor .adjustment .accuracy:

synchronize -> Result?:
  outgoing ::= Packet.outgoing
  network ::= net.open
  socket := network.udp_open
  try:
    ips := network.resolve NTP_SERVER_HOSTNAME_
    socket.connect
      net.SocketAddress
        ips[0]
        NTP_SERVER_PORT_

    marker ::= (random << 32) | random
    outgoing.marker = marker

    transmit ::= Time.monotonic_us
    socket.write outgoing.bytes

    catch: with_timeout NTP_MAX_ROUND_TRIP_:
      data ::= socket.read
      received ::= Time.monotonic_us
      now ::= Time.now

      round_trip ::= Duration --us=(received - transmit)
      incoming ::= Packet.incoming data
      t1 ::= now - round_trip  // Validated through the marker.
      t2 ::= incoming.receive_timestamp
      t3 ::= incoming.transmit_timestamp
      t4 ::= now

      // Drop invalid or too delayed packets.
      if incoming.marker != marker or incoming.version != VERSION_ or incoming.mode != MODE_SERVER_ or
          round_trip > NTP_MAX_ROUND_TRIP_ or t2 > t3:
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
  return null

// --------------------------------------------------------------------------------------------------------

LEAP_INDICATOR_NO_WARNING_ ::= 0
LEAP_INDICATOR_PLUS_ONE_   ::= 1
LEAP_INDICATOR_MINUS_ONE_  ::= 2
LEAP_INDICATOR_RESERVED_   ::= 3

VERSION_                   ::= 4

MODE_CLIENT_               ::= 3
MODE_SERVER_               ::= 4

class Packet:
  bytes/ByteArray ::= ?

  constructor.outgoing:
    bytes = ByteArray DATAGRAM_SIZE_
    bytes[0] = (LEAP_INDICATOR_NO_WARNING_ << LEAP_INDICATOR_SHIFT_) | (VERSION_ << VERSION_SHIFT_) | MODE_CLIENT_

  constructor.incoming .bytes:

  // Code warning of impending leap-second to be inserted at the end of the last day of the current month.
  leap_indicator -> int: return (bytes[0] & LEAP_INDICATOR_MASK_) >> LEAP_INDICATOR_SHIFT_

  // 3-bit integer representing the NTP version number, currently 4
  version -> int: return (bytes[0] & VERSION_MASK_) >> VERSION_SHIFT_

  // 3-bit integer representing the mode.
  mode -> int: return (bytes[0] & MODE_MASK_)

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
    seconds ::= (BIG_ENDIAN.uint32 bytes offset) - TIME_SECONDS_ADJUSTMENT_
    ns ::= (BIG_ENDIAN.uint32 bytes offset + 4) * Duration.NANOSECONDS_PER_SECOND / (1 << 32)
    return Time.epoch --s=seconds --ns=ns

  // Private parts.
  static DATAGRAM_SIZE_           ::= 4 * 4 + 4 * 8
  static LEAP_INDICATOR_MASK_     ::= 0b11000000
  static VERSION_MASK_            ::= 0b00111000
  static MODE_MASK_               ::= 0b00000111
  static LEAP_INDICATOR_SHIFT_    ::= 6
  static VERSION_SHIFT_           ::= 3

  static TIME_SECONDS_ADJUSTMENT_ ::= 2_208_988_800  // Seconds from 1900 to 1970.
