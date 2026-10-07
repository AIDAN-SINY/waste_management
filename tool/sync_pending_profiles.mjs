#!/usr/bin/env node
/**
 * sync_pending_profiles.mjs
 * -------------------------
 * Synchronise les profils des CANDIDATS PENDANTS (`users/{téléphone}` +
 * `auth_profiles/{uid}`) avec l'agence actuelle de leur candidature
 * (`registrations`). Utilisé après une réaffectation de candidature
 * (`reassign_registration.mjs`, `cleanup_disorder.mjs`) : le doc
 * `registrations` a été déplacé vers une autre agence, mais le profil de
 * connexion du client pointait encore vers l'ANCIENNE agence — il restait
 * « scotché » au mauvais backoffice.
 *
 * Pour chaque candidature :
 *   - si le numéro a un compte `users/{téléphone}`, les champs agence
 *     (agenceId / agenceName / societeId) sont alignés sur la candidature ;
 *   - `auth_profiles/{uid}` reçoit le même agenceId / societeId ;
 *   - une candidature SANS compte `users` est signalée (pré-migration) mais
 *     pas modifiée.
 *
 * Usage :
 *   node tool/sync_pending_profiles.mjs              # rapport seul (dry-run)
 *   node tool/sync_pending_profiles.mjs --apply      # applique
 */
const PROJECT = process.env.FIREBASE_PROJECT ?? 'waste-pro-f67a5';
const APPLY = process.argv.includes('--apply');

const FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

function canonicalPhone(raw) {
  const cleaned = String(raw ?? '').trim().replace(/[\s-]/g, '');
  if (!cleaned) return '';
  if (cleaned.startsWith('+')) return cleaned;
  if (cleaned.startsWith('237')) return '+' + cleaned;
  return '+237' + cleaned;
}

async function fetchAll(collection) {
  const docs = new Map();
  let pageToken = '';
  do {
    const url = `${FIRESTORE}/${collection}?pageSize=300${
      pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ''
    }`;
    const res = await fetch(url);
    if (!res.ok) {
      throw new Error(
        `GET ${collection} a échoué (${res.status}) : ${(await res.text()).slice(0, 400)}`,
      );
    }
    const data = await res.json();
    for (const doc of data.documents ?? []) {
      const id = doc.name.split('/').pop();
      docs.set(id, decodeFields(doc.fields ?? {}));
    }
    pageToken = data.nextPageToken ?? '';
  } while (pageToken);
  return docs;
}

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
    if (v === null || v === undefined) fields[k] = { nullValue: null };
    else if (typeof v === 'boolean') fields[k] = { booleanValue: v };
    else if (typeof v === 'number') fields[k] = { doubleValue: v };
    else fields[k] = { stringValue: String(v) };
  }
  return fields;
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

async function main() {
  console.log(`Synchronisation des profils candidats pendants — « ${PROJECT} »\n`);
  const registrations = await fetchAll('registrations');
  const users = await fetchAll('users');
  const profiles = await fetchAll('auth_profiles');

  const pending = [...registrations.entries()].filter(
    ([, r]) => String(r.status ?? '').toLowerCase() === 'pending',
  );
  console.log(`${pending.length} candidature(s) en attente.\n`);

  let synced = 0;
  for (const [regId, reg] of pending) {
    const phone = canonicalPhone(reg.phone);
    const nom = reg.fullName ?? regId;
    console.log(`\n=== ${regId} «${nom}» (${phone}) ===`);
    console.log(
      `  candidature → agenceId=${reg.agenceId ?? ''} («${reg.agenceName ?? ''}») societeId=${reg.societeId ?? ''}`,
    );
    if (!phone) {
      console.log('  ⏭️  numéro invalide — ignoré');
      continue;
    }

    const user = users.get(phone);
    if (!user) {
      console.log(`  ⏭️  pas de compte users/${phone} (pré-migration) — rien à faire`);
      continue;
    }
    const uid = user.uid ?? '';
    const profile = uid ? profiles.get(uid) : null;

    const userPatch = {};
    if ((user.agenceId ?? '') !== (reg.agenceId ?? '')) {
      userPatch.agenceId = reg.agenceId ?? '';
    }
    if ((user.agenceName ?? '') !== (reg.agenceName ?? '')) {
      userPatch.agenceName = reg.agenceName ?? '';
    }
    if ((user.societeId ?? '') !== (reg.societeId ?? '')) {
      userPatch.societeId = reg.societeId ?? '';
    }

    const profilePatch = {};
    if (profile) {
      if ((profile.agenceId ?? '') !== (reg.agenceId ?? '')) {
        profilePatch.agenceId = reg.agenceId ?? '';
      }
      if ((profile.societeId ?? '') !== (reg.societeId ?? '')) {
        profilePatch.societeId = reg.societeId ?? '';
      }
    }

    if (Object.keys(userPatch).length === 0 && Object.keys(profilePatch).length === 0) {
      console.log('  ✅ déjà synchronisé — rien à faire');
      continue;
    }

    console.log(`  users/${phone}     → ${JSON.stringify(userPatch)}`);
    if (profile) {
      console.log(`  auth_profiles/${uid} → ${JSON.stringify(profilePatch)}`);
    } else {
      console.log(`  ⚠️  uid=${uid || '(aucun)'} sans auth_profile`);
    }

    if (APPLY) {
      if (Object.keys(userPatch).length) await patchDoc('users', phone, userPatch);
      if (profile && Object.keys(profilePatch).length) {
        await patchDoc('auth_profiles', uid, profilePatch);
      }
      synced++;
      console.log('  ✅ écrit');
    }
  }

  console.log(
    `\n${APPLY ? `Terminé — ${synced} profil(s) synchronisé(s).` : 'DRY-RUN — aucune écriture. Relancez avec --apply.'}`,
  );
}

main().catch((err) => {
  console.error(`\nErreur : ${err.message}`);
  process.exit(2);
});
