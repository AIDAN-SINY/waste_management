// Read-only verification: managers' login accounts + pending registrations
// each backoffice would see (same query the app uses).
const KEY = 'AIzaSyBtZ2G7JI-XMHyWolGjLMtRMpbFBoq5Yhw';
const BASE =
  'https://firestore.googleapis.com/v1/projects/waste-pro-f67a5/databases/(default)/documents';

async function runQuery(collectionId, whereField, whereValue) {
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
    : { structuredQuery: { from: [{ collectionId }], limit: 200 } };
  const res = await fetch(`${BASE}:runQuery?key=${KEY}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  if (!Array.isArray(data)) return [];
  return data
    .filter((d) => d.document)
    .map((d) => {
      const f = d.document.fields ?? {};
      const rec = { id: d.document.name.split('/').pop() };
      for (const k of [
        'fullName',
        'nom',
        'role',
        'status',
        'phoneNumber',
        'phone',
        'agenceId',
        'agenceName',
        'societeId',
        'ville',
        'uid',
      ]) {
        if (f[k]?.stringValue != null) rec[k] = f[k].stringValue;
        else if (f[k]?.booleanValue != null) rec[k] = f[k].booleanValue;
        else if (f[k]?.integerValue != null)
          rec[k] = Number(f[k].integerValue);
      }
      return rec;
    });
}

// (login phone, nom) → agenceId
const MANAGERS = [
  ['+237677980000', 'Eric Ekwa', 'c1786459997542000'],
  ['+237697894567', 'shayn durand', 'c1786460992699000'],
  ['+237656778990', 'shayn', 'c1786468189675000'],
  ['+237677123456', 'Jean CAms', 'ag1'],
];

const utilisateurs = await runQuery('utilisateurs');

for (const [phone, nom, agenceId] of MANAGERS) {
  console.log(`\n=== ${nom} (${phone}) — agence ${agenceId} ===`);

  // 1. Compte console
  const consoleUser = utilisateurs.find(
    (u) =>
      (u.telephone ?? '').replace(/[\s-]/g, '') === phone.replace('+', '') ||
      (u.telephone ?? '') === phone,
  );
  console.log(
    `  console (utilisateurs) : ${consoleUser ? `✅ ${consoleUser.id} role=${consoleUser.role} status=${consoleUser.status}` : '❌ ABSENT'}`,
  );

  // 2. Compte de connexion (users/{téléphone} + auth_profiles)
  const login = await runQuery('users', 'phoneNumber', phone);
  const userDoc = login.find((u) => u.phoneNumber === phone);
  if (userDoc) {
    console.log(
      `  login (users/${userDoc.id}) : ✅ role=${userDoc.role} agenceId=${userDoc.agenceId} uid=${userDoc.uid ? 'présent' : '❌ MANQUANT'}`,
    );
    if (userDoc.uid) {
      const prof = await runQuery('auth_profiles', 'uid', userDoc.uid);
      console.log(
        `  auth_profiles/${userDoc.uid} : ${prof.length ? '✅ présent' : '❌ ABSENT'}`,
      );
    }
  } else {
    console.log(`  login (users/${phone}) : ❌ ABSENT — connexion impossible`);
  }

  // 3. Agence (ville = nom affiché + clé du fallback par nom)
  const agences = await runQuery('agences');
  const agence = agences.find((a) => a.id === agenceId);
  console.log(`  agence : ${agence ? `«${agence.ville}»` : '❌ INTROUVABLE'}`);

  // 4. Candidatures pending visibles (même requête que le backoffice)
  const byId = await runQuery('registrations', 'agenceId', agenceId);
  const pendingById = byId.filter((r) => r.status === 'pending');
  const byName = agence
    ? await runQuery('registrations', 'agenceName', agence.ville)
    : [];
  const pendingByName = byName.filter((r) => r.status === 'pending');
  console.log(`  candidatures pending par agenceId : ${pendingById.length}`);
  for (const r of pendingById) {
    console.log(`    • ${r.id} «${r.fullName}» (${r.phone})`);
  }
  if (pendingByName.length && pendingByName.length !== pendingById.length) {
    console.log(
      `  ⚠️  + ${pendingByName.length} via le fallback par NOM (agenceName) :`,
    );
    for (const r of pendingByName) {
      if (!pendingById.some((x) => x.id === r.id)) {
        console.log(`    • ${r.id} «${r.fullName}» (${r.phone})`);
      }
    }
  }
}

// Récapitulatif : candidatures pending totales
console.log('\n=== RÉCAP CANDIDATURES PENDING (toutes) ===');
const allRegs = await runQuery('registrations');
for (const r of allRegs.filter((r) => r.status === 'pending')) {
  console.log(`  ${r.id} «${r.fullName}» ${r.phone} → agence ${r.agenceId} («${r.agenceName}»)`);
}
