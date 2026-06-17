// SPDX-License-Identifier: MPL-2.0

/*
 * Multitouch data structures and private API declarations are adapted from
 * Kyome22/OpenMultitouchSupport, Copyright (c) 2019 Takuto Nakamura, under
 * the MIT License. The complete notice is bundled with Mac Unseen.
 */

#include "TrackpadBridge.h"

#include <dlfcn.h>
#include <os/lock.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int finger_id;
    int hand_id;
    MTVector normalized_position;
    float total;
    float pressure;
    float angle;
    float major_axis;
    float minor_axis;
    MTVector absolute_position;
    int field14;
    int field15;
    float density;
} MTTouch;

typedef void *MTDeviceRef;
typedef void (*MTFrameCallback)(
    MTDeviceRef device,
    MTTouch touches[],
    int num_touches,
    double timestamp,
    int frame
);

typedef bool (*MTDeviceIsAvailableFn)(void);
typedef MTDeviceRef (*MTDeviceCreateDefaultFn)(void);
typedef int32_t (*MTDeviceStartFn)(MTDeviceRef, int);
typedef int32_t (*MTDeviceStopFn)(MTDeviceRef);
typedef void (*MTDeviceReleaseFn)(MTDeviceRef);
typedef bool (*MTDeviceIsRunningFn)(MTDeviceRef);
typedef bool (*MTDeviceIsBuiltInFn)(MTDeviceRef);
typedef int32_t (*MTDeviceGetDimensionsFn)(MTDeviceRef, int *, int *);
typedef int32_t (*MTDeviceGetIntFn)(MTDeviceRef, int *);
typedef int32_t (*MTDeviceGetIDFn)(MTDeviceRef, uint64_t *);
typedef void (*MTRegisterCallbackFn)(MTDeviceRef, MTFrameCallback);

static void *g_framework;
static MTDeviceRef g_device;
static MTDeviceIsAvailableFn p_is_available;
static MTDeviceCreateDefaultFn p_create_default;
static MTDeviceStartFn p_start;
static MTDeviceStopFn p_stop;
static MTDeviceReleaseFn p_release;
static MTDeviceIsRunningFn p_is_running;
static MTDeviceIsBuiltInFn p_is_built_in;
static MTDeviceGetDimensionsFn p_surface_dimensions;
static MTDeviceGetDimensionsFn p_sensor_dimensions;
static MTDeviceGetIntFn p_family_id;
static MTDeviceGetIDFn p_device_id;
static MTRegisterCallbackFn p_register_callback;
static MTRegisterCallbackFn p_unregister_callback;

static os_unfair_lock g_lock = OS_UNFAIR_LOCK_INIT;
static SLTouchPoint g_touches[SL_MAX_TOUCHES];
static int32_t g_touch_count;
static SLTrackpadInfo g_info;

static int resolve_symbols(void) {
    if (g_framework == NULL) {
        return 0;
    }
    p_is_available =
        (MTDeviceIsAvailableFn)dlsym(g_framework, "MTDeviceIsAvailable");
    p_create_default =
        (MTDeviceCreateDefaultFn)dlsym(g_framework, "MTDeviceCreateDefault");
    p_start = (MTDeviceStartFn)dlsym(g_framework, "MTDeviceStart");
    p_stop = (MTDeviceStopFn)dlsym(g_framework, "MTDeviceStop");
    p_release = (MTDeviceReleaseFn)dlsym(g_framework, "MTDeviceRelease");
    p_is_running =
        (MTDeviceIsRunningFn)dlsym(g_framework, "MTDeviceIsRunning");
    p_is_built_in =
        (MTDeviceIsBuiltInFn)dlsym(g_framework, "MTDeviceIsBuiltIn");
    p_surface_dimensions = (MTDeviceGetDimensionsFn)dlsym(
        g_framework, "MTDeviceGetSensorSurfaceDimensions");
    p_sensor_dimensions = (MTDeviceGetDimensionsFn)dlsym(
        g_framework, "MTDeviceGetSensorDimensions");
    p_family_id =
        (MTDeviceGetIntFn)dlsym(g_framework, "MTDeviceGetFamilyID");
    p_device_id =
        (MTDeviceGetIDFn)dlsym(g_framework, "MTDeviceGetDeviceID");
    p_register_callback = (MTRegisterCallbackFn)dlsym(
        g_framework, "MTRegisterContactFrameCallback");
    p_unregister_callback = (MTRegisterCallbackFn)dlsym(
        g_framework, "MTUnregisterContactFrameCallback");

    return p_is_available && p_create_default && p_start && p_stop &&
           p_release && p_is_running && p_register_callback &&
           p_unregister_callback;
}

static int ensure_loaded(void) {
    if (g_framework != NULL) {
        return 1;
    }
    const char *path =
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/"
        "Versions/Current/MultitouchSupport";
    g_framework = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
    if (g_framework == NULL) {
        return 0;
    }
    if (!resolve_symbols()) {
        dlclose(g_framework);
        g_framework = NULL;
        return 0;
    }
    return 1;
}

static void contact_callback(
    MTDeviceRef device,
    MTTouch touches[],
    int num_touches,
    double timestamp,
    int frame
) {
    (void)device;
    (void)timestamp;
    (void)frame;

    int32_t count = num_touches;
    if (count < 0) {
        count = 0;
    }
    if (count > SL_MAX_TOUCHES) {
        count = SL_MAX_TOUCHES;
    }

    os_unfair_lock_lock(&g_lock);
    g_touch_count = count;
    for (int32_t i = 0; i < count; i++) {
        const MTTouch *source = &touches[i];
        SLTouchPoint *target = &g_touches[i];
        target->identifier = source->identifier;
        target->state = source->state;
        target->x = source->normalized_position.position.x;
        target->y = source->normalized_position.position.y;
        target->velocity_x = source->normalized_position.velocity.x;
        target->velocity_y = source->normalized_position.velocity.y;
        target->total = source->total;
        target->pressure = source->pressure;
        target->angle = source->angle;
        target->major_axis = source->major_axis;
        target->minor_axis = source->minor_axis;
        target->density = source->density;
        target->timestamp = source->timestamp;
    }
    os_unfair_lock_unlock(&g_lock);
}

int32_t SLTrackpadIsAvailable(void) {
    return ensure_loaded() && p_is_available() ? 1 : 0;
}

int32_t SLTrackpadStart(void) {
    if (!ensure_loaded() || !p_is_available()) {
        return 0;
    }
    if (g_device != NULL && p_is_running(g_device)) {
        return 1;
    }

    g_device = p_create_default();
    if (g_device == NULL) {
        return 0;
    }

    memset(&g_info, 0, sizeof(g_info));
    if (p_surface_dimensions) {
        p_surface_dimensions(
            g_device, &g_info.surface_width, &g_info.surface_height);
    }
    if (p_sensor_dimensions) {
        p_sensor_dimensions(
            g_device, &g_info.sensor_rows, &g_info.sensor_columns);
    }
    if (p_family_id) {
        p_family_id(g_device, &g_info.family_id);
    }
    if (p_device_id) {
        p_device_id(g_device, &g_info.device_id);
    }
    g_info.built_in =
        p_is_built_in == NULL || p_is_built_in(g_device) ? 1 : 0;

    p_register_callback(g_device, contact_callback);
    int32_t result = p_start(g_device, 0);
    g_info.running = result == 0 ? 1 : 0;
    if (result != 0) {
        p_unregister_callback(g_device, contact_callback);
        p_release(g_device);
        g_device = NULL;
        return 0;
    }
    return 1;
}

void SLTrackpadStop(void) {
    if (g_device == NULL || !ensure_loaded()) {
        return;
    }
    if (p_is_running(g_device)) {
        p_unregister_callback(g_device, contact_callback);
        p_stop(g_device);
    }
    p_release(g_device);
    g_device = NULL;

    os_unfair_lock_lock(&g_lock);
    g_touch_count = 0;
    g_info.running = 0;
    os_unfair_lock_unlock(&g_lock);
}

int32_t SLTrackpadCopyTouches(SLTouchPoint *buffer, int32_t capacity) {
    if (buffer == NULL || capacity <= 0) {
        return 0;
    }
    os_unfair_lock_lock(&g_lock);
    int32_t count = g_touch_count < capacity ? g_touch_count : capacity;
    memcpy(buffer, g_touches, (size_t)count * sizeof(SLTouchPoint));
    os_unfair_lock_unlock(&g_lock);
    return count;
}

SLTrackpadInfo SLTrackpadGetInfo(void) {
    os_unfair_lock_lock(&g_lock);
    SLTrackpadInfo result = g_info;
    os_unfair_lock_unlock(&g_lock);
    return result;
}
