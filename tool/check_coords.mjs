#!/usr/bin/env node
const PROJECT = process.env.FIREBASE_PROJECT ?? 'waste-pro-f67a5';
const FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

function decodeFields(fields) {
  const out = {};
  for (const [k, v] of Object.entries(fields)) {
    if ('stringValue' in v) out[k] = v.stringValue;
    else if ('booleanValue' in v) out[k] = v.booleanValue;
    else if ('integerValue' in v) out[k] = Number(v.integerValue);
    else if ('doubleValue' in v) out[k] = v.doubleValue;
    else if ('nullValue' in v) out[k] = null;
    else if ('arrayValue' in v) out[k] = (v.arrayValue?.values ?? []).map(e => decodeValue(e));
    else if ('mapValue' in v) out[k] = decodeFields(v.mapValue?.fields ?? {});
    else out[k] = v;
  }
  return out;
}
function decodeValue(v) {
  if ('stringValue' in v) return v.stringValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('nullValue' in v) return null;
  if ('arrayValue' in v) return (v.arrayValue?.values ?? []).map(e => decodeValue(e));
  if ('mapValue' in v) return decodeFields(v.mapValue?.fields ?? {});
  return v;
}

async function getDoc(col, id) {
  const r = await fetch(`${FIRESTORE}/${col}/${encodeURIComponent(id)}`);
  if (r.status === 404) return null;
  return decodeFields((await r.json()).fields ?? {});
}

(async () => {
  const ismael = await getDoc('clients', 'b1787075214968000');
  const manuella = await getDoc('clients', 'b1787076977754000');
  console.log('Ismael:', JSON.stringify({ lat: ismael?.latitude, lng: ismael?.longitude, adresse: ismael?.adresse, quartier: ismael?.quartier, zone: ismael?.zone }));
  console.log('Manuella:', JSON.stringify({ lat: manuella?.latitude, lng: manuella?.longitude, adresse: manuella?.adresse, quartier: manuella?.quartier, zone: manuella?.zone }));
})();
