const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const source = fs.readFileSync(path.join(__dirname, '..', 'Panel.qml'), 'utf8')
// Execute the actual QML JavaScript request builder, with a fake Process.
const start = source.indexOf('  function run(process, url, origin, allowErrorBody) {')
const end = source.indexOf('  function refresh(', start)
const context = {}
vm.createContext(context)
vm.runInContext(source.slice(start, end), context)
for (const allowError of [true, false]) {
  const process = {running: false}
  const url = 'https://my.meteoblue.com/packages/basic-1h_basic-day?apikey=TEST_SECRET'
  context.run(process, url, '', allowError)
  assert.equal(process.command[0], 'curl')
  assert.equal(process.command[1], '-q')
  assert.equal(process.command.includes('--config'), true)
  assert.equal(process.command.includes('-'), true)
  assert.equal(JSON.stringify(process.command).includes('TEST_SECRET'), false)
  assert.equal(process.requestConfig, 'url = ' + JSON.stringify(url) + '\n')
  assert.equal(process.stdinEnabled, true)
  assert.equal(process.running, true)
  context.run(process, 'https://example.invalid/other', '', allowError)
  assert.equal(process.requestConfig, 'url = ' + JSON.stringify(url) + '\n', 'running requests must not have their pipe payload replaced')
}
console.log('Request credential transport tests passed')
