#ifndef KSU_SUSFS_DEF_H
#define KSU_SUSFS_DEF_H

#include <linux/bits.h>
#include <linux/string.h>

/********/
/* ENUM */
/********/
#include <uapi/linux/susfs_abi.h>

#define TRY_UMOUNT_DEFAULT 0 /* used by susfs_try_umount() */
#define TRY_UMOUNT_DETACH 1 /* used by susfs_try_umount() */

#define DEFAULT_KSU_MNT_ID 2000000000 /* used for mounts created or single cloned by ksu process */
#define DEFAULT_KSU_MNT_GROUP_ID 200000 /* used by mount->mnt_group_id */
#define DEFAULT_KSU_MNT_MINOR_DEV (1 << 12) /* should be way enough, here minor(dev) begins with 4097 */

#ifndef FUSE_SUPER_MAGIC
#define FUSE_SUPER_MAGIC 0x65735546
#endif

/*
 * mnt->mnt.mnt_flags => An 'int' primitive storing flag 'VFSMOUNT_MNT_FLAGS_'
 * task_struct->thread_info.flags => storing flag 'TIF_' which is an unsigned long primitive :D
 * inode->i_mapping->flags => An 'unsigned long' primitive storing flag 'AS_FLAGS_', bit 1 to 31 is not usable since 6.12
 * nd->state => storing flag 'ND_STATE_'
 * nd->flags => storing flag 'ND_FLAGS_'
 * statx request_mark => storing flag 'STATX_'
 */

#define VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT 0x80000000 /* used for mounts that are unshared by ksu process */

#define TIF_PROC_UMOUNTED 33
#define TIF_PROC_NO_SU 34
#define TIF_PROC_UMOUNTED_FOR_ZYGOTE_NEXT 35

#define AS_FLAGS_SUS_PATH 33
#define AS_FLAGS_SUS_MOUNT 34
#define AS_FLAGS_SUS_KSTAT 35
#define AS_FLAGS_OPEN_REDIRECT 36
#define AS_FLAGS_SUS_MAP 39

#define ND_STATE_LOOKUP_LAST 32
#define ND_STATE_OPEN_LAST 64
#define ND_FLAGS_LOOKUP_LAST 0x2000000

#define STATX_SUS_KSTAT 0x10000000U
#define STATX_SUS_KSTAT_FUSE 0x20000000U

static inline bool susfs_starts_with(const char *str, const char *prefix) {
    while (*prefix) {
        if (*str++ != *prefix++)
            return false;
    }
    return true;
}

static inline bool susfs_ends_with(const char *str, const char *suffix) {
	size_t str_len, suffix_len;

	if (!str || !suffix)
		return false;

	str_len = strlen(str);
	suffix_len = strlen(suffix);

	if (suffix_len > str_len)
		return false;

	return !strcmp(str + str_len - suffix_len, suffix);
}

static inline bool susfs_is_current_app_uid(void) {
	return ((current_uid().val % 100000) >= 10000);
}

static inline bool susfs_is_current_proc_umounted(void) {
	return (likely(test_thread_flag(TIF_PROC_UMOUNTED)));
}

static inline void susfs_set_current_proc_umounted(void) {
	set_thread_flag(TIF_PROC_UMOUNTED);
}

static inline void susfs_clear_current_proc_umounted(void) {
	clear_thread_flag(TIF_PROC_UMOUNTED);
}

static inline bool susfs_is_current_proc_umounted_for_zygote_next(void) {
	return (likely(test_thread_flag(TIF_PROC_UMOUNTED_FOR_ZYGOTE_NEXT)));
}

static inline void susfs_set_current_proc_umounted_for_zygote_next(void) {
	set_thread_flag(TIF_PROC_UMOUNTED_FOR_ZYGOTE_NEXT);
}

static inline void susfs_clear_current_proc_umounted_for_zygote_next(void) {
	clear_thread_flag(TIF_PROC_UMOUNTED_FOR_ZYGOTE_NEXT);
}

static inline bool susfs_is_current_proc_umounted_app(void) {
	return (likely(test_thread_flag(TIF_PROC_UMOUNTED)) &&
			current_uid().val >= 10000);
}

static inline bool susfs_is_current_proc_no_su(void) {
	return (likely(test_thread_flag(TIF_PROC_NO_SU)));
}

static inline void susfs_set_current_proc_no_su(void) {
	set_thread_flag(TIF_PROC_NO_SU);
}

static inline void susfs_clear_current_proc_no_su(void) {
	clear_thread_flag(TIF_PROC_NO_SU);
}

#define SUSFS_IS_INODE_SUS_MAP(inode) \
		inode && inode->i_mapping && \
		unlikely(test_bit(AS_FLAGS_SUS_MAP, &inode->i_mapping->flags)) && \
		susfs_is_current_proc_umounted_app()

#define SUSFS_IS_INODE_OPEN_REDIRECT_WITHOUT_UID_CHECK(inode) \
		inode && inode->i_mapping && \
		unlikely(test_bit(AS_FLAGS_OPEN_REDIRECT, &inode->i_mapping->flags))

#define SUSFS_IS_INODE_OPEN_REDIRECT(inode) \
		inode && inode->i_mapping && \
		unlikely(test_bit(AS_FLAGS_OPEN_REDIRECT, &inode->i_mapping->flags)) && \
		susfs_is_current_proc_umounted_app()
#endif // #ifndef KSU_SUSFS_DEF_H
