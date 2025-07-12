# Building Mesa/Turnip on Windows with MSYS2 and VS Code

This guide covers all steps and settings needed to build Mesa/Turnip on Windows using MSYS2 and VS Code, based on a workflow that is confirmed to work.

## 1. Install MSYS2
- Download from [https://www.msys2.org/](https://www.msys2.org/)
- Run the installer and install to a path without spaces (e.g., `C:\msys64`)

## 2. Update MSYS2
Open the "MSYS2 MSYS" terminal and run:
```sh
pacman -Syu
```
If prompted, close the terminal and reopen it, then run:
```sh
pacman -Su
```

## 3. Install Required Packages (MinGW64)
Open the "MSYS2 MinGW 64-bit" terminal and run:
```sh
pacman -S mingw-w64-x86_64-meson mingw-w64-x86_64-ninja unzip curl flex bison zip python python-pip python-mako mingw-w64-x86_64-glslang patch
```

## 4. VS Code Terminal Integration
- Open VS Code settings (`settings.json`).
- Add the following profile for MSYS2 bash:
```jsonc
"terminal.integrated.profiles.windows": {
  "MSYS2 (bash)": {
    "path": "C:\\msys64\\usr\\bin\\bash.exe",
    "args": ["--login", "-i", "-c", "cd \"$PWD\"; exec bash"]
  }
},
"terminal.integrated.cwd": "${workspaceFolder}",
"terminal.integrated.env.windows": {
  "CHERE_INVOKING": "1"
}
```
- Set default terminal profile if desired:
```jsonc
"terminal.integrated.defaultProfile.windows": "MSYS2 (bash)"
```
- To ensure MinGW64 binaries (like meson, ninja, etc.) are available in bash, add this to the top of your build script:
```bash
export PATH="/mingw64/bin:$PATH"
```
- This guarantees all required tools are found when running in the VS Code-integrated MSYS2 bash terminal.

## 5. Prepare Your Build Script
- Use the provided `build-turnip.mingw64.sh` script.
- Make sure your `deps` list uses only MSYS2/MinGW64 package names:
  - `mingw-w64-x86_64-meson`, `mingw-w64-x86_64-ninja`, `unzip`, `curl`, `flex`, `bison`, `zip`, `python`, `python-pip`, `python-mako`, `mingw-w64-x86_64-glslang`, `patch`
- The script will check and install missing dependencies automatically.

## 6. Running the Build
- Open VS Code terminal and select "MSYS2 (bash)".
- Navigate to your project folder (should be automatic with the above settings).
- Run your build script:
```sh
./build-turnip.mingw64.sh --preserve-cache --author yourname
```

## 7. Using ADB to move files to android (example)
- Depends on while you've adb, connection to phone, and place to store files
```sh
# adb.pushfiles.sh
target="/c/ProgramData/Android/platform-tools"
ip="192.168.1.104"
driver_dir="//sdcard/games/drivers/"

if [[ ":$PATH:" != *":$target:"* ]]; then
    export PATH="$target:$PATH"
fi

adb connect "$ip"
adb push -a ./turnip_workdir/emulator "$driver_dir"
adb push -a ./turnip_workdir/magisk   "$driver_dir"

```

## 8. Notes
- Do not use Ubuntu/Debian package names in your script (`apt`, etc.).
- All patching and build steps work natively in MSYS2 MinGW64.
- If you need to use MinGW64 binaries, prepend their bin directory to your PATH as needed.
- For glslangValidator, use `mingw-w64-x86_64-glslang`.
- For patching, use the standard `patch` utility (installed via `patch`).

## 9. Troubleshooting
- If a package is not found, check its name in the MSYS2 package database: [https://packages.msys2.org/](https://packages.msys2.org/)
- Always run your build script in the MinGW64 shell for native Windows binaries.
- If you encounter path or environment issues, verify your VS Code settings and shell profile.

---

**This guide is based on a workflow confirmed to work for building Mesa/Turnip on Windows with MSYS2 and VS Code.**
