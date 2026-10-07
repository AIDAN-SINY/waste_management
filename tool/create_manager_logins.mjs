#!/usr/bin/env node
/**
 * create_manager_logins.mjs
 * -------------------------
 * Crée les comptes de connexion manquants des chefs d'agence (rôle
 * « Agency Manager » dans `utilisateurs`) : un compte Firebase Auth (email
 * dérivé du numéro) + le profil `users/{téléphone}` + `auth_profiles/{uid}`,
 * et renseigne le mot de passe sur le doc `utilisateurs` (source de vérité
 * de la console super admin, cf. check_console_users.mjs).
 *
 * Mot de passe : par défaut « wastepro » (choix utilisateur). Peut être
 * surchargé avec --password.
 *
 * Usage :
 *   node tool/create_manager_logins.mjs                 # rapport seul (dry-run)
 *   node tool/create_manager_logins.mjs --apply         # crée les comptes
 *   node tool/create_manager_logins.mjs --apply --password MonMdp123
 */
import * as fs from 'node:fs';

const PROJECT = process.env.FIREBASE_PROJECT ?? 'waste-pro-f67a5';
const APPLY = process.argv.includes('--apply');
const PASSWORD =
  (process.argv.includes('--password')
    ? process.argv[process.argv.indexOf('--password') + 1]
    : undefined) ?? 'wastepro';

// --- Clé API (publique) : firebase_options.dart sinon env / flag ---
function apiKeyFromOptions() {
  try {
    const src = fs.readFileSync('lib/firebase_options.dart', 'utf8');
    const webBlock = src
      .split('static const FirebaseOptions web')[1]
      ?.split('static const FirebaseOptions windows')[0];
    const m = webBlock?.match(/apiKey:\s*'([^']+)'/);
    if (m) return m[1];
    const webMatch =
      src.match(/appId:\s*'[^']*:web:[^']*'[\s\S]*?apiKey:\s*'([^']+)'/) ?? [];
    if (webMatch[1]) return webMatch[1];
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

function canonicalPhone(raw) {
  const cleaned = String(raw ?? '').trim().replace(/[\s-]/g, '');
  if (!cleaned) return '';
  if (cleaned.startsWith('+')) return cleaned;
  if (cleaned.startsWith('237')) return '+' + cleaned;
  return '+237' + cleaned;
}

function emailFor(phone) {
  const canonical = canonicalPhone(phone);
  return canonical ? canonical.replace(/\+/g, '') + '@wastepro.cm' : '';
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
      `POST ${collection}/${id} (${res.status}) : ${(await res.text()).slice(0, 300)}`,
    );
}

async function createAuthAccount(email, password) {
  // Crée le compte Auth. Si l'email existe déjà (relance idempotente), on se
  // connecte avec le mot de passe cible pour récupérer son uid — le compte
  // porte alors le bon mot de passe (soit créé par nous, soit à vérifier).
  const res = await fetch(IDENTITY, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const data = await res.json();
  if (res.ok) return { uid: data.localId, created: true };
  if (data.error?.message?.startsWith('EMAIL_EXISTS')) {
    const sign = await fetch(SIGN_IN, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    });
    const signData = await sign.json();
    if (sign.ok) {
      return { uid: signData.localId, created: false, recovered: true };
    }
    return { uid: null, created: false, error: 'email existe, mot de passe non vérifié' };
  }
  return { uid: null, created: false, error: data.error?.message ?? `HTTP ${res.status}` };
}

const isManager = (role) =>
  ['agency manager', 'responsable dagence']
    .includes(String(role ?? '').trim().toLowerCase().replaceAll("'", ''));

async function main() {
  console.log(`Chefs d'agence sans compte de connexion — projet « ${PROJECT} »\n`);
  const utilisateurs = await fetchAll('utilisateurs');
  const users = await fetchAll('users');

  const managers = [...utilisateurs.entries()].filter(([, u]) => {
    const active = ['active', 'actif'].includes(
      String(u.status ?? '').trim().toLowerCase(),
    );
    return isManager(u.role) && active;
  });

  let created = 0;
  for (const [id, u] of managers) {
    const phone = canonicalPhone(u.telephone);
    const nom = u.nom ?? id;
    console.log(`\n=== ${nom} (${id}) — ${phone || 'SANS NUMÉRO'} ===`);
    if (!phone) {
      console.log('  ⏭️  pas de numéro — impossible de créer un login');
      continue;
    }
    const existing = users.get(phone);
    if (existing && (existing.uid || existing.password)) {
      console.log(
        `  ✅ compte de connexion déjà présent (users/${phone}, uid=${existing.uid ?? '?'}) — rien à faire`,
      );
      continue;
    }

    const email = emailFor(phone);
    if (!APPLY) {
      console.log(
        `  → LOGIN À CRÉER : ${phone} / ${PASSWORD}  (agenceId=${u.agenceId ?? ''})`,
      );
      continue;
    }

    const { uid, created: justCreated, error } = await createAuthAccount(
      email,
      PASSWORD,
    );
    if (!uid) {
      console.log(`  ❌ création Auth impossible : ${error}`);
      continue;
    }

    console.log(
      `  → compte Auth ${justCreated ? 'créé' : 'existant'} (${email}) uid=${uid}`,
    );
    {
      // Profil de connexion + profil de règles + mot de passe console.
      await createDoc('users', phone, {
        phoneNumber: phone,
        fullName: nom,
        role: 'agency_manager',
        uid,
        societeId: u.societeId ?? '',
        agenceId: u.agenceId ?? '',
        isSubscribed: false,
        consoleCreated: true,
        consoleUserId: id,
      });
      await createDoc('auth_profiles', uid, {
        uid,
        phone,
        role: 'agency_manager',
        status: 'active',
        societeId: u.societeId ?? '',
        agenceId: u.agenceId ?? '',
      });
      await patchDoc('utilisateurs', id, { password: PASSWORD });
      created++;
      console.log(
        `  ✅ LOGIN : ${phone} / ${PASSWORD}  (agenceId=${u.agenceId ?? ''})`,
      );
    }
  }

  console.log(
    `\n${APPLY ? `Terminé — ${created} compte(s) créé(s).` : 'DRY-RUN — aucune écriture. Relancez avec --apply.'}`,
  );
  console.log('\nRappel : le login se fait avec le NUMÉRO + le mot de passe');
  console.log('dans l app (email dérivé automatiquement côté serveur).');
}

main().catch((err) => {
  console.error(`\nErreur : ${err.message}`);
  process.exit(2);
});
