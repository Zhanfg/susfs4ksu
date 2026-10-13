#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

MODULES_STAGE="$tmp/source"
WORKSPACE="$tmp/workspace"
original="$MODULES_STAGE/kernel_platform/msm-kernel"
vendor="$MODULES_STAGE/vendor/oplus/kernel/storage"
kernel="$WORKSPACE/msm-kernel"

mkdir -p "$original/drivers/soc/oplus" "$vendor/storage_feature_in_module/common" \
  "$vendor/common/io_metrics" "$kernel/drivers/soc/oplus"
ln -s ../../../../../vendor/oplus/kernel/storage/storage_feature_in_module \
  "$original/drivers/soc/oplus/storage"
ln -s ../../common/io_metrics \
  "$vendor/storage_feature_in_module/common/io_metrics"
printf 'config OPLUS_FEATURE_STORAGE_IO_METRICS_QCOM\n' > \
  "$vendor/common/io_metrics/Kconfig"
ln -s ../../../../../vendor/oplus/kernel/storage/storage_feature_in_module \
  "$kernel/drivers/soc/oplus/storage"

# Execute the exact workspace helper with synthetic pinned vendor inputs.
func="$(sed -n '/^materialize_external_vendor_links() {/,/^}$/p' \
  "$root/tools/oneplus13-workspace.sh")"
[ -n "$func" ]
eval "$func"
materialize_external_vendor_links

kconfig="$kernel/drivers/soc/oplus/storage/common/io_metrics/Kconfig"
test -f "$kconfig"
grep -q 'OPLUS_FEATURE_STORAGE_IO_METRICS_QCOM' "$kconfig"
test -d "$kernel/drivers/soc/oplus/storage"
test ! -L "$kernel/drivers/soc/oplus/storage"
test ! -L "$kernel/drivers/soc/oplus/storage/common/io_metrics"

# A subsequent execution should be idempotent and preserve installed sources.
materialize_external_vendor_links
test -f "$kconfig"
echo "PASS: nested OnePlus vendor symlinks resolved; repeated closure is idempotent"
