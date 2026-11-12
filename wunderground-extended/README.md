# Wunderground Extended for Omarchy

An Omarchy 4 / Quickshell port of [plasmoid-wunderground-extended](https://github.com/rliwoch/plasmoid-wunderground-extended).

It provides a compact weather bar item plus a native Omarchy popup with current Personal Weather Station readings, a stationless local Open-Meteo fallback, a 24-hour outlook, a seven-day forecast, sunrise/sunset details, metric/imperial/UK hybrid units, fast observation refresh, and traveling-mode station discovery.

## Install

```bash
omarchy plugin add https://your-git-host.example/wunderground-extended.git --enable
```

For a local checkout:

```bash
ln -sfn "$PWD" ~/.config/omarchy/plugins/wunderground.extended
omarchy plugin validate ~/.config/omarchy/plugins/wunderground.extended
omarchy plugin enable wunderground.extended center
```

Open Omarchy's bar settings and configure:

- `Weather.com API key`: when filled, settings show the case-sensitive Weather Underground station-ID field and current conditions come from that PWS.
- `Open-Meteo location`: when the Weather.com key is empty, settings instead show a city/postcode search field. Leave it empty to use approximate public-IP location.
- `Meteoblue API key`: optional. When present, Meteoblue replaces the default Open-Meteo forecasts.
- Units and refresh intervals.
- Traveling mode, if you want the nearest station selected from public-IP geolocation.

Current PWS observations always use your Weather Underground/Weather.com key. By default, the plugin follows Omarchy's built-in weather approach and uses Open-Meteo for keyless hourly and daily forecasts at the PWS coordinates. If a Meteoblue key is configured, the forecast request instead combines Meteoblue's `basic-1h` and `basic-day` packages in one call; a small keyless Open-Meteo supplement supplies sunrise and sunset because those fields are not included in that Meteoblue package. Keep API keys in local Omarchy settings and do not commit them to a repository.

## Controls

- Left click: open/close the weather panel.
- Middle click: refresh observations and forecasts.
- Right click: open the active PWS dashboard.
- The main view uses a labeled 24-point hourly temperature graph with condition icons beside every temperature.
- The gear beside Refresh opens an in-panel settings page. It switches between the PWS station-ID field and an Open-Meteo location search according to whether the Weather.com key is filled.
- The station header stays compact; use `More` to expand the full PWS measurements above the forecast.
- The compact header includes feels-like and today's forecast high/low; expanded measurements use icon-led rows without cards.
- The current block stacks temperature, feels-like, and high/low values beside the weather icon; `More` is a red underlined link directly below any warning.
- The compact station block always includes its location name; stationless mode identifies the approximate city and region.
- The hourly graph marks the current hour with a dotted vertical `Now` line.
- The main weather icon and condition follow the current hourly forecast entry and advance automatically at each hour instead of using the forecast's midnight entry.
- Hourly temperatures remain labeled, condition icons appear every three hours, and the temperature line uses a low-to-high color gradient.
- Seven-day temperatures use floating, shared-scale gradient min–max bars, with daily rain probability and quantity.
- Hourly rain bars show their forecast quantity directly below the bar and three-hour precipitation probability immediately below the graph.
- Rain bars, quantities, probabilities, and drop symbols use a dedicated blue color; weather-condition icons use semantic colors.
- Sunrise and sunset remain available with either forecast provider.
- Left/right arrows in the popup: switch between Now and 7 days.
- Enter: refresh.
- Escape: close.
- Tab / Shift+Tab: move to adjacent Omarchy panels.

## Compatibility

- Omarchy 4 (`schemaVersion: 1` shell plugin API)
- Quickshell through `omarchy-shell`
- `curl`
- A Weather Underground/Weather.com API key for current PWS readings
- Open-Meteo forecasts require no API key
- A Meteoblue API key is optional and overrides Open-Meteo forecasts

## Attribution and license

This is a clean Omarchy/Quickshell port based on the behavior and data model of Rafal Liwoch's Wunderground Extended KDE plasmoid and Kevin Donnelly's earlier Wunderground plasmoid. It is not affiliated with or endorsed by Weather Underground or The Weather Company.

GPL-2.0-or-later, matching the upstream project. See `LICENSE`.
