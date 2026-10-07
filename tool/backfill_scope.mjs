#!/usr/bin/env node
/**
 * backfill_scope.mjs
 * ------------------
 * ONE-OFF: adds the tenant scope (`agenceId` / `societeId`) that the
 * hardened firestore.rules rely on, to documents created before it existed:
 *
 *   - users/{phone}       ← from auth_profiles/{uid} (collector tours read
 *                           their agency's clients / login profiles);
 *   - pickups, issues,    ← from the client's `clients` record (matched by
 *     transactions          phone) — staff only see their agency's.
 *
 * It also renames the backoffice's old plan names to the app's
 * (Essential → Monthly, Standard → Weekly, Premium → Daily).
 *
 * New pickups / issues are stamped by the `stampPickupScope` /
 * `stampIssueScope` functions; this script only fixes the past.
 *
 * Run it AFTER deploying the functions and BEFORE deploying the rules
 * (public REST API, like migrate_auth.mjs / strip_passwords.mjs).
 *
 *   node tool/backfill_scope.mjs            # report only (dry-run)
 *   node tool/backfill_scope.mjs --apply    # write
 */
const PROJECT = process.env.FIREBASE_PROJECT ?? 'waste-pro-f67a5';
const APPLY = process.argv.includes('--apply');
const FIRESTORE =
  `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

function canonicalPhone(raw) {
  const cleaned = String(raw ?? '').trim().replace(/[\s-]/g, '');
  if (!cleaned) return '';
  if (cleaned.startsWith('+')) return cleaned;
  if (cleaned.startsWith('237')) return '+' + cleaned;
  return '+237' + cleaned;
}

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
      const fields = {};
      for (const [k, v] of Object.entries(d.fields ?? {})) {
        fields[k] = v.stringValue ?? v.booleanValue ?? v.integerValue ??
          v.doubleValue ?? null;
      }
      out.push({id: d.name.split('/').pop(), fields});
    }
    pageToken = data.nextPageToken ?? '';
  } while (pageToken);
  return out;
}

async function setScope(collection, id, scope) {
  const mask = ['agenceId', 'societeId']
      .map((k) => `updateMask.fieldPaths=${k}`).join('&');
  const res = await fetch(
      `${FIRESTORE}/${collection}/${encodeURIComponent(id)}?${mask}&currentDocument.exists=true`,
      {
        method: 'PATCH',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({fields: {
          agenceId: {stringValue: scope.agenceId},
          societeId: {stringValue: scope.societeId ?? ''},
        }}),
      });
  if (!res.ok) {
    throw new Error(`PATCH ${collection}/${id}: ${res.status} ${(await res.text()).slice(0, 300)}`);
  }
}

console.log(`Backfill tenant scope — project ${PROJECT}` +
  (APPLY ? '' : ' (dry-run)') + '\n');

let updated = 0;
let unresolved = 0;

// 1. users ← auth_profiles
const profiles = await listDocs('auth_profiles');
const users = new Map((await listDocs('users')).map((u) => [u.id, u.fields]));
for (const p of profiles) {
  const phone = canonicalPhone(p.fields.phone);
  const agenceId = p.fields.agenceId ?? '';
  if (!phone || !agenceId) continue;
  const key = users.has(phone) ? phone : phone.replace(/^\+237/, '');
  const user = users.get(key);
  if (!user || user.agenceId) continue;
  if (APPLY) {
    await setScope('users', key, {agenceId, societeId: p.fields.societeId});
  }
  updated++;
  console.log(`  users/${key} ← ${agenceId}`);
}

// 2. pickups / issues / transactions ← clients (by phone)
const scopeByPhone = new Map();
for (const c of await listDocs('clients')) {
  const phone = canonicalPhone(c.fields.phone);
  if (phone && c.fields.agenceId) {
    scopeByPhone.set(phone,
        {agenceId: c.fields.agenceId, societeId: c.fields.societeId ?? ''});
  }
}
const SOURCES = {
  pickups: (f) => f.client_id,
  issues: (f) => f.client_id,
  transactions: (f) => f.phone ?? f.userId,
};
for (const [collection, phoneOf] of Object.entries(SOURCES)) {
  let fixed = 0;
  for (const d of await listDocs(collection)) {
    if (d.fields.agenceId) continue;
    const scope = scopeByPhone.get(canonicalPhone(phoneOf(d.fields)));
    if (!scope) {
      unresolved++;
      continue;
    }
    if (APPLY) await setScope(collection, d.id, scope);
    fixed++;
    updated++;
  }
  console.log(`  ${collection}: ${fixed} document(s) scoped`);
}

// 3. Plan names unified with the app: Essential → Monthly, Standard →
//    Weekly, Premium → Daily (clients.plan, users.subscription_plan).
const PLAN_RENAME = {Essential: 'Monthly', Standard: 'Weekly', Premium: 'Daily'};
async function renamePlan(collection, field) {
  let renamed = 0;
  for (const d of await listDocs(collection)) {
    const next = PLAN_RENAME[d.fields[field]];
    if (!next) continue;
    if (APPLY) {
      const res = await fetch(
          `${FIRESTORE}/${collection}/${encodeURIComponent(d.id)}` +
          `?updateMask.fieldPaths=${field}`, {
            method: 'PATCH',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({fields: {[field]: {stringValue: next}}}),
          });
      if (!res.ok) throw new Error(`PATCH ${collection}/${d.id}: ${res.status}`);
    }
    renamed++;
    updated++;
  }
  console.log(`  ${collection}.${field}: ${renamed} plan name(s) renamed`);
}
await renamePlan('clients', 'plan');
await renamePlan('users', 'subscription_plan');

console.log(`\n${APPLY ? 'Updated' : 'Would update'} ${updated} document(s); ` +
  `${unresolved} without a matching client (stay visible to the super ` +
  'admin only).');
if (!APPLY) console.log('Re-run with --apply to write.');
