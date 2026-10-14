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
# Official OPlus trees also contain dangling relative links in copied vendor
# subtrees; closure must not invent a replacement target for these.
mkdir -p "$vendor/storage_feature_in_module/soc/oplus/dfr"
ln -s ../../include/ \
  "$vendor/storage_feature_in_module/soc/oplus/dfr/include"
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
test -L "$kernel/drivers/soc/oplus/storage/soc/oplus/dfr/include"

# A subsequent execution should be idempotent and preserve installed sources.
materialize_external_vendor_links
test -f "$kconfig"

# Reproduce the real OnePlus OSS build fault: the copied storage tree still
# contains its original nested relative link, which is dangling after
# relocation. The pinned-source fallback must materialize a real directory.
rm -rf "$kernel/drivers/soc/oplus/storage/common/io_metrics"
ln -s ../../common/io_metrics \
  "$kernel/drivers/soc/oplus/storage/common/io_metrics"
test ! -f "$kconfig"
fix="$(sed -n '/^materialize_official_storage_metrics() {/,/^}$/p' \
  "$root/tools/oneplus13-workspace.sh")"
[ -n "$fix" ]
eval "$fix"
materialize_official_storage_metrics
test -f "$kconfig"
test ! -L "$kernel/drivers/soc/oplus/storage/common/io_metrics"
grep -q 'OPLUS_FEATURE_STORAGE_IO_METRICS_QCOM' "$kconfig"
materialize_official_storage_metrics
test -f "$kconfig"
echo "PASS: nested OnePlus vendor symlinks and pinned Kconfig recovery verified"
