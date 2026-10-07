#!/usr/bin/env node
/**
 * check_console_users.mjs
 * -----------------------
 * Liste les utilisateurs console (`utilisateurs`) qui n'ont PAS de compte
 * de connexion `users/{téléphone}` — c.-à-d. ceux créés avant le correctif
 * (téléphone non obligatoire) et qui ne peuvent donc pas se connecter.
 *
 * Utilise l'API REST Firestore (aucune dépendance, aucune clé) — cela
 * fonctionne tant que les règles déployées sont ouvertes (firestore.rules).
 * Si vous obtenez une erreur 403, redéployez les règles :
 *   firebase deploy --only firestore:rules --project waste-pro-f67a5
 *
 * Usage :
 *   node tool/check_console_users.mjs
 *
 * Logique de clés identique à AuthService.canonicalKeys() :
 *   +237699999999 (canonique) puis le numéro tel que saisi.
 */
const PROJECT = process.env.FIREBASE_PROJECT ?? 'waste-pro-f67a5';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

// --- Normalisation (miroir de AuthService.canonicalPhone) ---
function canonicalPhone(raw) {
  const cleaned = String(raw ?? '').trim().replace(/[\s-]/g, '');
  if (!cleaned) return '';
  if (cleaned.startsWith('+')) return cleaned;
  if (cleaned.startsWith('237')) return '+' + cleaned;
  return '+237' + cleaned;
}

// --- Clés candidates (miroir de AuthService.canonicalKeys) ---
function candidateKeys(raw) {
  return [...new Set([canonicalPhone(raw), String(raw ?? '').trim()])].filter(
    Boolean,
  );
}

// --- Récupère TOUS les docs d'une collection (avec pagination) ---
async function fetchAll(collection) {
  const docs = new Map(); // docId -> champs décodés
  let pageToken = '';
  do {
    const url = `${BASE}/${collection}?pageSize=300${
      pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ''
    }`;
    const res = await fetch(url);
    if (!res.ok) {
      const body = await res.text();
      throw new Error(
        `GET ${collection} a échoué (${res.status}) : ${body.slice(0, 400)}`,
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

const PAD = (s, n) => String(s ?? '').padEnd(n);

// Utilisateurs de démo insérés automatiquement à la première ouverture de
// la console (seedIfEmpty) : pas de mot de passe, jamais de compte de
// connexion par conception. Ids stables de seed_data.dart.
const SEED_IDS = new Set(['us1', 'us2', 'us3', 'us4']);

function printHeader() {
  console.log(
    `${PAD('NOM', 24)} | ${PAD('TÉLÉPHONE', 18)} | ${PAD('RÔLE', 24)} | ${PAD('STATUT', 10)} | DIAGNOSTIC`,
  );
  console.log('-'.repeat(130));
}

const rows = [];
const orphans = [];

try {
  console.log(`Lecture de la base « ${PROJECT} »…\n`);
  const utilisateurs = await fetchAll('utilisateurs');
  const users = await fetchAll('users');
  const userKeys = new Set(users.keys());

  for (const [id, u] of utilisateurs) {
    const nom = u.nom ?? '(sans nom)';
    const telephone = u.telephone ?? '';
    const password = u.password ?? '';
    const status = u.status ?? 'Active';
    const role = u.role ?? '?';
    const keys = candidateKeys(telephone);
    const foundKey = keys.find((k) => userKeys.has(k));
    const userDoc = foundKey ? users.get(foundKey) : null;

    let verdict;
    let detail = '';
    if (SEED_IDS.has(id)) {
      verdict =
        'ℹ️  DÉMO (seed) — pas de mot de passe par conception : à supprimer ' +
        'ou à compléter (numéro réel + mot de passe) pour se connecter';
    } else if (!String(telephone).trim()) {
      verdict = '❌ AUCUN NUMÉRO — impossible de se connecter, à corriger';
    } else if (!password) {
      verdict = '❌ PAS DE MOT DE PASSE — jamais de compte de connexion';
    } else if (!foundKey) {
      verdict = '❌ SANS COMPTE DE CONNEXION — à corriger (numéro + mdp)';
    } else {
      const storedPwd = userDoc.password ?? '';
      detail = `clé « ${foundKey} » · mdp stocké: ${storedPwd.length > 0 ? storedPwd.length + ' car.' : 'VIDE'} · rôle: ${userDoc.role ?? '?'}`;
      if (userDoc.password !== password) {
        verdict =
          '⚠️  compte existe mais mot de passe DIFFÉRENT du console';
      } else {
        verdict = '✅ OK (compte de connexion actif)';
      }
    }

    rows.push({ nom, telephone, status, role, verdict, id, detail });
  }

  // Comptes de connexion orphelins : users/... marqués consoleCreated mais
  // sans utilisateur console correspondant (numéro changé / user supprimé).
  for (const [key, doc] of users) {
    if (doc.consoleCreated !== true) continue;
    const stillUsed = [...utilisateurs.values()].some(
      (u) => candidateKeys(u.telephone).includes(key),
    );
    if (!stillUsed) orphans.push({ key, doc });
  }

  // --- Rapport ---
  const broken = rows.filter((r) => r.verdict.startsWith('❌'));
  const warnings = rows.filter((r) => r.verdict.startsWith('⚠️'));
  const ok = rows.filter((r) => r.verdict.startsWith('✅'));

  console.log(`— UTILISATEURS CONSOLE : ${rows.length} au total —\n`);
  printHeader();
  for (const r of rows) {
    const line =
      `${PAD(r.nom, 24)} | ${PAD(r.telephone, 18)} | ${PAD(r.role, 24)} | ` +
      `${PAD(r.status, 10)} | ${r.verdict}`;
    console.log(line);
    if (r.detail) console.log(`${' '.repeat(24)} | ${' '.repeat(18)} | ${' '.repeat(24)} | ${' '.repeat(10)} |   └─ ${r.detail}`);
  }

  if (orphans.length > 0) {
    console.log(`\n— COMPTES DE CONNEXION ORPHELINS (${orphans.length}) —\n`);
    console.log('Comptes users/{téléphone} marqués consoleCreated mais sans');
    console.log('utilisateur console correspondant (numéro changé / supprimé) :');
    for (const { key, doc } of orphans) {
      const hasPwd = doc.password ? 'oui' : 'NON';
      const stillActive = doc.password ? '→ PEUT ENCORE SE CONNECTER' : '→ inutilisable';
      console.log(`  • ${key}  (${doc.fullName ?? '?'})  mdp: ${hasPwd}  ${stillActive}`);
    }
  }

  console.log('\n' + '='.repeat(130));
  console.log(
    `RÉSUMÉ : ${ok.length} OK · ${warnings.length} à vérifier · ${broken.length} à corriger (sur ${rows.length} utilisateurs console)`,
  );

  if (broken.length > 0) {
    console.log('\nPour corriger : ouvrez chaque utilisateur ci-dessus dans la');
    console.log('console super admin (page Users → ✏️), renseignez le numéro et');
    console.log('le mot de passe, puis enregistrez — le compte de connexion');
    console.log('users/{téléphone} sera créé automatiquement.');
  }
  if (orphans.length > 0) {
    console.log('\nComptes orphelins : soit recréez l utilisateur console avec ce');
    console.log('numéro (il récupérera son compte), soit supprimez le doc');
    console.log('users/{téléphone} directement dans la console Firebase.');
  }
  process.exit(broken.length > 0 ? 1 : 0);
} catch (err) {
  console.error(`\nErreur : ${err.message}`);
  console.error(
    '\nSi c est une erreur 403 (permission-denied), les règles déployées ne sont',
    'pas ouvertes. Redéployez-les :',
  );
  console.error('  firebase deploy --only firestore:rules --project waste-pro-f67a5');
  process.exit(2);
}
