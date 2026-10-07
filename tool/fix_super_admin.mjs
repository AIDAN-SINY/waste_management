#!/usr/bin/env node
/**
 * fix_super_admin.mjs
 * -------------------
 * Répare les comptes super admin de la collection `users` qui ne peuvent
 * PAS se connecter depuis l'app (symptôme : « User not found » au login).
 *
 * Corrections appliquées (après relecture du rapport) :
 *   1. Clé de document non canonique (ex. `653645807` au lieu de
 *      `+237653645807`) → le doc est recopié sous la clé canonique puis
 *      l'ancien est supprimé. Le login de l'app ne tente que `users/+237…`.
 *   2. Rôle erroné (`super-admin` avec un tiret) → corrigé en `super_admin`
 *      (le routeur ne reconnaît que `super_admin`).
 *   3. Champ `phoneNumber` manquant/vide → rempli avec la clé canonique
 *      (nécessaire à l'auto-login / refreshUser).
 *   4. Mot de passe vide → signalé ; renseigné seulement si `--password`
 *      est fourni (appliqué aux comptes concernés).
 *
 * Par défaut : DRY-RUN — aucun accès en écriture. Ajoutez `--apply` pour
 * appliquer les corrections (les règles déployées doivent autoriser
 * l'écriture, cf. firestore.rules).
 *
 * Usage :
 *   node tool/fix_super_admin.mjs                  # rapport seul
 *   node tool/fix_super_admin.mjs --apply          # applique les corrections
 *   node tool/fix_super_admin.mjs --apply --password MonMdp123
 *   FIREBASE_PROJECT=autre-projet node tool/fix_super_admin.mjs
 */
const PROJECT = process.env.FIREBASE_PROJECT ?? 'waste-pro-f67a5';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

const APPLY = process.argv.includes('--apply');
const PASSWORD = process.argv.includes('--password')
  ? process.argv[process.argv.indexOf('--password') + 1]
  : null;

// --- Normalisation (miroir de AuthService.canonicalPhone) ---
function canonicalPhone(raw) {
  const cleaned = String(raw ?? '').trim().replace(/[\s-]/g, '');
  if (!cleaned) return '';
  if (cleaned.startsWith('+')) return cleaned;
  if (cleaned.startsWith('237')) return '+' + cleaned;
  return '+237' + cleaned;
}

const isSuperAdmin = (role) =>
  ['super_admin', 'super-admin'].includes(String(role ?? '').trim().toLowerCase());

// --- Récupère tous les docs d'une collection (avec pagination) ---
async function fetchAll(collection) {
  const docs = new Map();
  let pageToken = '';
  do {
    const url = `${BASE}/${collection}?pageSize=300${
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

// --- Décodage des champs typés de l'API REST ---
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

// --- Encodage des champs pour l'API REST ---
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

// Chemin du doc : la collection DOIT être dans le chemin REST v1
// (`documents/users/{id}`) et le masque se passe via
// `updateMask.fieldPaths=` (l'ancien `updateMask.field=` n'est plus
// accepté par l'API).
const docPath = (id) => `${BASE}/documents/users/${encodeURIComponent(id)}`;

async function createDoc(id, fields) {
  const res = await fetch(
    `${BASE}/users?documentId=${encodeURIComponent(id)}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ fields: encodeFields(fields) }),
    },
  );
  if (!res.ok)
    throw new Error(`POST users/${id} a échoué (${res.status}) : ${(await res.text()).slice(0, 400)}`);
}

async function patchDoc(id, fields) {
  const mask = Object.keys(fields)
    .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`)
    .join('&');
  const res = await fetch(`${docPath(id)}?${mask}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: encodeFields(fields) }),
  });
  if (!res.ok)
    throw new Error(`PATCH users/${id} a échoué (${res.status}) : ${(await res.text()).slice(0, 400)}`);
}

async function deleteDoc(id) {
  const res = await fetch(docPath(id), { method: 'DELETE' });
  if (!res.ok)
    throw new Error(`DELETE users/${id} a échoué (${res.status}) : ${(await res.text()).slice(0, 400)}`);
}

const PAD = (s, n) => String(s ?? '').padEnd(n);

function planFor(key, doc) {
  const role = String(doc.role ?? '').trim();
  const canonical = canonicalPhone(key);
  const fixes = [];
  const changed = {};

  if (!isSuperAdmin(role)) return null; // hors périmètre (clients, admin console…)

  if (canonical && key !== canonical) fixes.push('clé non canonique → déplacer');
  if (role.toLowerCase() === 'super-admin') fixes.push('rôle « super-admin » → « super_admin »');
  if (!doc.phoneNumber) fixes.push('phoneNumber manquant → à remplir');
  if (!doc.password) fixes.push('mot de passe VIDE → à renseigner');
  if (fixes.length === 0) return { ok: true, fixes, changed };

  const targetKey = canonical || key;
  changed.role = 'super_admin';
  changed.phoneNumber = targetKey;
  if (PASSWORD && !doc.password) changed.password = PASSWORD;
  return { ok: false, targetKey, move: key !== targetKey, fixes, changed };
}

async function applyPlan(key, doc, plan) {
  const base = { ...doc, ...plan.changed };
  if (plan.move) {
    await createDoc(plan.targetKey, base);
    await deleteDoc(key);
  } else {
    await patchDoc(key, plan.changed);
  }
}

async function main() {
  console.log(`Lecture de la base « ${PROJECT} »…\n`);

  const users = await fetchAll('users');
  const broken = [];
  const ok = [];

  for (const [key, doc] of users) {
    const plan = planFor(key, doc);
    if (!plan) continue;
    (plan.ok ? ok : broken).push({ key, doc, plan });
  }

  // Détection de conflit : la clé canonique cible existe déjà (ex. les deux
  // clés '653645807' ET '+237653645807' sont présentes) — un simple POST
  // échouerait (409). Ces comptes sont exclus du déplacement automatique et
  // signalés pour fusion manuelle.
  for (const { plan } of broken) {
    if (plan.move && users.has(plan.targetKey)) plan.conflict = true;
  }

  console.log(`— COMPTES SUPER ADMIN : ${broken.length + ok.length} au total —\n`);

  const header =
    `${PAD('CLÉ', 24)} | ${PAD('RÔLE', 14)} | ${PAD('MDP', 6)} | DIAGNOSTIC`;
  console.log(header);
  console.log('-'.repeat(110));

  for (const { key, doc, plan } of ok) {
    console.log(
      `${PAD(key, 24)} | ${PAD(doc.role, 14)} | ${PAD(doc.password ? doc.password.length + ' car.' : 'VIDE', 6)} | ✅ OK — compte utilisable`,
    );
  }
  for (const { key, doc, plan } of broken) {
    const target = plan.move ? ` → ${plan.targetKey}` : '';
    const verdict = plan.conflict
      ? `⚠️  clé cible ${plan.targetKey} déjà existante — fusion manuelle requise`
      : `❌ ${plan.fixes.join(' ; ')}${target}`;
    console.log(
      `${PAD(key, 24)} | ${PAD(doc.role, 14)} | ${PAD(doc.password ? doc.password.length + ' car.' : 'VIDE', 6)} | ${verdict}`,
    );
  }

  console.log('\n' + '='.repeat(110));
  console.log(
    `RÉSUMÉ : ${ok.length} OK · ${broken.length} à corriger (${APPLY ? 'APPLICATION demandée' : 'DRY-RUN — rien n a été écrit'})`,
  );

  if (broken.length === 0) {
    console.log('\nAucun compte super admin à corriger.');
    return;
  }

  if (APPLY && PASSWORD == null && broken.some((b) => !b.doc.password)) {
    console.log('\n⚠️  Des comptes ont un mot de passe vide : relancez avec');
    console.log('   --password <motdepasse> pour le renseigner (ou renseignez');
    console.log('   le champ password manuellement dans la console Firebase).');
  }

  if (!APPLY) {
    console.log('\nPour appliquer :');
    console.log('  node tool/fix_super_admin.mjs --apply');
    if (broken.some((b) => !b.doc.password)) {
      console.log('  node tool/fix_super_admin.mjs --apply --password MonMdp123');
    }
    // exitCode (et non process.exit) : laisse les handles réseau se fermer
    // proprement (évite le bruit libuv sur Windows).
    process.exitCode = broken.length > 0 ? 1 : 0;
    return;
  }

  // --- Application ---
  console.log('\nApplication des corrections…');
  let applied = 0;
  for (const { key, doc, plan } of broken) {
    if (plan.conflict) {
      console.log(`   • ${key} — ⚠️ ignoré (clé cible ${plan.targetKey} déjà existante)`);
      continue;
    }
    try {
      const pwd = plan.changed.password ? ' (mot de passe renseigné)' : '';
      console.log(`   • ${key}${plan.move ? ` → ${plan.targetKey}` : ''}${pwd}`);
      await applyPlan(key, doc, plan);
      applied++;
    } catch (err) {
      console.error(`     ✗ ${err.message}`);
      process.exitCode = 2;
    }
  }
  console.log(`\n${applied} correction(s) appliquée(s) sur ${broken.length}.`);
  console.log('Re-vérifiez avec :');
  console.log('  node tool/check_console_users.mjs');
  console.log('\nTerminé. Re-vérifiez avec :');
  console.log('  node tool/check_console_users.mjs');
}

main().catch((err) => {
  console.error(`\nErreur : ${err.message}`);
  process.exitCode = 2;
});
