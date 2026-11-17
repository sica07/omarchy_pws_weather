const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const root = path.join(__dirname, '..')
const model = {}
vm.createContext(model)
vm.runInContext(fs.readFileSync(path.join(root, 'WeatherModel.js'), 'utf8').replace(/^\.pragma library\s*/m, ''), model)
let now = new Date('2026-11-17T10:59:59').getTime()
let fetches = 0, icons = 0, locations = 0
const context = {
  Date: class extends Date { constructor(...args) { super(...(args.length ? args : [now])) } },
  WeatherModel: model, hourlyClock: now, lastForecastHour: model.hourKey(now),
  secretsReady: true, settingsSaving: false, forecastProcess: {running: false},
  latitude: 45, longitude: 25,
  updateHourlyCondition() { icons++ },
  fetchForecasts() { fetches++; context.lastForecastHour = model.hourKey(now) },
  refresh() { locations++ }
}
vm.createContext(context)
const source = fs.readFileSync(path.join(root, 'Panel.qml'), 'utf8')
const start = source.indexOf('  function checkHourlyRefresh()')
vm.runInContext(source.slice(start, source.indexOf('  function updateHourlyCondition()', start)), context)
context.checkHourlyRefresh()
assert.equal(fetches, 0)
now += 1000
context.checkHourlyRefresh()
assert.equal(fetches, 1)
assert.equal(icons, 1)
assert.equal(context.hourlyClock, now, 'clock change invalidates graph paint')
context.checkHourlyRefresh()
assert.equal(fetches, 1, 'no extra request within same hour')
now += 4 * 3600000
context.forecastProcess.running = true
context.checkHourlyRefresh()
assert.equal(fetches, 1, 'wait for in-flight request after resume')
context.forecastProcess.running = false
context.checkHourlyRefresh()
assert.equal(fetches, 2, 'catch up after suspend')
now += 3600000
context.settingsSaving = true
context.checkHourlyRefresh()
assert.equal(fetches, 2)
context.settingsSaving = false
context.checkHourlyRefresh()
assert.equal(fetches, 3, 'defer until settings save is complete')
now += 3600000
context.latitude = NaN
context.checkHourlyRefresh()
context.checkHourlyRefresh()
assert.equal(locations, 1, 'location failures must not cause one request per second')
const hours = Array.from({length: 72}, (_, i) => new Date(Date.UTC(2026, 10, 16, i)).toISOString().slice(0, 16))
const payload = {data_1h: {time: hours, temperature: hours.map((_, i) => i)}}
const day = model.meteoblueHourlyForecast(payload, 'metric', '2026-11-17T12:00:00')
assert.equal(day.length, 24)
assert.equal(day[0].date, '2026-11-17T00:00')
assert.equal(day[23].date, '2026-11-17T23:00')
assert.equal(day[0].temperature, 24, 'skip previous day in provider response')
assert.equal(model.currentHourlyForecast(day, '2026-11-17T13:15').temperature, 37)
assert.notEqual(model.hourKey('2026-11-17T23:00'), model.hourKey('2026-11-18T00:00'))
console.log('Hourly refresh tests passed')
