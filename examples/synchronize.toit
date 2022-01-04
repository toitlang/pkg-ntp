// Copyright (C) 2021 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import ntp

main:
  result ::= ntp.synchronize
  if result:
    print "ntp: $result.adjustment ±$result.accuracy"
  else:
    print "ntp: synchronization request failed"
