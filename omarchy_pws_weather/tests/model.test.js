const fs = require("fs")
const vm = require("vm")

const source = fs.readFileSync(require("path").join(__dirname, "..", "WeatherModel.js"), "utf8").replace(/^\.pragma library\s*/m, "")
const context = {}
vm.createContext(context)
vm.runInContext(source, context)

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

assert(context.unitCode("metric") === "m", "metric unit code")
assert(context.unitCode("imperial") === "e", "imperial unit code")
assert(context.unitCode("uk_hybrid") === "h", "hybrid unit code")

const obs = context.observation({ observations: [{ stationID: "TEST", metric: { temp: 12.3, windSpeed: 4 } }] }, "metric")
assert(obs.stationID === "TEST" && obs.temp === 12.3, "observation flattening")

const station = context.nearestStation({ location: { stationId: ["ABC"], stationName: ["Roof"], latitude: [1], longitude: [2] } })
assert(station.id === "ABC" && station.name === "Roof", "nearest station")
assert(context.nearestStations({ location: { stationId: ["A", "B"] } }).length === 2, "nearest station candidates")

const coords = context.ipCoordinates({ loc: "44.4,26.1" })
assert(coords.latitude === 44.4 && coords.longitude === 26.1, "IP coordinates")
assert(context.ipLocationName({ city: "Bucharest", region: "Bucuresti", country: "RO" }) === "Bucharest, Bucuresti, RO", "IP location label")
const searchedLocation = context.openMeteoLocationResult({ results: [{ name: "Brasov", admin1: "Brasov", country: "Romania", latitude: 45.65, longitude: 25.61 }] })
assert(searchedLocation.name === "Brasov, Romania" && searchedLocation.latitude === 45.65 && searchedLocation.longitude === 25.61, "Open-Meteo location search result")

const days = context.dailyForecast({ forecasts: [{ fcst_valid_local: "2026-09-01T07:00:00+0300", day: { long_daypart_name: "Tuesday", temp: 28, icon_code: 32, pop: 10 }, night: { temp: 16 } }] })
assert(days.length === 1 && days[0].high === 28 && days[0].low === 16, "daily forecast")

const hours = context.hourlyForecast({ forecasts: Array.from({ length: 30 }, (_, i) => ({ temp: i, icon_code: 32 })) })
assert(hours.length === 24, "hourly limit")

const v3Days = context.dailyForecast({
  validTimeLocal: ["2026-09-01T07:00:00+0300"],
  dayOfWeek: ["Tuesday"],
  temperatureMax: [28],
  temperatureMin: [16],
  sunriseTimeLocal: ["2026-09-01T06:40:00+0300"],
  sunsetTimeLocal: ["2026-09-01T19:45:00+0300"],
  moonPhase: ["Waning Gibbous"],
  daypart: [{
    daypartName: ["Tuesday", "Tuesday night"],
    wxPhraseLong: ["Sunny", "Clear"],
    iconCode: [32, 31],
    precipChance: [10, 5],
    relativeHumidity: [40, 60],
    windPhrase: ["Light wind", "Calm"]
  }]
})
assert(v3Days.length === 1 && v3Days[0].phrase === "Sunny" && v3Days[0].high === 28, "v3 daily forecast")

const v3Hours = context.hourlyForecast({
  validTimeLocal: ["2026-09-01T12:00:00+0300"],
  temperature: [25],
  temperatureFeelsLike: [26],
  wxPhraseLong: ["Partly Cloudy"],
  iconCode: [30],
  precipChance: [15]
})
assert(v3Hours.length === 1 && v3Hours[0].temperature === 25 && v3Hours[0].phrase === "Partly Cloudy", "v3 hourly forecast")

const meteobluePayload = {
  data_1h: {
    time: ["2026-09-01 12:00", "2026-09-01 13:00"],
    temperature: [25, 26],
    felttemperature: [26, 27],
    pictocode: [3, 6],
    precipitation_probability: [15, 60],
    precipitation: [0, 1.2],
    relativehumidity: [45, 50],
    windspeed: [10, 12],
    sealevelpressure: [1013, 1012]
  },
  data_day: {
    time: ["2026-09-01", "2026-09-02"],
    temperature_max: [28, 25],
    temperature_min: [16, 15],
    pictocode: [2, 7],
    precipitation: [3.08, 0],
    precipitation_probability: [10, 55],
    relativehumidity_mean: [50, 65],
    windspeed_mean: [8, 14]
  }
}
const meteoblueHours = context.meteoblueHourlyForecast(meteobluePayload, "metric")
assert(meteoblueHours.length === 2 && meteoblueHours[0].phrase === "Partly cloudy" && meteoblueHours[0].date.indexOf("T") > 0, "Meteoblue hourly forecast")
assert(context.currentHourlyForecast(meteoblueHours, "2026-09-01T12:45").phrase === "Partly cloudy", "current condition uses latest elapsed forecast hour")
assert(context.currentHourlyForecast(meteoblueHours, "2026-09-01T13:00").phrase === "Rain", "current condition changes at the next hour")
assert(context.currentHourlyForecast(meteoblueHours, "2026-09-01T11:30").phrase === "Partly cloudy", "current condition falls back to first future forecast hour")
const meteoblueDays = context.meteoblueDailyForecast(meteobluePayload, "metric")
assert(meteoblueDays.length === 2 && meteoblueDays[0].high === 28 && meteoblueDays[1].rainChance === 55, "Meteoblue daily forecast")
assert(meteoblueDays[0].rainAmount === 3.08, "Meteoblue daily precipitation amount")
const imperialHours = context.meteoblueHourlyForecast(meteobluePayload, "imperial")
assert(Math.round(imperialHours[0].temperature) === 77 && Math.round(imperialHours[0].windSpeed) === 6, "Meteoblue unit conversion")

const openMeteoPayload = {
  latitude: 44.43,
  longitude: 26.1,
  current: {
    temperature_2m: 25,
    apparent_temperature: 26,
    relative_humidity_2m: 45,
    dew_point_2m: 12,
    precipitation: 0.2,
    weather_code: 2,
    wind_speed_10m: 10,
    wind_gusts_10m: 18,
    pressure_msl: 1013,
    uv_index: 5,
    is_day: 1
  },
  hourly: {
    time: ["2026-09-01T13:00", "2026-09-01T14:00"],
    temperature_2m: [25, 24],
    apparent_temperature: [26, 25],
    relative_humidity_2m: [45, 50],
    precipitation_probability: [10, 65],
    precipitation: [0, 1.5],
    weather_code: [2, 63],
    wind_speed_10m: [10, 12],
    pressure_msl: [1013, 1012],
    uv_index: [5, 4],
    cloud_cover: [40, 85],
    is_day: [1, 1]
  },
  daily: {
    time: ["2026-09-01", "2026-09-02"],
    weather_code: [2, 80],
    temperature_2m_max: [28, 25],
    temperature_2m_min: [16, 15],
    precipitation_probability_max: [10, 55],
    precipitation_sum: [1.2, 4.6],
    wind_speed_10m_max: [18, 20],
    sunrise: ["2026-09-01T06:40", "2026-09-02T06:41"],
    sunset: ["2026-09-01T19:45", "2026-09-02T19:43"]
  }
}
const openMeteoHours = context.openMeteoHourlyForecast(openMeteoPayload, "metric")
assert(openMeteoHours.length === 2 && openMeteoHours[0].phrase === "Partly cloudy" && openMeteoHours[1].rainChance === 65, "Open-Meteo hourly forecast")
assert(openMeteoHours[1].rainAmount === 1.5, "Open-Meteo precipitation amount")
const openMeteoNow = context.openMeteoCurrent(openMeteoPayload, "metric", "Bucharest, RO")
assert(openMeteoNow.temp === 25 && openMeteoNow.heatIndex === 26 && openMeteoNow.neighborhood === "Bucharest, RO", "Open-Meteo current fallback")
const openMeteoDays = context.openMeteoDailyForecast(openMeteoPayload, "metric")
assert(openMeteoDays.length === 2 && openMeteoDays[0].high === 28 && openMeteoDays[1].phrase === "Rain showers", "Open-Meteo daily forecast")
assert(openMeteoDays[1].rainAmount === 4.6 && openMeteoDays[0].sunrise.indexOf("06:40") >= 0, "Open-Meteo daily rain and astronomy")
const supplement = context.openMeteoDailySupplement(openMeteoPayload, "metric")
const mergedDays = context.mergeDailySupplement([{ date: "2026-09-01", high: 28, low: 16 }], supplement)
assert(mergedDays[0].sunrise.indexOf("06:40") >= 0 && mergedDays[0].sunset.indexOf("19:45") >= 0 && mergedDays[0].rainAmount === 1.2, "daily astronomy supplement")
const openMeteoImperial = context.openMeteoHourlyForecast(openMeteoPayload, "imperial")
assert(Math.round(openMeteoImperial[0].temperature) === 77 && Math.round(openMeteoImperial[0].windSpeed) === 6, "Open-Meteo unit conversion")

const chartHours = Array.from({ length: 24 }, (_, index) => ({
  date: "2026-09-01T" + String(index).padStart(2, "0") + ":00",
  phrase: index === 4 ? "Rain" : "Clear",
  iconCode: index === 4 ? 12 : 32,
  rainChance: index === 4 ? 80 : 5,
  rainAmount: index === 4 ? 2 : 0,
  temperature: 15 + index / 2
}))
const threeHourly = context.threeHourForecast(chartHours)
assert(threeHourly.length === 8 && threeHourly[0].hours === 3, "three-hour forecast chunks")
assert(threeHourly[1].phrase === "Rain" && threeHourly[1].rainChance === 80, "three-hour severe condition selection")
assert(context.weatherWarning({ windGust: 65, precipRate: 0, uv: 2 }, [], "metric").indexOf("Strong gusts") >= 0, "live station warning")
assert(context.weatherWarning(null, [{ phrase: "Thunderstorms", date: "2026-09-01T18:00" }], "metric").indexOf("18:00") >= 0, "forecast warning")
assert(context.weatherWarning({ windGust: 5, precipRate: 0, uv: 2 }, chartHours, "metric") === "", "no warning for ordinary weather")
assert(context.weatherColor(12) === "#55aef0" && context.temperatureColor(0, 0, 30) !== context.temperatureColor(30, 0, 30), "semantic weather and temperature colors")
const dailyRange = context.dailyTemperatureRange([{ low: 10, high: 22 }, { low: 7, high: 19 }, { low: 12, high: 25 }])
assert(dailyRange.minimum === 7 && dailyRange.maximum === 25, "shared daily temperature range")

console.log("WeatherModel tests passed")
