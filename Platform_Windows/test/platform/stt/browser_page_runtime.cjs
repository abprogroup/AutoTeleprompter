// Runs the actual HTML served by Dart, with a virtual clock and browser APIs.
// This verifies lifecycle/protocol logic, not microphone/cloud accuracy.
const assert = require('node:assert/strict');
const vm = require('node:vm');
let html = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => html += chunk);
process.stdin.on('end', () => {
  const source = html.match(/<script[^>]*>([\s\S]*?)<\/script>/)[1];
  function host(offline = false) {
    let now = 100000, nextId = 0;
    const timers = new Map(), messages = [], recognizers = [], elements = new Map(), listeners = new Map();
    class Socket {
      constructor() { this.readyState = 1; }
      send(json) { messages.push(JSON.parse(json)); }
      close() { this.readyState = 3; if (this.onclose) this.onclose(); }
    }
    class Recognition {
      constructor() { recognizers.push(this); }
      start(...args) { this.startArgs = args; this.onstart(); }
      abort() { this.aborted = true; if (this.onend) this.onend(); }
    }
    const context = vm.createContext({
      WebSocket: Socket, navigator: {onLine: !offline},
      window: {SpeechRecognition: Recognition, close() {}, addEventListener: (name, fn) => listeners.set(name, fn)},
      document: {getElementById(id) {
        if (!elements.has(id)) {
          const classes = new Set();
          elements.set(id, {textContent: '', classList: {
            add: x => classes.add(x), remove: x => classes.delete(x), contains: x => classes.has(x)
          }});
        }
        return elements.get(id);
      }},
      Date: {now: () => now}, console,
      setTimeout: (fn, ms) => { timers.set(++nextId, {fn, due: now + ms}); return nextId; },
      clearTimeout: id => timers.delete(id),
      setInterval: (fn, ms) => { timers.set(++nextId, {fn, due: now + ms, interval: ms}); return nextId; },
      clearInterval: id => timers.delete(id),
    });
    vm.runInContext(source, context);
    vm.runInContext('ensureWatchdog(); startRec(currentLocale);', context);
    function advance(ms) {
      const end = now + ms;
      for (;;) {
        const entries = [...timers].filter(([,v]) => v.due <= end).sort((a,b) => a[1].due - b[1].due);
        if (!entries.length) break;
        const [id, timer] = entries[0]; now = timer.due;
        if (timer.interval) timer.due += timer.interval; else timers.delete(id);
        timer.fn();
      }
      now = end;
    }
    return {context, messages, recognizers, advance, emit: name => listeners.get(name)()};
  }
  const lostEnd = host();
  lostEnd.recognizers[0].onerror({error: 'network'});
  lostEnd.advance(6000);
  assert.equal(lostEnd.recognizers.length, 2, 'network error without onend must recover in bounded time');
  assert.equal(lostEnd.recognizers[0].aborted, true);
  assert.equal(lostEnd.recognizers[1].startArgs.length, 0, 'keep default microphone path');
  const count = lostEnd.messages.length;
  lostEnd.recognizers[0].onresult({results: [[{transcript: 'stale'}]], resultIndex: 0});
  assert.equal(lostEnd.messages.length, count, 'old generation must not deliver speech');

  const normal = host();
  normal.recognizers[0].onerror({error: 'network'});
  normal.recognizers[0].onend();
  normal.advance(6000);
  assert.equal(normal.recognizers.length, 2, 'onend and watchdog cannot double restart');

  const quiet = host(); quiet.advance(120000);
  assert.equal(quiet.recognizers.length, 1, 'silence is not a recognition failure');
  const denied = host(); denied.recognizers[0].onerror({error: 'not-allowed'});
  denied.advance(120000);
  assert.equal(denied.recognizers.length, 1, 'do not retry permission failure');
  const closed = host(); closed.recognizers[0].onerror({error: 'network'});
  vm.runInContext("ws.onmessage({data: JSON.stringify({type: 'close'})});", closed.context);
  closed.advance(120000);
  assert.equal(closed.recognizers.length, 1, 'close cancels pending recovery');
  const resumed = host();
  resumed.recognizers[0].onerror({error: 'network'});
  function result(text, final) { const r = [{transcript: text}]; r.isFinal = final; return r; }
  quiet.recognizers[0].onresult({resultIndex: 0, results: [result('delayed but valid speech', true)]});
  assert.equal(quiet.messages.filter(m => m.type === 'result').at(-1).words,
    'delayed but valid speech', 'mere delay must not discard pending recognition');
  // An explicit failed generation is retired immediately, even if the browser
  // later sends a result. Only its replacement may prove speech has recovered.
  resumed.recognizers[0].onresult({resultIndex: 0, results: [
    result('late failed request', true)
  ]});
  assert.equal(resumed.messages.filter(m => m.type === 'result').length, 0);
  resumed.advance(1250);
  resumed.recognizers[1].onresult({resultIndex: 0, results: [
    result('corrected consumed words', true), result('new speech', false)
  ]});
  resumed.advance(6000);
  assert.equal(resumed.recognizers.length, 2, 'productive replacement result ends recovery');
  const delivered = resumed.messages.find(m => m.type === 'result');
  assert.equal(delivered.words, 'corrected consumed words new speech');
  assert.equal(delivered.isFinal, false);
  assert.deepEqual(delivered.segments, ['corrected consumed words', 'new speech']);
  assert.equal(delivered.finalizedSegmentCount, 1);

  const failures = host();
  for (const delay of [1250, 2500, 5000, 8000, 8000, 8000]) {
    const oldCount = failures.recognizers.length;
    const failed = failures.recognizers.at(-1);
    failed.onerror({error: 'network'});
    failed.onend(); // Must not schedule a competing restart.
    failures.advance(delay - 1);
    assert.equal(failures.recognizers.length, oldCount, 'respect capped backoff');
    failures.advance(1);
    assert.equal(failures.recognizers.length, oldCount + 1, 'one retry, no terminal third failure');
  }
  assert(failures.messages.some(m => m.phase === 'networkAwaitingSpeech'));
  failures.recognizers.at(-1).onresult({resultIndex: 0, results: [result('fresh matched words', false)]});
  failures.recognizers.at(-1).onerror({error: 'network'});
  const beforeReset = failures.recognizers.length;
  failures.advance(1250);
  assert.equal(failures.recognizers.length, beforeReset + 1, 'productive result resets backoff');

  const offline = host();
  offline.recognizers[0].onerror({error: 'network'});
  offline.emit('offline');
  offline.advance(120000);
  assert.equal(offline.recognizers.length, 1, 'no retry storm while explicitly offline');
  assert(offline.messages.some(m => m.phase === 'networkOffline'));
  assert(offline.messages.filter(m => m.type === 'heartbeat').length >= 19,
    'offline cloud connection must not starve localhost heartbeat');
  offline.emit('online'); offline.emit('online');
  offline.advance(250);
  assert.equal(offline.recognizers.length, 2, 'online resumes once, same engine');
  assert(offline.messages.some(m => m.phase === 'networkAwaitingSpeech'));
  const initialOffline = host(true);
  initialOffline.advance(60000);
  assert.equal(initialOffline.recognizers.length, 0, 'offline startup waits');
  assert(initialOffline.messages.filter(m => m.type === 'heartbeat').length >= 9);
  initialOffline.emit('online'); initialOffline.advance(250);
  assert.equal(initialOffline.recognizers.length, 1);

  const offlineStopped = host(); offlineStopped.emit('offline');
  vm.runInContext("ws.onmessage({data: JSON.stringify({type: 'close'})});", offlineStopped.context);
  offlineStopped.emit('online'); offlineStopped.advance(120000);
  assert.equal(offlineStopped.recognizers.length, 1, 'online cannot revive stopped session');
  denied.emit('offline'); denied.emit('online'); denied.advance(30000);
  assert.equal(denied.recognizers.length, 1, 'online cannot bypass permission denial');
  console.log('browser lifecycle checks passed');
});
