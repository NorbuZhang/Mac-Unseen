#include "SystemMonitorBridge.h"
#include <libproc.h>
#include <mach/mach_time.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <sys/sysctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/if_types.h>
#include <net/route.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>

static uint64_t cpu_nanoseconds(uint64_t user, uint64_t system, mach_timebase_info_data_t timebase) {
    // Both libproc time sources use Mach absolute time, including on Apple Silicon.
    __uint128_t nanoseconds = ((__uint128_t)user + system) * timebase.numer / timebase.denom;
    return nanoseconds > UINT64_MAX ? UINT64_MAX : (uint64_t)nanoseconds;
}

int MUCopyProcessSamples(MUProcessSample **samples) {
    *samples = NULL;
    mach_timebase_info_data_t timebase;
    if (mach_timebase_info(&timebase) != KERN_SUCCESS || timebase.denom == 0) return -1;
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes <= 0 || bytes > INT_MAX / 2) return -1;
    // Headroom for processes launched between size discovery and enumeration.
    int capacity = bytes + 1024 * (int)sizeof(pid_t);
    pid_t *pids = malloc((size_t)capacity);
    if (!pids) return -1;
    int count = proc_listpids(PROC_ALL_PIDS, 0, pids, capacity) / (int)sizeof(pid_t);
    if (count <= 0) { free(pids); return -1; }
    MUProcessSample *result = calloc((size_t)count, sizeof(*result));
    if (!result) { free(pids); return -1; }
    int written = 0;
    for (int i = 0; i < count; ++i) {
        if (pids[i] <= 0) continue;
        struct proc_bsdinfo bsd = {0};
        if (proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) != sizeof(bsd)) continue;
        MUProcessSample item = {0};
        item.pid = pids[i]; item.parent_pid = bsd.pbi_ppid; item.uid = bsd.pbi_uid;
        item.start_seconds = bsd.pbi_start_tvsec;
        item.start_microseconds = bsd.pbi_start_tvusec;
        if (proc_name(pids[i], item.name, sizeof(item.name)) <= 0)
            snprintf(item.name, sizeof(item.name), "%.*s", (int)sizeof(bsd.pbi_comm), bsd.pbi_comm);
        item.name[sizeof(item.name) - 1] = '\0';
        struct rusage_info_v4 usage = {0};
        if (proc_pid_rusage(pids[i], RUSAGE_INFO_V4, (rusage_info_t *)&usage) == 0) {
            item.cpu_nanoseconds = cpu_nanoseconds(usage.ri_user_time, usage.ri_system_time, timebase);
            item.resident_bytes = usage.ri_resident_size;
            item.footprint_bytes = usage.ri_phys_footprint;
            item.has_usage = item.has_footprint = 1;
        } else {
            struct proc_taskinfo task = {0};
            if (proc_pidinfo(pids[i], PROC_PIDTASKINFO, 0, &task, sizeof(task)) == sizeof(task)) {
                item.cpu_nanoseconds = cpu_nanoseconds(task.pti_total_user, task.pti_total_system, timebase);
                item.resident_bytes = task.pti_resident_size;
                item.threads = task.pti_threadnum;
                item.has_usage = 1;
            }
        }
        // Recheck identity: a PID may have exited and been reused mid-read.
        struct proc_bsdinfo after = {0};
        if (proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &after, sizeof(after)) != sizeof(after)
            || after.pbi_start_tvsec != bsd.pbi_start_tvsec
            || after.pbi_start_tvusec != bsd.pbi_start_tvusec) continue;
        result[written++] = item;
    }
    free(pids);
    *samples = result;
    return written;
}
void MUFreeProcessSamples(MUProcessSample *samples) { free(samples); }
int MUProcessPath(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds, char *buffer, uint32_t size) {
    if (!buffer || size == 0) return 0;
    buffer[0] = 0;
    struct proc_bsdinfo before = {0}, after = {0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &before, sizeof(before)) != sizeof(before)
        || before.pbi_start_tvsec != start_seconds || before.pbi_start_tvusec != start_microseconds) return 0;
    int result = proc_pidpath(pid, buffer, size);
    buffer[size - 1] = 0;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &after, sizeof(after)) != sizeof(after)
        || after.pbi_start_tvsec != start_seconds || after.pbi_start_tvusec != start_microseconds) { buffer[0] = 0; return 0; }
    return result;
}

int MUProcessCount(void) {
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes <= 0 || bytes > INT_MAX / 2) return -1;
    int capacity = bytes + 1024 * (int)sizeof(pid_t);
    pid_t *pids = malloc((size_t)capacity);
    if (!pids) return -1;
    int received = proc_listpids(PROC_ALL_PIDS, 0, pids, capacity);
    int result = received < 0 ? -1 : 0;
    for (int i = 0; i < received / (int)sizeof(pid_t); ++i) if (pids[i] > 0) ++result;
    free(pids);
    return result;
}

int MUCopyNetworkSamples(MUNetworkSample **samples) {
    *samples = NULL;
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    size_t length = 0;
    if (sysctl(mib, 6, NULL, &length, NULL, 0) != 0 || length == 0) return -1;
    char *buffer = malloc(length);
    if (!buffer) return -1;
    if (sysctl(mib, 6, buffer, &length, NULL, 0) != 0) { free(buffer); return -1; }
    size_t capacity = length / sizeof(struct if_msghdr2) + 1;
    MUNetworkSample *result = calloc(capacity, sizeof(*result));
    if (!result) { free(buffer); return -1; }
    int written = 0;
    // Address messages are shorter than if_msghdr. Read the shared four-byte
    // prefix so an address belonging to lo0 cannot hide all subsequent interfaces.
    struct route_prefix { uint16_t length; uint8_t version, type; };
    for (char *cursor = buffer; cursor + sizeof(struct route_prefix) <= buffer + length;) {
        struct route_prefix header;
        memcpy(&header, cursor, sizeof(header));
        if (header.length < sizeof(header) || (size_t)(buffer + length - cursor) < header.length) break;
        if (header.type == RTM_IFINFO2 && header.length >= sizeof(struct if_msghdr2)) {
            struct if_msghdr2 aligned_info;
            memcpy(&aligned_info, cursor, sizeof(aligned_info));
            struct if_msghdr2 *info = &aligned_info;
            char name[IFNAMSIZ] = {0};
            if (info->ifm_data.ifi_type == IFT_ETHER && (info->ifm_flags & IFF_UP)
                && (info->ifm_flags & IFF_RUNNING) && if_indextoname(info->ifm_index, name)
                && strncmp(name, "en", 2) == 0) {
                MUNetworkSample item = {0};
                item.index = info->ifm_index;
                item.received_bytes = info->ifm_data.ifi_ibytes;
                item.sent_bytes = info->ifm_data.ifi_obytes;
                strlcpy(item.name, name, sizeof(item.name));
                result[written++] = item;
            }
        }
        cursor += header.length;
    }
    free(buffer);
    *samples = result;
    return written;
}
void MUFreeNetworkSamples(MUNetworkSample *samples) { free(samples); }
