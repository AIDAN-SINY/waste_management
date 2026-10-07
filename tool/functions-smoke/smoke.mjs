// Smoke test of functions/index.js against the local emulators.
//
//   cd tool/functions-smoke
//   firebase emulators:exec --only auth,firestore,functions \
//     --project demo-wastepro "node smoke.mjs"
//
// Needs functions/.env.local (SMS_DEV_CODE=123456, CAMPAY_ENV=demo,
// CAMPAY_API=http://127.0.0.1:9177) and functions/.secret.local (dummy
// CAMPAY_* / HF_TOKEN). CamPay is replaced by a local fake server started
// below. No real SMS / payment is ever sent.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';

const jwt = createRequire(import.meta.url)('../../functions/node_modules/jsonwebtoken');
const CAMPAY_WEBHOOK_KEY = 'dummy-emulator-webhook-key';

const PROJECT = 'demo-wastepro';
const AUTH = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099'}`;
const FS = `http://${process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:9090'}` +
  `/v1/projects/${PROJECT}/databases/(default)/documents`;
const FN = `http://127.0.0.1:5001/${PROJECT}/us-central1`;

let failures = 0;
async function check(name, fn) {
  try {
    await fn();
    console.log(`ok   ${name}`);
  } catch (error) {
    failures++;
    console.log(`FAIL ${name}\n     ${error.message}`);
  }
}

// --- Emulator helpers ---------------------------------------------------
function encode(value) {
  if (value === null) return {nullValue: null};
  if (typeof value === 'boolean') return {booleanValue: value};
  if (typeof value === 'number') {
    return Number.isInteger(value) ? {integerValue: String(value)} : {doubleValue: value};
  }
  if (value instanceof Date) return {timestampValue: value.toISOString()};
  if (Array.isArray(value)) return {arrayValue: {values: value.map(encode)}};
  if (typeof value === 'object') {
    return {mapValue: {fields: Object.fromEntries(
        Object.entries(value).map(([k, v]) => [k, encode(v)]))}};
  }
  return {stringValue: String(value)};
}
function decode(v) {
  if ('stringValue' in v) return v.stringValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('nullValue' in v) return null;
  if ('arrayValue' in v) return (v.arrayValue.values ?? []).map(decode);
  if ('mapValue' in v) {
    return Object.fromEntries(Object.entries(v.mapValue.fields ?? {})
        .map(([k, x]) => [k, decode(x)]));
  }
  return v;
}
const ADMIN = {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'};
async function seed(path, data) {
  const res = await fetch(`${FS}/${path}`, {
    method: 'PATCH', headers: ADMIN,
    body: JSON.stringify({fields: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, encode(v)]))}),
  });
  if (!res.ok) throw new Error(`seed ${path}: ${await res.text()}`);
}
async function read(path) {
  const res = await fetch(`${FS}/${path}`, {headers: ADMIN});
  if (res.status === 404) return null;
  const doc = await res.json();
  return Object.fromEntries(Object.entries(doc.fields ?? {})
      .map(([k, v]) => [k, decode(v)]));
}
async function list(collection) {
  const res = await fetch(`${FS}/${collection}?pageSize=300`, {headers: ADMIN});
  const data = await res.json();
  return (data.documents ?? []).map((d) => Object.fromEntries(
      Object.entries(d.fields ?? {}).map(([k, v]) => [k, decode(v)])));
}

async function signUp(phone) {
  const res = await fetch(
      `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, {
        method: 'POST', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          email: `${phone.replace('+', '')}@wastepro.cm`,
          password: 'secret123', returnSecureToken: true,
        }),
      });
  const data = await res.json();
  return {uid: data.localId, idToken: data.idToken, refreshToken: data.refreshToken};
}

async function call(name, account, body = {}, method = 'POST') {
  const res = await fetch(`${FN}/${name}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(account ? {'Authorization': `Bearer ${account.idToken}`} : {}),
    },
    ...(method === 'POST' ? {body: JSON.stringify(body)} : {}),
  });
  return {status: res.status, data: await res.json().catch(() => ({}))};
}

async function account(key, phone, role, extra = {}) {
  const acc = await signUp(phone);
  await seed(`auth_profiles/${acc.uid}`, {uid: acc.uid, phone, role, ...extra});
  await seed(`users/${phone}`, {phoneNumber: phone, role, uid: acc.uid,
    fullName: key, ...extra});
  return acc;
}

// --- Scenario -----------------------------------------------------------
const client = await account('client', '+237650000001', 'client',
    {collecteurId: 'col1', agenceId: 'ag1', societeId: 'so1'});
const other = await account('other', '+237650000002', 'client');
const collector = await account('collector', '+237660000001', 'collector',
    {collecteurId: 'col1'});
const ga = await account('ga', '+237640000002', 'general_admin',
    {societeId: 'so1'});

await seed('agences/ag1', {id: 'ag1', ville: 'Yaoundé', societeId: 'so1'});
await seed('agences/ag2', {id: 'ag2', ville: 'Douala', societeId: 'so1'});
await seed('utilisateurs/u1', {role: 'Agency Manager', status: 'Active',
  agenceId: 'ag1'});
await seed('pickups/PKP-1', {client_id: client.uid && '+237650000001',
  collector_id: 'col1', collector_name: 'Boris', poids: 12.5,
  date: '2026-10-05', status: 'pending_client_confirmation'});

await check('publicAgencies: only agencies with an active manager', async () => {
  await seed('zones/z1', {name: 'Bastos', agenceId: 'ag1', status: 'Active'});
  await seed('zones/z2', {name: 'Mvan', agenceId: 'ag1', status: 'Inactive'});
  await seed('zones/z3', {name: 'Akwa', agenceId: 'ag2', status: 'Active'});
  const {status, data} = await call('publicAgencies', null, {}, 'GET');
  assert.equal(status, 200);
  assert.deepEqual(data.agences.map((a) => a.id), ['ag1']);
  // Active zones of listed agencies only.
  assert.deepEqual(data.zones, {ag1: ['Bastos']});
});

await check('notify: the collector asks the client to validate', async () => {
  const r = await call('notify', collector,
      {event: 'pickup_confirmation_request', pickupId: 'PKP-1'});
  assert.equal(r.status, 200, JSON.stringify(r.data));
  const notifs = (await list('notifications'))
      .filter((n) => n.phone === '+237650000001');
  assert.equal(notifs.length, 1);
  assert.match(notifs[0].message, /Boris collected 12\.5 kg/);
});

await check('notify: each event is delivered once', async () => {
  const r = await call('notify', collector,
      {event: 'pickup_confirmation_request', pickupId: 'PKP-1'});
  assert.equal(r.data.duplicate, true);
});

await check('notify: another client cannot act on this pickup', async () => {
  const r = await call('notify', other,
      {event: 'pickup_confirmed', pickupId: 'PKP-1'});
  assert.equal(r.status, 403);
});

await check('notify: the client confirms → client + collector notified', async () => {
  await seed('collecteurs/col1', {phone: '+237660000001'});
  const r = await call('notify', client,
      {event: 'pickup_confirmed', pickupId: 'PKP-1'});
  assert.equal(r.status, 200, JSON.stringify(r.data));
  const toCollector = (await list('notifications'))
      .filter((n) => n.phone === '+237660000001');
  assert.equal(toCollector.length, 1);
});

await check('notify: issue assigned / started / resolved, checked by role', async () => {
  await seed('issues/ISS-1', {id: 'ISS-1', client_id: '+237650000001',
    client_name: 'client', category: 'Overflowing bin', status: 'assigned',
    agenceId: 'ag1', societeId: 'so1', assignedCollecteurId: 'col1',
    assignedCollectorName: 'Boris', assignedCollectorPhone: '+237660000001'});
  const count = async (phone, type) => (await list('notifications'))
      .filter((n) => n.phone === phone && n.type === type).length;

  // Only the agency's staff announce an assignment; only HIS collector
  // reports progress.
  assert.equal((await call('notify', client,
      {event: 'issue_assigned', issueId: 'ISS-1'})).status, 403);
  assert.equal((await call('notify', other,
      {event: 'issue_started', issueId: 'ISS-1'})).status, 403);

  let r = await call('notify', ga, {event: 'issue_assigned', issueId: 'ISS-1'});
  assert.equal(r.status, 200, JSON.stringify(r.data));
  assert.equal(await count('+237660000001', 'issue_assigned'), 1);
  assert.equal(await count('+237650000001', 'issue_assigned'), 1);

  r = await call('notify', collector, {event: 'issue_started', issueId: 'ISS-1'});
  assert.equal(r.status, 200, JSON.stringify(r.data));
  r = await call('notify', collector, {event: 'issue_resolved', issueId: 'ISS-1'});
  assert.equal(r.status, 200, JSON.stringify(r.data));
  // Delivered once even if reported twice.
  await call('notify', collector, {event: 'issue_resolved', issueId: 'ISS-1'});
  assert.equal(await count('+237650000001', 'issue_started'), 1);
  assert.equal(await count('+237650000001', 'issue_resolved'), 1);
});

await check('chatbot: answers through the server (dummy token → clean error)', async () => {
  const r = await call('chatbot', client, {message: 'Hello', french: false});
  assert.ok([200, 502, 503].includes(r.status), JSON.stringify(r));
  assert.ok(!JSON.stringify(r.data).includes('hf_'), 'token leaked');
  const usage = await read(`chatbot_usage/${client.uid}`);
  assert.equal(usage.count, 1);
});

await check('startPayment: no pending leftover when CamPay is unreachable', async () => {
  const r = await call('startPayment', client,
      {purpose: 'subscription', plan: 'weekly', momoPhone: '650000001'});
  assert.equal(r.status, 502, JSON.stringify(r.data));
  const txs = await list('transactions');
  assert.equal(txs.length, 1);
  assert.equal(txs[0].status, 'failed');
  assert.equal(txs[0].displayAmount, 5500);
  assert.equal(txs[0].amount, 25);
});

await check('startPayment: refused for staff', async () => {
  const r = await call('startPayment', collector,
      {purpose: 'subscription', plan: 'weekly', momoPhone: '650000001'});
  assert.equal(r.status, 403);
});

// --- Fake CamPay (CAMPAY_API in functions/.env.local) -------------------
const campay = {payments: new Map(), collects: []};
const campayServer = createServer((req, res) => {
  let raw = '';
  req.on('data', (c) => raw += c);
  req.on('end', () => {
    const reply = (code, body) => {
      res.writeHead(code, {'Content-Type': 'application/json'});
      res.end(JSON.stringify(body));
    };
    const body = raw ? JSON.parse(raw) : {};
    if (req.method === 'POST' && req.url === '/token/') {
      return body.username === 'dummy-user' && body.password === 'dummy-pass' ?
        reply(200, {token: 'campay-token'}) :
        reply(401, {detail: 'Invalid credentials'});
    }
    if (req.headers.authorization !== 'Token campay-token') {
      return reply(401, {detail: 'Invalid token'});
    }
    if (req.method === 'POST' && req.url === '/collect/') {
      campay.collects.push(body);
      if (body.from === '237670000002') {
        return reply(400, {message: 'Number refused'});
      }
      const reference = `cp-${campay.payments.size + 1}`;
      campay.payments.set(reference, {reference, amount: Number(body.amount),
        external_reference: body.external_reference, status: 'PENDING',
        operator: 'MTN'});
      return reply(200, {reference, ussd_code: '*126#', operator: 'MTN'});
    }
    const ref = decodeURIComponent((req.url.match(/^\/transaction\/(.+)\/$/) ?? [])[1] ?? '');
    if (req.method === 'GET' && campay.payments.has(ref)) {
      return reply(200, campay.payments.get(ref));
    }
    return reply(404, {detail: 'Not found'});
  });
});
await new Promise((r) => campayServer.listen(9177, '127.0.0.1', r));

const payer = await account('payer', '+237650000009', 'client',
    {agenceId: 'ag1', societeId: 'so1'});
await seed('clients/cpayer', {phone: '+237650000009', agenceId: 'ag1',
  societeId: 'so1', name: 'Payer', zone: 'Bastos', plan: 'None'});
let paid;

await check('startPayment: sends the CamPay collect request (demo cap)', async () => {
  const r = await call('startPayment', payer, {purpose: 'subscription',
    plan: 'monthly', momoPhone: '6 70 00 00 00'});
  assert.equal(r.status, 200, JSON.stringify(r.data));
  assert.equal(r.data.amount, 25);
  assert.equal(r.data.displayAmount, 3000);
  assert.equal(r.data.ussdCode, '*126#');
  paid = r.data.txRef;
  const sent = campay.collects.at(-1);
  assert.equal(sent.from, '237670000000');
  assert.equal(sent.external_reference, paid);
  const tx = await read(`transactions/${paid}`);
  assert.equal(tx.status, 'pending');
  assert.equal(tx.paymentMethod, 'campay');
});

await check('startPayment: a number refused by CamPay → clean error', async () => {
  const r = await call('startPayment', payer, {purpose: 'extra_pickup',
    momoPhone: '670000002'});
  assert.equal(r.status, 502);
  assert.equal(r.data.error, 'Number refused');
});

await check('checkPayment: pending until CamPay succeeds', async () => {
  const r = await call('checkPayment', payer, {txRef: paid});
  assert.equal(r.data.status, 'pending');
  assert.equal((await read('users/+237650000009')).isSubscribed, undefined);
});

const webhook = (params) => fetch(`${FN}/campayWebhook`, {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify(params),
});

await check('campayWebhook: a forged signature is refused', async () => {
  const r = await webhook({external_reference: paid, status: 'SUCCESSFUL',
    signature: jwt.sign({source: 'campay'}, 'wrong-key')});
  assert.equal(r.status, 401);
  assert.equal((await read(`transactions/${paid}`)).status, 'pending');
});

await check('campayWebhook: settles only once CamPay says SUCCESSFUL', async () => {
  const tx = await read(`transactions/${paid}`);
  // The payload alone claims success: the server re-checks CamPay.
  const params = {external_reference: paid, status: 'SUCCESSFUL',
    reference: tx.campayReference,
    signature: jwt.sign({source: 'campay'}, CAMPAY_WEBHOOK_KEY)};
  let r = await webhook(params);
  assert.equal(r.status, 200);
  assert.equal((await read(`transactions/${paid}`)).status, 'pending');

  campay.payments.get(tx.campayReference).status = 'SUCCESSFUL';
  r = await webhook(params);
  assert.equal(r.status, 200);
  assert.equal((await read(`transactions/${paid}`)).status, 'successful');
  const user = await read('users/+237650000009');
  assert.equal(user.isSubscribed, true);
  assert.equal(user.subscription_plan, 'Monthly');
  const check = await call('checkPayment', payer, {txRef: paid});
  assert.equal(check.data.status, 'successful');
});

await check('manageAccount: an admin can act right after login (no 2FA)', async () => {
  const r = await call('manageAccount', ga,
      {action: 'ensure', phone: '+237699000001', password: 'secret123'});
  assert.equal(r.status, 200, JSON.stringify(r.data));
  assert.equal(r.data.created, true);
});

await check('manageAccount: a GA cannot reset a super admin', async () => {
  const sa = await account('sa', '+237640000001', 'super_admin');
  void sa;
  const r = await call('manageAccount', ga,
      {action: 'ensure', phone: '+237640000001', password: 'hijack123'});
  assert.equal(r.status, 403);
});

await check('stampPickupScope: a new pickup gets its client\'s agency', async () => {
  await seed('clients/cl1', {phone: '+237650000001', agenceId: 'ag1',
    societeId: 'so1', collecteurId: 'col1', status: 'Active',
    name: 'Alice', adresse: 'Rue 1', quartier: 'Bastos',
    latitude: 3.86712, longitude: 11.51234});
  await seed('pickups/PKP-2', {client_id: '+237650000001',
    collector_id: 'col1', status: 'pending_client_confirmation'});
  let pickup;
  for (let i = 0; i < 20; i++) {
    pickup = await read('pickups/PKP-2');
    if (pickup.agenceId) break;
    await new Promise((r) => setTimeout(r, 300));
  }
  assert.equal(pickup.agenceId, 'ag1');
  assert.equal(pickup.societeId, 'so1');
});

await check('collectorRoute: own stop in full, others anonymous', async () => {
  await seed('clients/cl2', {phone: '+237650000002', agenceId: 'ag1',
    societeId: 'so1', collecteurId: 'col1', status: 'Active',
    name: 'Bob Secret', adresse: 'Private street 9',
    latitude: 3.871234, longitude: 11.521987});
  // Bob pays (only paying clients are on the tour); an unpaid one is not.
  await seed('users/+237650000002', {phoneNumber: '+237650000002',
    role: 'client', uid: other.uid, isSubscribed: true});
  await seed('clients/cl3', {phone: '+237650000003', agenceId: 'ag1',
    collecteurId: 'col1', status: 'Active', name: 'Unpaid',
    latitude: 3.88, longitude: 11.53});
  const r = await call('collectorRoute', client);
  assert.equal(r.status, 200, JSON.stringify(r.data));
  assert.equal(r.data.stops.length, 2);
  const mine = r.data.stops.find((s) => s.isMine);
  const otherStop = r.data.stops.find((s) => !s.isMine);
  assert.equal(mine.name, 'Alice');
  assert.equal(otherStop.name, undefined);
  assert.equal(otherStop.address, undefined);
  assert.equal(otherStop.lat, 3.871);
  assert.ok(!JSON.stringify(r.data).includes('Bob'), 'other client leaked');
  assert.equal(r.data.stopsBeforeMe, 1);
});

await check('collectorRoute: clients only', async () => {
  const r = await call('collectorRoute', collector);
  assert.equal(r.status, 403);
});

// --- Automatic approval of applications --------------------------------
async function applicant(phone, extra) {
  const acc = await signUp(phone);
  await seed(`users/${phone}`, {phoneNumber: phone, role: 'pending_client',
    uid: acc.uid, fullName: 'Applicant'});
  await seed(`auth_profiles/${acc.uid}`, {uid: acc.uid, phone,
    role: 'pending_client'});
  await seed(`registrations/${extra.id}`, {phone, fullName: 'Applicant',
    status: 'pending', agenceId: 'agA', societeId: 'soA',
    agenceName: 'Yaoundé', createdAt: '2026-10-05', ...extra});
  return acc;
}
async function waitFor(path, predicate) {
  for (let i = 0; i < 30; i++) {
    const doc = await read(path);
    if (doc && predicate(doc)) return doc;
    await new Promise((r) => setTimeout(r, 300));
  }
  return read(path);
}

await seed('collecteurs/colZ', {name: 'Zoe Zone', zone: 'Bastos',
  status: 'Active', agenceId: 'agA', latitude: 3.90, longitude: 11.50});
await seed('collecteurs/colN', {name: 'Nina Near', zone: 'Mvog-Ada',
  status: 'Active', agenceId: 'agA', latitude: 3.8601, longitude: 11.5201});
await seed('collecteurs/colOff', {name: 'Off Duty', zone: 'Bastos',
  status: 'Inactive', agenceId: 'agA'});

await check('auto-approval: zone match wins, account becomes client', async () => {
  const acc = await applicant('+237670000011',
      {id: 'regZ', zone: 'Yaoundé: Bastos'});
  const reg = await waitFor('registrations/regZ', (r) => r.status !== 'pending');
  assert.equal(reg.status, 'approved', JSON.stringify(reg));
  assert.equal(reg.collecteurId, 'colZ');
  const user = await read('users/+237670000011');
  assert.equal(user.role, 'client');
  assert.equal(user.collecteurId, 'colZ');
  assert.equal(user.agenceId, 'agA');
  // Access only: the subscription starts with the client's payment.
  assert.equal(user.isSubscribed, false);
  assert.equal(user.subscription_plan, '');
  assert.equal((await read(`auth_profiles/${acc.uid}`)).role, 'client');
  assert.equal((await read('notifications/notifregZ')).type, 'approved');
  const clients = (await list('clients'))
      .filter((c) => c.phone === '+237670000011');
  assert.equal(clients.length, 1);
  assert.equal(clients[0].collecteurId, 'colZ');
  assert.equal(clients[0].plan, 'None');
  assert.equal(clients[0].subscribedAt, '');
});

await check('auto-approval: no zone match → nearest collector by GPS', async () => {
  await applicant('+237670000012', {id: 'regN', zone: 'Odza',
    latitude: 3.8600, longitude: 11.5200});
  const reg = await waitFor('registrations/regN', (r) => r.status !== 'pending');
  assert.equal(reg.collecteurId, 'colN');
  assert.equal(reg.autoApproval.reason, 'nearest');
});

await check('auto-approval: GPS inside a collector\'s circled zone wins', async () => {
  // Agency agZ: one collector matches the zone NAME, the other has the
  // applicant's GPS point inside the zone circled on the map.
  await seed('collecteurs/colName', {name: 'Name Match', zone: 'Nkoabang',
    status: 'Active', agenceId: 'agZ'});
  await seed('collecteurs/colArea', {name: 'Area Match', zone: 'Est',
    status: 'Active', agenceId: 'agZ', zoneArea: {name: 'Nkoabang',
      kind: 'polygon', source: 'drawn', centerLat: 3.864, centerLng: 11.587,
      radiusMeters: 0, points: [
        {lat: 3.85, lng: 11.57}, {lat: 3.85, lng: 11.60},
        {lat: 3.88, lng: 11.60}, {lat: 3.88, lng: 11.57}]}});
  await applicant('+237670000020', {id: 'regArea', zone: 'Nkoabang',
    agenceId: 'agZ', latitude: 3.865, longitude: 11.585});
  const reg = await waitFor('registrations/regArea',
      (r) => r.status !== 'pending');
  assert.equal(reg.collecteurId, 'colArea', JSON.stringify(reg));
  assert.equal(reg.autoApproval.reason, 'zone_area');

  // Outside the drawn zone → back to the zone name.
  await applicant('+237670000021', {id: 'regOut', zone: 'Nkoabang',
    agenceId: 'agZ', latitude: 3.95, longitude: 11.70});
  const out = await waitFor('registrations/regOut',
      (r) => r.status !== 'pending');
  assert.equal(out.collecteurId, 'colName', JSON.stringify(out));
  assert.equal(out.autoApproval.reason, 'zone');
});

await check('auto-approval: no zone match, no GPS → stays for the manager', async () => {
  await applicant('+237670000013', {id: 'regM', zone: 'Unknown place'});
  const reg = await waitFor('registrations/regM', (r) => r.autoApproval);
  assert.equal(reg.status, 'pending');
  assert.equal(reg.autoApproval.status, 'manual');
  assert.match(reg.autoApproval.reason, /no GPS point/);
  assert.equal((await read('users/+237670000013')).role, 'pending_client');
});

await check('auto-approval: capacity limit skips a full collector', async () => {
  await seed('agency_settings/agA', {agenceId: 'agA',
    maxClientsPerCollector: 1});
  // colZ already has 1 client (regZ) → full; colN has 1 (regN) → full.
  await applicant('+237670000014', {id: 'regF', zone: 'Bastos'});
  const reg = await waitFor('registrations/regF', (r) => r.autoApproval);
  assert.equal(reg.status, 'pending');
  assert.match(reg.autoApproval.reason, /limit of 1 clients/);
});

await check('auto-approval: a burst of applications never exceeds capacity', async () => {
  await seed('agency_settings/agA', {agenceId: 'agA',
    maxClientsPerCollector: 3});
  // colZ and colN have 1 client each → 4 free slots for 6 applicants.
  await Promise.all([1, 2, 3, 4, 5, 6].map((i) =>
    applicant(`+23767100000${i}`, {id: `regB${i}`, zone: 'Bastos',
      latitude: 3.86, longitude: 11.52})));
  const regs = [];
  for (let i = 1; i <= 6; i++) {
    regs.push(await waitFor(`registrations/regB${i}`,
        (r) => r.status !== 'pending' || r.autoApproval));
  }
  const approved = regs.filter((r) => r.status === 'approved');
  assert.equal(approved.length, 4, JSON.stringify(regs.map((r) => r.status)));
  const clients = (await list('clients')).filter((c) => c.agenceId === 'agA');
  for (const id of ['colZ', 'colN']) {
    assert.ok(clients.filter((c) => c.collecteurId === id).length <= 3,
        `${id} over capacity`);
  }
});

await check('auto-approval: switched off by the agency → untouched', async () => {
  await seed('agency_settings/agA', {agenceId: 'agA', autoApproval: false});
  await applicant('+237670000015', {id: 'regOff', zone: 'Bastos'});
  await new Promise((r) => setTimeout(r, 2500));
  const reg = await read('registrations/regOff');
  assert.equal(reg.status, 'pending');
  assert.equal(reg.autoApproval, undefined);
});

await check('recordCashPayment: a manager records a cash subscription', async () => {
  const manager = await account('managerA', '+237640000013', 'agency_manager',
      {agenceId: 'agA', societeId: 'soA'});
  // regZ's applicant was auto-approved in agA (access only).
  const r = await call('recordCashPayment', manager,
      {phone: '+237670000011', plan: 'weekly'});
  assert.equal(r.status, 200, JSON.stringify(r.data));
  assert.equal(r.data.amount, 5500);
  const user = await read('users/+237670000011');
  assert.equal(user.isSubscribed, true);
  assert.equal(user.subscription_plan, 'Weekly');
  const tx = await read(`transactions/${r.data.txRef}`);
  assert.equal(tx.paymentMethod, 'cash');
  assert.equal(tx.status, 'successful');
  assert.equal(tx.agenceId, 'agA');
  assert.equal((await read(`contracts/${r.data.contractId}`)).status, 'Active');
  const client = (await list('clients'))
      .find((c) => c.phone === '+237670000011');
  assert.equal(client.plan, 'Weekly');
  assert.notEqual(client.subscribedAt, '');
});

await check('recordCashPayment: refused outside the manager\'s agency', async () => {
  const other = await account('managerB', '+237640000014', 'agency_manager',
      {agenceId: 'agB', societeId: 'soA'});
  const r = await call('recordCashPayment', other,
      {phone: '+237670000011', plan: 'daily'});
  assert.equal(r.status, 403);
  const byClient = await call('recordCashPayment', client,
      {phone: '+237650000001', plan: 'daily'});
  assert.equal(byClient.status, 403);
});

// --- Collection days + next-period plans ------------------------------
const cashManager = await signUp('+237640000023');
await seed(`auth_profiles/${cashManager.uid}`, {uid: cashManager.uid,
  phone: '+237640000023', role: 'agency_manager', agenceId: 'agA',
  societeId: 'soA'});
async function cashClient(phone, zone) {
  await seed(`clients/c${phone.slice(-4)}`, {phone, agenceId: 'agA',
    societeId: 'soA', zone, status: 'Active', name: 'Cash ' + phone,
    plan: 'None'});
  await seed(`users/${phone}`, {phoneNumber: phone, role: 'client',
    uid: 'u' + phone.slice(-4), isSubscribed: false});
}

await check('collection days: from the zone calendar, per plan', async () => {
  await seed('zones/zBastos', {name: 'Bastos', agenceId: 'agA',
    collectionDays: ['Tuesday', 'Thursday', 'Saturday'],
    standardPickupTime: '06:00 — 07:00'});
  await cashClient('+237672000001', 'Yaoundé: Bastos');
  const r = await call('recordCashPayment', cashManager,
      {phone: '+237672000001', plan: 'weekly'});
  assert.equal(r.status, 200, JSON.stringify(r.data));
  const user = await read('users/+237672000001');
  assert.equal(user.collection_days.length, 2);
  assert.ok(user.collection_days.every((d) =>
    ['Tuesday', 'Thursday', 'Saturday'].includes(d)));
  assert.equal(user.pickup_time, '06:00 — 07:00');
  assert.equal(user.zone_name, 'Bastos');
});

await check('collection days: defaults when the agency has no calendar', async () => {
  await cashClient('+237672000002', 'Nowhere');
  const r = await call('recordCashPayment', cashManager,
      {phone: '+237672000002', plan: 'monthly'});
  assert.equal(r.status, 200, JSON.stringify(r.data));
  assert.deepEqual((await read('users/+237672000002')).collection_days,
      ['Wednesday']);
});

await check('next period: paying during a plan queues the new one', async () => {
  // +237672000001 runs Weekly; they switch to Daily for next month.
  const before = await read('users/+237672000001');
  const r = await call('recordCashPayment', cashManager,
      {phone: '+237672000001', plan: 'daily'});
  assert.equal(r.status, 200, JSON.stringify(r.data));
  assert.equal(r.data.scheduled, true);
  assert.equal(new Date(r.data.startsAt).getTime(),
      new Date(before.subscription_end).getTime());
  const user = await read('users/+237672000001');
  assert.equal(user.subscription_plan, 'Weekly'); // still running
  assert.equal(user.next_plan, 'Daily');
  const contract = await read(`contracts/${r.data.contractId}`);
  assert.equal(contract.status, 'Scheduled');
  assert.deepEqual(contract.collection_days,
      ['Tuesday', 'Thursday', 'Saturday']);
});

await check('next period: the daily job activates the queued plan', async () => {
  const day = 864e5;
  await seed('contracts/CTR-run', {client_id: '+237672000003',
    status: 'Active', frequency_id: 'Weekly',
    expiry_date: new Date(Date.now() - 2 * day)});
  await seed('contracts/CTR-next', {client_id: '+237672000003',
    status: 'Scheduled', frequency_id: 'Monthly',
    start_date: new Date(Date.now() - 2 * day),
    expiry_date: new Date(Date.now() + 28 * day),
    collection_days: ['Wednesday'], pickup_time: '07:00 — 08:00',
    amount_paid: 3000});
  await seed('users/+237672000003', {phoneNumber: '+237672000003',
    role: 'client', isSubscribed: true, active_contract_id: 'CTR-run',
    subscription_plan: 'Weekly', next_plan: 'Monthly'});
  const require = createRequire(import.meta.url);
  await require('../../functions/index.js').contractExpiry.run({});
  assert.equal((await read('contracts/CTR-run')).status, 'Expired');
  assert.equal((await read('contracts/CTR-next')).status, 'Active');
  const user = await read('users/+237672000003');
  assert.equal(user.isSubscribed, true);
  assert.equal(user.active_contract_id, 'CTR-next');
  assert.equal(user.subscription_plan, 'Monthly');
  assert.deepEqual(user.collection_days, ['Wednesday']);
  assert.equal(user.next_plan, undefined);
});

await check('repairSubscriptions: legacy accounts fixed, preview first', async () => {
  // samira-like: "Standard" granted at approval, never paid, no days.
  await seed('users/+237673000001', {phoneNumber: '+237673000001',
    role: 'client', fullName: 'Samira', isSubscribed: true,
    subscription_plan: 'Standard', agenceId: 'agA'});
  await seed('agences/agA', {id: 'agA', ville: 'Yaoundé — Bastos'});
  await seed('clients/cSam', {phone: '+237673000001', agenceId: 'agA',
    zone: 'Yaoundé: Bastos', plan: 'Standard', status: 'Active'});

  const sa = await account('saRepair', '+237640000099', 'super_admin');
  // Not for staff below super admin.
  const denied = await call('repairSubscriptions', cashManager, {});
  assert.equal(denied.status, 403);

  const preview = await call('repairSubscriptions', sa, {apply: false});
  assert.equal(preview.status, 200, JSON.stringify(preview.data));
  const samira = preview.data.changes.find((c) => c.phone === '+237673000001');
  assert.ok(samira, 'samira not in the report');
  assert.ok(samira.actions.some((a) => a.includes('30-day grace (Weekly)')));
  assert.equal((await read('users/+237673000001')).subscription_plan,
      'Standard', 'preview must not write');

  const applied = await call('repairSubscriptions', sa, {apply: true});
  assert.equal(applied.status, 200);
  const user = await read('users/+237673000001');
  assert.equal(user.subscription_plan, 'Weekly');
  assert.deepEqual(user.collection_days, ['Tuesday', 'Thursday']);
  assert.equal(user.agenceName, 'Yaoundé — Bastos');
  assert.ok(user.subscription_end);
  assert.equal((await read(`contracts/${user.active_contract_id}`)).status,
      'Active');
  // Second run: nothing left to repair for her.
  const again = await call('repairSubscriptions', sa, {apply: false});
  assert.ok(!again.data.changes.some((c) => c.phone === '+237673000001'));
});

// --- Forgotten password ------------------------------------------------
await check('password reset: same answer for unknown numbers', async () => {
  const r = await call('passwordResetStart', null, {phone: '+237699999998'});
  assert.equal(r.status, 200);
  assert.equal(r.data.sent, true);
  assert.equal(await read('password_resets/+237699999998'), null);
});

await check('password reset: SMS code → new password works', async () => {
  // `client` (+237650000001) signed up with "secret123".
  const start = await call('passwordResetStart', null,
      {phone: '650000001'});
  assert.equal(start.status, 200);
  const wrong = await call('passwordResetConfirm', null,
      {phone: '+237650000001', code: '000000', newPassword: 'newpass1'});
  assert.equal(wrong.status, 400);
  assert.match(wrong.data.error, /4 attempt/);
  const ok = await call('passwordResetConfirm', null,
      {phone: '+237650000001', code: '123456', newPassword: 'newpass1'});
  assert.equal(ok.status, 200, JSON.stringify(ok.data));
  const signIn = async (password) => (await fetch(
      `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake`,
      {method: 'POST', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({email: '237650000001@wastepro.cm', password,
          returnSecureToken: true})})).ok;
  assert.equal(await signIn('newpass1'), true);
  assert.equal(await signIn('secret123'), false);
  // The code cannot be reused.
  const again = await call('passwordResetConfirm', null,
      {phone: '+237650000001', code: '123456', newPassword: 'other123'});
  assert.equal(again.status, 400);
});

await check('contractExpiry: expires due contracts, reminds J-3', async () => {
  const day = 864e5;
  await seed('contracts/CTR-old', {client_id: '+237650000001', status: 'Active',
    expiry_date: new Date(Date.now() - 2 * day)});
  await seed('contracts/CTR-soon', {client_id: '+237650000002', status: 'Active',
    expiry_date: new Date(Date.now() + 3 * day)});
  await seed('users/+237650000001', {phoneNumber: '+237650000001',
    role: 'client', uid: client.uid, isSubscribed: true,
    active_contract_id: 'CTR-old'});
  const require = createRequire(import.meta.url);
  const fns = require('../../functions/index.js');
  await fns.contractExpiry.run({});
  assert.equal((await read('contracts/CTR-old')).status, 'Expired');
  assert.equal((await read('users/+237650000001')).isSubscribed, false);
  assert.deepEqual((await read('contracts/CTR-soon')).expiry_reminders_sent, ['3']);
});

console.log(failures ? `\n${failures} failure(s)` : '\nAll smoke checks passed.');
process.exit(failures ? 1 : 0);
