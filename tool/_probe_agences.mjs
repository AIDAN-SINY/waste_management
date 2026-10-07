// Read-only probe: dump agences + the 3-manager agency scopes + registrations.
const KEY = 'AIzaSyBtZ2G7JI-XMHyWolGjLMtRMpbFBoq5Yhw';
const BASE =
  'https://firestore.googleapis.com/v1/projects/waste-pro-f67a5/databases/(default)/documents';

async function runQuery(collectionId) {
  const url = `${BASE}:runQuery?key=${KEY}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      structuredQuery: { from: [{ collectionId }], limit: 100 },
    }),
  });
  return res.json();
}

function flat(f) {
  if (f?.stringValue != null) return f.stringValue;
  if (f?.integerValue != null) return Number(f.integerValue);
  if (f?.booleanValue != null) return f.booleanValue;
  return '';
}

for (const coll of ['agences', 'utilisateurs', 'registrations']) {
  const data = await runQuery(coll);
  if (!Array.isArray(data)) {
    console.log(`${coll} ERROR:`, JSON.stringify(data).slice(0, 400));
    continue;
  }
  console.log(`\n=== ${coll} (${data.filter((d) => d.document).length}) ===`);
  for (const d of data) {
    if (!d.document) continue;
    const f = d.document.fields ?? {};
    const name = d.document.name.split('/').pop();
    const rec = { name };
    for (const k of ['ville', 'nom', 'role', 'status', 'telephone', 'agenceId', 'societeId', 'agenceName', 'phone', 'fullName', 'responsable']) {
      if (f[k]) rec[k] = flat(f[k]);
    }
    console.log(JSON.stringify(rec));
  }
}
