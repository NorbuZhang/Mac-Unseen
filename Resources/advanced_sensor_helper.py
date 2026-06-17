#!/usr/bin/python3
# SPDX-License-Identifier: MPL-2.0
"""Read undocumented Apple SPU sensors and publish a local JSON snapshot.

The helper is intentionally read-only. It enables reporting on AppleSPUHID
drivers, listens for input reports, and invokes the bundled iSMC binary for
thermal/electrical telemetry.

Apple SPU access patterns and report layouts are adapted from
olvvier/apple-silicon-accelerometer, Copyright (c) 2026 olvvier, under the
MIT License. The complete notice is bundled with Mac Unseen.
"""

from __future__ import annotations

import argparse
import collections
import copy
import ctypes
import ctypes.util
import json
import math
import os
import re
import signal
import struct
import subprocess
import sys
import tempfile
import threading
import time

PAGE_VENDOR = 0xFF00
PAGE_SENSOR = 0x0020
USAGE_ACCEL = 3
USAGE_GYRO = 9
USAGE_ALS = 4
USAGE_LID = 138

IMU_REPORT_LEN = 22
IMU_DATA_OFFSET = 6
ALS_REPORT_LEN = 122
REPORT_BUFFER_SIZE = 4096
REPORT_INTERVAL_US = 5000
SPU_FIRST_REPORT_TIMEOUT = 5.0
IOHID_REPORT_TYPE_FEATURE = 2
ACTIVE_SNAPSHOT_INTERVAL = 0.1
SNAPSHOT_HEARTBEAT_INTERVAL = 2.0
ACTIVE_LOOP_INTERVAL = 0.05
LID_POLL_INTERVAL = 1.0 / 15.0
LUX_POLL_INTERVAL = 1.0
LUX_RETRY_INTERVAL = 5.0
RAW_SAMPLE_RATE = 200
DEFAULT_SAMPLE_RATE = 100
MINIMUM_IMU_HARDWARE_RATE = 50
Q16_SCALE = 65536.0

CF_UTF8 = 0x08000100
CF_SINT32 = 3
CF_SINT64 = 4

state_lock = threading.Lock()
stop_event = threading.Event()
motion_energy = collections.deque(maxlen=300)

state = {
    "status": "starting",
    "timestamp": time.time(),
    "collectorTimestamps": {},
    "collectorErrors": {},
    "capabilities": {
        "accelerometer": "unknown",
        "gyroscope": "unknown",
        "lidAngle": "unknown",
        "spectral": "unknown",
        "ambientLux": "unknown",
        "fans": "unknown",
        "temperature": "unknown",
        "power": "unknown",
    },
    "motion": {
        "accelerometer": None,
        "gyroscope": None,
        "orientation": None,
        "vibration": {
            "rms": 0.0,
            "peak": 0.0,
            "sampleRate": 0.0,
        },
    },
    "environment": {
        "lidAngle": None,
        "alsIntensity": None,
        "lux": None,
        "spectralChannels": [],
    },
    "storageSmart": {
        "available": False,
    },
    "ismc": {},
    "errors": [],
}

accel_decimation = 0
gyro_decimation = 0
imu_decimation = RAW_SAMPLE_RATE // DEFAULT_SAMPLE_RATE
imu_hardware_rate = RAW_SAMPLE_RATE
app_active = True
high_rate_active = False
active_section = "overview"
expanded_temperature_groups = ()
section_generation = 0
sample_counter = 0
sample_window_start = time.monotonic()
last_gyro_time = None
yaw_degrees = 0.0
callback_roots = []
model_identifier = None
spu_ready_event = threading.Event()
spu_sensor_lock = threading.Lock()
spu_opened_capabilities = set()
spu_reported_capabilities = set()


def append_error(message: str) -> None:
    with state_lock:
        errors = state.setdefault("errors", [])
        if not errors or errors[-1] != message:
            errors.append(message)
            del errors[:-8]


def apply_configuration(configuration: dict) -> None:
    global app_active, high_rate_active, active_section
    global expanded_temperature_groups, section_generation, imu_decimation
    global imu_hardware_rate
    allowed_rates = (25, 50, 100, 200)
    requested = int(
        configuration.get("imuSampleRate", DEFAULT_SAMPLE_RATE)
    )
    if requested not in allowed_rates:
        return
    next_app_active = bool(configuration.get("appActive", True))
    next_section = str(configuration.get("activeSection", "overview"))
    if not next_app_active:
        next_section = "inactive"
    next_temperature_groups = tuple(
        str(value)
        for value in configuration.get("expandedTemperatureGroups", [])
    )
    if (
        next_app_active != app_active
        or next_section != active_section
        or next_temperature_groups != expanded_temperature_groups
    ):
        section_generation += 1
    app_active = next_app_active
    active_section = next_section
    high_rate_active = bool(configuration.get("highRateActive", False))
    expanded_temperature_groups = next_temperature_groups
    effective_rate = (
        requested
        if app_active and high_rate_active and active_section == "motion"
        else min(requested, 25)
    )
    imu_hardware_rate = max(MINIMUM_IMU_HARDWARE_RATE, effective_rate)
    imu_decimation = max(
        1,
        round(imu_hardware_rate / effective_rate),
    )


def load_configuration(path: str):
    try:
        modified_ns = os.stat(path).st_mtime_ns
        with open(path, "r", encoding="utf-8") as stream:
            apply_configuration(json.load(stream))
        return modified_ns
    except (
        FileNotFoundError,
        ValueError,
        TypeError,
        json.JSONDecodeError,
    ):
        return None


def poll_configuration(path: str, last_modified_ns) -> None:
    while not stop_event.is_set():
        try:
            modified_ns = os.stat(path).st_mtime_ns
            if modified_ns != last_modified_ns:
                with open(path, "r", encoding="utf-8") as stream:
                    apply_configuration(json.load(stream))
                last_modified_ns = modified_ns
        except (
            FileNotFoundError,
            ValueError,
            TypeError,
            json.JSONDecodeError,
        ):
            pass
        stop_event.wait(0.25)


def wait_for_configuration_change(timeout: float, generation: int) -> None:
    deadline = time.monotonic() + timeout
    while not stop_event.is_set() and section_generation == generation:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return
        stop_event.wait(min(0.25, remaining))


def set_collector_error(name: str, message) -> None:
    with state_lock:
        errors = state.setdefault("collectorErrors", {})
        if message:
            errors[name] = message
        else:
            errors.pop(name, None)


def set_capability(name: str, status: str) -> None:
    with state_lock:
        state["capabilities"][name] = status


def mark_spu_opened(name: str) -> None:
    with spu_sensor_lock:
        spu_opened_capabilities.add(name)
    set_capability(name, "probing")


def mark_spu_report(name: str) -> None:
    with spu_sensor_lock:
        spu_reported_capabilities.add(name)
    set_capability(name, "available")


def expire_missing_spu_reports(capabilities) -> None:
    with spu_sensor_lock:
        missing = [
            capability
            for capability in capabilities
            if capability in spu_opened_capabilities
            and capability not in spu_reported_capabilities
        ]
    for capability in missing:
        set_capability(capability, "unsupported")


def is_known_fanless_model() -> bool:
    global model_identifier
    if model_identifier is None:
        process = subprocess.run(
            ["/usr/sbin/sysctl", "-n", "hw.model"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        model_identifier = process.stdout.strip()
    return (
        model_identifier.startswith("MacBookAir")
        or model_identifier == "Mac17,5"
    )


def normalized_ismc_section(decoded: dict, section_name: str) -> dict:
    candidate = decoded.get(section_name)
    if isinstance(candidate, dict) and not any(
        key in candidate for key in ("key", "value", "quantity", "unit")
    ):
        return candidate
    return decoded


def atomic_write_json(path: str, payload: dict) -> None:
    directory = os.path.dirname(path)
    os.makedirs(directory, mode=0o755, exist_ok=True)
    fd, temporary_path = tempfile.mkstemp(prefix=".snapshot-", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, ensure_ascii=False, separators=(",", ":"))
        os.chmod(temporary_path, 0o644)
        os.replace(temporary_path, path)
    finally:
        try:
            os.unlink(temporary_path)
        except FileNotFoundError:
            pass


def snapshot_for_section(section: str) -> dict:
    """Copy only the readings consumed by the currently visible page."""
    snapshot = {
        "status": state["status"],
        "timestamp": state["timestamp"],
        "collectorTimestamps": dict(state["collectorTimestamps"]),
        "collectorErrors": dict(state["collectorErrors"]),
        "capabilities": dict(state["capabilities"]),
        "errors": list(state["errors"]),
    }
    if section == "motion":
        snapshot["motion"] = copy.deepcopy(state["motion"])
    elif section == "environment":
        snapshot["environment"] = copy.deepcopy(state["environment"])
    elif section == "storage":
        snapshot["storageSmart"] = copy.deepcopy(state["storageSmart"])
    else:
        ismc_section = {
            "overview": "Power",
            "fans": "Fans",
            "temperature": "Temperature",
        }.get(section)
        if ismc_section:
            snapshot["ismc"] = {
                ismc_section: copy.deepcopy(
                    state["ismc"].get(ismc_section, {})
                )
            }
    return snapshot


def read_fan_speeds(fan_probe_path: str) -> tuple[int, dict]:
    process = subprocess.run(
        [fan_probe_path],
        capture_output=True,
        text=True,
        timeout=5,
        check=False,
    )
    if process.returncode != 0:
        message = process.stderr.strip().splitlines()
        raise RuntimeError(message[-1] if message else "fan probe failed")
    decoded = json.loads(process.stdout)
    fan_count = int(decoded.get("fanCount", 0))
    values = {}
    for speed in decoded.get("speeds", []):
        index = int(speed["index"])
        key = str(speed["key"])
        rpm = float(speed["rpm"])
        values[f"Fan {index} Current Speed"] = {
            "key": key,
            "type": "probe",
            "value": f"{rpm:.0f} rpm",
            "quantity": rpm,
            "unit": "rpm",
        }
    return fan_count, values


def poll_ismc(ismc_path: str, fan_probe_path: str) -> None:
    last_temperature_generation = -1
    while not stop_event.is_set():
        section = active_section
        generation = section_generation
        collector = None
        command = None
        if app_active and section == "overview":
            collector = "power"
            command = "power"
        elif app_active and section == "fans":
            collector = "fans"
            command = "fans"
        elif app_active and section == "temperature" and (
            expanded_temperature_groups
            or generation != last_temperature_generation
        ):
            collector = "temperature"
            command = "temp"
        if command is None:
            wait_for_configuration_change(0.25, generation)
            continue

        try:
            process = subprocess.run(
                [ismc_path, "-o", "json", command],
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
            )
            output = process.stdout.strip()
            decoded = json.loads(output) if output else {}
            section_name = {
                "power": "Power",
                "fans": "Fans",
                "temperature": "Temperature",
            }[collector]
            values = normalized_ismc_section(decoded, section_name)
            collector_error = None
            hardware_absent = False
            if section_name == "Fans":
                try:
                    fan_count, live_speeds = read_fan_speeds(fan_probe_path)
                    hardware_absent = fan_count == 0
                    values["Fan Count"] = {
                        "key": "FNum",
                        "type": "probe",
                        "value": str(fan_count),
                        "quantity": fan_count,
                        "unit": "",
                    }
                    values.update(live_speeds)
                    set_capability(
                        "fans",
                        "unsupported" if fan_count == 0 else "available",
                    )
                    if fan_count > 0 and not live_speeds:
                        collector_error = (
                            "Fan speed keys are present but returned no readings"
                        )
                except Exception as exc:
                    if is_known_fanless_model():
                        hardware_absent = True
                        set_capability("fans", "unsupported")
                        values["Fan Count"] = {
                            "key": "FNum",
                            "type": "inferred",
                            "value": "0",
                            "quantity": 0,
                            "unit": "",
                        }
                    else:
                        set_capability("fans", "unreadable")
                        collector_error = f"Fan speed probe: {exc}"
            elif section_name == "Temperature":
                set_capability(
                    "temperature",
                    "available" if values else "unsupported",
                )
            elif section_name == "Power":
                set_capability(
                    "power",
                    "available" if values else "unsupported",
                )
            if not values:
                raise RuntimeError(f"iSMC {command} returned no readings")
            with state_lock:
                telemetry = state.setdefault("ismc", {})
                if section_name == "Fans":
                    existing = telemetry.get("Fans", {})
                    static_values = {
                        name: entry
                        for name, entry in existing.items()
                        if name == "Fan Count"
                        or name.endswith(
                            (
                                "Minimal Speed",
                                "Maximum Speed",
                                "Safe Speed",
                            )
                        )
                    }
                    values.update(static_values)
                telemetry[section_name] = values
                state["collectorTimestamps"][collector] = time.time()
            set_collector_error(collector, collector_error)
            if collector == "temperature":
                last_temperature_generation = generation
            if (
                collector_error is None
                and not hardware_absent
                and process.returncode != 0
                and process.stderr.strip()
            ):
                message = process.stderr.strip().splitlines()[-1]
                set_collector_error(collector, f"iSMC: {message}")
                append_error("iSMC: " + message)
        except Exception as exc:
            if collector in ("temperature", "power"):
                with state_lock:
                    capability = state["capabilities"].get(collector)
                if capability != "unsupported":
                    set_capability(collector, "unreadable")
            set_collector_error(collector, f"iSMC: {exc}")
            append_error(f"iSMC unavailable: {exc}")
        wait_for_configuration_change(1.0, generation)


LUX_QUERIES = (
    ("/usr/sbin/ioreg", "-l", "-w0", "-r", "-c", "AppleSPUHIDDevice"),
    ("/usr/sbin/ioreg", "-l", "-w0", "-r", "-n", "als"),
    ("/usr/sbin/ioreg", "-l", "-w0", "-r", "-c", "AppleLMUController"),
    ("/usr/sbin/ioreg", "-l", "-w0", "-r", "-c", "AppleHIDALSService"),
)


def poll_environment_lux() -> None:
    preferred_query = None
    registry_service = None
    iokit = None
    try:
        (
            iokit,
            core_foundation,
            _allocator,
            _run_loop_mode,
            _mach_to_seconds,
            cf_string,
            _cf_number32,
            _property_integer,
        ) = initialize_iokit()
        registry_service = find_lux_registry_service(iokit)

        while not stop_event.is_set():
            if not app_active or active_section != "environment":
                stop_event.wait(0.25)
                continue
            generation = section_generation
            lux = None
            try:
                lux = read_registry_lux(
                    iokit,
                    core_foundation,
                    registry_service,
                    cf_string,
                )
                matched_query = None
                if lux is None:
                    queries = (
                        (preferred_query,)
                        if preferred_query is not None
                        else LUX_QUERIES
                    )
                    lux, matched_query = read_current_lux(queries)
                if lux is None and preferred_query is not None:
                    fallback_queries = tuple(
                        query for query in LUX_QUERIES
                        if query != preferred_query
                    )
                    lux, matched_query = read_current_lux(
                        fallback_queries
                    )
                if lux is not None:
                    if matched_query is not None:
                        preferred_query = matched_query
                    with state_lock:
                        state["environment"]["lux"] = lux
                        state["collectorTimestamps"]["environment"] = (
                            time.time()
                        )
                    set_capability("ambientLux", "available")
                else:
                    preferred_query = None
                    set_capability("ambientLux", "unsupported")
            except Exception:
                lux = None
                preferred_query = None
                set_capability("ambientLux", "unreadable")
            wait_for_configuration_change(
                LUX_POLL_INTERVAL
                if lux is not None
                else LUX_RETRY_INTERVAL,
                generation,
            )
    except Exception:
        set_capability("ambientLux", "unreadable")
    finally:
        if registry_service is not None and iokit is not None:
            iokit.IOObjectRelease(registry_service)


def read_current_lux(queries=LUX_QUERIES):
    for query in queries:
        process = subprocess.run(
            query,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        matches = re.findall(r'"CurrentLux"\s*=\s*(\d+)', process.stdout)
        if matches:
            return float(matches[-1]), query
    return None, None


def smart_number(value):
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return None
    return None


def poll_storage_smart(smartctl_path: str) -> None:
    while not stop_event.is_set():
        if not app_active or active_section != "storage":
            stop_event.wait(0.25)
            continue
        generation = section_generation
        try:
            process = subprocess.run(
                [smartctl_path, "-a", "-j", "/dev/disk0"],
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
            )
            decoded = json.loads(process.stdout)
            log = decoded.get("nvme_smart_health_information_log", {})
            percentage_used = smart_number(log.get("percentage_used"))
            units_read = smart_number(log.get("data_units_read"))
            units_written = smart_number(log.get("data_units_written"))
            temperature = smart_number(log.get("temperature"))
            smart_status = decoded.get("smart_status", {})
            payload = {
                "available": bool(log),
                "healthPercentage": (
                    max(0.0, min(100.0, 100.0 - percentage_used))
                    if percentage_used is not None
                    else None
                ),
                "percentageUsed": percentage_used,
                "totalBytesRead": (
                    units_read * 512000 if units_read is not None else None
                ),
                "totalBytesWritten": (
                    units_written * 512000 if units_written is not None else None
                ),
                "powerOnHours": smart_number(log.get("power_on_hours")),
                "powerCycles": smart_number(log.get("power_cycles")),
                "unsafeShutdowns": smart_number(log.get("unsafe_shutdowns")),
                "mediaErrors": smart_number(log.get("media_errors")),
                "availableSpare": smart_number(log.get("available_spare")),
                "temperature": temperature,
                "passed": smart_status.get("passed"),
            }
            with state_lock:
                state["storageSmart"] = payload
                state["collectorTimestamps"]["storage"] = time.time()
            if not log and process.stderr.strip():
                append_error(
                    "SMART: " + process.stderr.strip().splitlines()[-1]
                )
        except Exception as exc:
            append_error(f"SMART unavailable: {exc}")
        wait_for_configuration_change(300.0, generation)


def initialize_iokit():
    iokit = ctypes.cdll.LoadLibrary(ctypes.util.find_library("IOKit"))
    core_foundation = ctypes.cdll.LoadLibrary(
        ctypes.util.find_library("CoreFoundation")
    )
    libc = ctypes.cdll.LoadLibrary(ctypes.util.find_library("c"))

    allocator = ctypes.c_void_p.in_dll(
        core_foundation, "kCFAllocatorDefault"
    )
    run_loop_mode = ctypes.c_void_p.in_dll(
        core_foundation, "kCFRunLoopDefaultMode"
    )

    iokit.IOServiceMatching.restype = ctypes.c_void_p
    iokit.IOServiceMatching.argtypes = [ctypes.c_char_p]
    iokit.IOServiceNameMatching.restype = ctypes.c_void_p
    iokit.IOServiceNameMatching.argtypes = [ctypes.c_char_p]
    iokit.IOServiceGetMatchingServices.restype = ctypes.c_int
    iokit.IOServiceGetMatchingServices.argtypes = [
        ctypes.c_uint,
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_uint),
    ]
    iokit.IOIteratorNext.restype = ctypes.c_uint
    iokit.IOIteratorNext.argtypes = [ctypes.c_uint]
    iokit.IOObjectRelease.argtypes = [ctypes.c_uint]
    iokit.IORegistryEntryCreateCFProperty.restype = ctypes.c_void_p
    iokit.IORegistryEntryCreateCFProperty.argtypes = [
        ctypes.c_uint,
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_uint,
    ]
    iokit.IORegistryEntrySearchCFProperty.restype = ctypes.c_void_p
    iokit.IORegistryEntrySearchCFProperty.argtypes = [
        ctypes.c_uint,
        ctypes.c_char_p,
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_uint,
    ]
    iokit.IORegistryEntrySetCFProperty.restype = ctypes.c_int
    iokit.IORegistryEntrySetCFProperty.argtypes = [
        ctypes.c_uint,
        ctypes.c_void_p,
        ctypes.c_void_p,
    ]
    iokit.IOHIDDeviceCreate.restype = ctypes.c_void_p
    iokit.IOHIDDeviceCreate.argtypes = [ctypes.c_void_p, ctypes.c_uint]
    iokit.IOHIDDeviceOpen.restype = ctypes.c_int
    iokit.IOHIDDeviceOpen.argtypes = [ctypes.c_void_p, ctypes.c_int]
    iokit.IOHIDDeviceClose.restype = ctypes.c_int
    iokit.IOHIDDeviceClose.argtypes = [ctypes.c_void_p, ctypes.c_int]
    iokit.IOHIDDeviceGetReport.restype = ctypes.c_int
    iokit.IOHIDDeviceGetReport.argtypes = [
        ctypes.c_void_p,
        ctypes.c_int,
        ctypes.c_long,
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.POINTER(ctypes.c_long),
    ]
    iokit.IOHIDDeviceRegisterInputReportWithTimeStampCallback.restype = None
    iokit.IOHIDDeviceRegisterInputReportWithTimeStampCallback.argtypes = [
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_long,
        ctypes.c_void_p,
        ctypes.c_void_p,
    ]
    iokit.IOHIDDeviceScheduleWithRunLoop.restype = None
    iokit.IOHIDDeviceScheduleWithRunLoop.argtypes = [
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_void_p,
    ]

    core_foundation.CFStringCreateWithCString.restype = ctypes.c_void_p
    core_foundation.CFStringCreateWithCString.argtypes = [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_uint32,
    ]
    core_foundation.CFNumberCreate.restype = ctypes.c_void_p
    core_foundation.CFNumberCreate.argtypes = [
        ctypes.c_void_p,
        ctypes.c_int,
        ctypes.c_void_p,
    ]
    core_foundation.CFNumberGetValue.restype = ctypes.c_bool
    core_foundation.CFNumberGetValue.argtypes = [
        ctypes.c_void_p,
        ctypes.c_int,
        ctypes.c_void_p,
    ]
    core_foundation.CFRunLoopGetCurrent.restype = ctypes.c_void_p
    core_foundation.CFRunLoopRunInMode.restype = ctypes.c_int32
    core_foundation.CFRunLoopRunInMode.argtypes = [
        ctypes.c_void_p,
        ctypes.c_double,
        ctypes.c_bool,
    ]
    core_foundation.CFRelease.argtypes = [ctypes.c_void_p]

    class MachTimebaseInfo(ctypes.Structure):
        _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]

    libc.mach_timebase_info.restype = ctypes.c_int
    libc.mach_timebase_info.argtypes = [ctypes.POINTER(MachTimebaseInfo)]
    timebase = MachTimebaseInfo()
    libc.mach_timebase_info(ctypes.byref(timebase))
    mach_to_seconds = (timebase.numer / timebase.denom) * 1e-9

    def cf_string(value: str):
        return core_foundation.CFStringCreateWithCString(
            None, value.encode("utf-8"), CF_UTF8
        )

    def cf_number32(value: int):
        raw = ctypes.c_int32(value)
        return core_foundation.CFNumberCreate(
            None, CF_SINT32, ctypes.byref(raw)
        )

    def property_integer(service: int, key: str):
        key_ref = cf_string(key)
        value_ref = iokit.IORegistryEntryCreateCFProperty(
            service, key_ref, None, 0
        )
        core_foundation.CFRelease(key_ref)
        if not value_ref:
            return None
        raw = ctypes.c_long()
        ok = core_foundation.CFNumberGetValue(
            value_ref, CF_SINT64, ctypes.byref(raw)
        )
        core_foundation.CFRelease(value_ref)
        return raw.value if ok else None

    return (
        iokit,
        core_foundation,
        allocator,
        run_loop_mode,
        mach_to_seconds,
        cf_string,
        cf_number32,
        property_integer,
    )


def find_lux_registry_service(iokit):
    matching = iokit.IOServiceNameMatching(b"als")
    iterator = ctypes.c_uint()
    if iokit.IOServiceGetMatchingServices(
        0, matching, ctypes.byref(iterator)
    ) != 0:
        return None
    service = iokit.IOIteratorNext(iterator.value)
    if iterator.value:
        iokit.IOObjectRelease(iterator.value)
    return service or None


def read_registry_lux(iokit, core_foundation, service, cf_string):
    if service is None:
        return None
    key_ref = cf_string("CurrentLux")
    value_ref = iokit.IORegistryEntrySearchCFProperty(
        service,
        b"IOService",
        key_ref,
        None,
        1,
    )
    core_foundation.CFRelease(key_ref)
    if not value_ref:
        return None
    raw = ctypes.c_long()
    ok = core_foundation.CFNumberGetValue(
        value_ref, CF_SINT64, ctypes.byref(raw)
    )
    core_foundation.CFRelease(value_ref)
    return float(raw.value) if ok else None


def configure_spu_drivers(
    iokit,
    core_foundation,
    cf_string,
    cf_number32,
    property_integer,
) -> None:
    matching = iokit.IOServiceMatching(b"AppleSPUHIDDriver")
    iterator = ctypes.c_uint()
    iokit.IOServiceGetMatchingServices(0, matching, ctypes.byref(iterator))
    while True:
        service = iokit.IOIteratorNext(iterator.value)
        if not service:
            break
        usage_page = property_integer(service, "PrimaryUsagePage") or 0
        usage = property_integer(service, "PrimaryUsage") or 0
        if (usage_page, usage) in (
            (PAGE_VENDOR, USAGE_ACCEL),
            (PAGE_VENDOR, USAGE_GYRO),
        ):
            report_interval = round(1_000_000 / imu_hardware_rate)
        elif (usage_page, usage) == (PAGE_VENDOR, USAGE_ALS):
            report_interval = (
                REPORT_INTERVAL_US
                if app_active and active_section == "environment"
                else round(1_000_000 / MINIMUM_IMU_HARDWARE_RATE)
            )
        else:
            iokit.IOObjectRelease(service)
            continue
        for key, value in (
            ("SensorPropertyReportingState", 1),
            ("SensorPropertyPowerState", 1),
            ("ReportInterval", report_interval),
        ):
            key_ref = cf_string(key)
            value_ref = cf_number32(value)
            iokit.IORegistryEntrySetCFProperty(
                service, key_ref, value_ref
            )
            core_foundation.CFRelease(key_ref)
            core_foundation.CFRelease(value_ref)
        iokit.IOObjectRelease(service)
    if iterator.value:
        iokit.IOObjectRelease(iterator.value)


def poll_lid_angle() -> None:
    device = None
    iokit = None
    try:
        (
            iokit,
            _core_foundation,
            allocator,
            _run_loop_mode,
            _mach_to_seconds,
            _cf_string,
            _cf_number32,
            property_integer,
        ) = initialize_iokit()

        matching = iokit.IOServiceMatching(b"AppleSPUHIDDevice")
        iterator = ctypes.c_uint()
        iokit.IOServiceGetMatchingServices(
            0, matching, ctypes.byref(iterator)
        )
        while True:
            service = iokit.IOIteratorNext(iterator.value)
            if not service:
                break
            usage_page = property_integer(service, "PrimaryUsagePage") or 0
            usage = property_integer(service, "PrimaryUsage") or 0
            if usage_page == PAGE_SENSOR and usage == USAGE_LID:
                mark_spu_opened("lidAngle")
                device = iokit.IOHIDDeviceCreate(allocator, service)
                iokit.IOObjectRelease(service)
                break
            iokit.IOObjectRelease(service)

        if device is None:
            set_capability("lidAngle", "unsupported")
            return
        if iokit.IOHIDDeviceOpen(device, 0) != 0:
            set_capability("lidAngle", "unreadable")
            return

        report = (ctypes.c_uint8 * 8)()
        while not stop_event.is_set():
            if not app_active or active_section != "environment":
                stop_event.wait(0.25)
                continue
            length = ctypes.c_long(len(report))
            result = iokit.IOHIDDeviceGetReport(
                device,
                IOHID_REPORT_TYPE_FEATURE,
                1,
                report,
                ctypes.byref(length),
            )
            if result == 0 and length.value >= 3:
                angle = (int(report[2]) << 8) | int(report[1])
                if angle <= 0x1FF:
                    with state_lock:
                        state["environment"]["lidAngle"] = float(angle)
                    mark_spu_report("lidAngle")
            stop_event.wait(LID_POLL_INTERVAL)
    except Exception as exc:
        set_capability("lidAngle", "unreadable")
        set_collector_error("lidAngle", f"Lid angle unavailable: {exc}")
    finally:
        if device is not None and iokit is not None:
            iokit.IOHIDDeviceClose(device, 0)


def register_sensors():
    global accel_decimation, gyro_decimation, sample_counter
    global sample_window_start, last_gyro_time, yaw_degrees

    (
        iokit,
        core_foundation,
        allocator,
        run_loop_mode,
        mach_to_seconds,
        cf_string,
        cf_number32,
        property_integer,
    ) = initialize_iokit()

    callback_type = ctypes.CFUNCTYPE(
        None,
        ctypes.c_void_p,
        ctypes.c_int,
        ctypes.c_void_p,
        ctypes.c_int,
        ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_long,
        ctypes.c_uint64,
    )

    def on_accelerometer(
        context, result, sender, report_type, report_id, report, length, timestamp
    ):
        del context, result, sender, report_type, report_id
        global accel_decimation, sample_counter, sample_window_start
        if not app_active or active_section != "motion":
            return
        if length != IMU_REPORT_LEN:
            return
        accel_decimation += 1
        if accel_decimation < imu_decimation:
            return
        accel_decimation = 0

        data = ctypes.string_at(report, length)
        x, y, z = struct.unpack_from("<iii", data, IMU_DATA_OFFSET)
        x /= Q16_SCALE
        y /= Q16_SCALE
        z /= Q16_SCALE
        magnitude = math.sqrt(x * x + y * y + z * z)
        dynamic = abs(magnitude - 1.0)
        motion_energy.append(dynamic)

        now = time.monotonic()
        sample_counter += 1
        elapsed = now - sample_window_start
        rate = None
        if elapsed >= 1.0:
            rate = sample_counter / elapsed
            sample_counter = 0
            sample_window_start = now

        roll = math.degrees(math.atan2(y, z))
        pitch = math.degrees(math.atan2(-x, math.sqrt(y * y + z * z)))
        rms = math.sqrt(
            sum(value * value for value in motion_energy)
            / len(motion_energy)
        )
        peak = max(motion_energy, default=0.0)

        with state_lock:
            state["motion"]["accelerometer"] = {
                "x": x,
                "y": y,
                "z": z,
                "magnitude": magnitude,
                "timestamp": timestamp * mach_to_seconds,
            }
            state["motion"]["orientation"] = {
                "roll": roll,
                "pitch": pitch,
                "yaw": yaw_degrees,
            }
            vibration = state["motion"]["vibration"]
            vibration["rms"] = rms
            vibration["peak"] = peak
            if rate is not None:
                vibration["sampleRate"] = rate
        mark_spu_report("accelerometer")

    def on_gyroscope(
        context, result, sender, report_type, report_id, report, length, timestamp
    ):
        del context, result, sender, report_type, report_id
        global gyro_decimation, last_gyro_time, yaw_degrees
        if not app_active or active_section != "motion":
            return
        if length != IMU_REPORT_LEN:
            return
        gyro_decimation += 1
        if gyro_decimation < imu_decimation:
            return
        gyro_decimation = 0

        data = ctypes.string_at(report, length)
        x, y, z = struct.unpack_from("<iii", data, IMU_DATA_OFFSET)
        x /= Q16_SCALE
        y /= Q16_SCALE
        z /= Q16_SCALE
        report_time = timestamp * mach_to_seconds
        if last_gyro_time is not None:
            delta = max(0.0, min(0.1, report_time - last_gyro_time))
            yaw_degrees = (yaw_degrees + z * delta + 180.0) % 360.0 - 180.0
        last_gyro_time = report_time

        with state_lock:
            state["motion"]["gyroscope"] = {
                "x": x,
                "y": y,
                "z": z,
                "magnitude": math.sqrt(x * x + y * y + z * z),
                "timestamp": report_time,
            }
            orientation = state["motion"].get("orientation")
            if orientation:
                orientation["yaw"] = yaw_degrees
        mark_spu_report("gyroscope")

    def on_ambient_light(
        context, result, sender, report_type, report_id, report, length, timestamp
    ):
        del context, result, sender, report_type, report_id, timestamp
        if not app_active or active_section != "environment":
            return
        if length != ALS_REPORT_LEN:
            return
        data = ctypes.string_at(report, length)
        channels = [struct.unpack_from("<I", data, offset)[0] for offset in (20, 24, 28, 32)]
        intensity = struct.unpack_from("<f", data, 40)[0]
        if not math.isfinite(intensity):
            return
        with state_lock:
            state["environment"]["alsIntensity"] = intensity
            state["environment"]["spectralChannels"] = channels
        mark_spu_report("spectral")

    callbacks = {
        (PAGE_VENDOR, USAGE_ACCEL): callback_type(on_accelerometer),
        (PAGE_VENDOR, USAGE_GYRO): callback_type(on_gyroscope),
        (PAGE_VENDOR, USAGE_ALS): callback_type(on_ambient_light),
    }
    callback_roots.extend(callbacks.values())

    configure_spu_drivers(
        iokit,
        core_foundation,
        cf_string,
        cf_number32,
        property_integer,
    )

    capability_names = {
        (PAGE_VENDOR, USAGE_ACCEL): "accelerometer",
        (PAGE_VENDOR, USAGE_GYRO): "gyroscope",
        (PAGE_VENDOR, USAGE_ALS): "spectral",
    }
    seen = set()
    opened = []
    matching = iokit.IOServiceMatching(b"AppleSPUHIDDevice")
    iterator = ctypes.c_uint()
    iokit.IOServiceGetMatchingServices(0, matching, ctypes.byref(iterator))
    while True:
        service = iokit.IOIteratorNext(iterator.value)
        if not service:
            break
        usage_page = property_integer(service, "PrimaryUsagePage") or 0
        usage = property_integer(service, "PrimaryUsage") or 0
        callback = callbacks.get((usage_page, usage))
        if callback is not None:
            capability = capability_names[(usage_page, usage)]
            seen.add(capability)
            device = iokit.IOHIDDeviceCreate(allocator, service)
            if device and iokit.IOHIDDeviceOpen(device, 0) == 0:
                report_buffer = (ctypes.c_uint8 * REPORT_BUFFER_SIZE)()
                iokit.IOHIDDeviceRegisterInputReportWithTimeStampCallback(
                    device,
                    report_buffer,
                    REPORT_BUFFER_SIZE,
                    callback,
                    None,
                )
                iokit.IOHIDDeviceScheduleWithRunLoop(
                    device,
                    core_foundation.CFRunLoopGetCurrent(),
                    run_loop_mode,
                )
                opened.append((device, report_buffer))
                mark_spu_opened(capability)
            else:
                set_capability(capability, "unreadable")
        iokit.IOObjectRelease(service)

    callback_roots.extend(opened)
    for capability in capability_names.values():
        if capability not in seen:
            set_capability(capability, "unsupported")

    return (
        iokit,
        core_foundation,
        run_loop_mode,
        cf_string,
        cf_number32,
        property_integer,
    )


def run_spu_loop() -> None:
    try:
        (
            iokit,
            core_foundation,
            run_loop_mode,
            cf_string,
            cf_number32,
            property_integer,
        ) = register_sensors()
        spu_ready_event.set()
        last_driver_configuration = None
        while not stop_event.is_set():
            driver_configuration = (
                app_active,
                active_section,
                imu_hardware_rate,
            )
            if driver_configuration != last_driver_configuration:
                configure_spu_drivers(
                    iokit,
                    core_foundation,
                    cf_string,
                    cf_number32,
                    property_integer,
                )
                last_driver_configuration = driver_configuration
            core_foundation.CFRunLoopRunInMode(
                run_loop_mode, 0.05, False
            )
    except Exception as exc:
        append_error(f"SPU initialization failed: {exc}")
        for capability in (
            "accelerometer",
            "gyroscope",
            "spectral",
        ):
            set_capability(capability, "unreadable")
        set_collector_error("spu", f"SPU initialization failed: {exc}")
        spu_ready_event.set()


def monitor_spu_startup(timeout: float = 12.0) -> None:
    if spu_ready_event.wait(timeout):
        return
    for capability in (
        "accelerometer",
        "gyroscope",
        "spectral",
    ):
        set_capability(capability, "unreadable")
    message = "SPU sensor interface did not respond during initialization"
    set_collector_error("spu", message)
    append_error(message)


def monitor_spu_reports(timeout: float = SPU_FIRST_REPORT_TIMEOUT) -> None:
    watched_section = None
    section_started = None
    section_capabilities = {
        "motion": ("accelerometer", "gyroscope"),
        "environment": ("spectral", "lidAngle"),
    }

    while not stop_event.is_set():
        section = active_section if app_active else None
        if section not in section_capabilities:
            watched_section = None
            section_started = None
        elif section != watched_section:
            watched_section = section
            section_started = time.monotonic()
        elif (
            section_started is not None
            and time.monotonic() - section_started >= timeout
        ):
            expire_missing_spu_reports(section_capabilities[section])
        stop_event.wait(0.25)


def handle_signal(signum, frame):
    del signum, frame
    stop_event.set()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--stop", required=True)
    parser.add_argument("--ismc", required=True)
    parser.add_argument("--fan-probe", required=True)
    parser.add_argument("--smartctl", required=True)
    parser.add_argument("--config", required=True)
    args = parser.parse_args()

    if os.geteuid() != 0:
        print("advanced_sensor_helper requires administrator privileges", file=sys.stderr)
        return 2

    try:
        os.unlink(args.stop)
    except FileNotFoundError:
        pass

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)
    initial_config_mtime = load_configuration(args.config)

    telemetry_thread = threading.Thread(
        target=poll_ismc,
        args=(args.ismc, args.fan_probe),
        daemon=True,
    )
    telemetry_thread.start()
    environment_thread = threading.Thread(
        target=poll_environment_lux, daemon=True
    )
    environment_thread.start()
    configuration_thread = threading.Thread(
        target=poll_configuration,
        args=(args.config, initial_config_mtime),
        daemon=True,
    )
    configuration_thread.start()
    smart_thread = threading.Thread(
        target=poll_storage_smart, args=(args.smartctl,), daemon=True
    )
    smart_thread.start()
    lid_thread = threading.Thread(target=poll_lid_angle, daemon=True)
    lid_thread.start()
    spu_thread = threading.Thread(target=run_spu_loop, daemon=True)
    spu_thread.start()
    spu_monitor_thread = threading.Thread(
        target=monitor_spu_startup,
        daemon=True,
    )
    spu_monitor_thread.start()
    spu_report_monitor_thread = threading.Thread(
        target=monitor_spu_reports,
        daemon=True,
    )
    spu_report_monitor_thread.start()

    with state_lock:
        state["status"] = "running"

    last_write = 0.0
    last_written_payload = None
    while not stop_event.is_set():
        if os.path.exists(args.stop):
            stop_event.set()
            break
        loop_interval = (
            ACTIVE_LOOP_INTERVAL
            if app_active and active_section in ("motion", "environment")
            else 0.25
        )
        stop_event.wait(loop_interval)
        now = time.monotonic()
        if not app_active:
            write_interval = 2.0
        elif active_section in ("motion", "environment"):
            write_interval = ACTIVE_SNAPSHOT_INTERVAL
        elif active_section in ("overview", "temperature", "fans"):
            write_interval = 1.0
        elif active_section == "storage":
            write_interval = 2.0
        else:
            write_interval = 2.0
        if now - last_write >= write_interval:
            with state_lock:
                state["timestamp"] = time.time()
                snapshot = snapshot_for_section(active_section)
            comparable_payload = dict(snapshot)
            comparable_payload.pop("timestamp", None)
            if (
                comparable_payload != last_written_payload
                or now - last_write >= SNAPSHOT_HEARTBEAT_INTERVAL
            ):
                atomic_write_json(args.output, snapshot)
                last_written_payload = comparable_payload
                last_write = now

    with state_lock:
        state["status"] = "stopped"
        state["timestamp"] = time.time()
        snapshot = snapshot_for_section(active_section)
    atomic_write_json(args.output, snapshot)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
