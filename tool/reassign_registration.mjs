#!/usr/bin/env node
/**
 * reassign_registration.mjs
 * --------------------------
 * Re-scope une candidature échouée sur une agence SANS chef d'agence vers
 * une agence gérée (visible dans un backoffice).
 *
 * Contexte : la candidature de Pinky (reg1786714733355498) est sur
 * `c1786458771247000` (« Yaounde — agence de nkoabang »), une agence sans
 * compte Agency Manager → aucun backoffice ne peut la voir. On la
 * réaffecte à « Yaounde — agence d'etoudi » (c1786459997542000), gérée par
 * Eric Ekwa — même société (f1786018142263091).
 *
 * Usage :
 *   node tool/reassign_registration.mjs              # rapport seul (dry-run)
 *   node tool/reassign_registration.mjs --apply      # applique
 */
const PROJECT = process.env.FIREBASE_PROJECT ?? 'waste-pro-f67a5';
const APPLY = process.argv.includes('--apply');

const FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

const REG_ID = 'reg1786714733355498'; // Pinky
const NEW_AGENCE_ID = 'c1786459997542000'; // Yaounde — agence d'etoudi (Eric Ekwa)
const NEW_AGENCE_NAME = "Yaounde — agence d'etoudi";

function decodeFields(fields) {
  const out = {};
  for (const [k, v] of Object.entries(fields)) {
    if ('stringValue' in v) out[k] = v.stringValue;
    else if ('booleanValue' in v) out[k] = v.booleanValue;
    else if ('integerValue' in v) out[k] = Number(v.integerValue);
    else if ('doubleValue' in v) out[k] = v.doubleValue;
    else out[k] = v;
  }
  return out;
}

function encodeFields(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === null || v === undefined) fields[k] = { nullValue: null };
    else fields[k] = { stringValue: String(v) };
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
      `GET ${collection}/${id} a échoué (${res.status}) : ${(await res.text()).slice(0, 400)}`,
    );
  const data = await res.json();
  return decodeFields(data.fields ?? {});
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
      `PATCH ${collection}/${id} a échoué (${res.status}) : ${(await res.text()).slice(0, 400)}`,
    );
}

async function main() {
  const reg = await getDoc('registrations', REG_ID);
  if (!reg) {
    console.error(`Candidature ${REG_ID} introuvable.`);
    process.exit(1);
  }
  console.log('Candidature actuelle :');
  console.log(`  fullName   : ${reg.fullName}`);
  console.log(`  phone      : ${reg.phone}`);
  console.log(`  status     : ${reg.status}`);
  console.log(`  agenceId   : ${reg.agenceId}`);
  console.log(`  agenceName : ${reg.agenceName}`);
  console.log(`  societeId  : ${reg.societeId}`);

  const target = await getDoc('agences', NEW_AGENCE_ID);
  if (!target) {
    console.error(`\nAgence cible ${NEW_AGENCE_ID} introuvable. Abandon.`);
    process.exit(1);
  }
  console.log(`\nAgence cible   : ${NEW_AGENCE_ID}`);
  console.log(`  ville      : ${target.ville}`);
  console.log(`  societeId  : ${target.societeId}`);

  if (reg.societeId !== target.societeId) {
    console.error(
      '\n⚠️  Sociétés différentes — réaffectation REFUSÉE (changement de société).',
    );
    process.exit(1);
  }
  if (reg.agenceId === NEW_AGENCE_ID) {
    console.log('\nDéjà sur l agence cible — rien à faire.');
    process.exit(0);
  }

  console.log(
    `\n${APPLY ? 'APPLICATION' : 'DRY-RUN (--apply pour écrire)'} : ` +
      `agenceId → ${NEW_AGENCE_ID}, agenceName → « ${NEW_AGENCE_NAME} »`,
  );

  if (APPLY) {
    await patchDoc('registrations', REG_ID, {
      agenceId: NEW_AGENCE_ID,
      agenceName: NEW_AGENCE_NAME,
    });
    const after = await getDoc('registrations', REG_ID);
    console.log('\nAprès :');
    console.log(`  agenceId   : ${after.agenceId}`);
    console.log(`  agenceName : ${after.agenceName}`);
    if (after.agenceId !== NEW_AGENCE_ID) {
      console.error('ÉCRITURE NON CONFIRMÉE — vérifier manuellement.');
      process.exit(1);
    }
    console.log('\n✅ Réaffectation confirmée.');
  }
}

main().catch((err) => {
  console.error(`\nErreur : ${err.message}`);
  process.exit(2);
});
