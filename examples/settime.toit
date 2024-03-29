// Copyright (C) 2021 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

// If the current system time is not credible this
// program fetches a new time from the NTP servers
// and sets the system time.

import ntp
import esp32 show adjust_real_time_clock

main:
  now := Time.now
  if now < (Time.from_string "2022-01-10T00:00:00Z"):
    result ::= ntp.synchronize
    if result:
      adjust_real_time_clock result.adjustment
      print "Set time to $Time.now by adjusting $result.adjustment"
    else:
      print "ntp: synchronization request failed"
  else:
    print "We already know the time is $now"
