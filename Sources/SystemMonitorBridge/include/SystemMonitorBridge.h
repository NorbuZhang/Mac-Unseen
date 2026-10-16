#ifndef SYSTEM_MONITOR_BRIDGE_H
#define SYSTEM_MONITOR_BRIDGE_H
#include <stdint.h>
typedef struct {
    int32_t pid;
    uint32_t uid;
    uint64_t start_seconds, start_microseconds;
    uint64_t cpu_nanoseconds, resident_bytes, footprint_bytes;
    uint32_t threads;
    int has_usage, has_footprint;
    char name[256];
} MUProcessSample;
// Caller owns the returned allocation. Failure returns -1, not an empty list.
int MUCopyProcessSamples(MUProcessSample **samples);
void MUFreeProcessSamples(MUProcessSample *samples);
typedef struct {
    uint32_t index;
    uint64_t received_bytes, sent_bytes;
    char name[32];
} MUNetworkSample;
int MUCopyNetworkSamples(MUNetworkSample **samples);
void MUFreeNetworkSamples(MUNetworkSample *samples);
#endif
