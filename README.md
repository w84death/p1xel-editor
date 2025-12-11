# P1Xel Editor

```
_ \   _ | \ \  /        |      ____|      | _)  |                
|   |   |  \  /    _ \  |      __|     _` |  |  __|   _ \     __| 
___/    |     \    __/  |      |      (   |  |  |    (   |   |    
_|     _|  _/\_\ \___| _|     _____| \__,_| _| \__|  \___/  _|    
```

pre-alpha

![prealpha](screenshot.png)

## Run
```
zig build run
```

## Build Small Binary

![Windows vs Linux](win-linux.png)

Linux
```
zig build -Doptimize=ReleaseSmall upx
```

Windows
``` 
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseSmall
upx zig-out/bin/ray_zig_engine.exe
```
