#!/bin/bash -e

# Required variables
sdkver="33"
default_vkver="1.4.311+"
default_ndk="https://dl.google.com/android/repository/android-ndk-r28b-linux.zip"
default_mesa="https://gitlab.freedesktop.org/mesa/mesa/-/archive/main/mesa-main.zip"
default_author="v3kt0r-87"

# Required packages for building the turnip driver
deps="meson ninja-build patchelf unzip curl flex bison zip python3 python3-pip python3-mako python-is-python3 glslang-tools"

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
ndkdir="${ndkdir%-linux}"
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

# Check for required dependencies 
aptlist=$(apt list --installed 2>/dev/null)
for deps_chk in $deps; do
    sleep 0.025
    
    if echo "$aptlist" | grep -q "^$deps_chk" >/dev/null 2>&1; then
        echo -e "$green - $deps_chk found $nocolor"
    else
        echo -e "$red - $deps_chk not found $nocolor"
        deps_missing=1
    fi
done

# Install missing dependencies automatically
if [ "$deps_missing" == "1" ]; then
    echo "Missing dependencies, installing them now..." $'\n'
    sudo apt install -y $deps &> /dev/null    
else
    echo ""
fi

#clear

# Cleanup, but keeping or deleting cache from previous runs
cachelist="$ndkfile $ndkdir $mesafile"
if [[ ! -d "$patchesdir" || ! $(ls "$patchesdir"/*.patch 2> /dev/null) ]]; then
    cachelist="$cachelist $mesadir"
fi

if [ ! -d "$workdir" ]; then
    echo "Creating the work directory..." $'\n'
    mkdir -p "$workdir" && cd "$_"
else
    cd "$workdir"

    find_conditions=""
    if [[ $preserve_cache -eq 1 ]]; then
        for name in $cachelist; do    
            if [ -e "$name" ]; then #TODO: ADD INTEGRITY CHECK        
                echo "[*] Keeping $name" $'\n'
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

# Applying patches
srcdir="$(pwd)" #since we're in $mesadir
if [[ -d "$patchesdir" ]]; then
    if ls "$patchesdir"/*.patch 1> /dev/null 2>&1; then        
        # Apply patches here

        for patch in "$patchesdir"/*.patch; do       
            if [[ -f "$patch" ]]; then
                patchfile=$(sed -n '2p' "$patch" | sed -E 's/^\+\+\+ (.*)\t.*$/\1/')

                hash1=$(cksum $patchfile)
                
                echo -n "Applying $(basename "$patch")... "                
                patch_output="$(patch -p0 -d "$srcdir"  < "$patch" 2>&1)" || true                
                
                hash2=$(cksum $patchfile)
                
                #if echo "$patch_output" | tail -n 1 | grep -q "patching file $patchfile"; then
                if [[ "$hash1" != "$hash2" ]]; then
                    echo "Success!" $'\n'
                else
                    echo "failed. Output: "
                    echo "$patch_output"
                    exit 1
                fi
            fi
        done
    else
        echo "No patch files found. Skipping patches." $'\n'
    fi    
else
    echo "No patches directory found. Skipping patches." $'\n'
fi

sleep 2

echo "Author: $author" 
echo "Android version: $andver" 
echo "Vulkan version: $vkver" 
echo "Android NDK: $ndkver" 
echo "Mesa version: $mesaver" $'\n'

#clear
# Set NDK Clang bin directory
ndk_bin="$workdir/$ndkdir/toolchains/llvm/prebuilt/linux-x86_64/bin"

# Set toolchain variables
export CC=clang
export CXX=clang++
export AR=llvm-ar
export RANLIB=llvm-ranlib
export STRIP=llvm-strip
export OBJDUMP=llvm-objdump
export OBJCOPY=llvm-objcopy
export LDFLAGS="-fuse-ld=lld"

# Create a temporary directory for fake cc/c++
mkdir -p /tmp/fake-cc

# Create symbolic links to NDK-Clang
ln -sf "$ndk_bin/clang" /tmp/fake-cc/cc
ln -sf "$ndk_bin/clang++" /tmp/fake-cc/c++

# Prepend both fake-cc and NDK bin to PATH
export PATH="/tmp/fake-cc:$ndk_bin:$PATH"

echo "Creating Meson cross file..." $'\n'
cat <<EOF >"android-aarch64.txt"
[binaries]
ar = '$ndk_bin/llvm-ar'
c = ['ccache', '$ndk_bin/aarch64-linux-android$sdkver-clang']
cpp = ['ccache', '$ndk_bin/aarch64-linux-android$sdkver-clang++', '--start-no-unused-arguments', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++', '--end-no-unused-arguments', '-Wno-error=c++11-narrowing']
c_ld = '$ndk_bin/ld.lld'
cpp_ld = '$ndk_bin/ld.lld'
strip = '$ndk_bin/aarch64-linux-android-strip'
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
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

echo "Generating build files..." $'\n'
CC=clang CXX=clang++ meson setup build-android-aarch64 \
    --cross-file "$workdir/$mesadir/android-aarch64.txt" \
    --native-file "$workdir/$mesadir/native.txt" \
    -Dbuildtype=release \
    -Dplatforms=android \
    -Dplatform-sdk-version=$sdkver \
    -Dandroid-stub=true \
    -Dgallium-drivers= \
    -Dvulkan-drivers=freedreno \
    -Dfreedreno-kmds=kgsl \
    -Db_lto=true \
    -Degl=disabled \
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

# Create updater-script
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

echo "Packing driver files into Magisk/KSU module ..." $'\n'
mkdir -p $workdir/magisk
zip -r $workdir/magisk/Turnip-$mesaver-MAGISK-KSU.zip * &> /dev/null

if ! [ -a $workdir/magisk/Turnip-$mesaver-MAGISK-KSU.zip ]; then
    echo -e "$red-Packing failed!$nocolor" && exit 1
else
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
    rm -rf /tmp/fake-cc/cc
    rm -rf /tmp/fake-cc/c++
    rm -rf /tmp/fake-cc
fi