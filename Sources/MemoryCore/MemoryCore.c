#include "MemoryCore.h"
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <sys/resource.h>
#include <libproc.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

bool mm_read_memory(MMMemory *out) {
    memset(out, 0, sizeof(*out));
    vm_statistics64_data_t vm = {0};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    mach_port_t host = mach_host_self();
    vm_size_t page = 0;
    kern_return_t result = host_page_size(host, &page);
    if (result == KERN_SUCCESS) result = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (result != KERN_SUCCESS) return false;
    size_t size = sizeof(out->total);
    if (sysctlbyname("hw.memsize", &out->total, &size, NULL, 0)) return false;
    out->wired = (uint64_t)vm.wire_count * page;
    out->compressed = (uint64_t)vm.compressor_page_count * page;
    /* Anonymous resident pages exclude purgeable pages; compressed is physical storage. */
    out->app = (uint64_t)(vm.internal_page_count > vm.purgeable_count ? vm.internal_page_count - vm.purgeable_count : 0) * page;
    out->cached = ((uint64_t)vm.external_page_count + vm.purgeable_count) * page;
    out->free_bytes = (uint64_t)vm.free_count * page;
    out->swapouts = vm.swapouts;
    struct xsw_usage swap = {0}; size = sizeof(swap);
    out->swap_valid = sysctlbyname("vm.swapusage", &swap, &size, NULL, 0) == 0;
    out->swap = swap.xsu_used;
    /* Best-effort bootstrap only: this sysctl is not a stable public API. */
    size = sizeof(out->pressure);
    if (sysctlbyname("kern.memorystatus_vm_pressure_level", &out->pressure, &size, NULL, 0)) out->pressure = 0;
    return true;
}
static int compare(const void *a, const void *b) {
    uint64_t x = ((const MMProcess *)a)->footprint, y = ((const MMProcess *)b)->footprint;
    return (y > x) - (y < x);
}
int mm_read_processes(MMProcess *out, int capacity) {
    int count = proc_listallpids(NULL, 0);
    if (count <= 0 || capacity <= 0) return 0;
    int slots = count + 256;
    pid_t *pids = calloc((size_t)slots, sizeof(pid_t));
    MMProcess *rows = calloc((size_t)slots, sizeof(MMProcess));
    if (!pids || !rows) { free(pids); free(rows); return 0; }
    count = proc_listallpids(pids, slots * sizeof(pid_t));
    int used = 0;
    for (int i = 0; i < count && i < slots; i++) {
        struct rusage_info_v2 info = {0};
        if (pids[i] <= 0 || proc_pid_rusage(pids[i], RUSAGE_INFO_V2, (rusage_info_t *)&info) || !info.ri_phys_footprint) continue;
        rows[used].pid = pids[i]; rows[used].footprint = info.ri_phys_footprint;
        if (!proc_name(pids[i], rows[used].name, sizeof(rows[used].name))) strcpy(rows[used].name, "Unknown");
        used++;
    }
    qsort(rows, used, sizeof(MMProcess), compare);
    int n = used < capacity ? used : capacity;
    memcpy(out, rows, n * sizeof(MMProcess)); free(pids); free(rows); return n;
}
