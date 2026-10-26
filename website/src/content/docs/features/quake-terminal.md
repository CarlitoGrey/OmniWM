---
title: Quake Terminal
description: Summon an embedded Ghostty terminal or Kitty's quick-access terminal with a single hotkey.
sidebar:
  order: 1
---

OmniWM's Quake terminal can be summoned over any workspace. By default, it runs an embedded terminal built on Ghostty's [libghostty](https://ghostty.org), with multiple tabs and splits within tabs. When building from `main`, you can also choose Kitty's quick-access terminal.

Toggle it with `` Option + ` `` (backtick) by default; the binding is configurable in Settings under Keyboard Shortcuts, alongside the rest of the [keyboard shortcuts](/guides/keyboard-shortcuts/).

## Kitty provider

:::note[Unreleased]
The Kitty provider is available when building from `main`.
:::

Install the Kitty app, then open **Settings → Quake Terminal** and choose **Kitty** in the **Terminal** picker. The same global shortcut toggles a dedicated Kitty quick-access terminal instance.

Kitty's `quick-access-terminal.conf` supplies its configuration, including fonts, tabs, splits and keybindings. In OmniWM's Settings, you can override the panel's placement, auto-hide on focus loss and background opacity. Unset overrides follow Kitty's configuration when a new quick-access process starts. Turning an override off keeps its last applied value in the running process; start a new Kitty quick-access process to restore that setting from Kitty's file. Hiding and showing the panel reuses the current process. Placement changes apply the next time it is shown.

Opacity changes apply live. If the panel was created without transparency support, Settings explains that it needs to be closed and reopened; OmniWM does not restart its shell sessions automatically. See the [Kitty settings reference](/config/settings-reference/#quaketerminalkitty) for TOML keys.

The sections below describe the embedded Ghostty provider and its shortcuts.

## Position and size

Configure Ghostty's embedded terminal in **Settings → Quake Terminal**:

- **Position** — `Top`, `Bottom`, `Left`, `Right`, or `Center`. The default is `Center`, which fades the terminal in place; the four edge positions slide it in from that screen edge.
- **Show On** — which monitor the terminal appears on: `Mouse Cursor's Monitor`, `Focused Window's Monitor` (the default), or `Main Monitor`. `Main Monitor` follows the **Monitor Roles** ranking in **Settings → Displays** when one is set, so you can pin the terminal to a preferred display with a fallback when it is disconnected; without a ranking it is the display with the macOS menu bar. See [Multi-Monitor Setup](/guides/multi-monitor/#monitor-roles).
- **Width / Height** — each 10–100% of the monitor's available screen area in 5% steps; both default to 50%.

You can also adjust the terminal directly with the mouse: drag its edges to resize, and hold `Option` and drag to move it. OmniWM remembers one custom size and position. It reuses that frame when it fits the selected monitor; otherwise it uses the configured position and percentages. A **Reset to Default Position** button appears in Settings once a custom frame is in use.

## Appearance

Quake Terminal loads Ghostty's normal configuration files and their included files, so your font, theme, and other terminal preferences can be shared. OmniWM applies its Quake background opacity and background effect afterward; configure those controls in **Settings → Quake Terminal**.

- **Background Effect** — choose `Standard Blur`, `Regular Glass`, or `Clear Glass`. `Standard Blur` comes with an adjustable blur radius; the native glass effects do not, but switching effects preserves the saved Standard Blur radius so it becomes active again when you return to it.
- **Quake Background Opacity** — 10–100%.

:::tip
Blur only shows through a translucent terminal — lower the opacity to see it.
:::

## Behavior

Command-click an OSC 8 web or email hyperlink printed by a terminal application to open it in the default browser or mail app. Supported schemes are `http`, `https`, and `mailto`; file links and custom application schemes remain blocked. Plain URL detection continues to follow Ghostty's `link-url` setting.

- **Animation Duration** — 0 to 1 second, default 0.2s. Ignored while global animations are disabled.
- **Auto-hide on Focus Loss** — optionally hide the terminal whenever it loses focus.

## Inside-terminal shortcuts

Customize tab and pane shortcuts with Ghostty `keybind` entries in `~/.config/ghostty/config.ghostty` (or your existing Ghostty config). User bindings override the defaults below; `unbind` removes a binding. Reload inside Quake with `Cmd + Shift + ,`, or relaunch OmniWM. The global toggle stays in **Settings → Keyboard Shortcuts** and OmniWM's `settings.toml`.

```ini
keybind = cmd+t=unbind
keybind = ctrl+shift+t=new_tab
keybind = cmd+enter=new_split:right
keybind = cmd+shift+enter=close_surface
```

See [Ghostty's keybinding syntax](https://ghostty.org/docs/config/keybind). Quake supports `new_tab`, `close_tab`, `goto_tab`, `next_tab`, `previous_tab`, `last_tab`, `new_split`, `goto_split`, `close_surface`, and `equalize_splits`, alongside Ghostty's terminal actions such as copy, paste, and font sizing.

| Action | Default Shortcut |
|--------|----------|
| New Tab | `Cmd + T` |
| Close Tab | `Cmd + W` |
| Next Tab | `Cmd + Shift + ]` |
| Previous Tab | `Cmd + Shift + [` |
| Next Tab (Alt) | `Ctrl + Tab` |
| Previous Tab (Alt) | `Ctrl + Shift + Tab` |
| Select Tab 1-9 | `Cmd + 1-9` |
| Split Pane (Horizontal) | `Cmd + D` |
| Split Pane (Vertical) | `Cmd + Shift + D` |
| Close Pane | `Cmd + Shift + W` |
| Equalize Splits | `Cmd + Shift + =` |
| Navigate Pane | `Cmd + Option + Arrow Keys` |
