// SPDX-License-Identifier: MPL-2.0

/*
 * Portions adapted from Kyome22/OpenMultitouchSupport,
 * Copyright (c) 2019 Takuto Nakamura, MIT License.
 */

#ifndef TRACKPAD_BRIDGE_H
#define TRACKPAD_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SL_MAX_TOUCHES 16

typedef struct {
    int32_t identifier;
    int32_t state;
    float x;
    float y;
    float velocity_x;
    float velocity_y;
    float total;
    float pressure;
    float angle;
    float major_axis;
    float minor_axis;
    float density;
    double timestamp;
} SLTouchPoint;

typedef struct {
    int32_t surface_width;
    int32_t surface_height;
    int32_t sensor_rows;
    int32_t sensor_columns;
    int32_t family_id;
    uint64_t device_id;
    int32_t built_in;
    int32_t running;
} SLTrackpadInfo;

int32_t SLTrackpadIsAvailable(void);
int32_t SLTrackpadStart(void);
void SLTrackpadStop(void);
int32_t SLTrackpadCopyTouches(SLTouchPoint *buffer, int32_t capacity);
SLTrackpadInfo SLTrackpadGetInfo(void);

#ifdef __cplusplus
}
#endif

#endif
