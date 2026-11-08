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
       POWERSHELL SMOKE TESTING
======================================

[SUCCESS] HTTP 200 - https://www.windows93.net                                                                          
[SUCCESS] HTTP 200 - https://www.asciimation.co.nz                                                                      
[SUCCESS] HTTP 200 - https://dos.zone                                                                                   
[SUCCESS] HTTP 200 - https://telehack.com                                                                               
[ERROR] https://t.ly - This host is unknown. (t.ly:443)
[ERROR] https://is.gd - The replica's status code does not indicate success: 403 (Forbidden).                                
[SUCCESS] HTTP 200 - https://geekprank.com                                                                              

======================================
              TEST SUMMARY
======================================
Total Targets:    7
Successful:       5
Failed:            2
======================================
```
