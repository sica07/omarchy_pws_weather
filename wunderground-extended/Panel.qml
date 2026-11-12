import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "WeatherModel.js" as WeatherModel

Panel {
  id: root
  moduleName: "wunderground.extended"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property int activeTab: 0
  property bool loading: false
  property bool forecastLoading: false
  property bool showStationDetails: false
  property bool showSettingsPage: false
  property string draftStationId: ""
  property string draftApiKey: ""
  property string draftMeteoblueApiKey: ""
  property string draftOpenMeteoLocation: ""
  property string draftUnits: "metric"
  property bool settingsSaving: false
  property string settingsError: ""
  property string errorMessage: ""
  property var current: null
  property var hourly: []
  property var daily: []
  property var dailySupplement: []
  readonly property var threeHourly: WeatherModel.threeHourForecast(hourly)
  readonly property var dailyTemperatureRange: WeatherModel.dailyTemperatureRange(daily)
  readonly property string weatherWarning: WeatherModel.weatherWarning(current, hourly, unitsName)
  readonly property var firstDaily: daily.length > 0 ? daily[0] : null
  property string activeStationId: ""
  property string stationName: ""
  property string condition: ""
  property int iconCode: 44
  property double latitude: NaN
  property double longitude: NaN
  property bool initialized: false
  property bool fallbackLocated: false
  property var travelCandidates: []
  property int travelCandidateIndex: -1

  readonly property string configuredStationId: WeatherModel.trim(setting("stationId", ""))
  readonly property string apiKey: WeatherModel.trim(setting("apiKey", ""))
  readonly property string meteoblueApiKey: WeatherModel.trim(setting("meteoblueApiKey", ""))
  readonly property string configuredOpenMeteoLocation: WeatherModel.trim(setting("openMeteoLocation", ""))
  readonly property string configuredOpenMeteoLatitudeRaw: WeatherModel.trim(setting("openMeteoLatitude", ""))
  readonly property string configuredOpenMeteoLongitudeRaw: WeatherModel.trim(setting("openMeteoLongitude", ""))
  readonly property double configuredOpenMeteoLatitude: configuredOpenMeteoLatitudeRaw === "" ? NaN : Number(configuredOpenMeteoLatitudeRaw)
  readonly property double configuredOpenMeteoLongitude: configuredOpenMeteoLongitudeRaw === "" ? NaN : Number(configuredOpenMeteoLongitudeRaw)
  readonly property string unitsName: String(setting("units", "metric"))
  readonly property string unitsCode: WeatherModel.unitCode(unitsName)
  readonly property var unit: WeatherModel.unitLabels(unitsName)
  readonly property int refreshSeconds: Math.max(15, Number(setting("refreshSeconds", 60)) || 60)
  readonly property int forecastMinutes: Math.max(5, Number(setting("forecastMinutes", 30)) || 30)
  readonly property bool travelMode: setting("travelMode", false) === true
  readonly property bool openMeteoFallback: apiKey === ""
  readonly property bool showConditions: setting("showConditions", false) === true
  readonly property string glyph: WeatherModel.weatherGlyph(iconCode)
  readonly property color currentWeatherColor: WeatherModel.weatherColor(iconCode)
  readonly property color rainColor: "#55aef0"
  readonly property string temperature: current ? WeatherModel.fixed(current.temp, 0) + unit.temperature : "—"
  readonly property string barLabel: glyph + " " + temperature + (showConditions && condition ? "  " + condition : "")
  readonly property string barTooltip: errorMessage || ([stationName || activeStationId, condition, current ? "Feels " + WeatherModel.fixed(current.heatIndex !== undefined ? current.heatIndex : current.windChill, 0) + unit.temperature : ""].filter(function(value) { return value }).join(" · "))

  onConfiguredStationIdChanged: Qt.callLater(function() { root.fallbackLocated = false; root.refresh(true) })
  onApiKeyChanged: Qt.callLater(function() { root.fallbackLocated = false; root.refresh(true) })
  onMeteoblueApiKeyChanged: Qt.callLater(function() { root.refresh(true) })
  onUnitsNameChanged: Qt.callLater(function() { root.refresh(true) })
  onTravelModeChanged: Qt.callLater(function() { root.fallbackLocated = false; root.refresh(true) })

  function open() {
    controller.show()
    if (!initialized) refresh(true)
  }

  function close() { controller.hide() }
  function toggle() { if (opened) close(); else open() }
  function closeForPopoutSwitch() { close() }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function openSettingsPage() {
    draftStationId = configuredStationId
    draftApiKey = apiKey
    draftMeteoblueApiKey = meteoblueApiKey
    draftOpenMeteoLocation = configuredOpenMeteoLocation
    draftUnits = ["metric", "imperial", "uk_hybrid"].indexOf(unitsName) >= 0 ? unitsName : "metric"
    settingsError = ""
    settingsSaving = false
    showSettingsPage = true
  }

  function saveSettingsPage() {
    settingsError = ""
    var locationQuery = WeatherModel.trim(draftOpenMeteoLocation)
    if (WeatherModel.trim(draftApiKey) === "" && locationQuery !== ""
        && (locationQuery !== configuredOpenMeteoLocation || isNaN(configuredOpenMeteoLatitude) || isNaN(configuredOpenMeteoLongitude))) {
      settingsSaving = true
      run(geocodingProcess, openMeteoGeocodingUrl({ name: locationQuery, count: 1, language: "en", format: "json" }), "", true)
      return
    }
    persistSettings(null)
  }

  function persistSettings(locationResult) {
    var next = {}
    Object.keys(settings || {}).forEach(function(key) { next[key] = settings[key] })
    next.stationId = WeatherModel.trim(draftStationId)
    next.apiKey = WeatherModel.trim(draftApiKey)
    next.meteoblueApiKey = WeatherModel.trim(draftMeteoblueApiKey)
    next.units = draftUnits
    if (next.apiKey === "") {
      if (locationResult) {
        next.openMeteoLocation = locationResult.name
        next.openMeteoLatitude = String(locationResult.latitude)
        next.openMeteoLongitude = String(locationResult.longitude)
      } else if (WeatherModel.trim(draftOpenMeteoLocation) === "") {
        next.openMeteoLocation = ""
        next.openMeteoLatitude = ""
        next.openMeteoLongitude = ""
      }
    }
    settings = next
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, next)
    showSettingsPage = false
    settingsSaving = false
    fallbackLocated = false
    Qt.callLater(function() { root.refresh(true) })
  }

  function settingValue(key, fallback) {
    if (!settings || typeof settings !== "object") return fallback
    return key in settings && settings[key] !== undefined && settings[key] !== null ? settings[key] : fallback
  }

  function updateHourlyCondition() {
    var currentForecast = WeatherModel.currentHourlyForecast(hourly, new Date())
    if (!currentForecast) return
    condition = currentForecast.phrase
    iconCode = currentForecast.iconCode
  }

  function buildUrl(base, path, query) {
    var args = []
    Object.keys(query).forEach(function(key) {
      if (query[key] !== undefined && query[key] !== null && String(query[key]) !== "")
        args.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(query[key])))
    })
    return base + path + "?" + args.join("&")
  }

  function apiUrl(path, query) {
    return buildUrl("https://api.weather.com", path, query)
  }

  function meteoblueUrl(query) {
    return buildUrl("https://my.meteoblue.com", "/packages/basic-1h_basic-day", query)
  }

  function openMeteoUrl(query) {
    return buildUrl("https://api.open-meteo.com", "/v1/forecast", query)
  }

  function openMeteoGeocodingUrl(query) {
    return buildUrl("https://geocoding-api.open-meteo.com", "/v1/search", query)
  }

  function run(process, url, origin, allowErrorBody) {
    if (process.running) process.running = false
    var command = ["curl", allowErrorBody === true ? "-sS" : "-fsS", "--compressed", "--max-time", "12"]
    var requestOrigin = origin === undefined ? "https://www.wunderground.com" : origin
    if (requestOrigin) command.push("--header", "Origin: " + requestOrigin)
    command.push(url)
    process.command = command
    process.running = true
  }

  function refresh(includeForecast) {
    initialized = true
    errorMessage = ""
    if (openMeteoFallback) {
      activeStationId = ""
      loading = true
      if (fallbackLocated && includeForecast !== true && current !== null
          && !isNaN(latitude) && !isNaN(longitude)) {
        fetchOpenMeteoCurrent()
        return
      }
      if (fallbackLocated && !isNaN(latitude) && !isNaN(longitude)) fetchForecasts()
      else if (!isNaN(configuredOpenMeteoLatitude) && !isNaN(configuredOpenMeteoLongitude)) {
        latitude = configuredOpenMeteoLatitude
        longitude = configuredOpenMeteoLongitude
        stationName = configuredOpenMeteoLocation || "Open-Meteo location"
        fallbackLocated = true
        fetchForecasts()
      }
      else {
        current = null
        stationName = ""
        run(ipProcess, "https://ipinfo.io/json")
      }
      return
    }
    if (!apiKey) {
      loading = false
      forecastLoading = false
      errorMessage = "Add your Weather.com API key in this widget's settings."
      return
    }
    loading = true
    if (travelMode) run(ipProcess, "https://ipinfo.io/json")
    else {
      activeStationId = configuredStationId
      if (!activeStationId) {
        loading = false
        errorMessage = "Add a Weather Underground station ID in Weather settings."
        return
      }
      fetchCurrent(includeForecast)
    }
  }

  function fetchCurrent(includeForecast) {
    currentProcess.fetchForecastAfter = includeForecast === true
    currentProcess.noObservation = false
    run(currentProcess, apiUrl("/v2/pws/observations/current", {
      stationId: activeStationId,
      format: "json",
      units: unitsCode,
      numericPrecision: "decimal",
      apiKey: apiKey
    }))
  }

  function tryNextTravelStation() {
    travelCandidateIndex += 1
    if (travelCandidateIndex >= travelCandidates.length) {
      fail("No active personal weather station was found nearby.")
      return false
    }
    var candidate = travelCandidates[travelCandidateIndex]
    activeStationId = candidate.id
    stationName = candidate.name
    fetchCurrent(true)
    return true
  }

  function fetchForecasts() {
    if (isNaN(latitude) || isNaN(longitude)) return
    if (!openMeteoFallback) {
      run(conditionsProcess, apiUrl("/v3/wx/observations/current", { geocode: latitude + "," + longitude, apiKey: apiKey, language: "en-US", units: unitsCode, format: "json" }))
      run(identityProcess, apiUrl("/v2/pwsidentity", { stationId: activeStationId, apiKey: apiKey, format: "json", units: unitsCode }))
    }
    forecastLoading = true
    if (meteoblueApiKey) {
      forecastProcess.provider = "Meteoblue"
      dailySupplement = []
      if (openMeteoFallback) fetchOpenMeteoCurrent()
      run(forecastProcess, meteoblueUrl({
        lat: latitude,
        lon: longitude,
        apikey: meteoblueApiKey
      }), "", true)
      run(astronomyProcess, openMeteoUrl({
        latitude: latitude,
        longitude: longitude,
        daily: "sunrise,sunset,precipitation_sum",
        forecast_days: 7,
        timezone: "auto"
      }), "", true)
    } else {
      forecastProcess.provider = "Open-Meteo"
      dailySupplement = []
      run(forecastProcess, openMeteoUrl({
        latitude: latitude,
        longitude: longitude,
        current: "temperature_2m,apparent_temperature,relative_humidity_2m,dew_point_2m,precipitation,weather_code,wind_speed_10m,wind_gusts_10m,pressure_msl,uv_index,is_day",
        hourly: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation_probability,precipitation,weather_code,wind_speed_10m,pressure_msl,uv_index,cloud_cover,is_day",
        daily: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_speed_10m_max,sunrise,sunset",
        forecast_hours: 24,
        forecast_days: 7,
        timezone: "auto"
      }), "", true)
    }
  }

  function fetchOpenMeteoCurrent() {
    if (isNaN(latitude) || isNaN(longitude)) return
    loading = true
    run(fallbackCurrentProcess, openMeteoUrl({
      latitude: latitude,
      longitude: longitude,
      current: "temperature_2m,apparent_temperature,relative_humidity_2m,dew_point_2m,precipitation,weather_code,wind_speed_10m,wind_gusts_10m,pressure_msl,uv_index,is_day",
      timezone: "auto"
    }), "", true)
  }

  function fail(message) {
    loading = false
    forecastLoading = false
    errorMessage = message
  }

  function openStationDashboard() {
    if (activeStationId) Quickshell.execDetached(["xdg-open", "https://www.wunderground.com/dashboard/pws/" + activeStationId])
  }

  Timer {
    interval: root.refreshSeconds * 1000
    running: true
    repeat: true
    onTriggered: root.refresh(false)
  }

  Timer {
    interval: root.forecastMinutes * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh(true)
  }

  Timer {
    interval: 60 * 1000
    running: root.hourly.length > 0
    repeat: true
    onTriggered: root.updateHourlyCondition()
  }

  Process {
    id: geocodingProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var locationResult = WeatherModel.openMeteoLocationResult(WeatherModel.parseJson(text))
        if (!locationResult) {
          root.settingsSaving = false
          root.settingsError = "Location not found. Try a city followed by its country or region."
          return
        }
        root.draftOpenMeteoLocation = locationResult.name
        root.persistSettings(locationResult)
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.settingsSaving = false
        root.settingsError = "Could not search Open-Meteo locations. Check your network."
      }
    }
  }

  Process {
    id: currentProcess
    property bool fetchForecastAfter: false
    property bool noObservation: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = WeatherModel.parseJson(text)
        var observation = WeatherModel.observation(payload, root.unitsName)
        if (!observation) {
          currentProcess.noObservation = true
          return
        }
        root.current = observation
        root.latitude = Number(observation.lat)
        root.longitude = Number(observation.lon)
        root.stationName = String(observation.neighborhood || observation.stationID || root.activeStationId)
        root.loading = false
        root.errorMessage = ""
        if (currentProcess.fetchForecastAfter || root.daily.length === 0) root.fetchForecasts()
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 || currentProcess.noObservation) {
        if (root.travelMode && root.travelCandidates.length > 0) root.tryNextTravelStation()
        else if (currentProcess.noObservation) root.fail("Station not found, inactive, or returned no observations.")
        else root.fail("Could not fetch observations. Check the station ID, API key, and network.")
      }
    }
  }

  Process {
    id: fallbackCurrentProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = WeatherModel.parseJson(text)
        if (payload && payload.error === true) {
          root.loading = false
          root.errorMessage = "Open-Meteo current conditions failed: " + String(payload.reason || payload.error_message || "the API rejected the request.")
          return
        }
        var observation = WeatherModel.openMeteoCurrent(payload, root.unitsName, root.stationName)
        if (!observation) {
          root.loading = false
          root.errorMessage = "Open-Meteo returned no usable current conditions."
          return
        }
        root.current = observation
        root.condition = observation.phrase
        root.iconCode = observation.iconCode
        root.loading = false
        root.errorMessage = ""
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.loading = false
        root.errorMessage = "Could not load current Open-Meteo conditions. Check your network."
      }
    }
  }

  Process {
    id: forecastProcess
    property string provider: "Open-Meteo"
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = WeatherModel.parseJson(text)
        if (payload && payload.error === true) {
          root.errorMessage = forecastProcess.provider + " forecast failed: " + String(payload.error_message || payload.reason || "the API rejected the request.")
          return
        }
        if (forecastProcess.provider === "Meteoblue") {
          root.hourly = WeatherModel.meteoblueHourlyForecast(payload, root.unitsName)
          root.daily = WeatherModel.mergeDailySupplement(WeatherModel.meteoblueDailyForecast(payload, root.unitsName), root.dailySupplement)
        } else {
          root.hourly = WeatherModel.openMeteoHourlyForecast(payload, root.unitsName)
          root.daily = WeatherModel.openMeteoDailyForecast(payload, root.unitsName)
          if (root.openMeteoFallback) {
            var localObservation = WeatherModel.openMeteoCurrent(payload, root.unitsName, root.stationName)
            if (localObservation) root.current = localObservation
            root.loading = false
          }
        }
        root.updateHourlyCondition()
        if (root.openMeteoFallback && forecastProcess.provider === "Open-Meteo" && root.current === null)
          root.errorMessage = "Open-Meteo returned no usable current conditions."
        else if (!root.hourly.length || !root.daily.length)
          root.errorMessage = forecastProcess.provider + " returned no usable hourly or daily forecast data."
        else if (!root.openMeteoFallback || root.current !== null)
          root.errorMessage = ""
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.errorMessage = forecastProcess.provider === "Meteoblue"
        ? "Current conditions loaded, but the Meteoblue forecast request failed. Check your network and API key."
        : (root.openMeteoFallback
          ? "Could not load local Open-Meteo conditions. Check your network."
          : "Current conditions loaded, but the Open-Meteo forecast request failed. Check your network.")
      if (root.openMeteoFallback && forecastProcess.provider === "Open-Meteo") root.loading = false
      root.forecastLoading = false
    }
  }

  Process {
    id: astronomyProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.dailySupplement = WeatherModel.openMeteoDailySupplement(WeatherModel.parseJson(text), root.unitsName)
        if (root.daily.length > 0)
          root.daily = WeatherModel.mergeDailySupplement(root.daily, root.dailySupplement)
      }
    }
  }

  Process {
    id: conditionsProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = WeatherModel.parseJson(text)
        if (payload) {
          root.condition = String(payload.wxPhraseLong || "")
          root.iconCode = Number(payload.iconCode === undefined ? root.iconCode : payload.iconCode)
        }
      }
    }
  }

  Process {
    id: identityProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = WeatherModel.parseJson(text)
        if (payload && payload.location) root.stationName = String(payload.location.neighborhood || payload.location.stationName || root.stationName)
      }
    }
  }

  Process {
    id: ipProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = WeatherModel.parseJson(text)
        var coordinates = WeatherModel.ipCoordinates(payload)
        if (!coordinates) { root.fail(root.openMeteoFallback ? "Local weather could not determine your approximate location." : "Traveling mode could not determine the current location."); return }
        if (root.openMeteoFallback) {
          root.latitude = coordinates.latitude
          root.longitude = coordinates.longitude
          root.stationName = WeatherModel.ipLocationName(payload) || "Local forecast"
          root.fallbackLocated = true
          root.fetchForecasts()
        } else {
          root.run(nearestProcess, root.apiUrl("/v3/location/near", { geocode: coordinates.latitude + "," + coordinates.longitude, product: "pws", format: "json", apiKey: root.apiKey }))
        }
      }
    }
    onExited: function(exitCode) { if (exitCode !== 0) root.fail(root.openMeteoFallback ? "Local weather geolocation failed." : "Traveling mode geolocation failed.") }
  }

  Process {
    id: nearestProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.travelCandidates = WeatherModel.nearestStations(WeatherModel.parseJson(text))
        root.travelCandidateIndex = -1
        if (!root.travelCandidates.length) { root.fail("No nearby personal weather station was found."); return }
        root.tryNextTravelStation()
      }
    }
    onExited: function(exitCode) { if (exitCode !== 0) root.fail("Could not find a nearby personal weather station.") }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(600))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.showSettingsPage
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.activeTab = Math.max(0, Math.min(1, root.activeTab + dx)) }
      onActivateRequested: root.refresh(true)
      onCloseRequested: { if (root.showSettingsPage) root.showSettingsPage = false; else root.close() }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(14)

        Row {
          width: parent.width
          spacing: Style.space(14)

          Text {
            text: root.glyph
            color: root.currentWeatherColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.display + Style.space(18)
          }

          Column {
            width: parent.width - Style.space(164)
            spacing: Style.space(4)

            Row {
              Text {
                text: root.temperature
                color: Color.popups.text
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.display
                font.bold: true
              }
            }

            Text {
              visible: root.current !== null
              width: parent.width
              text: "Feels " + WeatherModel.fixed(root.current ? (root.current.heatIndex !== undefined ? root.current.heatIndex : root.current.windChill) : undefined, 0) + root.unit.temperature
              color: Color.popups.text
              opacity: 0.6
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Text {
              visible: root.firstDaily !== null
              width: parent.width
              text: "High " + WeatherModel.fixed(root.firstDaily ? root.firstDaily.high : undefined, 0) + root.unit.temperature
                    + " · Low " + WeatherModel.fixed(root.firstDaily ? root.firstDaily.low : undefined, 0) + root.unit.temperature
              color: Color.popups.text
              opacity: 0.6
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Text {
              visible: root.stationName !== ""
              width: parent.width
              text: "󰍎 " + root.stationName + (root.activeStationId ? " · " + root.activeStationId : " · Open-Meteo")
              color: Color.popups.text
              opacity: 0.62
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              visible: root.weatherWarning !== ""
              width: parent.width
              text: "⚠ " + root.weatherWarning
              color: Color.urgent
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.current !== null
              text: root.showStationDetails ? "Less ▴" : "More ▾"
              color: Color.urgent
              font.pixelSize: Style.font.caption
              font.bold: true
              font.underline: true
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(3)
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showStationDetails = !root.showStationDetails
              }
            }
          }

          Row {
            spacing: Style.space(12)

            Text {
              text: "󰒓"
              color: Color.popups.text
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.icon
              ToolTip.visible: settingsHover.hovered
              ToolTip.text: "Weather settings"
              HoverHandler { id: settingsHover }
              MouseArea { anchors.fill: parent; anchors.margins: -Style.space(6); cursorShape: Qt.PointingHandCursor; onClicked: root.openSettingsPage() }
            }

            Text {
              text: root.loading || root.forecastLoading ? "" : "󰑓"
              color: Color.popups.text
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.icon
              RotationAnimator on rotation { running: root.loading || root.forecastLoading; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
              ToolTip.visible: refreshHover.hovered
              ToolTip.text: "Refresh weather"
              HoverHandler { id: refreshHover }
              MouseArea { anchors.fill: parent; anchors.margins: -Style.space(6); cursorShape: Qt.PointingHandCursor; onClicked: root.refresh(true) }
            }
          }
        }

        Text {
          visible: root.errorMessage !== ""
          width: parent.width
          text: root.errorMessage
          color: Color.urgent
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Column {
          visible: root.showStationDetails && root.current !== null
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width
            text: [root.stationName || root.activeStationId, root.condition].filter(function(value) { return value }).join(" · ") + (root.travelMode ? " · traveling" : "")
            color: Color.popups.text
            opacity: 0.6
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Grid {
            width: parent.width
            columns: 4
            columnSpacing: Style.space(8)
            rowSpacing: Style.space(8)

            Repeater {
              model: root.current ? [
                ["󰔏", "Feels", WeatherModel.fixed(root.current.heatIndex !== undefined ? root.current.heatIndex : root.current.windChill, 0) + root.unit.temperature],
                ["󰖎", "Humidity", WeatherModel.fixed(root.current.humidity, 0) + "%"],
                ["󰖝", "Wind", WeatherModel.fixed(root.current.windSpeed, 1) + " " + root.unit.speed],
                ["󰘚", "Gust", WeatherModel.fixed(root.current.windGust, 1) + " " + root.unit.speed],
                ["󰓅", "Pressure", WeatherModel.fixed(root.current.pressure, 1) + " " + root.unit.pressure],
                ["󰖑", "Dew point", WeatherModel.fixed(root.current.dewpt, 1) + root.unit.temperature],
                ["󰖌", "Rain rate", WeatherModel.fixed(root.current.precipRate, 1) + " " + root.unit.rain],
                ["󰖙", "UV index", WeatherModel.fixed(root.current.uv, 1)]
              ] : []

              Item {
                required property var modelData
                width: (content.width - Style.space(24)) / 4
                height: Style.space(52)

                Row {
                  anchors.centerIn: parent
                  spacing: Style.space(7)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData[0]
                    color: Color.accent
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.icon
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(1)

                    Text {
                      text: modelData[2]
                      color: Color.popups.text
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }

                    Text {
                      text: modelData[1]
                      color: Color.popups.text
                      opacity: 0.55
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          Repeater {
            model: ["Now", "7 days"]
            Rectangle {
              required property int index
              required property string modelData
              width: (content.width - Style.space(8)) / 2
              height: Style.space(34)
              radius: Style.cornerRadius
              color: root.activeTab === index ? Color.accent : Style.normalFill
              border.color: root.activeTab === index ? Color.accent : Color.popups.border
              Text { anchors.centerIn: parent; text: modelData; color: root.activeTab === index ? Color.popups.background : Color.popups.text; font.pixelSize: Style.font.bodySmall; font.bold: root.activeTab === index }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.activeTab = index }
            }
          }
        }

        Column {
          visible: root.activeTab === 0 && root.hourly.length > 0
          width: parent.width
          spacing: Style.space(2)

          Canvas {
            id: temperatureGraph
            width: parent.width
            height: Style.space(188)
            antialiasing: true

          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          onVisibleChanged: if (visible) requestPaint()
          Component.onCompleted: requestPaint()

          Connections {
            target: root
            function onHourlyChanged() { temperatureGraph.requestPaint() }
            function onUnitsNameChanged() { temperatureGraph.requestPaint() }
          }

          onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            var points = root.hourly.slice(0, 24)
            if (points.length < 2) return

            var left = Style.space(8)
            var right = Style.space(8)
            var top = Style.space(32)
            var bottom = Style.space(34)
            var chartWidth = width - left - right
            var chartHeight = height - top - bottom
            var minimum = Number(points[0].temperature)
            var maximum = minimum
            var maximumRain = 0
            var index

            for (index = 0; index < points.length; index++) {
              var temperature = Number(points[index].temperature)
              var rain = Number(points[index].rainAmount)
              if (!isNaN(temperature)) {
                minimum = Math.min(minimum, temperature)
                maximum = Math.max(maximum, temperature)
              }
              if (!isNaN(rain)) maximumRain = Math.max(maximumRain, rain)
            }

            var colorMinimum = minimum
            var colorMaximum = maximum
            var padding = Math.max(2, (maximum - minimum) * 0.22)
            minimum -= padding
            maximum += padding
            if (maximum <= minimum) maximum = minimum + 4

            function pointX(pointIndex) {
              return left + pointIndex * chartWidth / (points.length - 1)
            }

            function pointY(value) {
              return top + (maximum - value) * chartHeight / (maximum - minimum)
            }

            ctx.save()
            ctx.strokeStyle = Color.popups.border
            ctx.globalAlpha = 0.45
            ctx.lineWidth = 1
            for (index = 0; index < 3; index++) {
              var gridY = top + index * chartHeight / 2
              ctx.beginPath()
              ctx.moveTo(left, gridY)
              ctx.lineTo(width - right, gridY)
              ctx.stroke()
            }
            ctx.restore()

            if (maximumRain > 0) {
              var barWidth = Math.max(2, chartWidth / points.length * 0.65)
              ctx.save()
              ctx.fillStyle = root.rainColor
              ctx.globalAlpha = 0.32
              for (index = 0; index < points.length; index++) {
                var rainAmount = Number(points[index].rainAmount)
                if (isNaN(rainAmount) || rainAmount <= 0) continue
                var rainHeight = rainAmount / maximumRain * chartHeight * 0.34
                ctx.fillRect(pointX(index) - barWidth / 2, top + chartHeight - rainHeight, barWidth, rainHeight)
              }
              ctx.restore()

              ctx.save()
              ctx.fillStyle = root.rainColor
              ctx.globalAlpha = 0.9
              ctx.font = String(Style.font.caption) + "px '" + (root.bar ? root.bar.fontFamily : Style.font.family) + "'"
              ctx.textAlign = "center"
              ctx.textBaseline = "top"
              for (index = 0; index < points.length; index++) {
                var labelledRain = Number(points[index].rainAmount)
                if (isNaN(labelledRain) || labelledRain <= 0) continue
                var rainDigits = labelledRain < 1 ? 1 : 0
                ctx.fillText(WeatherModel.fixed(labelledRain, rainDigits) + root.unit.rain, pointX(index), top + chartHeight + Style.space(2))
              }
              ctx.restore()
            }

            var currentIndex = 0
            var nearestDistance = Number.MAX_VALUE
            var currentTime = Date.now()
            for (index = 0; index < points.length; index++) {
              var pointTime = new Date(points[index].date).getTime()
              if (isNaN(pointTime)) continue
              var distance = Math.abs(pointTime - currentTime)
              if (distance < nearestDistance) {
                nearestDistance = distance
                currentIndex = index
              }
            }

            var currentX = pointX(currentIndex)
            ctx.save()
            ctx.fillStyle = Color.urgent
            ctx.globalAlpha = 0.65
            for (var dotY = top; dotY <= top + chartHeight; dotY += Style.space(6))
              ctx.fillRect(currentX - 1, dotY, 2, 2)
            ctx.font = String(Style.font.caption) + "px '" + (root.bar ? root.bar.fontFamily : Style.font.family) + "'"
            ctx.textAlign = currentX < Style.space(30) ? "left" : (currentX > width - Style.space(30) ? "right" : "center")
            ctx.textBaseline = "bottom"
            ctx.fillText("Now", currentX, top - Style.space(5))
            ctx.restore()

            ctx.save()
            var temperatureGradient = ctx.createLinearGradient(left, 0, width - right, 0)
            for (index = 0; index < points.length; index++)
              temperatureGradient.addColorStop(index / Math.max(1, points.length - 1), WeatherModel.temperatureColor(points[index].temperature, colorMinimum, colorMaximum))
            ctx.strokeStyle = temperatureGradient
            ctx.globalAlpha = 0.8
            ctx.lineWidth = 2.5
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            ctx.beginPath()
            for (index = 0; index < points.length; index++) {
              var x = pointX(index)
              var y = pointY(Number(points[index].temperature))
              if (index === 0) ctx.moveTo(x, y)
              else ctx.lineTo(x, y)
            }
            ctx.stroke()
            ctx.restore()

            ctx.save()
            ctx.font = String(Style.font.caption) + "px '" + (root.bar ? root.bar.fontFamily : Style.font.family) + "'"
            ctx.textAlign = "center"
            ctx.textBaseline = "bottom"
            for (index = 0; index < points.length; index++) {
              var pointTemperature = Number(points[index].temperature)
              var labelX = pointX(index)
              var labelY = pointY(pointTemperature)

              ctx.fillStyle = WeatherModel.temperatureColor(pointTemperature, colorMinimum, colorMaximum)
              ctx.beginPath()
              ctx.arc(labelX, labelY, 2.5, 0, Math.PI * 2)
              ctx.fill()

              ctx.globalAlpha = 0.82
              var temperatureLabelY = labelY - Style.space(4) - (index % 2) * Style.space(8)
              var temperatureLabel = Math.round(pointTemperature) + "°"
              if (index % 3 === 0) {
                ctx.textAlign = "right"
                ctx.fillStyle = WeatherModel.weatherColor(points[index].iconCode)
                ctx.fillText(WeatherModel.weatherGlyph(points[index].iconCode), labelX - Style.space(1), temperatureLabelY)
                ctx.textAlign = "left"
                ctx.fillStyle = Color.popups.text
                ctx.fillText(temperatureLabel, labelX + Style.space(1), temperatureLabelY)
              } else {
                ctx.textAlign = "center"
                ctx.fillStyle = Color.popups.text
                ctx.fillText(temperatureLabel, labelX, temperatureLabelY)
              }

              if (index % 3 === 0) {
                ctx.globalAlpha = 0.55
                ctx.textAlign = "center"
                ctx.textBaseline = "top"
                ctx.fillText(WeatherModel.shortTime(points[index].date), labelX, height - bottom + Style.space(17))
                ctx.textBaseline = "bottom"
              }
            }
            ctx.restore()
          }
        }

          Row {
            visible: root.threeHourly.length > 0
            width: parent.width
            height: Style.space(20)

          Repeater {
            model: root.threeHourly

            Item {
              required property var modelData
              width: parent.width / Math.max(1, root.threeHourly.length)
              height: parent.height

              Text {
                anchors.centerIn: parent
                text: "󰖌 " + WeatherModel.fixed(modelData.rainChance, 0) + "%"
                color: root.rainColor
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
            }
          }
        }

        ListView {
          visible: root.activeTab === 1
          width: parent.width
          height: Math.min(7, root.daily.length) * Style.space(34) + Math.max(0, Math.min(7, root.daily.length) - 1) * Style.space(2)
          model: root.daily
          clip: true
          spacing: Style.space(2)
          delegate: Item {
            id: dailyDelegate
            required property int index
            required property var modelData
            readonly property real dayLow: Number(modelData.low)
            readonly property real dayHigh: Number(modelData.high)
            readonly property real dayRainAmount: Number(modelData.rainAmount)
            readonly property real rangeMinimum: Number(root.dailyTemperatureRange.minimum)
            readonly property real rangeMaximum: Number(root.dailyTemperatureRange.maximum)
            readonly property real rangeSpan: Math.max(1, rangeMaximum - rangeMinimum)
            width: ListView.view.width
            height: Style.space(34)

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 1
              color: Color.popups.border
              opacity: 0.28
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(8)

              Text {
                width: Style.space(48)
                anchors.verticalCenter: parent.verticalCenter
                text: dailyDelegate.index === 0 ? "Today" : WeatherModel.shortDay(modelData.date)
                color: Color.popups.text
                font.pixelSize: Style.font.bodySmall
                font.bold: dailyDelegate.index === 0
              }

              Text {
                width: Style.space(28)
                anchors.verticalCenter: parent.verticalCenter
                text: WeatherModel.weatherGlyph(modelData.iconCode)
                color: WeatherModel.weatherColor(modelData.iconCode)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.icon
                horizontalAlignment: Text.AlignHCenter
              }

              Item {
                id: dailyRange
                width: parent.width - Style.space(236)
                height: parent.height
                readonly property real trackLeft: Style.space(40)
                readonly property real trackWidth: Math.max(1, width - Style.space(80))
                readonly property real lowPosition: (dailyDelegate.dayLow - dailyDelegate.rangeMinimum) / dailyDelegate.rangeSpan * trackWidth
                readonly property real highPosition: (dailyDelegate.dayHigh - dailyDelegate.rangeMinimum) / dailyDelegate.rangeSpan * trackWidth

                Rectangle {
                  id: temperatureCandle
                  x: dailyRange.trackLeft + dailyRange.lowPosition
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.max(Style.space(8), dailyRange.highPosition - dailyRange.lowPosition)
                  height: Style.space(7)
                  radius: height / 2
                  gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#a9d96f" }
                    GradientStop { position: 0.55; color: "#eccb62" }
                    GradientStop { position: 1.0; color: "#ef8d78" }
                  }
                }

                Text {
                  x: Math.max(0, temperatureCandle.x - width - Style.space(5))
                  width: Style.space(34)
                  anchors.verticalCenter: parent.verticalCenter
                  text: WeatherModel.fixed(dailyDelegate.dayLow, 0) + "°"
                  color: Color.popups.text
                  opacity: 0.65
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignRight
                }

                Text {
                  x: Math.min(parent.width - width, temperatureCandle.x + temperatureCandle.width + Style.space(5))
                  width: Style.space(34)
                  anchors.verticalCenter: parent.verticalCenter
                  text: WeatherModel.fixed(dailyDelegate.dayHigh, 0) + "°"
                  color: Color.popups.text
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                width: Style.space(64)
                anchors.verticalCenter: parent.verticalCenter
                text: Number(modelData.rainChance) > 0 ? "󰖌 " + WeatherModel.fixed(modelData.rainChance, 0) + "%" : ""
                color: root.rainColor
                opacity: 0.8
                font.pixelSize: Style.font.caption
              }

              Text {
                width: Style.space(64)
                anchors.verticalCenter: parent.verticalCenter
                text: !isNaN(dailyDelegate.dayRainAmount) && dailyDelegate.dayRainAmount > 0 ? WeatherModel.fixed(dailyDelegate.dayRainAmount, dailyDelegate.dayRainAmount < 1 ? 1 : 0) + " " + root.unit.rain : ""
                color: root.rainColor
                opacity: 0.65
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignRight
              }
            }

            ToolTip.visible: dailyHover.hovered
            ToolTip.delay: 250
            ToolTip.text: modelData.phrase || modelData.narrative || "Forecast"
            HoverHandler { id: dailyHover }
          }
        }

        Row {
          visible: root.firstDaily !== null
          width: parent.width
          spacing: Style.space(18)
          Text { text: "󰖜 Sunrise " + WeatherModel.shortTime(root.firstDaily ? root.firstDaily.sunrise : ""); color: Color.popups.text; opacity: 0.72; font.pixelSize: Style.font.caption }
          Text { text: "󰖛 Sunset " + WeatherModel.shortTime(root.firstDaily ? root.firstDaily.sunset : ""); color: Color.popups.text; opacity: 0.72; font.pixelSize: Style.font.caption }
          Text { text: root.firstDaily ? root.firstDaily.moonPhase : ""; color: Color.popups.text; opacity: 0.65; font.pixelSize: Style.font.caption }
          Item { width: Math.max(0, content.width - Style.space(360)); height: 1 }
          Text { text: root.activeStationId; color: Color.popups.text; opacity: 0.45; font.pixelSize: Style.font.caption; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openStationDashboard() } }
        }
      }

      Rectangle {
        anchors.fill: parent
        visible: root.showSettingsPage
        z: 100
        color: Color.popups.background

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(20)
          spacing: Style.space(10)

          Row {
            width: parent.width

            Text {
              width: parent.width - Style.space(40)
              text: "Weather settings"
              color: Color.popups.text
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: "󰅖"
              color: Color.popups.text
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.icon
              MouseArea { anchors.fill: parent; anchors.margins: -Style.space(6); cursorShape: Qt.PointingHandCursor; onClicked: root.showSettingsPage = false }
            }
          }

          Text { text: "Weather Underground / Weather.com API key"; color: Color.popups.text; opacity: 0.72; font.pixelSize: Style.font.caption }
          TextField {
            width: parent.width
            text: root.draftApiKey
            echoMode: TextInput.Password
            placeholderText: "Only required with a station ID"
            onTextChanged: root.draftApiKey = text
          }

          Text { visible: WeatherModel.trim(root.draftApiKey) !== ""; text: "Weather Underground station ID"; color: Color.popups.text; opacity: 0.72; font.pixelSize: Style.font.caption }
          TextField {
            visible: WeatherModel.trim(root.draftApiKey) !== ""
            width: parent.width
            text: root.draftStationId
            placeholderText: "Personal weather station ID"
            onTextChanged: root.draftStationId = text
          }

          Text { visible: WeatherModel.trim(root.draftApiKey) === ""; text: "Open-Meteo location"; color: Color.popups.text; opacity: 0.72; font.pixelSize: Style.font.caption }
          TextField {
            visible: WeatherModel.trim(root.draftApiKey) === ""
            width: parent.width
            text: root.draftOpenMeteoLocation
            placeholderText: "City or postcode; leave empty for automatic location"
            onTextChanged: root.draftOpenMeteoLocation = text
            onAccepted: root.saveSettingsPage()
          }

          Text {
            visible: root.settingsError !== ""
            width: parent.width
            text: root.settingsError
            color: Color.urgent
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text { text: "Meteoblue API key"; color: Color.popups.text; opacity: 0.72; font.pixelSize: Style.font.caption }
          TextField {
            width: parent.width
            text: root.draftMeteoblueApiKey
            echoMode: TextInput.Password
            placeholderText: "Optional forecast provider"
            onTextChanged: root.draftMeteoblueApiKey = text
          }

          Row {
            width: parent.width
            spacing: Style.space(10)
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Units"; color: Color.popups.text; opacity: 0.72; font.pixelSize: Style.font.caption }
            ComboBox {
              width: Style.space(190)
              model: ["Metric (°C, km/h)", "Imperial (°F, mph)", "UK hybrid (°C, mph)"]
              currentIndex: root.draftUnits === "imperial" ? 1 : (root.draftUnits === "uk_hybrid" ? 2 : 0)
              onActivated: function(index) { root.draftUnits = ["metric", "imperial", "uk_hybrid"][index] }
            }
          }

          Item { width: 1; height: Style.space(4) }

          Row {
            spacing: Style.space(10)

            Rectangle {
              width: Style.space(120)
              height: Style.space(34)
              radius: Style.cornerRadius
              color: Color.accent
              opacity: root.settingsSaving ? 0.6 : 1
              Text { anchors.centerIn: parent; text: root.settingsSaving ? "Searching…" : "Save"; color: Color.popups.background; font.bold: true }
              MouseArea { anchors.fill: parent; enabled: !root.settingsSaving; cursorShape: Qt.PointingHandCursor; onClicked: root.saveSettingsPage() }
            }

            Rectangle {
              width: Style.space(100)
              height: Style.space(34)
              radius: Style.cornerRadius
              color: Style.normalFill
              border.color: Color.popups.border
              Text { anchors.centerIn: parent; text: "Cancel"; color: Color.popups.text }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.showSettingsPage = false }
            }
          }
        }
      }
    }
  }
}
