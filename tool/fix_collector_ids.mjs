#!/usr/bin/env node
/**
 * fix_collector_ids.mjs
 * ---------------------
 * One-time migration: fixes the collector ID mismatch by ensuring every
 * collector's `users/{phone}` doc stores their document ID as `collecteurId`.
 *
 * Background: before the fix, `addCollecteur` wrote `collecteurId: ''` to
 * `users/{phone}`. But `reassignCollecteur` writes the collector's document
 * ID (e.g. `b1723...`) to client docs. The collector dashboard then queries
 * by `user.collecteurId`, which was empty → fell back to phone number → no
 * match.
 *
 * This script:
 *   1. Queries all `collecteurs` docs.
 *   2. For each, checks `users/{phone}` to see if `collecteurId` matches.
 *   3. Patches any mismatches.
 *
 * Usage:
 *   node tool/fix_collector_ids.mjs            # dry-run (report only)
 *   node tool/fix_collector_ids.mjs --apply    # apply changes
 */
const PROJECT = process.env.FIREBASE_PROJECT ?? 'waste-pro-f67a5';
const APPLY = process.argv.includes('--apply');

const FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

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
    } else {
      fields[k] = { stringValue: String(v) };
    }
  }
  return fields;
}

async function getDoc(collection, id) {
  const res = await fetch(
    `${FIRESTORE}/${collection}/${encodeURIComponent(id)}`,
  );
  if (res.status === 404) return null;
  if (!res.ok)
    throw new Error(
      `GET ${collection}/${id} (${res.status}) : ${(await res.text()).slice(0, 300)}`,
    );
  return decodeFields((await res.json()).fields ?? {});
}

async function queryAll(collectionId) {
  const body = {
    structuredQuery: {
      from: [{ collectionId }],
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

const canonical = (raw) => {
  const cleaned = String(raw ?? '').trim().replace(/[\s-]/g, '');
  if (!cleaned) return '';
  if (cleaned.startsWith('+')) return cleaned;
  if (cleaned.startsWith('237')) return '+' + cleaned;
  return '+237' + cleaned;
};

// ------------------------------------------------------------------
async function main() {
  console.log('Fixing collector ID mismatch on users/{phone} docs...\n');

  const collectors = await queryAll('collecteurs');
  console.log(`Found ${collectors.length} collector(s).\n`);

  let fixed = 0;
  let alreadyOk = 0;
  let skipped = 0;
  let errors = 0;

  for (const collector of collectors) {
    const docId = collector.id;
    const name = collector.fields.name ?? '(unknown)';
    const phone = collector.fields.phone ?? '';
    const canonicalPhone = canonical(phone);

    if (!canonicalPhone) {
      console.log(`  ⏭️  ${docId} "${name}" — no phone number, skipping`);
      skipped++;
      continue;
    }

    const userDoc = await getDoc('users', canonicalPhone);
    if (!userDoc) {
      console.log(`  ⏭️  ${docId} "${name}" — no users/${canonicalPhone} doc, skipping`);
      skipped++;
      continue;
    }

    const currentCollecteurId = userDoc.collecteurId ?? '';
    if (currentCollecteurId === docId) {
      alreadyOk++;
      continue; // already correct, no output for clean docs
    }

    if (APPLY) {
      try {
        await patchDoc('users', canonicalPhone, { collecteurId: docId });
        console.log(`  ✅ ${canonicalPhone} "${name}" — collecteurId: "${currentCollecteurId || '(empty)'}" → "${docId}"`);
        fixed++;
      } catch (err) {
        console.error(`  ❌ ${canonicalPhone} "${name}" — ${err.message}`);
        errors++;
      }
    } else {
      console.log(`  → ${canonicalPhone} "${name}" — collecteurId: "${currentCollecteurId || '(empty)'}" → "${docId}"`);
      fixed++;
    }
  }

  console.log(
    `\n${APPLY
      ? `Done — ${fixed} fixed, ${alreadyOk} already OK, ${skipped} skipped, ${errors} error(s).`
      : `DRY-RUN — ${fixed} collector(s) would be fixed. Relancez avec --apply.`
    }`,
  );
}

main().catch((err) => {
  console.error(`\nError: ${err.message}`);
  process.exit(2);
});
