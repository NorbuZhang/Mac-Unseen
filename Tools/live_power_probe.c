/*
 * Read-only Apple SMC live power probe for Mac Unseen.
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

static int fixed_fraction_bits(char digit) {
    if (digit >= '0' && digit <= '9') {
        return digit - '0';
    }
    if (digit >= 'a' && digit <= 'f') {
        return digit - 'a' + 10;
    }
    return -1;
}

static int decode_value(const SMCVal_t *value, double *decoded) {
    if (strncmp(value->dataType, SMC_TYPE_FLT, 3) == 0
        && value->dataSize >= 4) {
        uint32_t bits = (uint32_t)value->bytes[0]
            | ((uint32_t)value->bytes[1] << 8)
            | ((uint32_t)value->bytes[2] << 16)
            | ((uint32_t)value->bytes[3] << 24);
        float number;
        memcpy(&number, &bits, sizeof(number));
        if (!isfinite(number)) {
            return 0;
        }
        *decoded = (double)number;
        return 1;
    }

    if ((strncmp(value->dataType, "fp", 2) == 0
            || strncmp(value->dataType, "sp", 2) == 0)
        && value->dataSize >= 2) {
        int fraction_bits = fixed_fraction_bits(value->dataType[3]);
        if (fraction_bits < 0) {
            return 0;
        }
        uint16_t raw = (uint16_t)read_big_endian_uint(value->bytes, 2);
        double divisor = (double)(1u << fraction_bits);
        *decoded = value->dataType[0] == 's'
            ? (double)(int16_t)raw / divisor
            : (double)raw / divisor;
        return 1;
    }

    if (strncmp(value->dataType, SMC_TYPE_UI8, 3) == 0
        || strncmp(value->dataType, SMC_TYPE_UI16, 4) == 0
        || strncmp(value->dataType, SMC_TYPE_UI32, 4) == 0) {
        *decoded = read_big_endian_uint(value->bytes, value->dataSize);
        return 1;
    }

    return 0;
}

static int read_key(
    io_connect_t connection,
    const char *key,
    double minimum,
    double maximum,
    double *decoded
) {
    SMCVal_t value;
    if (SMCReadKey(connection, key, &value) != kIOReturnSuccess
        || !decode_value(&value, decoded)
        || !isfinite(*decoded)
        || *decoded < minimum
        || *decoded > maximum) {
        return 0;
    }
    return 1;
}

static void write_number(
    const char *name,
    double value,
    int *wrote_value
) {
    if (*wrote_value) {
        putchar(',');
    }
    printf("\"%s\":%.6f", name, value);
    *wrote_value = 1;
}

int main(void) {
    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t result = SMCOpen("AppleSMC", &connection);
    if (result != kIOReturnSuccess) {
        fprintf(stderr, "unable to open Apple SMC: return code %d\n", result);
        return 1;
    }

    double input_power;
    double battery_power;
    double system_power;
    double input_voltage;
    int has_input_power = read_key(
        connection, "PDTR", -1000, 1000, &input_power
    );
    int has_battery_power = read_key(
        connection, "PPBR", -1000, 1000, &battery_power
    );
    int has_system_power = read_key(
        connection, "PSTR", -1000, 1000, &system_power
    );
    int has_input_voltage = read_key(
        connection, "VD0R", 0, 100, &input_voltage
    );

    putchar('{');
    int wrote_value = 0;
    if (has_input_power) {
        write_number("inputPower", input_power, &wrote_value);
    }
    if (has_battery_power) {
        write_number("batteryPower", battery_power, &wrote_value);
    }
    if (has_system_power) {
        write_number("systemPower", system_power, &wrote_value);
    }
    if (has_input_voltage) {
        write_number("inputVoltage", input_voltage, &wrote_value);
    }
    puts("}");
    SMCClose(connection);
    return wrote_value ? 0 : 1;
}
