#!/system/bin/sh
MODDIR="/data/adb/modules/agent_mobile_use"
if [ ! -d "$MODDIR" ]; then
    MODDIR="$(cd "$(dirname "$0")/.." && pwd)"
fi

DEX_PATH="$MODDIR/bin/agent_vd.dex"
if [ ! -f "$DEX_PATH" ]; then
    DEX_PATH="/data/local/tmp/agent_vd.dex"
fi

# Auto detect physical screen metrics
WIDTH=1080
HEIGHT=2400
DPI=420

PHYS_SIZE=$(/system/bin/wm size 2>/dev/null | grep "Physical size:" | awk '{print $3}')
if [ -n "$PHYS_SIZE" ]; then
    W=$(echo "$PHYS_SIZE" | cut -d'x' -f1)
    H=$(echo "$PHYS_SIZE" | cut -d'x' -f2)
    if [ -n "$W" ] && [ -n "$H" ]; then
        WIDTH="$W"
        HEIGHT="$H"
    fi
fi

PHYS_DPI=$(/system/bin/wm density 2>/dev/null | grep "Physical density:" | awk '{print $3}')
if [ -n "$PHYS_DPI" ]; then
    DPI="$PHYS_DPI"
fi

# Allow override from CLI args if provided
if [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ]; then
    WIDTH="$1"
    HEIGHT="$2"
    DPI="$3"
fi

echo "[run_daemon] Auto detected screen metrics: ${WIDTH}x${HEIGHT} @ ${DPI} DPI"

export ANDROID_ROOT=/system
export ANDROID_DATA=/data
export ANDROID_ART_ROOT=/apex/com.android.art
export ANDROID_I18N_ROOT=/apex/com.android.i18n
export ANDROID_TZDATA_ROOT=/apex/com.android.tzdata

# BOOTCLASSPATH：动态取**当前系统**的值。
#
# 为什么必须动态：旧版这里硬编码了一台 OPPO/一加 ROM 的完整 classpath（含
# oplus-framework.jar / qcom.fmradio.jar 等私有 jar）。在其它 ROM 上设备真实的
# BOOTCLASSPATH 与硬编码值对不上，app_process 起守护进程时直接
# NoClassDefFoundError（"Class not found using the boot class loader"），
# 副屏永远起不来 —— 实测 Android 15 模拟器：真实 BCP 44 条，硬编码里的
# oplus 条目命中 0 条。
#
# app_process 需要的就是本系统的 boot classpath。优先用 vd_server 传进来的
# 环境变量（它由 root 常驻拉起、环境干净）；拿不到再读 init(PID 1) 的环境块；
# 都不行才退到最小核心集兜底。
REAL_BCP=""
if [ -n "$BOOTCLASSPATH" ]; then
    REAL_BCP="$BOOTCLASSPATH"
else
    REAL_BCP=$(cat /proc/1/environ 2>/dev/null | tr '\0' '\n' | grep '^BOOTCLASSPATH=' | head -n 1 | cut -d= -f2-)
fi
if [ -z "$REAL_BCP" ]; then
    REAL_BCP="/apex/com.android.art/javalib/core-oj.jar:/apex/com.android.art/javalib/core-libart.jar:/apex/com.android.art/javalib/okhttp.jar:/apex/com.android.art/javalib/bouncycastle.jar:/apex/com.android.art/javalib/apache-xml.jar:/system/framework/framework.jar:/system/framework/ext.jar"
    echo "[run_daemon] WARN: could not read system BOOTCLASSPATH, using minimal fallback"
fi
echo "[run_daemon] BOOTCLASSPATH entries: $(echo "$REAL_BCP" | tr ':' '\n' | wc -l)"
export BOOTCLASSPATH="$REAL_BCP"

export DEX2OATBOOTCLASSPATH=/apex/com.android.art/javalib/core-oj.jar:/apex/com.android.art/javalib/core-libart.jar:/apex/com.android.art/javalib/okhttp.jar:/apex/com.android.art/javalib/bouncycastle.jar:/apex/com.android.art/javalib/apache-xml.jar

export CLASSPATH="$DEX_PATH"
exec /system/bin/app_process /system/bin com.agent.DaemonMain "$WIDTH" "$HEIGHT" "$DPI"
