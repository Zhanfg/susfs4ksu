/* Compile this contract for both host and Android target architectures. */
#include <stddef.h>
#include <linux/susfs_abi.h>

#define ABI_ASSERT(expr) _Static_assert((expr), #expr)

ABI_ASSERT(SUSFS_MAGIC == 0xFAFAFAFA);
ABI_ASSERT(SUSFS_INSTALL_MAGIC1 == 0xDEADBEEF);
ABI_ASSERT(CMD_SUSFS_SHOW_VERSION == 0x555e1);
ABI_ASSERT(CMD_SUSFS_SHOW_ENABLED_FEATURES == 0x555e2);
ABI_ASSERT(CMD_SUSFS_SHOW_VARIANT == 0x555e3);
ABI_ASSERT(CMD_SUSFS_QUERY_CAPABILITIES == 0x555e5);
ABI_ASSERT(sizeof(struct st_susfs_version) == 20);
ABI_ASSERT(offsetof(struct st_susfs_version, err) == 16);
ABI_ASSERT(sizeof(struct st_susfs_variant) == 20);
ABI_ASSERT(offsetof(struct st_susfs_variant, err) == 16);
ABI_ASSERT(sizeof(struct st_susfs_enabled_features) == 8196);
ABI_ASSERT(offsetof(struct st_susfs_enabled_features, err) == 8192);
ABI_ASSERT(sizeof(struct st_susfs_capabilities) == 64);
ABI_ASSERT(offsetof(struct st_susfs_capabilities, compiled_features) == 8);
ABI_ASSERT(offsetof(struct st_susfs_capabilities, runtime_features) == 16);
ABI_ASSERT(offsetof(struct st_susfs_capabilities, susfs_version) == 24);
ABI_ASSERT(offsetof(struct st_susfs_capabilities, susfs_variant) == 40);
ABI_ASSERT(offsetof(struct st_susfs_capabilities, err) == 56);
ABI_ASSERT(offsetof(struct st_susfs_capabilities, reserved) == 60);

int main(void)
{
	return 0;
}
