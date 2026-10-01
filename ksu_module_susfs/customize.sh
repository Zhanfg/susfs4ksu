unzip -q -o "$ZIPFILE" -d "$TMPDIR/susfs" || abort "Failed to extract SUSFS helper."

if [ "$ARCH" = "arm64" ]; then
	mkdir -p "$MODPATH/bin" || abort "Failed to create module binary directory."
	# ReSukiSU owns a ksu_susfs -> ksud hard link. Keep our fallback private,
	# and replace its inode atomically even if an old private path was linked.
	tool_tmp="$MODPATH/bin/.ksu_susfs.$$.tmp"
	cp "$TMPDIR/susfs/tools/ksu_susfs_arm64" "$tool_tmp" || abort "Failed to stage SUSFS helper."
	chmod 755 "$tool_tmp" || abort "Failed to set helper permissions."
	mv -f "$tool_tmp" "$MODPATH/bin/ksu_susfs" || abort "Failed to install SUSFS helper."
else
	ui_print "Only arm64 is currently supported by the bundled controller binary."
	exit 1
fi

chmod 755 "$MODPATH/controller.sh"
chmod 755 "$MODPATH/post-fs-data.sh" "$MODPATH/service.sh" "$MODPATH/boot-completed.sh" "$MODPATH/uninstall.sh"
chmod 644 "$MODPATH/config/default.conf" 2>/dev/null || true

rm -rf "$MODPATH/tools"
rm -f "$MODPATH/customize.sh" "$MODPATH/README.md"

ui_print "SUSFS control backend will be selected automatically at runtime."
ui_print "Default profile is inert; edit config/default.conf to enable rules."
