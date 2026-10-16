"""Regression checks for temperature sampling while groups are collapsed."""

import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


HELPER_PATH = Path(__file__).resolve().parents[1] / "Resources" / "advanced_sensor_helper.py"
spec = importlib.util.spec_from_file_location("advanced_sensor_helper", HELPER_PATH)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class TemperaturePollingTests(unittest.TestCase):
    def setUp(self):
        helper.stop_event.clear()
        helper.apply_configuration({"appActive": True, "activeSection": "temperature"})

    def tearDown(self):
        helper.stop_event.clear()

    def test_collapsed_groups_continue_to_sample(self):
        calls = []

        def sample(command, **_kwargs):
            calls.append(command[-1])
            payload = {"Temperature": {"CPU": {"value": str(40 + len(calls))}}}
            return subprocess.CompletedProcess(command, 0, json.dumps(payload), "")

        def finish_after_two_samples(_timeout, _generation):
            if len(calls) == 2:
                helper.stop_event.set()

        with patch.object(helper.subprocess, "run", side_effect=sample), patch.object(
            helper, "wait_for_configuration_change", side_effect=finish_after_two_samples
        ):
            helper.poll_ismc("ismc", "fan-probe")

        self.assertEqual(calls, ["temp", "temp"])
        self.assertEqual(helper.state["ismc"]["Temperature"]["CPU"]["value"], "42")

    def test_sampling_stops_when_app_is_inactive(self):
        helper.apply_configuration({"appActive": False, "activeSection": "temperature"})

        def finish_first_wait(_timeout, _generation):
            helper.stop_event.set()

        with patch.object(helper.subprocess, "run") as run, patch.object(
            helper, "wait_for_configuration_change", side_effect=finish_first_wait
        ):
            helper.poll_ismc("ismc", "fan-probe")

        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
