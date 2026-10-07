// Read-only probe: exact doc ids + all fields of collecteurs, clients, societes.
const KEY = 'AIzaSyBtZ2G7JI-XMHyWolGjLMtRMpbFBoq5Yhw';
const BASE =
  'https://firestore.googleapis.com/v1/projects/waste-pro-f67a5/databases/(default)/documents';

async function runQuery(collectionId) {
  const url = `${BASE}:runQuery?key=${KEY}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      structuredQuery: { from: [{ collectionId }], limit: 300 },
    }),
  });
  return res.json();
}

function flat(f) {
  if (f?.stringValue != null) return f.stringValue;
  if (f?.integerValue != null) return Number(f.integerValue);
  if (f?.booleanValue != null) return f.booleanValue;
  if (f?.doubleValue != null) return f.doubleValue;
  return '';
}

for (const coll of ['collecteurs', 'clients', 'societes', 'agences']) {
  const data = await runQuery(coll);
  if (!Array.isArray(data)) {
    console.log(`${coll} ERROR:`, JSON.stringify(data).slice(0, 400));
    continue;
  }
  console.log(`\n=== ${coll} (${data.filter((d) => d.document).length}) ===`);
  for (const d of data) {
    if (!d.document) continue;
    const id = d.document.name.split('/').pop();
    const f = d.document.fields ?? {};
    const rec = { id };
    for (const [k, v] of Object.entries(f)) {
      rec[k] = flat(v);
    }
    console.log(JSON.stringify(rec));
  }
}
