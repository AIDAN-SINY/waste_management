#!/usr/bin/env node
/**
 * diagnose_richard.mjs
 * --------------------
 * Diagnostic: traces the full tournee_service query chain for Richard
 * to find exactly why no clients appear on his dashboard.
 */
const PROJECT = process.env.FIREBASE_PROJECT ?? 'waste-pro-f67a5';
const FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

function decodeValue(v) {
  if ('stringValue' in v) return v.stringValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('nullValue' in v) return null;
  if ('arrayValue' in v)
    return (v.arrayValue?.values ?? []).map((e) => decodeValue(e));
  if ('mapValue' in v) return decodeFields(v.mapValue?.fields ?? {});
  return v;
}
function decodeFields(fields) {
  const out = {};
  for (const [k, v] of Object.entries(fields)) {
    out[k] = decodeValue(v);
  }
  return out;
}

async function getDoc(collection, id) {
  const res = await fetch(`${FIRESTORE}/${collection}/${encodeURIComponent(id)}`);
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`GET ${collection}/${id}: ${res.status}`);
  return decodeFields((await res.json()).fields ?? {});
}

async function query(collectionId, filters = {}) {
  const where = Object.entries(filters).map(([field, value]) => ({
    fieldFilter: {
      field: { fieldPath: field },
      op: 'EQUAL',
      value: { stringValue: value },
    },
  }));
  const body = {
    structuredQuery: {
      from: [{ collectionId }],
      where: where.length === 1 ? where[0] : { compositeFilter: { op: 'AND', filters: where } },
      limit: 100,
    },
  };
  const res = await fetch(`${FIRESTORE}:runQuery`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  return (Array.isArray(data) ? data : [])
    .filter((d) => d.document)
    .map((d) => ({
      id: d.document.name.split('/').pop(),
      fields: decodeFields(d.document.fields ?? {}),
    }));
}

const canonical = (raw) => {
  const cleaned = String(raw ?? '').trim().replace(/[\s-]/g, '');
  if (!cleaned) return '';
  if (cleaned.startsWith('+')) return cleaned;
  if (cleaned.startsWith('237')) return '+' + cleaned;
  return '+237' + cleaned;
};

const days = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
const today = days[new Date().getDay()];
console.log(`Today is: ${today}\n`);

async function main() {
  // 1. Find Richard's collector doc
  console.log('=== STEP 0: Find Richard ===');
  const allCollectors = await query('collecteurs');
  const richard = allCollectors.find(c => (c.fields.name ?? '').toLowerCase() === 'richard');
  if (!richard) { console.log('Richard not found!'); return; }
  const richardDocId = richard.id;
  const richardPhone = canonical(richard.fields.phone);
  console.log(`Richard doc ID: ${richardDocId}`);
  console.log(`Richard phone: ${richardPhone}`);

  // 2. Check his users/{phone} doc
  console.log('\n=== STEP 1: Check users/{phone} ===');
  const userDoc = await getDoc('users', richardPhone);
  if (!userDoc) { console.log(`users/${richardPhone} NOT FOUND!`); return; }
  console.log(`collecteurId: "${userDoc.collecteurId ?? '(missing)'}"`);
  console.log(`role: "${userDoc.role ?? '(missing)'}"`);
  console.log(`phone: "${userDoc.phoneNumber ?? '(missing)'}"`);

  // The collectorId the dashboard will use
  const dashboardCollectorId = userDoc.collecteurId && userDoc.collecteurId.length > 0
    ? userDoc.collecteurId
    : richardPhone;
  console.log(`\nDashboard will query with collectorId: "${dashboardCollectorId}"`);

  // 3. Query clients with this collecteurId
  console.log('\n=== STEP 2: Query clients where collecteurId = dashboardCollectorId ===');
  const clients = await query('clients', { collecteurId: dashboardCollectorId });
  console.log(`Found ${clients.length} client(s) with collecteurId="${dashboardCollectorId}"`);

  // Also try querying by phone number fallback
  if (dashboardCollectorId !== richardPhone) {
    const clientsByPhone = await query('clients', { collecteurId: richardPhone });
    console.log(`Found ${clientsByPhone.length} client(s) with collecteurId="${richardPhone}" (phone fallback)`);
  }

  // 4. Check each client's conditions
  console.log('\n=== STEP 3: Check each client ===');
  for (const client of clients) {
    const c = client.fields;
    const phone = canonical(c.phone);
    console.log(`\n--- Client: ${c.name} (${client.id}) ---`);
    console.log(`  status: "${c.status ?? '(missing)'}" ${c.status === 'Active' ? '✅' : '❌'}`);

    const userDoc = await getDoc('users', phone);
    if (!userDoc) {
      console.log(`  users/${phone}: NOT FOUND ❌`);
      continue;
    }
    console.log(`  users/${phone} exists ✅`);
    console.log(`  isSubscribed: ${userDoc.isSubscribed ?? '(missing)'} ${userDoc.isSubscribed === true ? '✅' : '❌'}`);

    const collectionDays = userDoc.collection_days ?? [];
    console.log(`  collection_days: [${collectionDays.join(', ')}] ${collectionDays.includes(today) ? '✅ includes today' : '❌ does NOT include today'}`);

    const pickupTime = userDoc.pickup_time ?? '(missing)';
    console.log(`  pickup_time: "${pickupTime}"`);
  }

  // 5. Also check if there are clients with richardDocId directly
  console.log('\n=== STEP 4: Query clients with richardDocId (doc ID) ===');
  if (dashboardCollectorId !== richardDocId) {
    const clientsByDocId = await query('clients', { collecteurId: richardDocId });
    console.log(`Found ${clientsByDocId.length} client(s) with collecteurId="${richardDocId}" (doc ID)`);
    for (const client of clientsByDocId) {
      console.log(`  ${client.fields.name} (${client.id}) — collecteurId: "${client.fields.collecteurId}"`);
    }
  }
}

main().catch((err) => { console.error(`Error: ${err.message}`); process.exit(2); });
