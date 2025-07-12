target="/c/ProgramData/Android/platform-tools"
ip="192.168.1.104"
driver_dir="//sdcard/games/drivers/"

if [[ ":$PATH:" != *":$target:"* ]]; then
    export PATH="$target:$PATH"
fi

adb connect "$ip"
adb push -a ./turnip_workdir/emulator "$driver_dir"
adb push -a ./turnip_workdir/magisk   "$driver_dir"

