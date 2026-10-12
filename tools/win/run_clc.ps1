$env:PATH = "C:\msys64\mingw64\bin;C:\Program Files\LLVM\bin;" + [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\barba\Documents\xbox360\FARCRY3\xbox360\fc3-nx\tools\win\build_clc_native.sh" 16
