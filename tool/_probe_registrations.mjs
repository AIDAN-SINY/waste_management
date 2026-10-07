// Read-only probe: full detail of registrations (zone etc).
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

const data = await runQuery('registrations');
if (!Array.isArray(data)) {
  console.log('ERROR:', JSON.stringify(data).slice(0, 400));
} else {
  for (const d of data) {
    if (!d.document) continue;
    const f = d.document.fields ?? {};
    const rec = { id: d.document.name.split('/').pop() };
    for (const k of [
      'fullName',
      'phone',
      'zone',
      'status',
      'agenceId',
      'agenceName',
      'societeId',
      'collecteurId',
      'createdAt',
    ]) {
      if (f[k] !== undefined) rec[k] = flat(f[k]);
    }
    console.log(JSON.stringify(rec));
  }
}
