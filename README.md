# NTP

NTP (Network Time Protocol) client.

Fetches the current time from a NTP server (by default "pool.ntp.org").

This package does not update the system time.

## Usage

```
import ntp
import esp32

main:
  result ::= ntp.synchronize
  if result:
    print "ntp: $result.adjustment ±$result.accuracy"
    esp32.adjust_real_time_clock result.adjustment
```
