#!/bin/bash -e

echo "in case you forgot: this is broken. use main instead. or fix this one."
exit 1

# Required variables
sdkver="34" #"33"
default_vkver="1.4.311+"
building_os="windows" #"linux"
default_ndkver="android-ndk-r29-beta2" #"android-ndk-r28b"
default_ndk="https://dl.google.com/android/repository/$default_ndkver-$building_os.zip"
default_mesaver="mesa-25.1.6" #"main"
default_mesa="https://gitlab.freedesktop.org/mesa/mesa/-/archive/$default_mesaver/mesa-$default_mesaver.zip"
default_author="v3kt0r-87"

if [[ "$building_os" == "windows" ]]; then
    # mingw-w64-x86_64-llvm
    deps="mingw-w64-x86_64-meson mingw-w64-x86_64-ninja mingw-w64-x86_64-python mingw-w64-x86_64-python-pip mingw-w64-x86_64-python-mako mingw-w64-x86_64-python-yaml mingw-w64-x86_64-glslang unzip curl flex bison zip patch"
elif [[ "$building_os" == "linux" ]]; then
    deps="meson ninja-build patchelf unzip curl flex bison zip python3 python3-pip python3-mako python-is-python3 glslang-tools"    
else
    echo "[ERROR] Unsupported building OS: $building_os"
    exit 1
fi

# Parameter parsing
preserve_cache=0
custom_ndk=""
custom_mesa=""
author=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ndk)
            custom_ndk="$2"
            shift 2
            ;;
        --mesa)
            custom_mesa="$2"
            shift 2
            ;;
        --author)
            author="$2"
            shift 2
            ;;
        --preserve-cache)
            preserve_cache=1
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Retrieve Android Version
andver=$(echo "$(curl -s "https://developer.android.com/tools/releases/platforms")" | grep -oP "Android \K[0-9.]+(?=.*?API level $sdkver)" | head -n1) || true
andver="${andver:-"(sdk$sdkver)"}"

# Android NDK
ndksrc="${custom_ndk:-$default_ndk}"
ndkfile=$(basename "$ndksrc")
ndkdir=$(basename "$ndksrc" .zip)
ndkdir="${ndkdir%${building_os}}" # Remove OS suffix
ndkdir="${ndkdir%-}" # Remove trailing hyphen if present
ndkver=$(echo "$ndksrc" | grep -oP '(?<=android-ndk-r)[0-9\.]+[a-z]*' | head -n 1)

# Mesa source
mesasrc="${custom_mesa:-$default_mesa}"
mesafile=$(basename "$mesasrc")
mesadir=$(basename "$mesasrc" .zip)
mesaver=$(echo "$mesadir" | grep -oP '(?<=mesa-)[\d\.]+.+' | head -n 1)

# Defining author
author="${author:-$default_author}"

# Colors for terminal output
green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

# Directories
basedir="$(pwd)"
patchesdir="$(pwd)/patches"
workdir="$(pwd)/turnip_workdir"
magiskdir="$workdir/turnip_module"

DRIVER_FILE="vulkan.turnip.so"
META_FILE="meta.json"

#clear

echo "Checking system for required dependencies..."

missing_packages=()
for deps_chk in $deps; do
    if [[ "$deps_chk" == python-* ]]; then
        # Extract module name (e.g. python-mako -> mako)
        py_mod=${deps_chk#python-}
        # Special case for python-pip -> pip
        [[ "$py_mod" == "pip" ]] && py_mod="pip"
        if pacman -Q $deps_chk &>/dev/null || python3 -c "import $py_mod" &>/dev/null; then
            echo -e "$green - $deps_chk (or pip $py_mod) found $nocolor"
        else
            echo -e "$red - $deps_chk (and pip $py_mod) not found $nocolor"
            missing_packages+=("$deps_chk")
        fi
    else
        if pacman -Q $deps_chk &>/dev/null; then
            echo -e "$green - $deps_chk found $nocolor"
        else
            echo -e "$red - $deps_chk not found $nocolor"
            missing_packages+=("$deps_chk")
        fi
    fi
done

if (( ${#missing_packages[@]} > 0 )); then
    echo -e "\nMissing dependencies, installing them now...\n"
    pacman -S --noconfirm "${missing_packages[@]}"
else
    echo -e "\nAll dependencies are already satisfied.\n"
fi

if [ ! -d "$workdir" ]; then
    echo "Creating the work directory..." $'\n'
    mkdir -p "$workdir" && cd "$_"
else
    # Cleanup, but keeping or deleting cache from previous runs
    cachelist="$ndkfile $ndkdir $mesafile $mesadir"
    cd "$workdir"

    find_conditions=""
    if [[ $preserve_cache -eq 1 ]]; then
        for name in $cachelist; do    
            if [ -e "$name" ]; then #TODO: ADD INTEGRITY CHECK        
                echo "[*] Keeping $name"
                if [ -n "$find_conditions" ]; then
                    find_conditions+=" -or "    
                fi
                find_conditions+=" -name '*$name'"   
            fi    
        done
    fi

    if [ -n "$find_conditions" ]; then
        echo "Cleaning up workdir (while keeping zips)..." $'\n'
        #eval "find . -mindepth 1 \( $find_conditions \) -prune -o -print"
        eval "find . -mindepth 1 \( $find_conditions \) -prune -o -exec rm -rf {} + 2>/dev/null" || true
    else
        echo "Cleaning up workdir..." $'\n'
        rm -rf ./*
    fi
fi

# Download Android NDK
if [ ! -d "$ndkdir" ]; then
    if [ ! -f "$ndkfile" ]; then
        if [[ "$ndksrc" =~ ^https?:// ]]; then
            echo "Downloading Android NDK..." $'\n'
            curl $ndksrc --output "$ndkfile" &> /dev/null
        elif [[ "$ndksrc" == /* || "$ndksrc" == ~/* ]]; then
            echo "Copying Android NDK..." $'\n'
            cp $ndksrc $ndkfile
        elif [[ "$ndksrc" == .* || "$ndksrc" == */* ]]; then
            echo "Copying Android NDK..." $'\n'
            cp "$basedir/$ndksrc" $ndkfile
        else
            echo "Invalid NDK source: $ndksrc" $'\n'
            exit 1
        fi        
    fi
    echo "Extracting Android NDK..." $'\n'
    unzip "$ndkfile" &> /dev/null
fi

# Download Mesa source
if [ ! -d "$mesadir" ]; then
    if [ ! -f "$mesafile" ]; then
        if [[ "$mesasrc" =~ ^https?:// ]]; then
            echo "Downloading Mesa source..." $'\n'
            curl $mesasrc --output "$mesafile" &> /dev/null
        elif [[ "$mesasrc" == /* || "$mesasrc" == ~/* ]]; then
            echo "Copying Mesa source..." $'\n'
            cp $mesasrc $mesafile
        elif [[ "$ndksrc" == .* || "$ndksrc" == */* ]]; then
            echo "Copying Mesa source..." $'\n'
            cp "$basedir/$mesasrc" $mesafile
        else
            echo "Invalid Mesa source: $mesasrc" $'\n'
            exit 1
        fi        
    fi
    echo "Extracting Mesa source..." $'\n'
    unzip "$mesafile" &> /dev/null
fi
cd $mesadir

sleep 2

#clear

# Fallback for mesaver retrieval
if [[ -z "$mesaver" ]]; then
    mesaver=$(cat "VERSION" | grep -oP '^[\d\.]+-.+' | head -n 1)
fi

# Retrieving Vulkan Version
vkxml="src/vulkan/registry/vk.xml"
vkver=""
if [[ -f "$vkxml" ]]; then
    # Extract patch (VK_HEADER_VERSION)
    vkpatch=$(grep -A 1 '<type api="vulkan" category="define"' "$vkxml" | grep -oP '#define <name>VK_HEADER_VERSION</name>\s*\K\d+')
    
    # Extract variant, major, minor from VK_HEADER_VERSION_COMPLETE
    read vkvariant vkmajor vkminor <<< $(grep -A 1 '<type api="vulkan" category="define"' "$vkxml" | grep -oP '#define <name>VK_HEADER_VERSION_COMPLETE</name> <type>VK_MAKE_API_VERSION</type>\(\K[0-9]+,\s*[0-9]+,\s*[0-9]+' | sed 's/,//g')

    if [[ -n "$vkpatch" && -n "$vkmajor" && -n "$vkminor" ]]; then
        vkver="${vkmajor}.${vkminor}.${vkpatch}"
    fi
fi
vkver="${vkver:-$default_vkver}"

echo -n $'\n'
echo "Author: $author" 
echo "Android version: $andver" 
echo "Vulkan version: $vkver" 
echo "Android NDK: $ndkver" 
echo "Mesa version: $mesaver" $'\n'

# Applying patches
srcdir="$(pwd)" #since we're in $mesadir
if [[ -d "$patchesdir" ]]; then
    if ls "$patchesdir"/*.patch 1> /dev/null 2>&1; then        
        # Apply patches here
        echo -n "Applying patches (if any)..." $'\n'
        for patchfile in "$patchesdir"/*.patch; do
            if [[ -f "$patchfile" ]]; then
                topatch=$(sed -n '2p' "$patchfile" | sed -E 's/^\+\+\+ (.*)\t.*$/\1/')
                if patch --dry-run -p0 -d "$srcdir" < "$patchfile" 2>&1 | tee patch_check.log | grep -q "FAILED"; then
                    echo "❌ Patch $(basename "$patchfile") failed — halting."
                    exit 1
                elif grep -q "Reversed (or previously applied) patch detected" patch_check.log; then
                    echo "✅ Patch $(basename "$patchfile") already applied — skipping."
                else
                    hash1=$(cksum $topatch)
                    echo -n "[*] Applying $(basename "$patchfile")... "
                    patch_output="$(patch -p0 -d "$srcdir"  < "$patchfile" 2>&1)" || true
                    hash2=$(cksum $topatch)
                    if [[ "$hash1" != "$hash2" ]]; then
                        echo "Success!" #$'\n'
                    else
                        echo "failed. Output: "
                        echo "$patch_output"
                        exit 1
                    fi
                fi
            fi
        done
        echo "All patches applied successfully." $'\n'
    else
        echo "No patch files found. Skipping patches." $'\n'
    fi    
else
    echo "No patches directory found. Skipping patches." $'\n'
fi

sleep 2

#clear
# Set NDK Clang bin directory
ndk_bin="$workdir/$ndkdir/toolchains/llvm/prebuilt/$building_os-x86_64/bin"

# Set toolchain variables

# Set compiler extensions for Windows/Linux
if [[ "$building_os" == "windows" ]]; then
    cmd_ext=".cmd"
    exe_ext=".exe"
else
    cmd_ext=""
    exe_ext=""
fi

export CC=clang
export CXX=clang++
export AR=llvm-ar
export RANLIB=llvm-ranlib
export STRIP=llvm-strip
export OBJDUMP=llvm-objdump
export OBJCOPY=llvm-objcopy
export LDFLAGS="-fuse-ld=lld"

# Create a temporary directory for fake cc/c++
mkdir -p "$workdir/fake-cc"

# Create symbolic links to NDK-Clang
echo "Creating symbolic links to NDK-Clang..." $'\n'
ln -sf "$ndk_bin/clang$exe_ext" "$workdir/fake-cc/cc"
ln -sf "$ndk_bin/clang++$exe_ext" "$workdir/fake-cc/c++"

# Prepend both fake-cc and NDK bin to PATH
export PATH="$workdir/fake-cc:$ndk_bin:$PATH"

if [[ ! -f "$ndk_bin/clang$exe_ext" ]]; then
    echo "[ERROR] clang.exe not found at $ndk_bin/clang$exe_ext"
    ls -l "$ndk_bin" # List contents for troubleshooting
    exit 1
fi

echo "Creating Meson cross file..." $'\n'
# Use .exe for c/cpp if building_os is windows, else use aarch64-linux-android${sdkver}-clang
if [[ "$building_os" == "windows" ]]; then
    meson_c_bin=$(cygpath -w "$ndk_bin/aarch64-linux-android${sdkver}-clang$cmd_ext")
    meson_cpp_bin=$(cygpath -w "$ndk_bin/aarch64-linux-android${sdkver}-clang++$cmd_ext")
    meson_ld_bin=$(cygpath -w "$ndk_bin/ld.lld$exe_ext")
    meson_ar_bin=$(cygpath -w "$ndk_bin/llvm-ar")
    meson_strip_bin=$(cygpath -w "$ndk_bin/aarch64-linux-android-strip")
elif [[ "$building_os" == "linux" ]]; then
    meson_c_bin="$ndk_bin/aarch64-linux-android${sdkver}-clang"
    meson_cpp_bin="$ndk_bin/aarch64-linux-android${sdkver}-clang++"
    meson_ld_bin="$ndk_bin/ld.lld$exe_ext"
    meson_ar_bin="$ndk_bin/llvm-ar"
    meson_strip_bin="$ndk_bin/aarch64-linux-android-strip"
else
    echo "[ERROR] Unsupported building OS: $building_os"
    exit 1
fi

cat <<EOF >"android-aarch64.txt"
[binaries]
ar = '$meson_ar_bin'
c = ['ccache', '$meson_c_bin']
cpp = ['ccache', '$meson_cpp_bin', '--start-no-unused-arguments', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++', '--end-no-unused-arguments', '-Wno-error=c++11-narrowing']
c_ld = '$meson_ld_bin'
cpp_ld = '$meson_ld_bin'
strip = '$meson_strip_bin'
pkg-config = ['env', 'PKG_CONFIG_LIBDIR=NDKDIR/pkg-config', '/usr/bin/pkg-config']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

cat <<EOF >"native.txt"
[build_machine]
c = ['ccache', 'clang']
cpp = ['ccache', 'clang++']
ar = 'llvm-ar'
strip = 'llvm-strip'
c_ld = 'ld.lld'
cpp_ld = 'ld.lld'
system = '$building_os'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

echo "Generating build files..." $'\n'

if [[ "$building_os" == "windows" ]]; then
    mingw_bin=/mingw64/bin
    if [[ ":$PATH:" != *":$mingw_bin:"* ]]; then
        export PATH="$mingw_bin:$PATH"
    fi
fi

# Set up Meson build configuration
CC=clang CXX=clang++ meson setup build-android-aarch64 \
    --cross-file "$workdir/$mesadir/android-aarch64.txt" \
    --native-file "$workdir/$mesadir/native.txt" \
    -Dbuildtype=release \
    -Dplatforms=android \
    -Dplatform-sdk-version=$sdkver \
    -Dandroid-stub=true \
    -Dgallium-drivers=zink \
    -Dllvm=disabled \
    -Dvulkan-drivers=freedreno \
    -Dfreedreno-kmds=kgsl \
    -Db_lto=true \
    -Degl=enabled \
    -Dgles1=disabled \
    -Dgles2=enabled \
    -Dshared-glapi=enabled \
    -Dstrip=true &> $workdir/meson_log

# Compile build files using Ninja
echo "Compiling build files..." $'\n'
ninja -C build-android-aarch64 &> "$workdir"/ninja_log

echo "Using patchelf to match .so name..." $'\n'
cp "$workdir"/"$mesadir"/build-android-aarch64/src/freedreno/vulkan/libvulkan_freedreno.so "$workdir"
cd "$workdir"

if ! [ -a libvulkan_freedreno.so ]; then
    echo -e "$red Build failed! libvulkan_freedreno.so not found $nocolor" && exit 1
fi

echo "Prepare magisk module structure..." $'\n'
p1="system/vendor/lib64/hw"
mkdir -p "$magiskdir/$p1"
cd "$magiskdir"

echo "Copy necessary files from the work directory..." $'\n'
cp "$workdir"/libvulkan_freedreno.so "$workdir"/vulkan.adreno.so
cp "$workdir"/vulkan.adreno.so "$magiskdir/$p1"

meta="META-INF/com/google/android"
mkdir -p "$meta"

# Create update-binary
cat <<EOF >"$meta/update-binary"
#!/sbin/sh

#################
# Initialization
#################

umask 022

# echo before loading util_functions
ui_print() { echo "\$1"; }

require_new_magisk() {
  ui_print "*******************************"
  ui_print " Please install Magisk v25.2+! "
  ui_print "*******************************"
  exit 1
}

#########################
# Load util_functions.sh
#########################

OUTFD=\$2
ZIPFILE=\$3

mount /data 2>/dev/null

[ -f /data/adb/magisk/util_functions.sh ] || require_new_magisk
. /data/adb/magisk/util_functions.sh
[ \$MAGISK_VER_CODE -lt 25200 ] && require_new_magisk

install_module
exit 0
EOF

cat <<EOF >"$meta/updater-script"
#MAGISK
EOF

cat <<EOF >"uninstall.sh"
find /data/user_de/*/*/*cache/* -iname "*shader*" -exec rm -rf {} +
find /data/data/* -iname "*shader*" -exec rm -rf {} +
find /data/data/* -iname "*graphitecache*" -exec rm -rf {} +
find /data/data/* -iname "*gpucache*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*shader*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*graphitecache*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*gpucache*" -exec rm -rf {} +
EOF

cat <<EOF >"module.prop"
id=turnip-mesa
name=Freedreno Turnip Vulkan Driver
version=$mesaver
versionCode=$(date +%Y%m%d)
author=$author
description=Turnip is an open-source vulkan driver for devices with Adreno 6xx-7xx GPUs.
updateJson=https://raw.githubusercontent.com/$default_author/Mesa-Turnip-Builder/refs/heads/stable/update.json
EOF

cat <<EOF >"customize.sh"
MODVER=\`grep_prop version \$MODPATH/module.prop\`
MODVERCODE=\`grep_prop versionCode \$MODPATH/module.prop\`

ui_print ""
ui_print "Version=\$MODVER "
ui_print "MagiskVersion=\$MAGISK_VER"
ui_print ""
ui_print "Freedreno Turnip Vulkan Driver - $author"
ui_print "Adreno Driver Support Group - Telegram"
ui_print ""
sleep 1.25

ui_print ""
ui_print "Checking Device info ..."
sleep 1.25

[ \$(getprop ro.system.build.version.sdk) -lt $sdkver ] && echo "Android $andver is required! Aborting ..." && abort
echo ""
echo "Everything looks fine .... proceeding"
ui_print ""
ui_print "Installing Driver Please Wait ..."
ui_print ""

sleep 1.25
set_perm_recursive \$MODPATH/system 0 0 755 u:object_r:system_file:s0
set_perm_recursive \$MODPATH/system/vendor 0 2000 755 u:object_r:vendor_file:s0
set_perm \$MODPATH/system/vendor/lib64/hw/vulkan.adreno.so 0 0 0644 u:object_r:same_process_hal_file:s0

# EGL/GLES2 permissions (only if present)
[ -f "$MODPATH/system/vendor/lib64/egl/libEGL_adreno.so" ] && \
    set_perm "$MODPATH/system/vendor/lib64/egl/libEGL_adreno.so" 0 0 0644 u:object_r:same_process_hal_file:s0

[ -f "$MODPATH/system/vendor/lib64/egl/libGLESv2_adreno.so" ] && \
    set_perm "$MODPATH/system/vendor/lib64/egl/libGLESv2_adreno.so" 0 0 0644 u:object_r:same_process_hal_file:s0

ui_print ""
ui_print " Cleaning GPU Cache ... Please wait!"
find /data/user_de/*/*/*cache/* -iname "*shader*" -exec rm -rf {} +
find /data/data/* -iname "*shader*" -exec rm -rf {} +
find /data/data/* -iname "*graphitecache*" -exec rm -rf {} +
find /data/data/* -iname "*gpucache*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*shader*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*graphitecache*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*gpucache*" -exec rm -rf {} +

ui_print ""
ui_print "- Gpu Cache Cleared ..."
ui_print ""

ui_print "Driver installed Successfully"
sleep 1.25

ui_print ""
ui_print "All done, Please REBOOT device"
ui_print ""
ui_print "BY: @$author"
ui_print ""
EOF

echo "Creating Vulkan ICD JSON..." $'\n'
mkdir -p "$magiskdir/system/vendor/etc/vulkan/icd.d"
cat <<EOF > "$magiskdir/system/vendor/etc/vulkan/icd.d/mesa_turnip.json"
{
  "file_format_version": "1.0.0",
  "ICD": {
    "library_path": "/vendor/lib64/hw/vulkan.adreno.so",
    "api_version": "$vkver"
  }
}
EOF

echo "Creating service.sh for Magisk module..." $'\n'
cat <<'EOF' > "$magiskdir/service.sh"
#!/system/bin/sh
MODDIR=${0%/*}
export MESA_GLTHREAD=true
# Bind Vulkan
if [ -f "$MODDIR/system/vendor/lib64/hw/vulkan.adreno.so" ]; then
    mount --bind "$MODDIR/system/vendor/lib64/hw/vulkan.adreno.so" /vendor/lib64/hw/vulkan.adreno.so
fi

# Bind GLESv2
if [ -f "$MODDIR/system/vendor/lib64/egl/libGLESv2_adreno.so" ]; then
    mount --bind "$MODDIR/system/vendor/lib64/egl/libGLESv2_adreno.so" /vendor/lib64/egl/libGLESv2_adreno.so
fi

# Bind EGL
if [ -f "$MODDIR/system/vendor/lib64/egl/libEGL_adreno.so" ]; then
    mount --bind "$MODDIR/system/vendor/lib64/egl/libEGL_adreno.so" /vendor/lib64/egl/libEGL_adreno.so
fi

# Optional: force override system properties (requires resetprop)
command -v resetprop >/dev/null && resetprop ro.hardware.vulkan turnip
command -v resetprop >/dev/null && resetprop ro.gfx.driver.0 org.freedesktop.mesa
EOF
chmod +x "$magiskdir/service.sh"

echo "Packing driver files into Magisk/KSU module ..." $'\n'
mkdir -p $workdir/magisk
zip -r $workdir/magisk/Turnip-$mesaver-MAGISK-KSU.zip * &> /dev/null

if ! [ -a $workdir/magisk/Turnip-$mesaver-MAGISK-KSU.zip ]; then
    echo -e "$red-Packing failed!$nocolor" && exit 1
fi

#clear

echo " Its time to create Turnip build for EMULATOR"  $'\n'

sleep 2

cd ..

mv vulkan.adreno.so vulkan.turnip.so

# Create meta.json file for turnip emulator
cat <<EOF > "$META_FILE"
{
  "schemaVersion": 1,
  "name": "Freedreno Turnip Driver $mesaver",
  "description": "Compiled using Android NDK $ndkver",
  "author": "$author",
  "packageVersion": "3",
  "vendor": "Mesa3D",
  "driverVersion": "Vulkan $vkver",
  "minApi": $sdkver,
  "libraryName": "vulkan.turnip.so"
}
EOF

# Zip the turnip .so file and meta.json file
mkdir -p "emulator"
if ! zip "emulator/Turnip-$mesaver-EMULATOR.zip" "$DRIVER_FILE" "$META_FILE" > /dev/null 2>&1; then
    echo -e "$red Error: Zipping driver files failed. $nocolor"
    exit 1
fi

#clear

echo -e "$green-All done, you can take your drivers from here;$nocolor" $'\n'
echo $workdir/magisk/Turnip-$mesaver-MAGISK-KSU.zip $'\n'
echo $workdir/emulator/Turnip-$mesaver-EMULATOR.zip $'\n'
echo -e "$green Build Finished :). $nocolor" $'\n'

# Cleanup 
rm "$DRIVER_FILE" "$META_FILE"

# Clean up fake-cc directory and symbolic links on exit
rm -rf "$workdir/fake-cc/cc"
rm -rf "$workdir/fake-cc/c++"
rm -rf "$workdir/fake-cc"