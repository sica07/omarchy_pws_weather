.pragma library

function trim(value) {
  return String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
}

function unitCode(name) {
  if (name === "imperial") return "e"
  if (name === "uk_hybrid") return "h"
  return "m"
}

function unitLabels(name) {
  if (name === "imperial")
    return { temperature: "°F", speed: "mph", pressure: "inHg", rain: "in" }
  if (name === "uk_hybrid")
    return { temperature: "°C", speed: "mph", pressure: "mbar", rain: "mm" }
  return { temperature: "°C", speed: "km/h", pressure: "hPa", rain: "mm" }
}

function parseJson(raw) {
  try { return JSON.parse(String(raw || "{}")) }
  catch (e) { return null }
}

function observation(payload, unitsName) {
  if (!payload || !payload.observations || !payload.observations.length) return null
  var source = payload.observations[0]
  var section = source[unitsName] || source.metric || source.imperial || source.uk_hybrid || {}
  var out = {}
  Object.keys(source).forEach(function(key) {
    if (key !== "metric" && key !== "imperial" && key !== "uk_hybrid") out[key] = source[key]
  })
  Object.keys(section).forEach(function(key) { out[key] = section[key] })
  return out
}

function nearestStation(payload) {
  var stations = nearestStations(payload)
  return stations.length ? stations[0] : null
}

function nearestStations(payload) {
  var location = payload && payload.location ? payload.location : null
  if (!location || !location.stationId || !location.stationId.length) return []
  var out = []
  for (var index = 0; index < location.stationId.length; index++) {
    out.push({
      id: String(location.stationId[index]),
      name: location.stationName && location.stationName[index] ? String(location.stationName[index]) : String(location.stationId[index]),
      latitude: location.latitude && location.latitude[index] !== undefined ? Number(location.latitude[index]) : NaN,
      longitude: location.longitude && location.longitude[index] !== undefined ? Number(location.longitude[index]) : NaN
    })
  }
  return out
}

function ipCoordinates(payload) {
  if (!payload || !payload.loc) return null
  var parts = String(payload.loc).split(",")
  if (parts.length !== 2) return null
  var lat = Number(parts[0])
  var lon = Number(parts[1])
  return isNaN(lat) || isNaN(lon) ? null : { latitude: lat, longitude: lon }
}

function ipLocationName(payload) {
  if (!payload) return ""
  var parts = [payload.city, payload.region, payload.country].filter(function(value) { return String(value || "").trim() !== "" })
  return parts.join(", ")
}

function openMeteoLocationResult(payload) {
  var results = payload && payload.results ? payload.results : []
  if (!results.length) return null
  var first = results[0]
  var parts = [first.name, first.admin1, first.country].filter(function(value, index, source) {
    var text = String(value || "").trim()
    if (!text) return false
    return source.slice(0, index).map(function(item) { return String(item || "").trim() }).indexOf(text) === -1
  })
  var latitude = Number(first.latitude)
  var longitude = Number(first.longitude)
  if (isNaN(latitude) || isNaN(longitude)) return null
  return { name: parts.join(", "), latitude: latitude, longitude: longitude }
}

function dailyForecast(payload) {
  if (!payload) return []
  if (payload.forecasts) return payload.forecasts.map(function(item) {
    var part = item.day || item.night || {}
    var night = item.night || {}
    return {
      date: String(item.fcst_valid_local || ""),
      day: String(part.long_daypart_name || part.alt_daypart_name || ""),
      phrase: String(part.phrase_32char || part.narrative || ""),
      narrative: String(part.narrative || ""),
      iconCode: Number(part.icon_code === undefined ? 44 : part.icon_code),
      high: item.day ? item.day.temp : night.hi,
      low: night.temp,
      rainChance: part.pop,
      rainAmount: part.qpf,
      humidity: part.rh,
      wind: String(part.wind_phrase || ""),
      sunrise: String(item.sunrise || ""),
      sunset: String(item.sunset || ""),
      moonPhase: String(item.lunar_phase || "")
    }
  })

  var times = payload.validTimeLocal || []
  var daypart = payload.daypart && payload.daypart.length ? payload.daypart[0] : {}
  var out = []
  for (var index = 0; index < times.length; index++) {
    var dayIndex = index * 2
    var partIndex = dayIndex
    if (!daypart.daypartName || daypart.daypartName[partIndex] === null || daypart.daypartName[partIndex] === undefined)
      partIndex = dayIndex + 1
    out.push({
      date: String(times[index] || ""),
      day: String((payload.dayOfWeek || [])[index] || (daypart.daypartName || [])[partIndex] || ""),
      phrase: String((daypart.wxPhraseLong || [])[partIndex] || (daypart.wxPhraseShort || [])[partIndex] || ""),
      narrative: String((daypart.narrative || [])[partIndex] || ""),
      iconCode: Number((daypart.iconCode || [])[partIndex] === undefined || (daypart.iconCode || [])[partIndex] === null ? 44 : daypart.iconCode[partIndex]),
      high: (payload.temperatureMax || [])[index],
      low: (payload.temperatureMin || [])[index],
      rainChance: (daypart.precipChance || [])[partIndex],
      rainAmount: (payload.qpf || [])[index],
      humidity: (daypart.relativeHumidity || [])[partIndex],
      wind: String((daypart.windPhrase || [])[partIndex] || ""),
      sunrise: String((payload.sunriseTimeLocal || [])[index] || ""),
      sunset: String((payload.sunsetTimeLocal || [])[index] || ""),
      moonPhase: String((payload.moonPhase || [])[index] || "")
    })
  }
  return out
}

function hourlyForecast(payload) {
  if (!payload) return []
  if (payload.forecasts) return payload.forecasts.slice(0, 24).map(function(item) {
    return {
      date: String(item.fcst_valid_local || ""),
      temperature: item.temp,
      feelsLike: item.feels_like,
      phrase: String(item.phrase_22char || item.phrase_32char || ""),
      iconCode: Number(item.icon_code === undefined ? 44 : item.icon_code),
      rainChance: item.pop,
      humidity: item.rh,
      windSpeed: item.wspd,
      pressure: item.mslp,
      uv: item.uv_index,
      clouds: item.clds
    }
  })

  var times = payload.validTimeLocal || []
  var out = []
  for (var index = 0; index < Math.min(24, times.length); index++) {
    out.push({
      date: String(times[index] || ""),
      temperature: (payload.temperature || [])[index],
      feelsLike: (payload.temperatureFeelsLike || [])[index],
      phrase: String((payload.wxPhraseLong || payload.wxPhraseShort || [])[index] || ""),
      iconCode: Number((payload.iconCode || [])[index] === undefined || (payload.iconCode || [])[index] === null ? 44 : payload.iconCode[index]),
      rainChance: (payload.precipChance || [])[index],
      humidity: (payload.relativeHumidity || [])[index],
      windSpeed: (payload.windSpeed || [])[index],
      pressure: (payload.pressureMeanSeaLevel || [])[index],
      uv: (payload.uvIndex || [])[index],
      clouds: (payload.cloudCover || [])[index]
    })
  }
  return out
}

function convertedTemperature(value, unitsName) {
  var parsed = Number(value)
  if (isNaN(parsed)) return undefined
  return unitsName === "imperial" ? parsed * 9 / 5 + 32 : parsed
}

function convertedSpeed(value, unitsName) {
  var parsed = Number(value)
  if (isNaN(parsed)) return undefined
  return unitsName === "imperial" || unitsName === "uk_hybrid" ? parsed * 0.621371 : parsed
}

function convertedPressure(value, unitsName) {
  var parsed = Number(value)
  if (isNaN(parsed)) return undefined
  return unitsName === "imperial" ? parsed * 0.0295299830714 : parsed
}

function convertedRain(value, unitsName) {
  var parsed = Number(value)
  if (isNaN(parsed)) return undefined
  return unitsName === "imperial" ? parsed * 0.0393700787 : parsed
}

function arrayValue(section, names, index) {
  if (!section) return undefined
  for (var nameIndex = 0; nameIndex < names.length; nameIndex++) {
    var values = section[names[nameIndex]]
    if (values && values[index] !== undefined && values[index] !== null) return values[index]
  }
  return undefined
}

function meteoblueBasePictocode(value) {
  var code = Number(value)
  if (isNaN(code)) return 0
  if (code > 17) code -= 17
  return code
}

function meteobluePhrase(value) {
  var phrases = {
    1: "Clear",
    2: "Mostly clear",
    3: "Partly cloudy",
    4: "Overcast",
    5: "Fog",
    6: "Rain",
    7: "Showers",
    8: "Rain showers",
    9: "Snow",
    10: "Snow showers",
    11: "Mixed rain and snow",
    12: "Light rain",
    13: "Light showers",
    14: "Scattered showers",
    15: "Thunderstorms",
    16: "Severe thunderstorms",
    17: "Freezing rain"
  }
  return phrases[meteoblueBasePictocode(value)] || "Forecast"
}

function meteoblueIconCode(value) {
  var code = meteoblueBasePictocode(value)
  if (code === 1) return 32
  if (code === 2) return 34
  if (code === 3) return 30
  if (code === 4) return 26
  if (code === 5) return 20
  if ([6, 12].indexOf(code) >= 0) return 12
  if ([7, 8, 13, 14].indexOf(code) >= 0) return 39
  if ([9, 10].indexOf(code) >= 0) return 16
  if (code === 11) return 5
  if ([15, 16].indexOf(code) >= 0) return 4
  if (code === 17) return 8
  return 44
}

function normalizedForecastTime(value) {
  return String(value || "").replace(" ", "T")
}

function currentHourlyForecast(hourly, nowValue) {
  var source = hourly || []
  if (!source.length) return null

  var targetTime = nowValue === undefined || nowValue === null
    ? Date.now()
    : new Date(nowValue).getTime()
  if (isNaN(targetTime)) targetTime = Date.now()

  var latestElapsed = null
  var latestElapsedTime = -Infinity
  var firstFuture = null
  var firstFutureTime = Infinity

  for (var index = 0; index < source.length; index++) {
    var forecastTime = new Date(normalizedForecastTime(source[index].date)).getTime()
    if (isNaN(forecastTime)) continue
    if (forecastTime <= targetTime && forecastTime > latestElapsedTime) {
      latestElapsed = source[index]
      latestElapsedTime = forecastTime
    } else if (forecastTime > targetTime && forecastTime < firstFutureTime) {
      firstFuture = source[index]
      firstFutureTime = forecastTime
    }
  }

  return latestElapsed || firstFuture || source[0]
}

function meteoblueHourlyForecast(payload, unitsName) {
  var source = payload && payload.data_1h ? payload.data_1h : null
  var times = source && source.time ? source.time : []
  var out = []
  for (var index = 0; index < Math.min(24, times.length); index++) {
    var pictocode = arrayValue(source, ["pictocode", "pictocode_detailed"], index)
    out.push({
      date: normalizedForecastTime(times[index]),
      temperature: convertedTemperature(arrayValue(source, ["temperature"], index), unitsName),
      feelsLike: convertedTemperature(arrayValue(source, ["felttemperature", "feelslike"], index), unitsName),
      phrase: meteobluePhrase(pictocode),
      iconCode: meteoblueIconCode(pictocode),
      rainChance: arrayValue(source, ["precipitation_probability"], index),
      rainAmount: convertedRain(arrayValue(source, ["precipitation"], index), unitsName),
      humidity: arrayValue(source, ["relativehumidity"], index),
      windSpeed: convertedSpeed(arrayValue(source, ["windspeed"], index), unitsName),
      pressure: convertedPressure(arrayValue(source, ["sealevelpressure"], index), unitsName),
      uv: arrayValue(source, ["uvindex"], index),
      clouds: arrayValue(source, ["totalcloudcover", "cloudcover"], index)
    })
  }
  return out
}

function meteoblueDailyForecast(payload, unitsName) {
  var source = payload && payload.data_day ? payload.data_day : null
  var times = source && source.time ? source.time : []
  var labels = unitLabels(unitsName)
  var out = []
  for (var index = 0; index < times.length; index++) {
    var pictocode = arrayValue(source, ["pictocode"], index)
    var windSpeed = convertedSpeed(arrayValue(source, ["windspeed_mean", "windspeed_max"], index), unitsName)
    var phrase = meteobluePhrase(pictocode)
    out.push({
      date: normalizedForecastTime(times[index]),
      day: "",
      phrase: phrase,
      narrative: phrase,
      iconCode: meteoblueIconCode(pictocode),
      high: convertedTemperature(arrayValue(source, ["temperature_max"], index), unitsName),
      low: convertedTemperature(arrayValue(source, ["temperature_min"], index), unitsName),
      rainChance: arrayValue(source, ["precipitation_probability"], index),
      rainAmount: convertedRain(arrayValue(source, ["precipitation"], index), unitsName),
      humidity: arrayValue(source, ["relativehumidity_mean", "relativehumidity_max"], index),
      wind: windSpeed === undefined ? "" : fixed(windSpeed, 0) + " " + labels.speed,
      sunrise: normalizedForecastTime(arrayValue(source, ["sunrisetime", "sunrise"], index)),
      sunset: normalizedForecastTime(arrayValue(source, ["sunsettime", "sunset"], index)),
      moonPhase: ""
    })
  }
  return out
}

function openMeteoPhrase(value) {
  var code = Number(value)
  if (code === 0) return "Clear"
  if (code === 1) return "Mostly clear"
  if (code === 2) return "Partly cloudy"
  if (code === 3) return "Overcast"
  if (code === 45 || code === 48) return "Fog"
  if ([51, 53, 55].indexOf(code) >= 0) return "Drizzle"
  if (code === 56 || code === 57) return "Freezing drizzle"
  if (code === 61) return "Light rain"
  if (code === 63) return "Rain"
  if (code === 65) return "Heavy rain"
  if (code === 66 || code === 67) return "Freezing rain"
  if (code === 71) return "Light snow"
  if (code === 73 || code === 77) return "Snow"
  if (code === 75) return "Heavy snow"
  if ([80, 81, 82].indexOf(code) >= 0) return "Rain showers"
  if (code === 85 || code === 86) return "Snow showers"
  if ([95, 96, 99].indexOf(code) >= 0) return "Thunderstorms"
  return "Forecast"
}

function openMeteoIconCode(value, isDay) {
  var code = Number(value)
  var day = Number(isDay) !== 0
  if (code === 0) return day ? 32 : 31
  if (code === 1) return day ? 34 : 33
  if (code === 2) return day ? 30 : 29
  if (code === 3) return day ? 28 : 27
  if (code === 45 || code === 48) return 20
  if ([51, 53, 55].indexOf(code) >= 0) return 9
  if ([56, 57, 66, 67].indexOf(code) >= 0) return 8
  if ([61, 63, 65].indexOf(code) >= 0) return 12
  if ([71, 73, 75, 77].indexOf(code) >= 0) return 16
  if ([80, 81, 82].indexOf(code) >= 0) return day ? 39 : 45
  if (code === 85 || code === 86) return day ? 41 : 46
  if ([95, 96, 99].indexOf(code) >= 0) return day ? 4 : 47
  return 44
}

function openMeteoCurrent(payload, unitsName, locationName) {
  var source = payload && payload.current ? payload.current : null
  if (!source || source.temperature_2m === undefined || source.temperature_2m === null) return null
  var apparent = convertedTemperature(source.apparent_temperature, unitsName)
  return {
    stationID: "",
    neighborhood: String(locationName || "Local forecast"),
    lat: Number(payload.latitude),
    lon: Number(payload.longitude),
    temp: convertedTemperature(source.temperature_2m, unitsName),
    heatIndex: apparent,
    windChill: apparent,
    humidity: source.relative_humidity_2m,
    windSpeed: convertedSpeed(source.wind_speed_10m, unitsName),
    windGust: convertedSpeed(source.wind_gusts_10m, unitsName),
    pressure: convertedPressure(source.pressure_msl, unitsName),
    dewpt: convertedTemperature(source.dew_point_2m, unitsName),
    precipRate: convertedRain(source.precipitation, unitsName),
    uv: source.uv_index,
    iconCode: openMeteoIconCode(source.weather_code, source.is_day),
    phrase: openMeteoPhrase(source.weather_code)
  }
}

function openMeteoHourlyForecast(payload, unitsName) {
  var source = payload && payload.hourly ? payload.hourly : null
  var times = source && source.time ? source.time : []
  var out = []
  for (var index = 0; index < Math.min(24, times.length); index++) {
    var weatherCode = arrayValue(source, ["weather_code"], index)
    var isDay = arrayValue(source, ["is_day"], index)
    out.push({
      date: normalizedForecastTime(times[index]),
      temperature: convertedTemperature(arrayValue(source, ["temperature_2m"], index), unitsName),
      feelsLike: convertedTemperature(arrayValue(source, ["apparent_temperature"], index), unitsName),
      phrase: openMeteoPhrase(weatherCode),
      iconCode: openMeteoIconCode(weatherCode, isDay),
      rainChance: arrayValue(source, ["precipitation_probability"], index),
      rainAmount: convertedRain(arrayValue(source, ["precipitation"], index), unitsName),
      humidity: arrayValue(source, ["relative_humidity_2m"], index),
      windSpeed: convertedSpeed(arrayValue(source, ["wind_speed_10m"], index), unitsName),
      pressure: convertedPressure(arrayValue(source, ["pressure_msl"], index), unitsName),
      uv: arrayValue(source, ["uv_index"], index),
      clouds: arrayValue(source, ["cloud_cover"], index)
    })
  }
  return out
}

function openMeteoDailyForecast(payload, unitsName) {
  var source = payload && payload.daily ? payload.daily : null
  var times = source && source.time ? source.time : []
  var labels = unitLabels(unitsName)
  var out = []
  for (var index = 0; index < times.length; index++) {
    var weatherCode = arrayValue(source, ["weather_code"], index)
    var windSpeed = convertedSpeed(arrayValue(source, ["wind_speed_10m_max"], index), unitsName)
    var phrase = openMeteoPhrase(weatherCode)
    out.push({
      date: normalizedForecastTime(times[index]),
      day: "",
      phrase: phrase,
      narrative: phrase,
      iconCode: openMeteoIconCode(weatherCode, 1),
      high: convertedTemperature(arrayValue(source, ["temperature_2m_max"], index), unitsName),
      low: convertedTemperature(arrayValue(source, ["temperature_2m_min"], index), unitsName),
      rainChance: arrayValue(source, ["precipitation_probability_max"], index),
      rainAmount: convertedRain(arrayValue(source, ["precipitation_sum"], index), unitsName),
      humidity: undefined,
      wind: windSpeed === undefined ? "" : fixed(windSpeed, 0) + " " + labels.speed,
      sunrise: normalizedForecastTime(arrayValue(source, ["sunrise"], index)),
      sunset: normalizedForecastTime(arrayValue(source, ["sunset"], index)),
      moonPhase: ""
    })
  }
  return out
}

function openMeteoDailySupplement(payload, unitsName) {
  var source = payload && payload.daily ? payload.daily : null
  var times = source && source.time ? source.time : []
  var out = []
  for (var index = 0; index < times.length; index++) {
    out.push({
      date: normalizedForecastTime(times[index]),
      sunrise: normalizedForecastTime(arrayValue(source, ["sunrise"], index)),
      sunset: normalizedForecastTime(arrayValue(source, ["sunset"], index)),
      rainAmount: convertedRain(arrayValue(source, ["precipitation_sum"], index), unitsName)
    })
  }
  return out
}

function mergeDailySupplement(primary, supplement) {
  var additions = supplement || []
  var byDate = {}
  for (var extraIndex = 0; extraIndex < additions.length; extraIndex++)
    byDate[String(additions[extraIndex].date || "").slice(0, 10)] = additions[extraIndex]

  return (primary || []).map(function(item) {
    var merged = {}
    Object.keys(item || {}).forEach(function(key) { merged[key] = item[key] })
    var extra = byDate[String(merged.date || "").slice(0, 10)] || {}
    if (!merged.sunrise) merged.sunrise = extra.sunrise || ""
    if (!merged.sunset) merged.sunset = extra.sunset || ""
    if ((merged.rainAmount === undefined || merged.rainAmount === null || isNaN(Number(merged.rainAmount))) && extra.rainAmount !== undefined)
      merged.rainAmount = extra.rainAmount
    return merged
  })
}

function forecastSeverity(iconCode) {
  var code = Number(iconCode)
  if ([3, 4, 35, 37, 38, 45, 47].indexOf(code) >= 0) return 5
  if ([13, 14, 15, 16, 41, 42, 43, 46].indexOf(code) >= 0) return 4
  if ([5, 6, 7, 8, 9, 10, 11, 12, 17, 18, 39, 40].indexOf(code) >= 0) return 3
  if ([20, 21, 22, 26, 27, 28, 29, 30, 44].indexOf(code) >= 0) return 2
  return 1
}

function threeHourForecast(hourly) {
  var source = hourly || []
  var out = []
  for (var start = 0; start < Math.min(24, source.length); start += 3) {
    var end = Math.min(start + 3, source.length)
    var representative = source[start]
    var rainChance = Number(representative.rainChance)
    var rainAmount = 0
    for (var index = start; index < end; index++) {
      var item = source[index]
      if (forecastSeverity(item.iconCode) > forecastSeverity(representative.iconCode)) representative = item
      var chance = Number(item.rainChance)
      var amount = Number(item.rainAmount)
      if (!isNaN(chance)) rainChance = isNaN(rainChance) ? chance : Math.max(rainChance, chance)
      if (!isNaN(amount)) rainAmount += amount
    }
    out.push({
      date: source[start].date,
      phrase: representative.phrase,
      iconCode: representative.iconCode,
      rainChance: rainChance,
      rainAmount: rainAmount,
      hours: end - start
    })
  }
  return out
}

function weatherWarning(current, hourly, unitsName) {
  var warnings = []
  var observation = current || {}
  var gust = Number(observation.windGust)
  var rainRate = Number(observation.precipRate)
  var uv = Number(observation.uv)
  var speedLimit = unitsName === "imperial" || unitsName === "uk_hybrid" ? 37 : 60
  var rainLimit = unitsName === "imperial" ? 0.6 : 15

  if (!isNaN(gust) && gust >= speedLimit) warnings.push("Strong gusts at the station")
  if (!isNaN(rainRate) && rainRate >= rainLimit) warnings.push("Heavy rain at the station")
  if (!isNaN(uv) && uv >= 8) warnings.push("Very high UV")

  var source = hourly || []
  for (var index = 0; index < Math.min(24, source.length); index++) {
    var phrase = String(source[index].phrase || "")
    var normalized = phrase.toLowerCase()
    if (normalized.indexOf("thunder") >= 0 || normalized.indexOf("freezing") >= 0 || normalized.indexOf("heavy rain") >= 0 || normalized.indexOf("heavy snow") >= 0) {
      warnings.push(phrase + " around " + shortTime(source[index].date))
      break
    }
  }

  return warnings.slice(0, 2).join(" · ")
}

function dailyTemperatureRange(daily) {
  var source = daily || []
  var minimum = Infinity
  var maximum = -Infinity
  for (var index = 0; index < source.length; index++) {
    var low = Number(source[index].low)
    var high = Number(source[index].high)
    if (!isNaN(low)) minimum = Math.min(minimum, low)
    if (!isNaN(high)) maximum = Math.max(maximum, high)
  }
  if (minimum === Infinity || maximum === -Infinity) return { minimum: 0, maximum: 1 }
  if (maximum <= minimum) maximum = minimum + 1
  return { minimum: minimum, maximum: maximum }
}

function weatherGlyph(code) {
  var c = Number(code)
  if (c === 31 || c === 33) return "󰖔"
  if (c === 32 || c === 34 || c === 36) return "󰖙"
  if (c === 26 || c === 27 || c === 28) return "󰖐"
  if (c === 29 || c === 30 || c === 44) return "󰖕"
  if (c === 20 || c === 21 || c === 22) return "󰖑"
  if ([13, 14, 15, 16, 41, 42, 43, 46].indexOf(c) >= 0) return "󰖘"
  if ([3, 4, 35, 37, 38, 45, 47].indexOf(c) >= 0) return "󰖓"
  if ([5, 6, 7, 8, 9, 10, 11, 12, 17, 18, 39, 40].indexOf(c) >= 0) return "󰖗"
  if ([23, 24, 25].indexOf(c) >= 0) return "󰖝"
  return "󰖕"
}

function weatherColor(code) {
  var c = Number(code)
  if ([31, 32, 33, 34, 36].indexOf(c) >= 0) return "#f4c84a"
  if ([3, 4, 35, 37, 38, 45, 47].indexOf(c) >= 0) return "#b58bea"
  if ([13, 14, 15, 16, 41, 42, 43, 46].indexOf(c) >= 0) return "#9bd9f5"
  if ([5, 6, 7, 8, 9, 10, 11, 12, 17, 18, 39, 40].indexOf(c) >= 0) return "#55aef0"
  if ([23, 24, 25].indexOf(c) >= 0) return "#79cfd1"
  return "#aab3c2"
}

function temperatureColor(value, minimum, maximum) {
  var low = Number(minimum)
  var high = Number(maximum)
  var current = Number(value)
  var ratio = high > low ? Math.max(0, Math.min(1, (current - low) / (high - low))) : 0.5
  var stops = ratio < 0.5
    ? [[105, 194, 112], [235, 203, 92], ratio * 2]
    : [[235, 203, 92], [239, 116, 101], (ratio - 0.5) * 2]
  var red = Math.round(stops[0][0] + (stops[1][0] - stops[0][0]) * stops[2])
  var green = Math.round(stops[0][1] + (stops[1][1] - stops[0][1]) * stops[2])
  var blue = Math.round(stops[0][2] + (stops[1][2] - stops[0][2]) * stops[2])
  return "rgb(" + red + "," + green + "," + blue + ")"
}

function number(value, fallback) {
  var parsed = Number(value)
  return isNaN(parsed) ? (fallback === undefined ? 0 : fallback) : parsed
}

function fixed(value, digits) {
  var parsed = Number(value)
  return isNaN(parsed) ? "—" : parsed.toFixed(digits === undefined ? 0 : digits)
}

function shortTime(value) {
  if (!value) return "—"
  var date = new Date(normalizedForecastTime(value))
  if (isNaN(date.getTime())) return "—"
  var hh = String(date.getHours()).padStart(2, "0")
  var mm = String(date.getMinutes()).padStart(2, "0")
  return hh + ":" + mm
}

function shortDay(value) {
  if (!value) return "—"
  var date = new Date(normalizedForecastTime(value))
  if (isNaN(date.getTime())) return "—"
  return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][date.getDay()]
}
