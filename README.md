# smoketesting
A PowerShell Script for Smoke Testing

## Example: targets.txt
```prompt
https://www.windows93.net
https://www.asciimation.co.nz
https://dos.zone
https://telehack.com
https://t.ly 
https://is.gd
https://geekprank.com 
```


## Example output
```prompt
==========================================
       POWERSHELL SMOKE TESTING
                VERSION 4.0
==========================================

[INFO] Starting parallel HTTP tests...
[INFO] Total targets: 7
[INFO] Max concurrency: 5
[INFO] Retry attempts: 2

[SUCCESS] HTTP 200 | 579.3ms | https://telehack.com                                                                     
[SUCCESS] HTTP 200 | 675.28ms | https://www.windows93.net
[SUCCESS] HTTP 200 | 1098.22ms | https://dos.zone
[SUCCESS] HTTP 200 | 1310.84ms | https://www.asciimation.co.nz
[SUCCESS] HTTP 200 | 739.82ms | https://geekprank.com
[FAILED] HTTP 403 | 8.87ms | https://t.ly  | This host is unknown. (t.ly:443)
[FAILED] HTTP 403 | 30.74ms | https://is.gd  | The replica's status code does not indicate success: 403 (Forbidden).

[INFO] Reports generated successfully.

==========================================
              TEST SUMMARY
==========================================
Total Targets:      7
Successful:         5
Failed:             2
Slow Endpoints:     0
Success Rate:       71.43%
Average Latency:    634.72 ms
Execution Time:     2.83 seconds

CSV Report:         .\reports\smoke-test_20261108_205627.csv
JSON Report:        .\reports\smoke-test_20261108_205627.json
==========================================
```
