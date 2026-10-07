#!/usr/bin/env node
/**
 * migrate_auth.mjs
 * ----------------
 * MIGRATION UNIQUE vers Firebase Auth (à exécuter UNE fois, avant de
 * déployer les règles durcies).
 *
 * Avant cette migration, les comptes vivaient uniquement dans Firestore
 * (`users/{téléphone}` avec un mot de passe EN CLAIR) et le login comparait
 * ce mot de passe côté app. Depuis, le login passe par Firebase Auth
 * (email dérivé du numéro : `2376XXXXXXX@wastepro.cm`). Ce script crée le
 * compte Auth de chaque utilisateur existant avec SON mot de passe actuel,
 * pour que personne ne soit verrouillé dehors — c'est la pièce qui manquait
 * à la tentative précédente (commit 8ecd422).
 *
 * Pour chaque doc `users/{téléphone}` avec un mot de passe :
 *   1. crée le compte Auth (email dérivé + mot de passe existant) ;
 *   2. écrit `uid` + `authMigrated: true` dans le doc et SUPPRIME le champ
 *      `password` (le secret n'a plus rien à faire dans Firestore) ;
 *   3. crée `auth_profiles/{uid}` (rôle + scope) que les règles consultent.
 *
 * Pour chaque candidature `registrations` avec un mot de passe :
 *   - si le numéro n'a pas de compte `users` → crée un compte `pending_client`
 *     (l'applicant pourra se connecter et suivre sa candidature) ;
 *   - le mot de passe est supprimé de la candidature.
 *
 * Pour les collecteurs avec latitude/longitude dans `users` :
 *   - copie la position dans `collector_locations/{téléphone}` (lue par
 *     `findNearestCollector`, les règles ne permettent plus de lister tous
 *     les `users`).
 *
 * Prérequis :
 *   - les règles déployées doivent être OUVERTES (firestore.rules actuel) —
 *     on durcit APRÈS la migration ;
 *   - l'identifiant Email/Password doit être activé dans la console Firebase
 *     (Authentication → Sign-in method) ;
 *   - la clé API (publique) : lue dans lib/firebase_options.dart, ou via
 *     l'environnement FIREBASE_API_KEY / --api-key.
 *
 * Usage :
 *   node tool/migrate_auth.mjs                    # rapport seul (dry-run)
 *   node tool/migrate_auth.mjs --apply            # applique la migration
 *   FIREBASE_PROJECT=autre-projet node tool/migrate_auth.mjs --apply
 */
import * as fs from 'node:fs';

const PROJECT = process.env.FIREBASE_PROJECT ?? 'waste-pro-f67a5';
const APPLY = process.argv.includes('--apply');

// --- Clé API (publique) : firebase_options.dart sinon env / flag ---
function apiKeyFromOptions() {
  try {
    const src = fs.readFileSync('lib/firebase_options.dart', 'utf8');
    // Seule la clé de la config WEB fonctionne avec l'API REST Identity
    // Toolkit (les clés Android/iOS sont rejetées : « API key not valid »).
    const webBlock = src
      .split('static const FirebaseOptions web')[1]
      ?.split('static const FirebaseOptions windows')[0];
    const m = webBlock?.match(/apiKey:\s*'([^']+)'/);
    if (m) return m[1];
    // Clé WEB en secours : la ligne de la config web est celle qui suit
    // `appId: '1:...:web:...'` (identifiants flottefire).
    const webMatch =
      src.match(/appId:\s*'[^']*:web:[^']*'[\s\S]*?apiKey:\s*'([^']+)'/) ??
      [];
    if (webMatch[1]) return webMatch[1];
    // Fallback : n'importe quelle clé du fichier.
    const any = src.match(/apiKey:\s*'([^']+)'/g);
    return any ? any[0].match(/'([^']+)'/)[1] : null;
  } catch (_) {
    return null;
  }
}
const ARGV_IDX = process.argv.indexOf('--api-key');
const API_KEY =
  process.env.FIREBASE_API_KEY ??
  (ARGV_IDX >= 0 ? process.argv[ARGV_IDX + 1] : undefined) ??
  apiKeyFromOptions();
if (!API_KEY) {
  console.error(
    'Clé API introuvable. Passez --api-key <cle> ou FIREBASE_API_KEY=<cle>.',
  );
  process.exit(2);
}

const FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const IDENTITY = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`;
const SIGN_IN = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`;

// --- Normalisation (miroir de AuthService.canonicalPhone) ---
function canonicalPhone(raw) {
  const cleaned = String(raw ?? '').trim().replace(/[\s-]/g, '');
  if (!cleaned) return '';
  if (cleaned.startsWith('+')) return cleaned;
  if (cleaned.startsWith('237')) return '+' + cleaned;
  return '+237' + cleaned;
}

// Email dérivé (miroir de AuthService.emailFor).
function emailFor(phone) {
  const canonical = canonicalPhone(phone);
  return canonical ? canonical.replace(/\+/g, '') + '@wastepro.cm' : '';
}

// --- REST Firestore (comme check_console_users.mjs / fix_super_admin.mjs) ---
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
  // API REST v1 actuelle : le chemin du doc doit inclure la collection
  // (`documents/{collection}/{id}`) et le masque se passe via
  // `updateMask.fieldPaths=` (l'ancien `updateMask.field=` n'est plus
  // accepté).
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

async function createDoc(collection, id, fields) {
  const res = await fetch(
    `${FIRESTORE}/${collection}?documentId=${encodeURIComponent(id)}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ fields: encodeFields(fields) }),
    },
  );
  if (!res.ok)
    throw new Error(
      `POST ${collection}/${id} a échoué (${res.status}) : ${(await res.text()).slice(0, 400)}`,
    );
}

// --- Création / récupération d'un compte Auth ---
async function createAuthAccount(email, password) {
  const res = await fetch(IDENTITY, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email,
      password,
      returnSecureToken: true,
    }),
  });
  const data = await res.json();
  if (res.ok) return { uid: data.localId, created: true };
  if (data.error?.message?.startsWith('EMAIL_EXISTS')) {
    // Compte déjà créé (relance idempotente) : récupère son uid.
    const sign = await fetch(SIGN_IN, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    });
    const signData = await sign.json();
    if (sign.ok) return { uid: signData.localId, created: false };
    return { uid: null, error: `email existe, mot de passe non vérifié` };
  }
  return { uid: null, error: data.error?.message ?? `HTTP ${res.status}` };
}

// ------------------------------------------------------------------
// RAPPORT
// ------------------------------------------------------------------
const rows = [];
let collectorsCopied = 0;

console.log(`Migration Auth sur le projet « ${PROJECT} »\n`);

try {
  const users = await fetchAll('users');
  const registrations = await fetchAll('registrations');

  for (const [key, doc] of users) {
    const canonical = canonicalPhone(key);
    const password = doc.password ?? '';
    const email = emailFor(canonical);
    const role = (doc.role ?? '').toLowerCase();
    let verdict;
    let detail = '';

    if (!canonical || !password) {
      if (!password)
        verdict = '⏭️  pas de mot de passe (compte non connectable) — rien à faire';
      else verdict = '⏭️  numéro invalide — ignoré';
      rows.push({ key, role, verdict, detail });
      continue;
    }

    if (doc.authMigrated === true && doc.uid) {
      verdict = '✅ déjà migré (uid présent) — rien à faire';
      rows.push({ key, role, verdict, detail });
      continue;
    }

    const { uid, error, created } = await createAuthAccount(email, password);
    if (!uid) {
      verdict = `❌ ${error}`;
      rows.push({ key, role, verdict, detail });
      continue;
    }

    detail = `${created ? 'compte créé' : 'compte existant'} · uid ${uid}`;

    if (APPLY) {
      // uid + authMigrated, suppression du mot de passe en clair.
      await patchDoc('users', key, {
        uid,
        authMigrated: true,
        password: null, // nullValue = suppression du champ via updateMask
      });
      // Profil de règles.
      const existingProfile = await getDoc('auth_profiles', uid);
      if (!existingProfile) {
        await createDoc('auth_profiles', uid, {
          uid,
          phone: canonical,
          role: role || 'client',
          status: 'active',
          societeId: doc.societeId ?? '',
          agenceId: doc.agenceId ?? '',
        });
      }
      // Position des collecteurs → collector_locations (lue par l'app client).
      if (
        role === 'collector' &&
        doc.latitude != null &&
        doc.longitude != null
      ) {
        const loc = await getDoc('collector_locations', canonical);
        if (!loc) {
          await createDoc('collector_locations', canonical, {
            phone: canonical,
            name: doc.fullName ?? '',
            latitude: Number(doc.latitude),
            longitude: Number(doc.longitude),
          });
          collectorsCopied++;
        }
      }
    }

    verdict = `${created ? '✅' : '♻️'} ${detail}`;
    rows.push({ key, role, verdict, detail });
  }

  // --- Candidatures : compte pending pour les applicants sans compte ---
  console.log('\n— CANDIDATURES (pré-inscriptions) —\n');
  for (const [id, reg] of registrations) {
    const canonical = canonicalPhone(reg.phone ?? '');
    const password = reg.password ?? '';
    let verdict;

    if (!canonical || !password) {
      verdict = password ? '⏭️  numéro invalide' : '⏭️  pas de mot de passe (déjà nettoyé)';
      console.log(`  ${id}  ${verdict}`);
      continue;
    }

    const existingUser = await getDoc('users', canonical);
    if (existingUser) {
      // Le compte users existe déjà (avec son uid) : supprime juste le mdp.
      if (APPLY) await patchDoc('registrations', id, { password: null });
      console.log(
        `  ${id}  ✅ compte users existant — mot de passe supprimé de la candidature`,
      );
      continue;
    }

    const email = emailFor(canonical);
    const { uid, error, created } = await createAuthAccount(email, password);
    if (!uid) {
      console.log(`  ${id}  ❌ ${error}`);
      continue;
    }
    if (APPLY) {
      await createDoc('users', canonical, {
        phoneNumber: canonical,
        fullName: reg.fullName ?? '',
        role: 'pending_client',
        uid,
        uid_created: created,
        societeId: reg.societeId ?? '',
        agenceId: reg.agenceId ?? '',
        agenceName: reg.agenceName ?? '',
        collecteurId: '',
        isSubscribed: false,
        authMigrated: true,
      });
      await createDoc('auth_profiles', uid, {
        uid,
        phone: canonical,
        role: 'pending_client',
        status: 'pending',
        societeId: reg.societeId ?? '',
        agenceId: reg.agenceId ?? '',
      });
      await patchDoc('registrations', id, { password: null });
    }
    console.log(
      `  ${id}  ✅ compte pending_client créé (uid ${uid}) — mot de passe supprimé`,
    );
  }

  // --- Rapport ---
  const migrated = rows.filter((r) => r.verdict.startsWith('✅'));
  const reused = rows.filter((r) => r.verdict.startsWith('♻️'));
  const skipped = rows.filter((r) => r.verdict.startsWith('⏭️'));
  const failed = rows.filter((r) => r.verdict.startsWith('❌'));

  console.log('\n' + '='.repeat(120));
  console.log(
    `RÉSUMÉ (${rows.length} comptes users) : ${migrated.length} migrés · ` +
      `${reused.length} existants · ${skipped.length} sans mdp · ${failed.length} en échec`,
  );
  if (APPLY) console.log(`Positions collecteurs copiées : ${collectorsCopied}`);

  for (const r of failed) {
    console.log(`  ❌ ${r.key} (${r.role}) : ${r.verdict}`);
  }

  if (!APPLY) {
    console.log(
      '\nDry-run : aucune écriture effectuée. Relancez avec --apply pour ' +
        'appliquer (comptes Auth + profils + nettoyage des mots de passe).',
    );
  } else {
    console.log(
      '\nTerminé. Vous pouvez maintenant déployer les règles durcies :\n' +
        '  firebase deploy --only firestore:rules --project ' + PROJECT,
    );
  }

  process.exit(failed.length > 0 ? 1 : 0);
} catch (err) {
  console.error(`\nErreur : ${err.message}`);
  console.error(
    '\nSi c est une erreur 403 (permission-denied), les règles déployées ne ' +
      'sont pas ouvertes — redéployez les règles actuelles d abord :\n' +
      '  firebase deploy --only firestore:rules --project waste-pro-f67a5',
  );
  process.exit(2);
}
