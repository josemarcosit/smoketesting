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
======================================
       POWERHELL SMOKE TESTING
                VERSION 3.0
======================================

[SUCCESS] HTTP 200 | 946.62ms | https://www.windows93.net                                                               
[SUCCESS] HTTP 200 | 970.41ms | https://www.asciimation.co.nz                                                           
[SUCCESS] HTTP 200 | 1075.74ms | https://dos.zone                                                                       
[SUCCESS] HTTP 200 | 589.07ms | https://telehack.com                                                                    
[ERROR] 278.89ms | https://t.ly | The replica status code does not indicate success: 403 (Forbidden).
[ERROR] 46.85ms | https://is.gd | The replica status code does not indicate success: 403 (Forbidden).
[SUCCESS] HTTP 200 | 690.79ms | https://geekprank.com                                                                   

[INFO] Report successfully exported: .\reports\smoke-test-results.csv

======================================
              TEST SUMMARY
======================================
Total Targets:     7
Successful:        5
Failed:            2
Average Response:  656.91 ms
CSV Report:        .\reports\smoke-test-results.csv
======================================
```
