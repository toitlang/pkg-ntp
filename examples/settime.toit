// Copyright (C) 2021 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

// If the current system time is not credible this
// program fetches a new time from the NTP servers
// and sets the system time.

import ntp
import esp32 show set_real_time_clock

main:
  now := Time.now
  if now < (Time.from_string "2022-01-07T00:00:00Z"):
    result ::= ntp.synchronize
    if result:
      new_now := Time.now + result.adjustment
      set_real_time_clock new_now
      print "Set time to $Time.now"
    else:
      print "ntp: synchronization request failed"
  else:
    print "We already know the time is $now"
