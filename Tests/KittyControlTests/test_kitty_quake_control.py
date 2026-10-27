# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import copy
import importlib.util
import json
import math
import pathlib
import struct
import sys
import types
import unittest
from collections import namedtuple
from unittest.mock import patch


CONFIG_FIELDS = (
    "type edge focus_policy output_name x_size_in_pixels y_size_in_pixels "
    "x_size_in_cells y_size_in_cells requested_top_margin requested_left_margin "
    "requested_bottom_margin requested_right_margin requested_exclusive_zone "
    "override_exclusive_zone hide_on_focus_loss"
)
LayerShellConfig = namedtuple("LayerShellConfig", CONFIG_FIELDS)
HELPER_PATH = pathlib.Path(__file__).resolve().parents[2] / "Sources/OmniWM/Resources/kitty-quake-control.py"


class NativeError(Exception):
    pass


def float32(value):
    return struct.unpack("f", struct.pack("f", value))[0]


class NativeKitty:
    def __init__(self):
        self.options = types.SimpleNamespace(
            dynamic_background_opacity=True,
            macos_use_physical_screen_frame=True,
        )
        self.metrics = {
            5: {"is_layer_shell": False, "xscale": 2.0, "yscale": 2.0},
            9: {"is_layer_shell": True, "xscale": 2.0, "yscale": 2.0},
        }
        self.configs = {
            9: LayerShellConfig(4, 1, 0, "Old screen", 800, 400, 0, 0, 8, 0, 0, 0, -1, False, False)._asdict()
        }
        self.visibility = {5: True, 9: False}
        self.opacity = {9: 1.0}
        self.supports_transparency = {9: True}
        self.os_forces_opaque = {9: False}
        self.reject_opacity = False
        self.spacing = {"left": 2.0, "right": 4.0, "top": 3.0, "bottom": 7.0}
        self.events = []
        self.setter_calls = 0
        self.reject_setter_call = None
        self.after_show_scale = None
        self.fail_show = False
        self.boss = types.SimpleNamespace(os_window_map={5: object(), 9: object()})

    def effective_opacity(self, window_id):
        if window_id not in self.opacity:
            return None
        if not self.supports_transparency[window_id] or self.os_forces_opaque[window_id]:
            return 1.0
        return float32(self.opacity[window_id])

    def change_opacity(self, window_id, opacity):
        self.events.append(("opacity", window_id, opacity))
        if window_id not in self.opacity or self.reject_opacity:
            return False
        self.opacity[window_id] = opacity
        return True

    def set_config(self, window_id, config):
        self.setter_calls += 1
        self.events.append(("config", window_id, config, self.effective_opacity(window_id)))
        if self.setter_calls == self.reject_setter_call:
            return False
        self.configs[window_id] = config._asdict()
        return True

    def set_visibility(self, window_id, visible, move_to_active_screen=False):
        self.events.append(("visibility", window_id, visible, move_to_active_screen))
        if window_id not in self.metrics or self.visibility[window_id] == visible:
            return False
        if visible and self.fail_show:
            return False
        self.visibility[window_id] = visible
        if visible and self.after_show_scale is not None:
            self.metrics[window_id]["xscale"] = self.after_show_scale
            self.metrics[window_id]["yscale"] = self.after_show_scale
        return True

    def modules(self):
        modules = {name: types.ModuleType(name) for name in (
            "kittens", "kittens.tui", "kittens.tui.handler", "kitty", "kitty.fast_data_types",
            "kitty.os_window_size", "kitty.rc", "kitty.rc.base", "kitty.types",
        )}

        def result_handler(no_ui=False):
            def decorate(function):
                function.no_ui = no_ui
                return function
            return decorate

        modules["kittens.tui.handler"].result_handler = result_handler
        native = modules["kitty.fast_data_types"]
        native.GLFW_EDGE_NONE = 0
        native.GLFW_EDGE_TOP = 1
        native.GLFW_FOCUS_ON_DEMAND = 2
        native.background_opacity_of = self.effective_opacity
        native.change_background_opacity = self.change_opacity
        native.get_options = lambda: self.options
        native.get_os_window_size = self.metrics.get
        native.layer_shell_config_for_os_window = lambda window_id: copy.copy(self.configs.get(window_id))
        native.set_layer_shell_config = self.set_config
        native.toggle_os_window_visibility = self.set_visibility
        modules["kitty.os_window_size"].edge_spacing = self.spacing.__getitem__
        modules["kitty.rc.base"].RemoteControlErrorWithoutTraceback = NativeError
        modules["kitty.types"].LayerShellConfig = LayerShellConfig
        return modules

    def load(self):
        with patch.dict(sys.modules, self.modules()):
            spec = importlib.util.spec_from_file_location("omniwm_kitty_control", HELPER_PATH)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module

    def outer_rectangle(self, request):
        config = self.configs[9]
        screen = request["screen"]
        base = screen["frame"] if self.options.macos_use_physical_screen_frame else screen["visibleFrame"]
        xscale = self.metrics[9]["xscale"]
        yscale = self.metrics[9]["yscale"]
        width = (self.spacing["left"] + self.spacing["right"]) * xscale
        width += math.floor(config["x_size_in_pixels"] * xscale) / xscale
        height = (self.spacing["top"] + self.spacing["bottom"]) * yscale
        height += math.floor(config["y_size_in_pixels"] * yscale) / yscale
        left = base["x"] + config["requested_left_margin"]
        top = base["y"] + base["height"] + 2 - config["requested_top_margin"]
        return left, top - height, width, height


def request(operation="toggle", position="top", width=60, height=40, auto_hide=None, opacity=None):
    placement = None if position is None else {
        "position": position, "widthPercent": width, "heightPercent": height,
    }
    return {
        "operation": operation,
        "settings": {"autoHide": auto_hide, "opacity": opacity, "placement": placement},
        "screen": {
            "frame": {"x": -1600, "y": -200, "width": 1600, "height": 1000},
            "visibleFrame": {"x": -1600, "y": -160, "width": 1600, "height": 930},
            "scale": 2,
        },
        "barBottom": 744,
    }


class KittyQuakeControlTests(unittest.TestCase):
    def setUp(self):
        self.native = NativeKitty()
        self.helper = self.native.load()

    def invoke(self, value):
        result = self.helper.handle_result([str(HELPER_PATH), json.dumps(value)], None, 99, self.native.boss)
        self.assertIsInstance(result, str)
        self.assertLess(len(result), 64)
        return json.loads(result)

    def test_five_positions_use_outer_size_below_bar_with_retina_padding(self):
        expected = {
            "top": (-1280, 383, 960, 361),
            "bottom": (-1280, -160, 960, 361),
            "left": (-1600, 111, 960, 361),
            "right": (-960, 111, 960, 361),
            "center": (-1280, 111, 960, 361),
        }
        for position, rectangle in expected.items():
            with self.subTest(position=position):
                self.setUp()
                value = request(position=position)
                self.assertEqual(self.invoke(value), {"opacityNeedsRestart": False})
                self.assertEqual(self.native.outer_rectangle(value), rectangle)
                config = self.native.configs[9]
                self.assertEqual(config["edge"], 0)
                self.assertEqual(config["output_name"], "")
                self.assertEqual((config["x_size_in_cells"], config["y_size_in_cells"]), (0, 0))
                self.assertEqual((config["x_size_in_pixels"], config["y_size_in_pixels"]), (948, 341))
                self.assertTrue(self.native.visibility[9])
                self.assertTrue(self.native.visibility[5])

    def test_full_size_fits_inside_visible_frame_for_both_native_base_policies(self):
        for physical in (True, False):
            with self.subTest(physical=physical):
                self.setUp()
                self.native.options.macos_use_physical_screen_frame = physical
                value = request(position="bottom", width=100, height=100)
                self.invoke(value)
                self.assertEqual(self.native.outer_rectangle(value), (-1600, -160, 1600, 904))

    def test_visible_toggle_hides_immediately_without_acknowledging_incoming_settings(self):
        self.native.visibility[9] = True
        self.native.options.dynamic_background_opacity = False
        self.assertEqual(self.invoke(request(auto_hide=True, opacity=0.5)), {"opacityNeedsRestart": False})
        self.assertEqual(self.native.events, [("visibility", 9, False, False)])
        self.assertFalse(self.native.visibility[9])
        self.assertFalse(hasattr(self.native.boss, "_omniwm_quake_settings"))

    def test_hidden_toggle_refreshes_using_native_scale_after_show(self):
        self.native.metrics[9].update(xscale=1.0, yscale=1.0)
        self.native.after_show_scale = 2.0
        value = request()
        self.invoke(value)
        self.assertEqual([event[0] for event in self.native.events], ["visibility", "config", "visibility", "config"])
        self.assertEqual(self.native.events[2], ("visibility", 9, True, True))
        self.assertEqual(self.native.outer_rectangle(value), (-1280, 383, 960, 361))

    def test_apply_changes_only_auto_hide_and_opacity_without_showing_or_moving(self):
        before = dict(self.native.configs[9])
        self.native.visibility[9] = True
        self.invoke(request(operation="apply", position="right", auto_hide=True, opacity=0.6))
        changed = self.native.configs[9]
        for key, value in before.items():
            if key not in ("hide_on_focus_loss", "focus_policy"):
                self.assertEqual(changed[key], value)
        self.assertTrue(changed["hide_on_focus_loss"])
        self.assertEqual(changed["focus_policy"], 2)
        self.assertEqual(self.native.opacity[9], 0.6)
        self.assertFalse(any(event[0] == "visibility" for event in self.native.events))
        self.assertNotIn("placement", self.native.boss._omniwm_quake_settings[9])
        self.assertEqual([event[0] for event in self.native.events], ["opacity", "config"])

    def test_deduplicates_native_config_and_float32_opacity(self):
        self.invoke(request(operation="apply", position=None, auto_hide=False, opacity=0.6))
        self.native.events.clear()
        self.native.opacity[9] = 0.6000000238418579
        self.invoke(request(operation="apply", position=None, auto_hide=False, opacity=0.6))
        self.assertEqual(self.native.events, [])

    def test_nil_settings_retain_acknowledged_policy_across_helper_reload(self):
        self.invoke(request(position="right", auto_hide=True, opacity=0.6))
        self.invoke(request())
        self.helper = self.native.load()
        value = request(position=None)
        value["screen"]["frame"]["x"] = 0
        value["screen"]["visibleFrame"]["x"] = 0
        self.invoke(value)
        self.assertEqual(self.native.outer_rectangle(value), (640, 111, 960, 361))
        self.assertTrue(self.native.configs[9]["hide_on_focus_loss"])
        self.assertEqual(self.native.opacity[9], 0.6)
        self.assertEqual(self.native.boss._omniwm_quake_settings[9]["placement"]["position"], "right")

    def test_new_native_instance_has_no_acknowledged_overrides(self):
        self.invoke(request(auto_hide=True, opacity=0.5))
        self.setUp()
        self.invoke(request(position=None))
        state = self.native.boss._omniwm_quake_settings[9]
        self.assertNotIn("placement", state)
        self.assertNotIn("autoHide", state)
        self.assertNotIn("opacity", state)

    def test_omitted_optional_keys_are_equivalent_to_null(self):
        value = request()
        value["settings"] = {}
        value.pop("barBottom")
        self.assertEqual(self.invoke(value), {"opacityNeedsRestart": False})
        self.assertEqual(self.native.configs[9]["requested_top_margin"], 8)
        self.assertNotIn("placement", self.native.boss._omniwm_quake_settings[9])
        self.assertTrue(self.native.visibility[9])

    def test_native_mode_preserves_original_margin_without_accumulation(self):
        self.invoke(request(position=None))
        self.assertEqual(self.native.configs[9]["requested_top_margin"], 58)
        self.invoke(request(position=None))
        value = request(position=None)
        value["barBottom"] = None
        self.invoke(value)
        self.assertEqual(self.native.configs[9]["requested_top_margin"], 8)

    def test_native_mode_does_not_reinterpret_non_top_edges(self):
        self.native.configs[9]["edge"] = 3
        self.invoke(request(position=None))
        self.assertEqual(self.native.configs[9]["edge"], 3)
        self.assertEqual(self.native.configs[9]["requested_top_margin"], 8)

    def test_missing_or_ambiguous_panel_rejects_without_mutating_regular_windows(self):
        for mode in ("missing", "ambiguous", "no-config"):
            with self.subTest(mode=mode):
                self.setUp()
                if mode == "missing":
                    self.native.metrics[9]["is_layer_shell"] = False
                elif mode == "ambiguous":
                    self.native.metrics[5]["is_layer_shell"] = True
                    self.native.configs[5] = dict(self.native.configs[9])
                else:
                    self.native.configs.pop(9)
                with self.assertRaises(NativeError):
                    self.invoke(request())
                self.assertEqual(self.native.events, [])

    def test_rejected_native_config_is_an_error_and_does_not_acknowledge_settings(self):
        self.native.reject_setter_call = 1
        with self.assertRaises(NativeError):
            self.invoke(request(auto_hide=True))
        self.assertFalse(self.native.visibility[9])
        self.assertFalse(hasattr(self.native.boss, "_omniwm_quake_settings"))
        self.assertFalse(any(event[0] == "visibility" and event[2] for event in self.native.events))

    def test_rejected_final_refresh_hides_panel_and_reports_error(self):
        self.native.reject_setter_call = 2
        with self.assertRaises(NativeError):
            self.invoke(request())
        self.assertFalse(self.native.visibility[9])
        self.assertEqual(self.native.events[-1], ("visibility", 9, False, False))

    def test_failed_native_show_reports_error(self):
        self.native.fail_show = True
        with self.assertRaises(NativeError):
            self.invoke(request())
        self.assertFalse(self.native.visibility[9])
        self.assertEqual(self.native.setter_calls, 1)

    def test_existing_transparent_panel_changes_opacity_live_without_dynamic_flag(self):
        self.native.options.dynamic_background_opacity = False
        self.native.opacity[9] = 0.85
        self.native.visibility[9] = True
        for value in (0.75, 0.25, 1.0, 0.0):
            with self.subTest(value=value):
                self.native.events.clear()
                result = self.invoke(request(operation="apply", position=None, opacity=value))
                self.assertEqual(result, {"opacityNeedsRestart": False})
                self.assertEqual(self.native.effective_opacity(9), float32(value))
                self.assertEqual(self.native.boss._omniwm_quake_settings[9]["opacity"], value)
                self.assertEqual([event[0] for event in self.native.events], ["opacity", "config"])
                self.assertEqual(self.native.events[1][3], float32(value))
                self.assertTrue(self.native.visibility[9])

    def test_opaque_panel_reports_restart_without_false_ack_and_keeps_other_controls(self):
        self.native.supports_transparency[9] = False
        value = request(auto_hide=True, opacity=0.55)
        self.assertEqual(self.invoke(value), {"opacityNeedsRestart": True})
        self.assertEqual(self.native.outer_rectangle(value), (-1280, 383, 960, 361))
        self.assertTrue(self.native.configs[9]["hide_on_focus_loss"])
        self.assertTrue(self.native.visibility[9])
        self.assertEqual(self.native.effective_opacity(9), 1)
        self.assertNotIn("opacity", self.native.boss._omniwm_quake_settings[9])
        self.assertTrue(self.native.boss._omniwm_quake_settings[9]["autoHide"])

    def test_os_forced_opacity_keeps_the_previous_acknowledged_value(self):
        self.invoke(request(operation="apply", position=None, opacity=0.6))
        self.native.os_forces_opaque[9] = True
        result = self.invoke(request(operation="apply", position=None, opacity=0.3))
        self.assertEqual(result, {"opacityNeedsRestart": True})
        self.assertEqual(self.native.boss._omniwm_quake_settings[9]["opacity"], 0.6)

    def test_rejected_native_opacity_is_an_error_without_acknowledgement(self):
        self.native.reject_opacity = True
        with self.assertRaises(NativeError):
            self.invoke(request(operation="apply", position=None, opacity=0.5))
        state = getattr(self.native.boss, "_omniwm_quake_settings", {}).get(9, {})
        self.assertNotIn("opacity", state)
        self.assertFalse(any(event[0] == "config" for event in self.native.events))

    def test_matching_effective_opacity_needs_no_native_calls_even_on_opaque_panels(self):
        self.native.opacity[9] = 0.85
        value = request(operation="apply", position=None, opacity=0.85)
        self.assertEqual(self.invoke(value), {"opacityNeedsRestart": False})
        self.assertEqual(self.native.events, [])
        self.native.supports_transparency[9] = False
        value = request(operation="apply", position=None, opacity=1.0)
        self.assertEqual(self.invoke(value), {"opacityNeedsRestart": False})
        self.assertEqual(self.native.events, [])

    def test_invalid_requests_reject_before_native_effects(self):
        bad_requests = []
        for path, value in (
            (("operation",), "show"),
            (("settings", "autoHide"), 1),
            (("settings", "opacity"), float("nan")),
            (("settings", "opacity"), 1.1),
            (("settings", "placement", "widthPercent"), 0),
            (("settings", "placement", "heightPercent"), 101),
            (("settings", "placement", "position"), "floating"),
            (("screen", "scale"), 0),
            (("screen", "visibleFrame", "width"), -1),
            (("barBottom",), float("inf")),
        ):
            value_request = request()
            target = value_request
            for key in path[:-1]:
                target = target[key]
            target[path[-1]] = value
            bad_requests.append(value_request)
        for value_request in bad_requests:
            with self.subTest(value=value_request):
                with self.assertRaises(NativeError):
                    self.invoke(value_request)
        self.assertEqual(self.native.events, [])

    def test_invalid_json_and_extra_fields_reject(self):
        for args in ([str(HELPER_PATH)], [str(HELPER_PATH), "{"], [str(HELPER_PATH), "null"]):
            with self.assertRaises(NativeError):
                self.helper.handle_result(args, None, 99, self.native.boss)
        value = request()
        value["settings"]["extra"] = True
        with self.assertRaises(NativeError):
            self.invoke(value)
        self.assertEqual(self.native.events, [])

    def test_impossible_bar_or_padding_rejects_instead_of_claiming_success(self):
        for mode in ("bar", "padding"):
            with self.subTest(mode=mode):
                self.setUp()
                value = request()
                if mode == "bar":
                    value["barBottom"] = -160
                else:
                    self.native.spacing["left"] = 1000
                with self.assertRaises(NativeError):
                    self.invoke(value)
                self.assertFalse(self.native.visibility[9])
                self.assertEqual(self.native.setter_calls, 0)

    def test_handler_is_declared_no_ui(self):
        self.assertTrue(self.helper.handle_result.no_ui)


if __name__ == "__main__":
    unittest.main()
