# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import json
import math
import struct

from kittens.tui.handler import result_handler
from kitty.fast_data_types import (
    GLFW_EDGE_NONE,
    GLFW_EDGE_TOP,
    GLFW_FOCUS_ON_DEMAND,
    background_opacity_of,
    change_background_opacity,
    get_options,
    get_os_window_size,
    layer_shell_config_for_os_window,
    set_layer_shell_config,
    toggle_os_window_visibility,
)
from kitty.os_window_size import edge_spacing
from kitty.rc.base import RemoteControlErrorWithoutTraceback
from kitty.types import LayerShellConfig


def reject(message):
    raise RemoteControlErrorWithoutTraceback(message)


def number(value, name):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        reject("Invalid OmniWM Kitty " + name)
    return float(value)


def rectangle(value, name):
    if not isinstance(value, dict) or set(value) != {"x", "y", "width", "height"}:
        reject("Invalid OmniWM Kitty " + name)
    result = {key: number(value[key], name + "." + key) for key in value}
    if result["width"] <= 0 or result["height"] <= 0:
        reject("Empty OmniWM Kitty " + name)
    return result


def request_for(args):
    if len(args) != 2:
        reject("Expected one OmniWM Kitty control request")
    try:
        request = json.loads(args[1])
    except (TypeError, ValueError):
        reject("Invalid OmniWM Kitty control JSON")
    if not isinstance(request, dict) or not {"operation", "settings", "screen"} <= set(request) or set(request) - {
        "operation", "settings", "screen", "barBottom"
    }:
        reject("Invalid OmniWM Kitty control request")
    request.setdefault("barBottom", None)
    if request["operation"] not in ("toggle", "apply"):
        reject("Invalid OmniWM Kitty operation")
    settings = request["settings"]
    if not isinstance(settings, dict) or set(settings) - {"autoHide", "opacity", "placement"}:
        reject("Invalid OmniWM Kitty settings")
    for key in ("autoHide", "opacity", "placement"):
        settings.setdefault(key, None)
    if settings["autoHide"] is not None and not isinstance(settings["autoHide"], bool):
        reject("Invalid OmniWM Kitty auto-hide value")
    if settings["opacity"] is not None:
        opacity = number(settings["opacity"], "opacity")
        if not 0 <= opacity <= 1:
            reject("OmniWM Kitty opacity must be between zero and one")
        settings["opacity"] = opacity
    placement = settings["placement"]
    if placement is not None:
        if not isinstance(placement, dict) or set(placement) != {"position", "widthPercent", "heightPercent"}:
            reject("Invalid OmniWM Kitty placement")
        if placement["position"] not in ("top", "bottom", "left", "right", "center"):
            reject("Invalid OmniWM Kitty position")
        for key in ("widthPercent", "heightPercent"):
            placement[key] = number(placement[key], key)
            if not 0 < placement[key] <= 100:
                reject("OmniWM Kitty dimensions must be above zero and at most one hundred percent")
    screen = request["screen"]
    if not isinstance(screen, dict) or set(screen) != {"frame", "visibleFrame", "scale"}:
        reject("Invalid OmniWM Kitty screen")
    screen["frame"] = rectangle(screen["frame"], "screen frame")
    screen["visibleFrame"] = rectangle(screen["visibleFrame"], "visible frame")
    screen["scale"] = number(screen["scale"], "screen scale")
    if not 0 < screen["scale"] < 24:
        reject("Invalid OmniWM Kitty screen scale")
    if request["barBottom"] is not None:
        request["barBottom"] = number(request["barBottom"], "bar bottom")
    return request


def select_panel(boss):
    panels = []
    for window_id in boss.os_window_map:
        metrics = get_os_window_size(window_id)
        if metrics is not None and metrics["is_layer_shell"]:
            config = layer_shell_config_for_os_window(window_id)
            if config is None:
                reject("Kitty's Quake panel has no native configuration")
            panels.append((window_id, metrics, dict(config)))
    if len(panels) != 1:
        reject("Expected exactly one OmniWM Kitty Quake panel")
    return panels[0]


def integer(value):
    if not math.isfinite(value) or not -(2**31) <= value <= 2**31 - 1:
        reject("OmniWM Kitty geometry is outside native integer bounds")
    return int(value)


def native_dimension(requested, available, spacing, scale):
    content = integer(math.floor(min(requested, available) - spacing))
    if content < 1:
        reject("Kitty's native padding does not fit inside the requested Quake size")
    actual = spacing + math.floor(content * scale) / scale
    if not math.isfinite(actual) or actual <= 0 or actual > available:
        reject("Kitty's Quake size does not fit inside the available screen area")
    return content, actual


def managed_geometry(config, placement, request, xscale, yscale):
    screen = request["screen"]
    visible = screen["visibleFrame"]
    base = screen["frame"] if get_options().macos_use_physical_screen_frame else visible
    left = visible["x"]
    right = left + visible["width"]
    bottom = visible["y"]
    top = bottom + visible["height"]
    if request["barBottom"] is not None:
        top = min(top, request["barBottom"])
    if top <= bottom:
        reject("The OmniShell bar leaves no room for the Kitty Quake panel")
    base_top = base["y"] + base["height"] + 2
    left_min = integer(math.ceil(left - base["x"]))
    top_min = integer(math.ceil(base_top - top))
    available_width = right - base["x"] - left_min
    available_height = base_top - top_min - bottom
    spacing_x = (edge_spacing("left") + edge_spacing("right")) * xscale
    spacing_y = (edge_spacing("top") + edge_spacing("bottom")) * yscale
    if not math.isfinite(spacing_x) or not math.isfinite(spacing_y):
        reject("Invalid Kitty Quake native spacing")
    width, actual_width = native_dimension(
        (right - left) * placement["widthPercent"] / 100, available_width, spacing_x, xscale
    )
    height, actual_height = native_dimension(
        (top - bottom) * placement["heightPercent"] / 100, available_height, spacing_y, yscale
    )
    x = left + (right - left - actual_width) / 2
    y_top = bottom + (top - bottom + actual_height) / 2
    position = placement["position"]
    if position == "left":
        x = left
    elif position == "right":
        x = right - actual_width
    elif position == "top":
        y_top = top
    elif position == "bottom":
        y_top = bottom + actual_height
    left_max = integer(math.floor(right - base["x"] - actual_width))
    top_max = integer(math.floor(base_top - bottom - actual_height))
    if left_max < left_min or top_max < top_min:
        reject("Kitty's Quake panel cannot be aligned inside the available screen area")
    config.update(
        edge=GLFW_EDGE_NONE,
        output_name="",
        x_size_in_cells=0,
        y_size_in_cells=0,
        x_size_in_pixels=width,
        y_size_in_pixels=height,
        requested_left_margin=max(left_min, min(integer(round(x - base["x"])), left_max)),
        requested_top_margin=max(top_min, min(integer(round(base_top - y_top)), top_max)),
        requested_right_margin=0,
        requested_bottom_margin=0,
    )


def state_for(boss, window_id):
    states = getattr(boss, "_omniwm_quake_settings", {})
    return states, dict(states.get(window_id, {}))


def save_state(boss, states, window_id, state):
    states = {key: value for key, value in states.items() if key in boss.os_window_map}
    states[window_id] = state
    boss._omniwm_quake_settings = states


def same_float32(left, right):
    return struct.pack("f", left) == struct.pack("f", right)


def effective_opacity(window_id):
    value = background_opacity_of(window_id)
    if value is None:
        reject("Kitty's Quake panel has no native opacity")
    return value


def apply_opacity(window_id, opacity):
    current = effective_opacity(window_id)
    if same_float32(current, opacity):
        return True, False
    if not change_background_opacity(window_id, opacity):
        reject("Kitty could not change the Quake panel opacity")
    effective = effective_opacity(window_id)
    return same_float32(effective, opacity), not same_float32(effective, current)


def prepare(boss, window_id, current, state, request, include_placement, xscale, yscale, force=False):
    settings = request["settings"]
    config = dict(current)
    placement = settings["placement"] if settings["placement"] is not None else state.get("placement")
    auto_hide = settings["autoHide"] if settings["autoHide"] is not None else state.get("autoHide")
    opacity = settings["opacity"] if settings["opacity"] is not None else state.get("opacity")
    if include_placement:
        if placement is not None:
            managed_geometry(config, placement, request, xscale, yscale)
        elif config["edge"] == GLFW_EDGE_TOP:
            baseline = state.get("nativeTopMargin", config["requested_top_margin"])
            state["nativeTopMargin"] = baseline
            screen = request["screen"]
            base = screen["frame"] if get_options().macos_use_physical_screen_frame else screen["visibleFrame"]
            clearance = 0 if request["barBottom"] is None else math.ceil(
                base["y"] + base["height"] + 2 - request["barBottom"]
            )
            config["requested_top_margin"] = integer(max(baseline, clearance))
    if auto_hide is not None:
        config["hide_on_focus_loss"] = auto_hide
        if auto_hide:
            config["focus_policy"] = GLFW_FOCUS_ON_DEMAND
    opacity_needs_restart = False
    opacity_changed = False
    if opacity is not None:
        applied, opacity_changed = apply_opacity(window_id, opacity)
        opacity_needs_restart = not applied
        if applied:
            state["opacity"] = opacity
            states, _ = state_for(boss, window_id)
            save_state(boss, states, window_id, state)
    if force or config != current or opacity_changed:
        if not set_layer_shell_config(window_id, LayerShellConfig(**config)):
            reject("Kitty rejected the Quake panel configuration")
    if include_placement and placement is not None:
        state["placement"] = placement
    if auto_hide is not None:
        state["autoHide"] = auto_hide
    states, _ = state_for(boss, window_id)
    save_state(boss, states, window_id, state)
    return opacity_needs_restart


def main(args):
    return None


@result_handler(no_ui=True)
def handle_result(args, result, target_window_id, boss):
    request = request_for(args)
    window_id, metrics, current = select_panel(boss)
    _, state = state_for(boss, window_id)
    if request["operation"] == "toggle" and toggle_os_window_visibility(window_id, False):
        return json.dumps({"opacityNeedsRestart": False})
    show = request["operation"] == "toggle"
    scale = request["screen"]["scale"]
    needs_restart = prepare(boss, window_id, current, state, request, show, scale, scale)
    if show:
        if not toggle_os_window_visibility(window_id, True, move_to_active_screen=True):
            reject("Kitty could not show its Quake panel")
        try:
            metrics = get_os_window_size(window_id)
            current = layer_shell_config_for_os_window(window_id)
            if metrics is None or current is None:
                reject("Kitty's Quake panel disappeared while showing")
            _, state = state_for(boss, window_id)
            xscale = number(metrics["xscale"], "native x scale")
            yscale = number(metrics["yscale"], "native y scale")
            if xscale <= 0 or yscale <= 0:
                reject("Invalid native Kitty Quake scale")
            needs_restart = prepare(boss, window_id, dict(current), state, request, True, xscale, yscale, force=True)
        except Exception:
            toggle_os_window_visibility(window_id, False)
            raise
    return json.dumps({"opacityNeedsRestart": bool(needs_restart)})
