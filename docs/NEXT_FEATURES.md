# SUSFS Next feature architecture

SUSFS Next should grow through reusable primitives rather than one-off hiding commands.

## 1. Control plane

### Versioned capability ABI
Status: **implemented on `modernize/runtime-api`**

A fixed 64-byte v1 query replaces the legacy 8 KiB feature string for modern clients while keeping the old interface as fallback.

### Declarative configuration
Planned:

- validate a complete configuration before applying it
- apply related changes as one transaction where practical
- expose schema / ABI version
- export current configuration for diagnostics
- reject duplicate or contradictory entries before touching kernel state

This should replace long boot scripts made of many independent CLI invocations.

### Lifecycle operations
Planned:

- add
- update
- remove
- list/count
- clear feature-local state

Today several subsystems are effectively add-only or require indirect replacement semantics.

## 2. Data plane

### Event-driven path refresh
Replace process-spawn-coupled full rescans with:

- dirty generations
- event/invalidation marking
- coalesced work
- bounded fallback verification

No permanent polling thread.

### Adaptive lookup containers
Replace fixed 16K-bucket tables with containers sized for actual workloads.

Selection criteria:

- read-heavy RCU-friendly lookup
- deterministic key semantics
- low empty-table overhead
- safe replacement/removal
- compatibility across maintained GKI versions

### Common object identity
Move path-backed features toward a shared internal identity model so kstat, map, redirect and path state do not each rediscover/store overlapping metadata independently.

Kernel-version-specific differences should stay in compatibility glue.

## 3. Observability

### Runtime statistics
Planned read-only counters:

- active entries per subsystem
- lookup hit/miss counts
- path refresh requests
- refreshes skipped/coalesced
- workqueue executions
- allocations/failures
- estimated resident table memory

Counters must be cheap when enabled and compile out or remain static-key gated when disabled.

### Diagnostics
Planned:

- `show status`
- `show capabilities`
- `show stats`
- configuration validation errors with stable error codes
- optional debug-only integrity checks

## 4. Userspace/runtime cleanup

### Registry-based command dispatch
Status: **implemented on `modernize/runtime-api`**

New commands are registered instead of extending a long strcmp chain.

### One runtime helper instead of shell pipelines
Move repeated boot-time shell parsing into the native helper where it materially reduces forks, pipes and scans.

Examples include deterministic mountinfo parsing and configuration ingestion.

### Separate examples from production boot logic
The module currently carries large demo blocks inside runtime scripts.

Move examples to documentation and keep boot scripts minimal.

## 5. Compatibility model

- Official upstream branches remain untouched.
- New ABI is additive.
- Legacy v2.3.0 commands remain supported.
- Modern clients probe capabilities before using a new operation.
- Shared core changes must be portable across all maintained GKI lanes.
- Every new stateful subsystem must define explicit invalidation and teardown semantics.

## Near-term implementation order

1. Complete capability ABI + userspace CI.
2. Centralize command IDs and shared userspace ABI definitions.
3. Add read-only runtime statistics.
4. Replace oversized fixed hash tables.
5. Introduce dirty-generation/event-driven path refresh.
6. Add lifecycle operations and declarative config.
7. Collapse boot-time shell work into the native helper.
8. Validate all maintained GKI ports before promotion to `next`.
