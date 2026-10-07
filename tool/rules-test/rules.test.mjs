// Firestore rules tests — run with `npm test` in this folder (starts the
// emulator through `firebase emulators:exec`).
import {readFileSync} from 'node:fs';
import {after, before, beforeEach, describe, test} from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteField,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:9090')
  .split(':');

let env;

const PHONES = {
  superAdmin: '+237640000001',
  ga: '+237640000002',
  manager: '+237640000003',
  client: '+237650000001',
  otherClient: '+237650000002',
  collector: '+237660000001',
  pending: '+237670000001',
  stranger: '+237680000001',
};

const emailFor = (phone) => `${phone.replace('+', '')}@wastepro.cm`;

/** Firestore client signed in as the account behind [phone]. */
const as = (key) =>
  env.authenticatedContext(`uid-${key}`, {
    email: emailFor(PHONES[key]),
  }).firestore();
const anon = () => env.unauthenticatedContext().firestore();

const ROLES = {
  superAdmin: 'super_admin',
  ga: 'general_admin',
  manager: 'agency_manager',
  client: 'client',
  otherClient: 'client',
  collector: 'collector',
  pending: 'pending_client',
};

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-wastepro',
    firestore: {
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url),
          'utf8'),
      host,
      port: Number(port),
    },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    // Everyone belongs to company so1 / agency ag1 (the GA has no agency,
    // the super admin no scope at all).
    for (const [key, role] of Object.entries(ROLES)) {
      const phone = PHONES[key];
      const societeId = key === 'superAdmin' ? '' : 'so1';
      const agenceId = ['superAdmin', 'ga'].includes(key) ? '' : 'ag1';
      await setDoc(doc(db, 'auth_profiles', `uid-${key}`), {
        uid: `uid-${key}`, phone, role, status: 'active', societeId, agenceId,
      });
      await setDoc(doc(db, 'users', phone), {
        phoneNumber: phone, role, uid: `uid-${key}`, fullName: key,
        societeId, agenceId, isSubscribed: key === 'client',
        subscription_plan: key === 'client' ? 'Monthly' : '',
        ...(key === 'collector' ? {collecteurId: 'col1'} : {}),
      });
    }
    // Another company / agency (so2 / ag2): must stay invisible.
    const other = {agenceId: 'ag2', societeId: 'so2'};
    await setDoc(doc(db, 'clients', 'cl-x'), {phone: '+237690000099', ...other});
    await setDoc(doc(db, 'collecteurs', 'col-x'), {phone: '+237690000098', ...other});
    await setDoc(doc(db, 'pickups', 'p-x'), {client_id: '+237690000099',
      collector_id: 'col-x', status: 'verified', ...other});
    await setDoc(doc(db, 'registrations', 'reg-x'), {phone: '+237690000097',
      status: 'pending', ...other});
    await setDoc(doc(db, 'transactions', 'WP-x'), {phone: '+237690000099',
      status: 'successful', ...other});
    await setDoc(doc(db, 'users', '+237690000099'), {role: 'client', ...other});
    await setDoc(doc(db, 'users', '650000009'), {
      phoneNumber: '+237650000009', role: 'client', fullName: 'legacy',
    });
    const mine = {agenceId: 'ag1', societeId: 'so1'};
    await setDoc(doc(db, 'transactions', 'WP-1'), {
      phone: PHONES.client, userId: PHONES.client, status: 'successful',
      ...mine,
    });
    await setDoc(doc(db, 'transactions', 'WP-2'), {
      phone: PHONES.otherClient, userId: PHONES.otherClient,
      status: 'successful', ...mine,
    });
    await setDoc(doc(db, 'subscriptions', PHONES.client), {status: 'active'});
    await setDoc(doc(db, 'registrations', 'reg1'), {
      phone: PHONES.pending, status: 'pending', ...mine,
    });
    // Legacy application: agency typed by name (Yaoundé = ag1's ville).
    await setDoc(doc(db, 'registrations', 'reg-legacy'), {
      phone: '+237670000002', status: 'pending', agenceId: '',
      agenceName: 'Yaoundé',
    });
    await setDoc(doc(db, 'notifications', 'n1'), {
      phone: PHONES.client, read: false,
    });
    await setDoc(doc(db, 'contracts', 'CTR-1'), {
      client_id: PHONES.client, status: 'Active',
    });
    await setDoc(doc(db, 'agences', 'ag1'), {societeId: 'so1', ville: 'Yaoundé'});
    await setDoc(doc(db, 'agences', 'ag2'), {societeId: 'so2', ville: 'Douala'});
    await setDoc(doc(db, 'utilisateurs', 'u1'), {
      societeId: 'so1', role: 'Agency Manager', password: 'secret',
    });
    await setDoc(doc(db, 'collecteurs', 'col1'), {phone: PHONES.collector,
      ...mine});
    await setDoc(doc(db, 'clients', 'cl1'), {phone: PHONES.client, ...mine});
    await setDoc(doc(db, 'clients', 'cl2'), {phone: PHONES.otherClient,
      ...mine});
    await setDoc(doc(db, 'password_resets', 'uid-ga'), {otp: '123456'});
    await setDoc(doc(db, 'pickups', 'p1'), {
      client_id: PHONES.client, collector_id: 'col1',
      status: 'pending_client_confirmation', ...mine,
    });
  });
});

describe('signed-out visitors', () => {
  test('cannot read accounts, OTPs or console users', async () => {
    await assertFails(getDoc(doc(anon(), 'users', PHONES.client)));
    await assertFails(getDoc(doc(anon(), 'password_resets', 'uid-ga')));
    await assertFails(getDocs(collection(anon(), 'utilisateurs')));
    await assertFails(getDocs(collection(anon(), 'transactions')));
  });

  test('can list agencies (pre-registration directory)', async () => {
    await assertSucceeds(getDocs(collection(anon(), 'agences')));
  });

  test('cannot write anything', async () => {
    await assertFails(setDoc(doc(anon(), 'users', PHONES.stranger),
        {role: 'super_admin'}));
  });
});

describe('privilege escalation', () => {
  test('a client cannot change their own role', async () => {
    await assertFails(updateDoc(doc(as('client'), 'users', PHONES.client),
        {role: 'super_admin'}));
    await assertFails(updateDoc(doc(as('client'), 'auth_profiles',
        'uid-client'), {role: 'super_admin'}));
  });

  test('a client cannot grant themselves a subscription', async () => {
    await assertFails(updateDoc(doc(as('otherClient'), 'users',
        PHONES.otherClient), {isSubscribed: true}));
    await assertFails(updateDoc(doc(as('client'), 'users', PHONES.client),
        {subscription_plan: 'Daily'}));
    await assertFails(setDoc(doc(as('client'), 'subscriptions', PHONES.client),
        {status: 'active'}));
    await assertFails(setDoc(doc(as('client'), 'transactions', 'X'),
        {phone: PHONES.client, status: 'successful'}));
    await assertFails(setDoc(doc(as('client'), 'pickups', 'PKP-x'),
        {client_id: PHONES.client, status: 'paid', type: 'extra'}));
  });

  test('a client may turn their own subscription off, never touch contracts',
      async () => {
        await assertSucceeds(updateDoc(doc(as('client'), 'users',
            PHONES.client), {
          isSubscribed: false, active_contract_id: deleteField(),
        }));
        // Expiry is the server's job now (`contractExpiry`).
        await assertFails(updateDoc(doc(as('client'), 'contracts',
            'CTR-1'), {status: 'Expired'}));
      });

  test('no user can write notifications or message logs for others',
      async () => {
        for (const key of ['client', 'collector']) {
          await assertFails(setDoc(doc(as(key), 'notifications', `x-${key}`),
              {phone: PHONES.otherClient, title: 'Call this number'}));
          await assertFails(setDoc(doc(as(key), 'sms_logs', `x-${key}`),
              {phone: PHONES.otherClient}));
          await assertFails(setDoc(doc(as(key), 'push_notifications',
              `x-${key}`), {to: PHONES.otherClient}));
        }
        await assertSucceeds(setDoc(doc(as('manager'), 'notifications', 'ok'),
            {phone: PHONES.pending, title: 'Application approved'}));
      });

  test('an agency manager cannot create admins', async () => {
    await assertFails(setDoc(doc(as('manager'), 'auth_profiles', 'uid-x'),
        {role: 'general_admin', phone: PHONES.stranger}));
    await assertFails(updateDoc(doc(as('manager'), 'users', PHONES.ga),
        {fullName: 'x'}));
    await assertSucceeds(setDoc(doc(as('manager'), 'auth_profiles', 'uid-x'),
        {role: 'client', phone: PHONES.stranger}));
    await assertSucceeds(updateDoc(doc(as('manager'), 'users',
        PHONES.pending), {role: 'client'}));
  });

  test('a general admin cannot create a super admin', async () => {
    await assertFails(setDoc(doc(as('ga'), 'users', PHONES.stranger),
        {role: 'super_admin'}));
    await assertSucceeds(setDoc(doc(as('ga'), 'users', PHONES.stranger),
        {role: 'agency_manager'}));
  });

  test('a general admin only manages their own company', async () => {
    await assertSucceeds(updateDoc(doc(as('ga'), 'agences', 'ag1'),
        {ville: 'Yaoundé II'}));
    await assertFails(updateDoc(doc(as('ga'), 'agences', 'ag2'),
        {ville: 'x'}));
    await assertFails(setDoc(doc(as('ga'), 'agences', 'ag3'),
        {societeId: 'so2'}));
  });
});

describe('clients', () => {
  test('read their own login profile, subscription and history', async () => {
    const db = as('client');
    await assertSucceeds(getDoc(doc(db, 'users', PHONES.client)));
    await assertSucceeds(getDoc(doc(db, 'subscriptions', PHONES.client)));
    await assertSucceeds(getDocs(query(collection(db, 'transactions'),
        where('phone', '==', PHONES.client))));
    await assertSucceeds(getDocs(query(collection(db, 'transactions'),
        where('userId', '==', PHONES.client))));
    await assertSucceeds(getDocs(query(collection(db, 'notifications'),
        where('phone', '==', PHONES.client))));
  });

  test("cannot read someone else's payments or OTP", async () => {
    const db = as('client');
    await assertFails(getDoc(doc(db, 'transactions', 'WP-2')));
    await assertFails(getDocs(query(collection(db, 'transactions'),
        where('phone', '==', PHONES.otherClient))));
    await assertFails(getDoc(doc(db, 'password_resets', 'uid-ga')));
    await assertFails(getDocs(collection(db, 'utilisateurs')));
  });

  test('update their own location, PIN and push token', async () => {
    const db = as('client');
    await assertSucceeds(setDoc(doc(db, 'users', PHONES.client), {
      latitude: 3.8, longitude: 11.5, securityPinHash: 'h', fcmToken: 't',
    }, {merge: true}));
    await assertSucceeds(updateDoc(doc(db, 'clients', 'cl1'),
        {latitude: 3.8, longitude: 11.5}));
    await assertFails(updateDoc(doc(db, 'clients', 'cl1'),
        {status: 'Active'}));
  });

  test('mark their notifications read, report issues, request pickups',
      async () => {
        const db = as('client');
        await assertSucceeds(updateDoc(doc(db, 'notifications', 'n1'),
            {read: true}));
        await assertSucceeds(setDoc(doc(db, 'issues', 'i1'),
            {client_id: PHONES.client}));
        await assertSucceeds(setDoc(doc(db, 'pickups', 'p2'),
            {client_id: PHONES.client, status: 'requested'}));
        await assertSucceeds(updateDoc(doc(db, 'pickups', 'p1'),
            {status: 'verified'}));
      });
});

describe('collectors', () => {
  test('read their agency clients and publish their position', async () => {
    const db = as('collector');
    await assertSucceeds(getDocs(query(collection(db, 'clients'),
        where('agenceId', '==', 'ag1'))));
    await assertSucceeds(setDoc(doc(db, 'collecteurs', 'col1'),
        {latitude: 1, longitude: 2, isTracking: true}, {merge: true}));
    await assertFails(updateDoc(doc(db, 'collecteurs', 'col1'),
        {phone: 'x'}));
  });

  test("update a client's pickup flags but not their plan", async () => {
    const db = as('collector');
    await assertSucceeds(setDoc(doc(db, 'users', PHONES.client),
        {needsPickup: false}, {merge: true}));
    await assertFails(updateDoc(doc(db, 'users', PHONES.client),
        {isSubscribed: false}));
  });

  test('see and move forward only the issues assigned to them', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      await setDoc(doc(admin, 'issues', 'mine'), {client_id: PHONES.client,
        status: 'assigned', assignedCollectorPhone: PHONES.collector,
        agenceId: 'ag1', societeId: 'so1'});
      await setDoc(doc(admin, 'issues', 'theirs'), {client_id: PHONES.client,
        status: 'assigned', assignedCollectorPhone: '+237660000009',
        agenceId: 'ag1', societeId: 'so1'});
    });
    const db = as('collector');
    await assertSucceeds(getDocs(query(collection(db, 'issues'),
        where('assignedCollectorPhone', '==', PHONES.collector))));
    await assertFails(getDoc(doc(db, 'issues', 'theirs')));
    await assertSucceeds(updateDoc(doc(db, 'issues', 'mine'),
        {status: 'in_progress', startedAt: 'now'}));
    await assertSucceeds(updateDoc(doc(db, 'issues', 'mine'),
        {status: 'resolved', resolvedAt: 'now'}));
    // Nothing else: not the assignment, not someone else's issue.
    await assertFails(updateDoc(doc(db, 'issues', 'mine'),
        {assignedCollectorPhone: '+237660000009'}));
    await assertFails(updateDoc(doc(db, 'issues', 'mine'), {status: 'open'}));
    await assertFails(updateDoc(doc(db, 'issues', 'theirs'),
        {status: 'resolved'}));
  });
});

describe('pre-registration', () => {
  const newPhone = '+237690000001';
  const applicant = () => env.authenticatedContext('uid-new',
      {email: emailFor(newPhone)}).firestore();

  test('a new applicant creates their own pending account', async () => {
    const db = applicant();
    await assertSucceeds(setDoc(doc(db, 'users', newPhone), {
      phoneNumber: newPhone, role: 'pending_client', uid: 'uid-new',
    }));
    await assertSucceeds(setDoc(doc(db, 'auth_profiles', 'uid-new'), {
      uid: 'uid-new', phone: newPhone, role: 'pending_client',
    }));
    await assertSucceeds(setDoc(doc(db, 'registrations', 'reg2'), {
      phone: newPhone, status: 'pending',
    }));
  });

  test('cannot register as client or for another number', async () => {
    const db = applicant();
    await assertFails(setDoc(doc(db, 'users', newPhone),
        {role: 'client', uid: 'uid-new'}));
    await assertFails(setDoc(doc(db, 'users', PHONES.stranger),
        {role: 'pending_client', uid: 'uid-new'}));
    await assertFails(setDoc(doc(db, 'registrations', 'reg3'),
        {phone: newPhone, status: 'approved'}));
  });

  test('a pending applicant follows their own application', async () => {
    const db = as('pending');
    await assertSucceeds(getDocs(query(collection(db, 'registrations'),
        where('phone', '==', PHONES.pending))));
    await assertSucceeds(getDoc(doc(db, 'users', PHONES.pending)));
    await assertFails(getDocs(collection(db, 'clients')));
  });

  test('a legacy bare-key profile is readable by its owner', async () => {
    const db = env.authenticatedContext('uid-legacy',
        {email: '237650000009@wastepro.cm'}).firestore();
    await assertSucceeds(getDoc(doc(db, 'users', '650000009')));
  });
});

describe('passwords', () => {
  test('no write may store a password in Firestore', async () => {
    await assertFails(setDoc(doc(as('manager'), 'clients', 'cl9'),
        {phone: PHONES.stranger, password: 'secret', agenceId: 'ag1'}));
    await assertFails(updateDoc(doc(as('manager'), 'collecteurs', 'col1'),
        {password: 'secret'}));
    await assertFails(setDoc(doc(as('ga'), 'utilisateurs', 'u9'),
        {societeId: 'so1', password: 'secret'}));
    await assertFails(setDoc(doc(as('manager'), 'users', PHONES.stranger),
        {role: 'client', password: 'secret'}));
    await assertSucceeds(setDoc(doc(as('ga'), 'utilisateurs', 'u9'),
        {societeId: 'so1', hasLogin: true}));
  });
});

describe('staff', () => {
  test('agency manager runs the backoffice', async () => {
    const db = as('manager');
    const mine = {agenceId: 'ag1', societeId: 'so1'};
    await assertSucceeds(getDocs(query(collection(db, 'registrations'),
        where('agenceId', '==', 'ag1'))));
    await assertSucceeds(updateDoc(doc(db, 'registrations', 'reg1'),
        {status: 'approved'}));
    await assertSucceeds(setDoc(doc(db, 'clients', 'cl3'),
        {phone: PHONES.stranger, ...mine}));
    await assertSucceeds(setDoc(doc(db, 'factures', 'f1'),
        {status: 'Paid', ...mine}));
    await assertSucceeds(getDocs(query(collection(db, 'transactions'),
        where('agenceId', '==', 'ag1'))));
    await assertSucceeds(getDocs(query(collection(db, 'pickups'),
        where('agenceId', '==', 'ag1'))));
    await assertFails(setDoc(doc(db, 'transactions', 'X'), {status: 'x'}));
  });

  test('reset codes are never readable from the app', async () => {
    await assertFails(getDoc(doc(as('ga'), 'password_resets', 'uid-ga')));
    await assertFails(setDoc(doc(as('ga'), 'password_resets', 'uid-ga'),
        {codeHash: 'x'}));
  });
});

describe('admin login', () => {
  test('admins get their role straight after login (no 2FA)', async () => {
    await assertSucceeds(getDocs(query(collection(as('ga'), 'utilisateurs'),
        where('societeId', '==', 'so1'))));
    await assertSucceeds(getDocs(collection(as('superAdmin'),
        'transactions')));
  });
});

describe('agency settings (auto-approval)', () => {
  test("only the agency's manager edits its settings", async () => {
    const settings = {agenceId: 'ag1', autoApproval: false,
      maxClientsPerCollector: 40};
    await assertSucceeds(setDoc(doc(as('manager'), 'agency_settings', 'ag1'),
        settings));
    await assertSucceeds(getDoc(doc(as('manager'), 'agency_settings', 'ag1')));
    await assertFails(setDoc(doc(as('manager'), 'agency_settings', 'ag2'),
        {...settings, agenceId: 'ag2'}));
    await assertFails(setDoc(doc(as('client'), 'agency_settings', 'ag1'),
        settings));
    await assertFails(setDoc(doc(as('collector'), 'agency_settings', 'ag1'),
        settings));
  });
});

describe('tenant isolation', () => {
  test('an agency manager only reaches their agency', async () => {
    const db = as('manager');
    await assertFails(getDoc(doc(db, 'clients', 'cl-x')));
    await assertFails(getDocs(collection(db, 'clients')));
    await assertFails(getDocs(query(collection(db, 'clients'),
        where('agenceId', '==', 'ag2'))));
    await assertFails(setDoc(doc(db, 'clients', 'cl9'),
        {phone: PHONES.stranger, agenceId: 'ag2', societeId: 'so2'}));
    await assertFails(updateDoc(doc(db, 'clients', 'cl1'),
        {agenceId: 'ag2'}));
    await assertFails(updateDoc(doc(db, 'registrations', 'reg-x'),
        {status: 'approved'}));
    await assertFails(getDoc(doc(db, 'transactions', 'WP-x')));
    await assertFails(getDoc(doc(db, 'pickups', 'p-x')));
    await assertFails(getDoc(doc(db, 'collecteurs', 'col-x')));
  });

  test('legacy applications addressed by agency name stay visible', async () => {
    const db = as('manager');
    await assertSucceeds(getDocs(query(collection(db, 'registrations'),
        where('agenceName', '==', 'Yaoundé'))));
    await assertSucceeds(updateDoc(doc(db, 'registrations', 'reg-legacy'),
        {status: 'approved'}));
    await assertFails(getDocs(query(collection(db, 'registrations'),
        where('agenceName', '==', 'Douala'))));
  });

  test('a general admin only reaches their company', async () => {
    const db = as('ga');
    await assertSucceeds(getDocs(query(collection(db, 'clients'),
        where('societeId', '==', 'so1'))));
    await assertFails(getDocs(query(collection(db, 'clients'),
        where('societeId', '==', 'so2'))));
    await assertFails(getDoc(doc(db, 'clients', 'cl-x')));
    await assertFails(getDocs(query(collection(db, 'utilisateurs'),
        where('societeId', '==', 'so2'))));
  });

  test('the super admin sees every company', async () => {
    await assertSucceeds(getDoc(doc(as('superAdmin'), 'clients', 'cl-x')));
    await assertSucceeds(getDocs(collection(as('superAdmin'), 'clients')));
  });

  test("a client never reads other clients' records", async () => {
    const db = as('client');
    await assertSucceeds(getDocs(query(collection(db, 'clients'),
        where('phone', '==', PHONES.client))));
    await assertFails(getDoc(doc(db, 'clients', 'cl2')));
    await assertFails(getDocs(query(collection(db, 'clients'),
        where('agenceId', '==', 'ag1'))));
    await assertFails(getDoc(doc(db, 'users', PHONES.otherClient)));
    await assertFails(getDoc(doc(db, 'pickups', 'p-x')));
    await assertSucceeds(getDocs(query(collection(db, 'pickups'),
        where('client_id', '==', PHONES.client))));
    // Their own collector's card / live position.
    await assertSucceeds(getDoc(doc(db, 'collecteurs', 'col1')));
    await assertFails(getDoc(doc(db, 'collecteurs', 'col-x')));
  });

  test('a collector stays within their agency', async () => {
    const db = as('collector');
    await assertFails(getDocs(collection(db, 'clients')));
    await assertFails(getDoc(doc(db, 'clients', 'cl-x')));
    await assertSucceeds(getDoc(doc(db, 'users', PHONES.client)));
    await assertFails(getDoc(doc(db, 'users', '+237690000099')));
    await assertSucceeds(getDocs(query(collection(db, 'pickups'),
        where('collector_id', '==', 'col1'))));
    await assertSucceeds(getDocs(query(collection(db, 'pickups'),
        where('agenceId', '==', 'ag1'),
        where('client_id', '==', PHONES.client))));
    await assertFails(getDoc(doc(db, 'pickups', 'p-x')));
    await assertFails(updateDoc(doc(db, 'collecteurs', 'col-x'),
        {latitude: 1}));
  });
});
