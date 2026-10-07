// Checks functions/local-server.js against the Firebase emulators:
//
//   firebase emulators:exec --only auth,firestore --project demo-wastepro \
//     "node tool/local-server-check.mjs"
//
// Starts the local server, then: HTTP functions answer (with CORS), a new
// pickup gets its agency stamped, a new application is auto-approved.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';

const PROJECT = 'demo-wastepro';
const FS = `http://${process.env.FIRESTORE_EMULATOR_HOST}` +
  `/v1/projects/${PROJECT}/databases/(default)/documents`;
const BASE = 'http://localhost:5056';
const ADMIN = {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'};

const enc = (v) => typeof v === 'number' ? {integerValue: String(v)} :
  typeof v === 'boolean' ? {booleanValue: v} :
  Array.isArray(v) ? {arrayValue: {values: v.map(enc)}} : {stringValue: String(v)};
async function seed(path, data) {
  const res = await fetch(`${FS}/${path}`, {method: 'PATCH', headers: ADMIN,
    body: JSON.stringify({fields: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, enc(v)]))})});
  if (!res.ok) throw new Error(`seed ${path}: ${await res.text()}`);
}
async function field(path, name) {
  const res = await fetch(`${FS}/${path}`, {headers: ADMIN});
  if (!res.ok) return undefined;
  const v = (await res.json()).fields?.[name];
  return v && Object.values(v)[0];
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(fn, label) {
  for (let i = 0; i < 40; i++) {
    if (await fn()) return;
    await wait(250);
  }
  throw new Error(`timeout: ${label}`);
}

await seed('agences/ag1', {id: 'ag1', ville: 'Yaoundé', societeId: 'so1'});
await seed('utilisateurs/u1', {role: 'Agency Manager', status: 'Active',
  agenceId: 'ag1'});
await seed('zones/z1', {name: 'Bastos', agenceId: 'ag1', status: 'Active'});
await seed('clients/c1', {phone: '+237650000001', agenceId: 'ag1',
  societeId: 'so1', zone: 'Bastos'});
await seed('collecteurs/col1', {id: 'col1', name: 'Paul', status: 'Active',
  agenceId: 'ag1', societeId: 'so1', zone: 'Bastos', phone: '+237660000001'});

const server = spawn(process.execPath, ['functions/local-server.js'], {
  env: {...process.env, PORT: '5056', GCLOUD_PROJECT: PROJECT},
  stdio: ['ignore', 'pipe', 'pipe'],
});
let log = '';
server.stdout.on('data', (d) => log += d);
server.stderr.on('data', (d) => log += d);

let failures = 0;
async function check(name, fn) {
  try {
    await fn();
    console.log(`ok   ${name}`);
  } catch (e) {
    failures++;
    console.log(`FAIL ${name}\n     ${e.message}`);
  }
}

try {
  await until(async () => (await fetch(BASE).catch(() => null))?.ok,
      'server start');

  await check('HTTP function answers with CORS (publicAgencies)', async () => {
    const res = await fetch(`${BASE}/publicAgencies`,
        {headers: {Origin: 'http://localhost:8080'}});
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('access-control-allow-origin'),
        'http://localhost:8080');
    const data = await res.json();
    assert.deepEqual(data.agences.map((a) => a.id), ['ag1']);
    assert.deepEqual(data.zones, {ag1: ['Bastos']});
  });

  await check('preflight OPTIONS is accepted', async () => {
    const res = await fetch(`${BASE}/manageAccount`, {method: 'OPTIONS',
      headers: {'Origin': 'http://localhost:8080',
        'Access-Control-Request-Method': 'POST'}});
    assert.equal(res.status, 204);
  });

  await check('authenticated function refuses a missing token', async () => {
    const res = await fetch(`${BASE}/manageAccount`, {method: 'POST',
      headers: {'Content-Type': 'application/json'}, body: '{}'});
    assert.equal(res.status, 401);
  });

  await check('a new pickup gets its agency stamped', async () => {
    await seed('pickups/p1', {client_id: '+237650000001', status: 'x'});
    await until(async () => (await field('pickups/p1', 'agenceId')) === 'ag1',
        'pickup stamped');
  });

  await check('a new application is auto-approved', async () => {
    await wait(500); // the watcher skips documents present at start-up
    await seed('registrations/r1', {phone: '+237670000011',
      fullName: 'Applicant', status: 'pending', agenceId: 'ag1',
      societeId: 'so1', zone: 'Yaoundé: Bastos'});
    await until(async () =>
      (await field('registrations/r1', 'status')) === 'approved',
    'application approved');
    assert.equal(await field('registrations/r1', 'collecteurId'), 'col1');
  });
} finally {
  server.kill();
}
if (failures) console.log(`\n--- server log ---\n${log}`);
console.log(failures ? `\n${failures} failure(s)` : '\nLocal server OK.');
process.exit(failures ? 1 : 0);
