#!/usr/bin/env node
/**
 * cleanup_etoudi.mjs
 * ------------------
 * Nettoie le doublon d'agence « etoudi » (décision utilisateur : une seule
 * agence par quartier) :
 *   1. supprime l'agence vide « Yaounde — etoudi » (c1786468189675000,
 *      gérée par shayn) — contrôle de références AVANT suppression ;
 *   2. déplace shayn (console + compte de connexion + auth_profile) vers
 *      l'agence etoudi restante « Yaounde — agence d'etoudi »
 *      (c1786459997542000, gérée par Eric Ekwa) ;
 *   3. rattache le collecteur orphelin Vincent Onana (co2) à l'agence
 *      etoudi restante — sans collecteur, le chef d'agence ne peut pas
 *      approuver de candidature (la fiche de revue exige d'en choisir un).
 *
 * Sécurité : la suppression est précédée d'un contrôle de références
 * (candidatures / clients / collecteurs / comptes de connexion) — le script
 * REFUSE de supprimer si des données pointent encore vers l'agence cible.
 *
 * Usage :
 *   node tool/cleanup_etoudi.mjs              # rapport seul (dry-run)
 *   node tool/cleanup_etoudi.mjs --apply      # applique
 */
const PROJECT = process.env.FIREBASE_PROJECT ?? 'waste-pro-f67a5';
const APPLY = process.argv.includes('--apply');

const FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

// --- Plan validé ---
const KEEP_AGENCE_ID = 'c1786459997542000'; // Yaounde — agence d'etoudi (Eric Ekwa)
const KEEP_AGENCE_NAME = "Yaounde — agence d'etoudi";
const DELETE_AGENCE_ID = 'c1786468189675000'; // Yaounde — etoudi (shayn) — doublon vide

// shayn : console + login + profil de règles à basculer sur l'agence restante.
const SHAYN = {
  utilisateurId: 'c1786468192576000', // console
  loginPhone: '+237656778990', // users/{téléphone}
  uid: 'tf25VGbd3KhFqan5kZsaHKe7mXA3', // auth_profiles/{uid}
};

// Collecteur orphelin (sans agence valide) à rattacher à etoudi pour que
// l'approbation des candidatures soit possible.
const COLLECTOR_ID = 'co2'; // Vincent Onana
const COLLECTOR_NAME = 'Vincent Onana';

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
    if (v === null || v === undefined) fields[k] = { nullValue: null };
    else if (typeof v === 'boolean') fields[k] = { booleanValue: v };
    else if (typeof v === 'number') fields[k] = { doubleValue: v };
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
      `GET ${collection}/${id} (${res.status}) : ${(await res.text()).slice(0, 300)}`,
    );
  return decodeFields((await res.json()).fields ?? {});
}

async function query(collectionId, whereField, whereValue) {
  const body = whereField
    ? {
        structuredQuery: {
          from: [{ collectionId }],
          where: {
            fieldFilter: {
              field: { fieldPath: whereField },
              op: 'EQUAL',
              value: { stringValue: whereValue },
            },
          },
          limit: 100,
        },
      }
    : { structuredQuery: { from: [{ collectionId }], limit: 100 } };
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

async function deleteDoc(collection, id) {
  const res = await fetch(
    `${FIRESTORE}/${collection}/${encodeURIComponent(id)}`,
    { method: 'DELETE' },
  );
  if (!res.ok)
    throw new Error(
      `DELETE ${collection}/${id} (${res.status}) : ${(await res.text()).slice(0, 300)}`,
    );
}

// ------------------------------------------------------------------
async function main() {
  let changes = 0;
  const done = (msg) => {
    changes++;
    console.log(`  ✅ ${msg}`);
  };
  const skipped = (msg) => console.log(`  ⏭️  ${msg}`);

  // ---------- 0. Cibles présentes ? ----------
  console.log('0) VÉRIFICATION des cibles');
  const keep = await getDoc('agences', KEEP_AGENCE_ID);
  if (!keep) {
    console.log(`  ❌ agence restante ${KEEP_AGENCE_ID} introuvable — arrêt.`);
    process.exit(1);
  }
  const del = await getDoc('agences', DELETE_AGENCE_ID);
  if (!del) {
    console.log(`  ⏭️  agence ${DELETE_AGENCE_ID} déjà absente — rien à supprimer.`);
  } else {
    console.log(
      `  cible à supprimer : «${del.ville ?? ''}» (responsable=${del.responsable ?? ''})`,
    );
  }
  const collector = await getDoc('collecteurs', COLLECTOR_ID);
  if (!collector) {
    console.log(`  ❌ collecteur ${COLLECTOR_ID} introuvable — arrêt.`);
    process.exit(1);
  }
  console.log(
    `  collecteur à rattacher : ${COLLECTOR_NAME} (co2) — agenceId actuel=${collector.agenceId ?? '(aucun)'}`,
  );

  // ---------- 1. Contrôle de références sur l'agence à supprimer ----------
  if (del) {
    console.log('\n1) CONTRÔLE DE RÉFÉRENCES sur l agence à supprimer');
    const refs = [];
    for (const coll of ['registrations', 'clients', 'collecteurs', 'users']) {
      const hits = await query(coll, 'agenceId', DELETE_AGENCE_ID);
      // Le login de shayn est DÉPLACÉ (étape 2), pas une référence bloquante.
      const blocking = hits.filter((h) => h.id !== SHAYN.loginPhone);
      if (blocking.length) refs.push(`${coll}: ${blocking.map((h) => h.id).join(',')}`);
    }
    if (refs.length) {
      console.log(
        `  ❌ agence ${DELETE_AGENCE_ID} a des références — NON supprimée (${refs.join(' | ')})`,
      );
      console.log('  Déplacez d abord ces données (reassign_registration.mjs…).');
      process.exit(1);
    }
    skipped('aucune référence — suppression possible');
  }

  // ---------- 2. Déplacement de shayn vers l'agence restante ----------
  console.log('\n2) DÉPLACEMENT de shayn vers l agence etoudi restante');
  const consoleUser = await getDoc('utilisateurs', SHAYN.utilisateurId);
  if (!consoleUser) {
    console.log(`  ⏭️  utilisateurs/${SHAYN.utilisateurId} introuvable`);
  } else if ((consoleUser.agenceId ?? '') === KEEP_AGENCE_ID) {
    skipped('déjà sur l agence restante');
  } else {
    console.log(
      `  utilisateurs/${SHAYN.utilisateurId} «${consoleUser.nom ?? ''}» agenceId=${consoleUser.agenceId ?? '(aucun)'} → ${KEEP_AGENCE_ID}`,
    );
    if (APPLY) {
      await patchDoc('utilisateurs', SHAYN.utilisateurId, {
        agenceId: KEEP_AGENCE_ID,
        agence: KEEP_AGENCE_NAME,
      });
      done(`utilisateurs/${SHAYN.utilisateurId} → ${KEEP_AGENCE_NAME}`);
    } else {
      console.log('  → à déplacer');
    }
  }

  const login = await getDoc('users', SHAYN.loginPhone);
  if (!login) {
    console.log(`  ⏭️  users/${SHAYN.loginPhone} introuvable`);
  } else if ((login.agenceId ?? '') === KEEP_AGENCE_ID) {
    skipped('login déjà sur l agence restante');
  } else {
    console.log(
      `  users/${SHAYN.loginPhone} agenceId=${login.agenceId ?? '(aucun)'} → ${KEEP_AGENCE_ID}`,
    );
    if (APPLY) {
      await patchDoc('users', SHAYN.loginPhone, {
        agenceId: KEEP_AGENCE_ID,
        agenceName: KEEP_AGENCE_NAME,
      });
      done(`users/${SHAYN.loginPhone} → ${KEEP_AGENCE_NAME}`);
    } else {
      console.log('  → à déplacer');
    }
  }

  const profile = await getDoc('auth_profiles', SHAYN.uid);
  if (!profile) {
    console.log(`  ⏭️  auth_profiles/${SHAYN.uid} introuvable`);
  } else if ((profile.agenceId ?? '') === KEEP_AGENCE_ID) {
    skipped('auth_profile déjà sur l agence restante');
  } else {
    console.log(
      `  auth_profiles/${SHAYN.uid} agenceId=${profile.agenceId ?? '(aucun)'} → ${KEEP_AGENCE_ID}`,
    );
    if (APPLY) {
      await patchDoc('auth_profiles', SHAYN.uid, { agenceId: KEEP_AGENCE_ID });
      done(`auth_profiles/${SHAYN.uid} → ${KEEP_AGENCE_NAME}`);
    } else {
      console.log('  → à déplacer');
    }
  }

  // ---------- 3. Suppression de l'agence doublon ----------
  console.log('\n3) SUPPRESSION de l agence doublon');
  if (del) {
    if (APPLY) {
      await deleteDoc('agences', DELETE_AGENCE_ID);
      const after = await getDoc('agences', DELETE_AGENCE_ID);
      if (after) {
        console.log(`  ❌ agences/${DELETE_AGENCE_ID} toujours présente — arrêt.`);
        process.exit(1);
      }
      done(`agences/${DELETE_AGENCE_ID} «${del.ville ?? ''}» supprimée`);
    } else {
      console.log(`  → agences/${DELETE_AGENCE_ID} à supprimer`);
    }
  }

  // ---------- 4. Rattachement du collecteur orphelin à etoudi ----------
  console.log('\n4) RATTACHEMENT du collecteur à l agence etoudi');
  const sameAgence = (collector.agenceId ?? '') === KEEP_AGENCE_ID;
  const sameSociete =
    (collector.societeId ?? '') === (keep.societeId ?? '');
  if (sameAgence && sameSociete) {
    skipped(`${COLLECTOR_NAME} déjà sur l agence restante`);
  } else {
    console.log(
      `  collecteurs/${COLLECTOR_ID} ${COLLECTOR_NAME} → agenceId=${KEEP_AGENCE_ID}, societeId=${keep.societeId ?? ''}`,
    );
    if (APPLY) {
      await patchDoc('collecteurs', COLLECTOR_ID, {
        agenceId: KEEP_AGENCE_ID,
        societeId: keep.societeId ?? '',
      });
      done(`${COLLECTOR_NAME} rattaché à etoudi`);
    } else {
      console.log('  → à rattacher');
    }
  }

  console.log(
    `\n${APPLY ? `Terminé — ${changes} écriture(s) effectuée(s).` : `DRY-RUN — aucune écriture (${changes} action(s) planifiée(s)). Relancez avec --apply.`}`,
  );
}

main().catch((err) => {
  console.error(`\nErreur : ${err.message}`);
  process.exit(2);
});
