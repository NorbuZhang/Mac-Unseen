#include "SystemMonitorBridge.h"
#include <libproc.h>
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

int MUCopyProcessSamples(MUProcessSample **samples) {
    *samples = NULL;
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
        item.pid = pids[i]; item.uid = bsd.pbi_uid;
        item.start_seconds = bsd.pbi_start_tvsec;
        item.start_microseconds = bsd.pbi_start_tvusec;
        if (proc_name(pids[i], item.name, sizeof(item.name)) <= 0)
            snprintf(item.name, sizeof(item.name), "%.*s", (int)sizeof(bsd.pbi_comm), bsd.pbi_comm);
        struct rusage_info_v4 usage = {0};
        if (proc_pid_rusage(pids[i], RUSAGE_INFO_V4, (rusage_info_t *)&usage) == 0) {
            item.cpu_nanoseconds = usage.ri_user_time + usage.ri_system_time;
            item.resident_bytes = usage.ri_resident_size;
            item.footprint_bytes = usage.ri_phys_footprint;
            item.has_usage = item.has_footprint = 1;
        } else {
            struct proc_taskinfo task = {0};
            if (proc_pidinfo(pids[i], PROC_PIDTASKINFO, 0, &task, sizeof(task)) == sizeof(task)) {
                item.cpu_nanoseconds = task.pti_total_user + task.pti_total_system;
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
    for (char *cursor = buffer; cursor + sizeof(struct if_msghdr) <= buffer + length;) {
        struct if_msghdr *header = (struct if_msghdr *)cursor;
        if (header->ifm_msglen < sizeof(*header) || cursor + header->ifm_msglen > buffer + length) break;
        if (header->ifm_type == RTM_IFINFO2 && header->ifm_msglen >= sizeof(struct if_msghdr2)) {
            struct if_msghdr2 *info = (struct if_msghdr2 *)cursor;
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
        cursor += header->ifm_msglen;
    }
    free(buffer);
    *samples = result;
    return written;
}
void MUFreeNetworkSamples(MUNetworkSample *samples) { free(samples); }
