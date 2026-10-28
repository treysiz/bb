/* Executes the actual bundled lifecycle bridge; no WebKit or sensor claims. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('ios_app/CameraApp/BridgeLifecycle.js', 'utf8');
let checks = 0;
function fixture(values = {}) {
  const calls = [];
  const context = {window: {}, ...values};
  context.stopCamera = reason => { calls.push(['camera', reason]); context.cameraActive = false; context.cameraStartPending = false; };
  context.stopListening = () => { calls.push(['audio']); context.ctx.state = 'closed'; };
  context.lockVault = () => calls.push(['lock']);
  for (const name of ['sessionToken', 'localStorage', 'sessionStorage']) {
    Object.defineProperty(context, name, {get() { throw Error('Native lifecycle must not read credentials'); }});
  }
  context.fetch = () => { throw Error('Unexpected request'); };
  context.startCamera = () => { throw Error('No automatic capture'); };
  vm.runInNewContext(source, context);
  return {context, calls, pause: () => context.window.MiniBridgeAppLifecycle.pause()};
}
{
  const f = fixture({cameraActive: true, cameraStartPending: false, ctx: {state: 'running'}});
  const result = f.pause();
  assert.equal(result.cameraStopped, true); assert.equal(result.audioStopped, true);
  assert.deepEqual(f.calls, [['camera', 'page_hidden'], ['audio'], ['lock']]);
  f.pause();
  assert.deepEqual(f.calls.slice(3), [['lock']]);
  checks += 4;
}
{
  const f = fixture({cameraActive: false, cameraStartPending: true, ctx: null});
  assert.equal(f.pause().cameraStopped, true);
  assert.deepEqual(f.calls, [['camera', 'page_hidden'], ['lock']]); checks += 2;
}
{
  const f = fixture({cameraActive: false, cameraStartPending: false, ctx: {state: 'closed'}, motionEnabled: true});
  f.pause();
  assert.deepEqual(f.calls, [['lock']]);
  assert.equal(f.context.motionEnabled, true); checks += 2;
}
{
  const context = {window: {}};
  vm.runInNewContext(source, context);
  const result = context.window.MiniBridgeAppLifecycle.pause();
  assert.equal(result.cameraStopped, false); assert.equal(result.audioStopped, false);
  assert.equal(Object.isFrozen(context.window.MiniBridgeAppLifecycle), true); checks += 3;
  assert.equal(context.window.MiniBridgeAppLifecycle.resume(), false); checks++;
}
{
  const f = fixture({cameraActive: false, ctx: {state: 'running'}});
  f.context.cameraActive = true;
  f.context.stopCamera = () => { throw Error('Synthetic player cleanup error'); };
  assert.equal(f.pause().audioStopped, true);
  assert.deepEqual(f.calls, [['audio'], ['lock']]); checks += 2;
}
for (const state of [null, {readyState: 2}, {readyState: 3}]) {
  const f = fixture({document: {querySelector: () => ({hidden: false})}, hasMediaDevice: () => true,
    cameraActive: false, cameraStartPending: false, cameraWs: state});
  f.context.reconnectCamera = () => f.calls.push(['control-only']);
  assert.equal(f.context.window.MiniBridgeAppLifecycle.resume(), true);
  assert.deepEqual(f.calls, [['control-only']]); checks += 2;
}
for (const values of [{cameraWs: {readyState: 1}}, {cameraWs: {readyState: 0}}, {cameraActive: true},
  {cameraStartPending: true}, {hasMediaDevice: () => false}, {document: {querySelector: () => ({hidden: true})}}]) {
  const f = fixture({document: {querySelector: () => ({hidden: false})}, hasMediaDevice: () => true,
    cameraActive: false, cameraStartPending: false, ...values});
  f.context.reconnectCamera = () => { throw Error('Must preserve existing/page scope'); };
  assert.equal(f.context.window.MiniBridgeAppLifecycle.resume(), false); checks++;
}
console.log(`PASS: ${checks} actual iOS lifecycle bridge checks; no credential reads, capture starts or monitor changes`);
