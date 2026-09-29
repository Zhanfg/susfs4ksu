#!/system/bin/sh
MODDIR=${0%/*}

[ -x "$MODDIR/controller.sh" ] || exit 0
"$MODDIR/controller.sh" service
exit 0
