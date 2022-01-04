# Ntp 

NTP (Network Time Protocol) client.

Fetches the current time from a NTP server (by default "pool.ntp.org").

This package does not update the system time.

## Usage

```
import ntp

main:
  result ::= ntp.synchronize
  if result:
    print "ntp: $result.adjustment ±$result.accuracy"
```
