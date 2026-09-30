#!/system/bin/sh
MODDIR=${0%/*}

[ -x "$MODDIR/controller.sh" ] || exit 0
"$MODDIR/controller.sh" post-fs-data
exit 0
