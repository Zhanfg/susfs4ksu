/* Execute the production registration function with host kernel-API shims.
 * Hashes deliberately collide; this checks equality, allocation and writer
 * locking, not kernel SRCU memory ordering or actual VFS path resolution.
 */
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <linux/susfs_abi.h>

typedef uint32_t u32;
#define __user
#define GFP_KERNEL 0
#define SUSFS_LOGI(...) do {} while (0)
#define SUSFS_LOGE(...) do {} while (0)

struct list_head { struct list_head *next, *prev; };
struct hlist_node { struct hlist_node *next; struct hlist_node **pprev; };
struct hlist_head { struct hlist_node *first; };
struct st_susfs_sus_path { char target_pathname[SUSFS_MAX_LEN_PATHNAME]; int err; };
struct st_susfs_sus_path_list {
	struct list_head list;
	struct hlist_node hash_node;
	char target_pathname[SUSFS_MAX_LEN_PATHNAME];
};
static struct list_head LH_SUS_PATH_LOOP = {&LH_SUS_PATH_LOOP, &LH_SUS_PATH_LOOP};
static struct hlist_head SUS_PATH_LOOP_HLIST[64];
static pthread_mutex_t susfs_mutex_lock_sus_path = PTHREAD_MUTEX_INITIALIZER;
static bool susfs_has_sus_path_loop, fail_allocation, fail_copy;
static unsigned int allocations, activations;

#define INIT_LIST_HEAD(head) do { (head)->next = (head); (head)->prev = (head); } while (0)
#define mutex_lock(lock) assert(pthread_mutex_lock(lock) == 0)
#define mutex_unlock(lock) assert(pthread_mutex_unlock(lock) == 0)
#define static_branch_unlikely(key) (*(key))
#define static_branch_enable(key) do { *(key) = true; activations++; } while (0)
#define container_of(ptr, type, member) ((type *)((char *)(ptr) - offsetof(type, member)))
#define hash_bucket(table, key) ((key) & (sizeof(table) / sizeof((table)[0]) - 1))
#define hash_for_each_possible(table, entry, member, key) \
	for (struct hlist_node *node = (table)[hash_bucket(table, key)].first; \
	     node && ((entry) = container_of(node, struct st_susfs_sus_path_list, member), 1); \
	     node = node->next)

static void list_add_tail_rcu(struct list_head *node, struct list_head *head)
{
	node->prev = head->prev; node->next = head;
	head->prev->next = node; head->prev = node;
}

static void add_hash(struct hlist_head *head, struct hlist_node *node)
{
	node->next = head->first; node->pprev = &head->first;
	if (node->next) node->next->pprev = &node->next;
	head->first = node;
}
#define hash_add(table, node, key) add_hash(&(table)[hash_bucket(table, key)], node)

static u32 full_name_hash(const void *salt, const char *name, size_t length)
{
	(void)salt; (void)name; (void)length;
	return 0; /* Exercise full hash collisions rather than trusting the key. */
}

static void *kzalloc(size_t size, int flags)
{
	(void)flags;
	if (fail_allocation) return NULL;
	allocations++;
	return calloc(1, size);
}

static int copy_from_user(void *dst, const void *src, size_t size)
{
	if (fail_copy) return 1;
	memcpy(dst, src, size); return 0;
}
static int copy_to_user(void *dst, const void *src, size_t size)
{
	memcpy(dst, src, size); return 0;
}

#include "sus-path-loop-under-test.h"

static int submit(struct st_susfs_sus_path *request)
{
	void *arg = request;
	request->err = SUSFS_ERR_CMD_NOT_SUPPORTED;
	susfs_add_sus_path_loop(&arg);
	return request->err;
}

static void *writer(void *data)
{
	uintptr_t seed = (uintptr_t)data;
	for (unsigned int i = 0; i < 128; i++) {
		struct st_susfs_sus_path request = {0};
		snprintf(request.target_pathname, sizeof(request.target_pathname), "/data/test/%u", (i + (unsigned int)seed) % 8);
		assert(submit(&request) == 0);
	}
	return NULL;
}

int main(void)
{
	struct st_susfs_sus_path request = {0};
	pthread_t writers[8];
	unsigned int count = 0;

	assert(submit(&request) == -EINVAL);
	memset(request.target_pathname, 'x', sizeof(request.target_pathname));
	assert(submit(&request) == -ENAMETOOLONG);
	assert(allocations == 0 && activations == 0);
	request.target_pathname[255] = '\0';
	assert(submit(&request) == 0);
	struct st_susfs_sus_path_list *first = container_of(LH_SUS_PATH_LOOP.next, struct st_susfs_sus_path_list, list);
	assert(!memcmp(first->target_pathname, request.target_pathname, 256));
	fail_allocation = true;
	assert(submit(&request) == 0); /* Duplicate success needs no allocation. */
	request.target_pathname[254] = '\0';
	assert(submit(&request) == -ENOMEM); /* Distinct 254/255-byte names. */
	fail_allocation = false;
	assert(submit(&request) == 0);
	fail_copy = true;
	assert(submit(&request) == -EFAULT);
	fail_copy = false;
	assert(allocations == 2 && activations == 1);

	for (uintptr_t i = 0; i < 8; i++) assert(!pthread_create(&writers[i], NULL, writer, (void *)i));
	for (unsigned int i = 0; i < 8; i++) assert(!pthread_join(writers[i], NULL));
	assert(allocations == 10 && activations == 1);
	for (struct list_head *node = LH_SUS_PATH_LOOP.next; node != &LH_SUS_PATH_LOOP; node = node->next) count++;
	assert(count == 10);
	count = 0;
	for (struct hlist_node *node = SUS_PATH_LOOP_HLIST[0].first; node; node = node->next) count++;
	assert(count == 10);
	while (LH_SUS_PATH_LOOP.next != &LH_SUS_PATH_LOOP) {
		struct list_head *node = LH_SUS_PATH_LOOP.next;
		LH_SUS_PATH_LOOP.next = node->next;
		free(container_of(node, struct st_susfs_sus_path_list, list));
	}
	puts("1024 concurrent registrations -> 8 unique rules; collisions, boundaries and failures passed");
	return 0;
}
