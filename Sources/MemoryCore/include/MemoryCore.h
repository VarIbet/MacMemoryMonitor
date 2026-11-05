#include <stdint.h>
#include <stdbool.h>
typedef struct {
    uint64_t total, app, wired, compressed, cached, free_bytes, swap;
    uint64_t swapouts;
    int pressure; /* optional kernel level: 1 normal, 2 warning, 4 critical; 0 unavailable */
    bool swap_valid;
} MMMemory;
typedef struct { int32_t pid; uint64_t footprint; char name[1024]; } MMProcess;
typedef struct { int32_t parent_pid; char executable_path[4096]; } MMProcessIdentity;
bool mm_read_memory(MMMemory *out);
int mm_read_processes(MMProcess *out, int capacity);
bool mm_read_process_identity(int32_t pid, MMProcessIdentity *out);
