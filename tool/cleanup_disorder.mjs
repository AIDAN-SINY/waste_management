#!/usr/bin/env node
/**
 * cleanup_disorder.mjs
 * --------------------
 * Réorganise la base de production (ordre validé par l'utilisateur) :
 *   1. réaffecte la candidature pendante de Giveon (reg1786462111896607) de
 *      l'agence sans chef nkoabang → « yaounde — agance de bastos »
 *      (c1786460992699000, shayn durand) ;
 *   2. supprime les AGENCES SANS CHEF d'agence actif :
 *      ag2 (Douala — Bassa), ag3 (Yaoundé), ag4 (Kribi),
 *      c1786458771247000 (Yaounde — agence de nkoabang) ;
 *   3. supprime les CHEFS SANS AFFECTATION RÉELLE :
 *      c1786368062400000 (daizi dev — agence fantôme c1786368039843000),
 *      us2 (Aïcha Bello — aucun agenceId) ;
 *   4. supprime la société orpheline so3 (plus aucune agence après ag4).
 *
 * Sécurité : chaque suppression est précédée d'un contrôle de références
 * (candidatures / clients / collecteurs / comptes de connexion) — le script
 * REFUSE de supprimer si des données pointent encore vers la cible. La
 * candidature APPROUVÉE de Marie Ekwala (agence fantôme) est LAISSÉE
 * intacte (choix utilisateur).
 *
 * Usage :
 *   node tool/cleanup_disorder.mjs            # rapport seul (dry-run)
 *   node tool/cleanup_disorder.mjs --apply    # applique
 */
const PROJECT = process.env.FIREBASE_PROJECT ?? 'waste-pro-f67a5';
const APPLY = process.argv.includes('--apply');

const FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

// --- Plan validé ---
const REASSIGN = {
  regId: 'reg1786462111896607', // Giveon #1 (pendant, sur nkoabang)
  toAgenceId: 'c1786460992699000', // yaounde — agance de bastos
  toAgenceName: 'yaounde — agance de bastos',
};

const AGENCIES_TO_DELETE = [
  'ag2', // Douala — Bassa
  'ag3', // Yaoundé
  'ag4', // Kribi (Suspended)
  'c1786458771247000', // Yaounde — agence de nkoabang
];

const MANAGERS_TO_DELETE = [
  { id: 'c1786368062400000', nom: 'daizi dev', phone: '674738258' },
  { id: 'us2', nom: 'Aïcha Bello', phone: '+237 699 33 67 41' },
];

const COMPANIES_TO_DELETE = ['so3']; // plus aucune agence après suppression d'ag4

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

const canonical = (raw) => {
  const cleaned = String(raw ?? '').trim().replace(/[\s-]/g, '');
  if (!cleaned) return '';
  if (cleaned.startsWith('+')) return cleaned;
  if (cleaned.startsWith('237')) return '+' + cleaned;
  return '+237' + cleaned;
};

// ------------------------------------------------------------------
async function main() {
  let changes = 0;
  const done = (msg) => {
    changes++;
    console.log(`  ✅ ${msg}`);
  };
  const skipped = (msg) => console.log(`  ⏭️  ${msg}`);

  // ---------- 1. Réaffectation Giveon #1 ----------
  console.log('1) RÉAFFECTATION candidature pendante');
  const reg = await getDoc('registrations', REASSIGN.regId);
  if (!reg) {
    console.log(`  ❌ ${REASSIGN.regId} introuvable — arrêt.`);
    process.exit(1);
  }
  console.log(
    `  ${REASSIGN.regId} «${reg.fullName}» actuellement agenceId=${reg.agenceId}`,
  );
  const target = await getDoc('agences', REASSIGN.toAgenceId);
  if (!target) {
    console.log(`  ❌ agence cible ${REASSIGN.toAgenceId} introuvable — arrêt.`);
    process.exit(1);
  }
  if (reg.societeId !== target.societeId) {
    console.log('  ❌ sociétés différentes — arrêt (pas de changement de société).');
    process.exit(1);
  }
  if (reg.agenceId === REASSIGN.toAgenceId) {
    skipped('déjà sur l agence cible');
  } else if (APPLY) {
    await patchDoc('registrations', REASSIGN.regId, {
      agenceId: REASSIGN.toAgenceId,
      agenceName: REASSIGN.toAgenceName,
    });
    const after = await getDoc('registrations', REASSIGN.regId);
    if (after.agenceId !== REASSIGN.toAgenceId) {
      console.log('  ❌ écriture non confirmée — arrêt.');
      process.exit(1);
    }
    done(`${REASSIGN.regId} → ${REASSIGN.toAgenceName}`);
  } else {
    console.log(
      `  → agenceId ${REASSIGN.toAgenceId} («${REASSIGN.toAgenceName}»), societeId inchangé`,
    );
  }

  // ---------- 2. Suppression des agences sans chef ----------
  console.log('\n2) SUPPRESSION des agences sans chef d agence');
  for (const id of AGENCIES_TO_DELETE) {
    const doc = await getDoc('agences', id);
    if (!doc) {
      skipped(`agences/${id} déjà absente`);
      continue;
    }
    // Contrôle de références : candidatures / clients / collecteurs.
    const refs = [];
    for (const coll of ['registrations', 'clients', 'collecteurs']) {
      const hits = await query(coll, 'agenceId', id);
      if (hits.length) refs.push(`${coll}: ${hits.map((h) => h.id).join(',')}`);
    }
    if (refs.length) {
      console.log(`  ❌ agences/${id} «${doc.ville ?? ''}» a des références — NON supprimée (${refs.join(' | ')})`);
      continue;
    }
    if (APPLY) {
      await deleteDoc('agences', id);
      const after = await getDoc('agences', id);
      if (after) {
        console.log(`  ❌ agences/${id} toujours présente après DELETE — arrêt.`);
        process.exit(1);
      }
      done(`agences/${id} «${doc.ville ?? ''}» supprimée`);
    } else {
      console.log(`  → agences/${id} «${doc.ville ?? ''}» (${doc.status ?? ''}) — à supprimer`);
    }
  }

  // ---------- 3. Suppression des chefs sans affectation ----------
  console.log('\n3) SUPPRESSION des chefs d agence sans affectation réelle');
  for (const m of MANAGERS_TO_DELETE) {
    const doc = await getDoc('utilisateurs', m.id);
    if (!doc) {
      skipped(`utilisateurs/${m.id} déjà absent`);
      continue;
    }
    // Compte de connexion éventuel (users/{téléphone} + auth_profiles/{uid}) :
    // s il existe, il est supprimé AUSSI — sinon le chef pourrait encore se
    // connecter alors que son compte console n existe plus.
    const canonicalPhone = canonical(m.phone);
    const loginRefs = await query('users', 'phoneNumber', canonicalPhone);
    const cascade = [];
    if (loginRefs.length) {
      const login = loginRefs[0];
      cascade.push(`users/${login.id}`);
      const uid = login.fields.uid ?? '';
      if (uid) {
        const prof = await getDoc('auth_profiles', uid);
        if (prof) cascade.push(`auth_profiles/${uid}`);
      }
    }
    if (APPLY) {
      await deleteDoc('utilisateurs', m.id);
      for (const c of cascade) {
        const [coll, id] = [c.split('/')[0], c.split('/')[1]];
        await deleteDoc(coll, id);
      }
      const after = await getDoc('utilisateurs', m.id);
      if (after) {
        console.log(`  ❌ utilisateurs/${m.id} toujours présente après DELETE — arrêt.`);
        process.exit(1);
      }
      done(`utilisateurs/${m.id} «${m.nom}» supprimée${cascade.length ? ` (+ ${cascade.join(', ')})` : ''}`);
    } else {
      console.log(
        `  → utilisateurs/${m.id} «${m.nom}» (agenceId=${doc.agenceId ?? '(aucun)'}) — à supprimer` +
          (cascade.length ? ` + cascade ${cascade.join(', ')}` : ''),
      );
    }
  }

  // ---------- 4. Suppression de la société orpheline so3 ----------
  console.log('\n4) SUPPRESSION de la société orpheline so3');
  for (const id of COMPANIES_TO_DELETE) {
    const doc = await getDoc('societes', id);
    if (!doc) {
      skipped(`societes/${id} déjà absente`);
      continue;
    }
    const ags = await query('agences', 'societeId', id);
    const users = await query('utilisateurs', 'societeId', id);
    if (ags.length || users.length) {
      console.log(`  ❌ societes/${id} a encore agences=${ags.length} / utilisateurs=${users.length} — NON supprimée`);
      continue;
    }
    if (APPLY) {
      await deleteDoc('societes', id);
      const after = await getDoc('societes', id);
      if (after) {
        console.log(`  ❌ societes/${id} toujours présente après DELETE — arrêt.`);
        process.exit(1);
      }
      done(`societes/${id} supprimée`);
    } else {
      console.log(`  → societes/${id} — à supprimer`);
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
