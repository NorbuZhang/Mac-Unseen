/*
 * Read-only Apple SMC fan speed probe for Mac Unseen.
 * Copyright (C) 2026 Mac Unseen contributors.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License, version 3.
 * SPDX-License-Identifier: GPL-3.0-only
 */

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "smc.h"

static uint32_t read_big_endian_uint(const UInt8 *bytes, UInt32 size) {
    uint32_t value = 0;
    if (size > 4) {
        size = 4;
    }
    for (UInt32 index = 0; index < size; ++index) {
        value = (value << 8) | bytes[index];
    }
    return value;
}

static int decode_speed(const SMCVal_t *value, double *speed) {
    if (strncmp(value->dataType, SMC_TYPE_FLT, 3) == 0
        && value->dataSize >= 4) {
        uint32_t bits = (uint32_t)value->bytes[0]
            | ((uint32_t)value->bytes[1] << 8)
            | ((uint32_t)value->bytes[2] << 16)
            | ((uint32_t)value->bytes[3] << 24);
        float decoded;
        memcpy(&decoded, &bits, sizeof(decoded));
        if (!isfinite(decoded) || decoded < 0) {
            return 0;
        }
        *speed = decoded;
        return 1;
    }

    if (strncmp(value->dataType, SMC_TYPE_FPE2, 4) == 0
        && value->dataSize >= 2) {
        *speed = read_big_endian_uint(value->bytes, 2) / 4.0;
        return 1;
    }

    if (strncmp(value->dataType, SMC_TYPE_UI8, 3) == 0
        || strncmp(value->dataType, SMC_TYPE_UI16, 4) == 0
        || strncmp(value->dataType, SMC_TYPE_UI32, 4) == 0) {
        *speed = read_big_endian_uint(value->bytes, value->dataSize);
        return 1;
    }

    return 0;
}

int main(void) {
    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t result = SMCOpen("AppleSMC", &connection);
    if (result != kIOReturnSuccess) {
        fprintf(stderr, "unable to open Apple SMC: return code %d\n", result);
        return 1;
    }

    SMCVal_t count_value;
    result = SMCReadKey(connection, "FNum", &count_value);
    if (result != kIOReturnSuccess || count_value.dataSize == 0) {
        SMCClose(connection);
        fprintf(stderr, "unable to read fan count\n");
        return 1;
    }

    uint32_t fan_count = read_big_endian_uint(
        count_value.bytes,
        count_value.dataSize
    );
    if (fan_count > 32) {
        fan_count = 32;
    }

    printf("{\"fanCount\":%u,\"speeds\":[", fan_count);
    int wrote_speed = 0;
    for (uint32_t index = 0; index < fan_count; ++index) {
        char key[5];
        snprintf(key, sizeof(key), "F%uAc", index);
        SMCVal_t value;
        double speed;
        if (SMCReadKey(connection, key, &value) != kIOReturnSuccess
            || !decode_speed(&value, &speed)) {
            continue;
        }
        if (wrote_speed) {
            putchar(',');
        }
        printf(
            "{\"index\":%u,\"key\":\"%s\",\"rpm\":%.3f}",
            index + 1,
            key,
            speed
        );
        wrote_speed = 1;
    }
    puts("]}");
    SMCClose(connection);
    return 0;
}
