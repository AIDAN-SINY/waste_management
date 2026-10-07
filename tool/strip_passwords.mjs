#!/usr/bin/env node
/**
 * strip_passwords.mjs
 * -------------------
 * ONE-OFF cleanup: removes the plaintext `password` fields still stored in
 * Firestore. Since `manageAccount` (functions/index.js), the consoles no
 * longer need them — passwords live in Firebase Auth only.
 *
 * Collections: clients, collecteurs, utilisateurs, registrations, users.
 *
 * Before removing a password, the script makes sure the person keeps a
 * working login: if no Firebase Auth account exists for the number, it is
 * created WITH that password (e.g. collectors suspended under the old code,
 * whose Auth account had been deleted). On `utilisateurs`, `hasLogin: true`
 * replaces the password as the "has a login account" marker.
 *
 * Run it AFTER deploying the functions + new app, and BEFORE deploying the
 * hardened firestore.rules (it uses the public REST API, like
 * migrate_auth.mjs, which the hardened rules refuse).
 *
 * Usage:
 *   node tool/strip_passwords.mjs            # report only (dry-run)
 *   node tool/strip_passwords.mjs --apply    # apply
 */
import * as fs from 'node:fs';

const PROJECT = process.env.FIREBASE_PROJECT ?? 'waste-pro-f67a5';
const APPLY = process.argv.includes('--apply');

function webApiKey() {
  const src = fs.readFileSync('lib/firebase_options.dart', 'utf8');
  const web = src.split('static const FirebaseOptions web')[1] ?? '';
  return web.match(/apiKey:\s*'([^']+)'/)?.[1] ?? null;
}
const API_KEY = process.env.FIREBASE_API_KEY ?? webApiKey();
if (!API_KEY) {
  console.error('Web API key not found (set FIREBASE_API_KEY).');
  process.exit(2);
}

const FIRESTORE =
  `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const SIGN_UP =
  `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`;
const SIGN_IN =
  `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`;

function canonicalPhone(raw) {
  const cleaned = String(raw ?? '').trim().replace(/[\s-]/g, '');
  if (!cleaned) return '';
  if (cleaned.startsWith('+')) return cleaned;
  if (cleaned.startsWith('237')) return '+' + cleaned;
  return '+237' + cleaned;
}
const emailFor = (phone) => canonicalPhone(phone).replace('+', '') + '@wastepro.cm';

async function listDocs(collection) {
  const out = [];
  let pageToken = '';
  do {
    const url = `${FIRESTORE}/${collection}?pageSize=300` +
      (pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : '');
    const res = await fetch(url);
    if (!res.ok) {
      throw new Error(`GET ${collection}: ${res.status} ${(await res.text()).slice(0, 300)}`);
    }
    const data = await res.json();
    for (const d of data.documents ?? []) {
      const f = d.fields ?? {};
      out.push({
        id: d.name.split('/').pop(),
        password: f.password?.stringValue ?? '',
        hasPasswordField: 'password' in f,
        phone: f.phone?.stringValue ?? f.telephone?.stringValue ??
          f.phoneNumber?.stringValue ?? '',
      });
    }
    pageToken = data.nextPageToken ?? '';
  } while (pageToken);
  return out;
}

/** Deletes `password` (in the mask, absent from the body) + optional sets. */
async function stripDoc(collection, id, extra = {}) {
  const paths = ['password', ...Object.keys(extra)];
  const mask = paths
    .map((p) => `updateMask.fieldPaths=${encodeURIComponent(p)}`)
    .join('&');
  const fields = {};
  for (const [k, v] of Object.entries(extra)) fields[k] = {booleanValue: v};
  const res = await fetch(
    `${FIRESTORE}/${collection}/${encodeURIComponent(id)}?${mask}`,
    {
      method: 'PATCH',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({fields}),
    },
  );
  if (!res.ok) {
    throw new Error(`PATCH ${collection}/${id}: ${res.status} ${(await res.text()).slice(0, 300)}`);
  }
}

async function post(url, body) {
  const res = await fetch(url, {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify(body),
  });
  return {ok: res.ok, data: await res.json().catch(() => ({}))};
}

/**
 * Makes sure an Auth account exists for [phone]. Returns a short verdict.
 * An existing account keeps ITS password (Auth is the source of truth).
 */
async function ensureLogin(phone, password) {
  const email = emailFor(phone);
  const signIn = await post(SIGN_IN, {email, password, returnSecureToken: false});
  if (signIn.ok) return 'login OK';
  if (!APPLY) return 'login to check/create';
  const signUp = await post(SIGN_UP, {email, password, returnSecureToken: false});
  if (signUp.ok) return 'login CREATED from stored password';
  const msg = signUp.data.error?.message ?? '';
  if (msg.startsWith('EMAIL_EXISTS')) return 'login exists (different password)';
  return `login NOT created (${msg || 'error'}) — set a new password in the console`;
}

console.log(`Strip plaintext passwords — project ${PROJECT}` +
  (APPLY ? '' : ' (dry-run)') + '\n');

const COLLECTIONS = ['clients', 'collecteurs', 'utilisateurs', 'registrations', 'users'];
let stripped = 0;
let failures = 0;

for (const collection of COLLECTIONS) {
  const docs = (await listDocs(collection)).filter((d) => d.hasPasswordField);
  console.log(`— ${collection}: ${docs.length} doc(s) with a password field`);
  for (const d of docs) {
    try {
      let verdict = 'empty password';
      // `registrations` / `users`: accounts were created at pre-registration
      // / by migrate_auth.mjs — the leftover field is just removed.
      if (d.password && canonicalPhone(d.phone) &&
          ['clients', 'collecteurs', 'utilisateurs'].includes(collection)) {
        verdict = await ensureLogin(d.phone, d.password);
      }
      if (verdict.startsWith('login NOT created')) failures++;
      const extra = collection === 'utilisateurs' && d.password
        ? {hasLogin: true}
        : {};
      if (APPLY) await stripDoc(collection, d.id, extra);
      stripped++;
      console.log(`   ${d.id}  ${canonicalPhone(d.phone) || '(no phone)'}  ${verdict}`);
    } catch (err) {
      failures++;
      console.log(`   ${d.id}  ERROR ${err.message}`);
    }
  }
}

console.log(`\n${APPLY ? 'Removed' : 'Would remove'} ${stripped} password field(s); ` +
  `${failures} issue(s).`);
if (!APPLY) console.log('Re-run with --apply to write.');
process.exit(failures > 0 ? 1 : 0);
