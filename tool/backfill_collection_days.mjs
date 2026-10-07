#!/usr/bin/env node
/**
 * backfill_collection_days.mjs
 * ----------------------------
 * One-time migration: backfills `collection_days` on existing `users/{phone}`
 * docs for clients created from the backoffice before the collection-days
 * feature was added.
 *
 * Scope:
 *   - Only targets docs where `role == 'client'` AND `consoleCreated == true`.
 *   - Skips docs that already have a non-empty `collection_days` array.
 *   - Sets a default of all 7 days (Monday–Sunday). The manager can refine
 *     individual clients afterwards through the backoffice edit form.
 *
 * Usage:
 *   node tool/backfill_collection_days.mjs            # dry-run (report only)
 *   node tool/backfill_collection_days.mjs --apply    # apply changes
 */
const PROJECT = process.env.FIREBASE_PROJECT ?? 'waste-pro-f67a5';
const APPLY = process.argv.includes('--apply');

const FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

const DEFAULT_DAYS = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday',
  'Friday', 'Saturday', 'Sunday',
];

// ------------------------------------------------------------------
function decodeFields(fields) {
  const out = {};
  for (const [k, v] of Object.entries(fields)) {
    if ('stringValue' in v) out[k] = v.stringValue;
    else if ('booleanValue' in v) out[k] = v.booleanValue;
    else if ('integerValue' in v) out[k] = Number(v.integerValue);
    else if ('doubleValue' in v) out[k] = v.doubleValue;
    else if ('nullValue' in v) out[k] = null;
    else if ('arrayValue' in v)
      out[k] = (v.arrayValue?.values ?? []).map((e) => decodeFields(e));
    else if ('mapValue' in v) out[k] = decodeFields(v.mapValue?.fields ?? {});
    else out[k] = v;
  }
  return out;
}

function encodeFields(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === null || v === undefined) {
      fields[k] = { nullValue: null };
    } else if (Array.isArray(v)) {
      fields[k] = { arrayValue: { values: v.map((item) => ({ stringValue: String(item) })) } };
    } else {
      fields[k] = { stringValue: String(v) };
    }
  }
  return fields;
}

async function query(collectionId, whereField, whereValue) {
  const body = {
    structuredQuery: {
      from: [{ collectionId }],
      where: {
        fieldFilter: {
          field: { fieldPath: whereField },
          op: 'EQUAL',
          value: { stringValue: whereValue },
        },
      },
      limit: 500,
    },
  };
  const res = await fetch(`${FIRESTORE}:runQuery`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  if (!res.ok)
    throw new Error(
      `QUERY ${collectionId} (${res.status}) : ${JSON.stringify(data).slice(0, 300)}`,
    );
  return (Array.isArray(data) ? data : [])
    .filter((d) => d.document)
    .map((d) => ({
      id: d.document.name.split('/').pop(),
      fields: decodeFields(d.document.fields ?? {}),
    }));
}

async function patchDoc(collection, id, fields) {
  const mask = Object.keys(fields)
    .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`)
    .join('&');
  const res = await fetch(
    `${FIRESTORE}/${collection}/${encodeURIComponent(id)}?${mask}`,
    {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ fields: encodeFields(fields) }),
    },
  );
  if (!res.ok)
    throw new Error(
      `PATCH ${collection}/${id} (${res.status}) : ${(await res.text()).slice(0, 300)}`,
    );
}

// ------------------------------------------------------------------
async function main() {
  console.log('Backfilling collection_days on backoffice-created client accounts...\n');

  // 1. Find all client accounts created by the backoffice.
  const clients = await query('users', 'role', 'client');
  const consoleClients = clients.filter((c) => c.fields.consoleCreated === true);
  console.log(`Found ${consoleClients.length} backoffice-created client account(s).`);

  // 2. Filter to those missing collection_days.
  const needsBackfill = consoleClients.filter((c) => {
    const days = c.fields.collection_days;
    return !Array.isArray(days) || days.length === 0;
  });
  console.log(`${needsBackfill.length} need collection_days backfill.\n`);

  if (needsBackfill.length === 0) {
    console.log('Nothing to do — all client accounts already have collection_days.');
    return;
  }

  // 3. Report & apply.
  let updated = 0;
  let errors = 0;

  for (const client of needsBackfill) {
    const phone = client.fields.phoneNumber ?? client.id;
    const name = client.fields.fullName ?? '(unknown)';
    const days = client.fields.collection_days;

    const existingInfo = Array.isArray(days) && days.length > 0
      ? ` (already has: ${days.join(', ')})`
      : '';

    if (APPLY) {
      try {
        await patchDoc('users', client.id, {
          collection_days: DEFAULT_DAYS,
        });
        console.log(`  ✅ ${phone} "${name}" — set to all 7 days${existingInfo}`);
        updated++;
      } catch (err) {
        console.error(`  ❌ ${phone} "${name}" — ${err.message}`);
        errors++;
      }
    } else {
      console.log(`  → ${phone} "${name}" — will set to all 7 days${existingInfo}`);
      updated++;
    }
  }

  console.log(
    `\n${APPLY
      ? `Done — ${updated} updated, ${errors} error(s).`
      : `DRY-RUN — ${updated} account(s) would be updated. Relancez avec --apply.`
    }`,
  );
}

main().catch((err) => {
  console.error(`\nError: ${err.message}`);
  process.exit(2);
});
