DEST_BIN_DIR=/data/adb/ksu/bin

if [ ! -d "$DEST_BIN_DIR" ]; then
	ui_print "'$DEST_BIN_DIR' not found, installation aborted."
	rm -rf "$MODPATH"
	exit 1
fi

unzip "$ZIPFILE" -d "$TMPDIR/susfs"

if [ "$ARCH" = "arm64" ]; then
	cp "$TMPDIR/susfs/tools/ksu_susfs_arm64" "$DEST_BIN_DIR/ksu_susfs"
else
	ui_print "Only arm64 is currently supported by the bundled controller binary."
	exit 1
fi

chmod 755 "$DEST_BIN_DIR/ksu_susfs"
chmod 755 "$MODPATH/controller.sh"
chmod 755 "$MODPATH/post-fs-data.sh" "$MODPATH/service.sh" "$MODPATH/boot-completed.sh" "$MODPATH/uninstall.sh"
chmod 644 "$MODPATH/config/default.conf" 2>/dev/null || true

rm -rf "$MODPATH/tools"
rm -f "$MODPATH/customize.sh" "$MODPATH/README.md"

ui_print "SUSFS control backend will be selected automatically at runtime."
ui_print "Default profile is inert; edit config/default.conf to enable rules."
