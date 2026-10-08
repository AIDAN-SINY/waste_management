const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {defineSecret, defineString} = require("firebase-functions/params");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getMessaging} = require("firebase-admin/messaging");
const {
  getFirestore,
  FieldValue,
  Timestamp,
} = require("firebase-admin/firestore");
const crypto = require("node:crypto");
const jwt = require("jsonwebtoken");

initializeApp();
const db = getFirestore();

// ============================================================
// CamPay configuration — credentials live ONLY on the server.
//
//   firebase functions:secrets:set CAMPAY_USERNAME
//   firebase functions:secrets:set CAMPAY_PASSWORD
//   firebase functions:secrets:set CAMPAY_WEBHOOK_KEY
//
// CAMPAY_ENV ("demo" | "production") goes in functions/.env.
// CAMPAY_API overrides the CamPay base URL (local emulator tests only).
// ============================================================
const CAMPAY_USERNAME = defineSecret("CAMPAY_USERNAME");
const CAMPAY_PASSWORD = defineSecret("CAMPAY_PASSWORD");
const CAMPAY_WEBHOOK_KEY = defineSecret("CAMPAY_WEBHOOK_KEY");
const CAMPAY_ENV = defineString("CAMPAY_ENV", {default: "demo"});
const CAMPAY_API = defineString("CAMPAY_API", {default: ""});

const isDemo = () => CAMPAY_ENV.value().toLowerCase() !== "production";
const campayBaseUrl = () => CAMPAY_API.value() ||
  (isDemo() ? "https://demo.campay.net/api" : "https://www.campay.net/api");

/** CamPay sandbox caps each transaction; plan prices stay display-only. */
const DEMO_MAX_AMOUNT = 25;

/**
 * Server-side price list — the client never decides what it pays.
 * Keys mirror `SubscriptionPlans` (lib/core/subscription_plans.dart).
 */
const PLANS = {
  monthly: {title: "Monthly", price: 3000},
  weekly: {title: "Weekly", price: 5500},
  daily: {title: "Daily", price: 15000},
};
const EXTRA_PICKUP_PRICE = 1000;

/**
 * Collection days per plan (what the client is sold — see
 * lib/core/subscription_plans.dart): Monthly = 1 collection per week,
 * Weekly = 2 per week, Daily = every collection day.
 */
const PLAN_DAYS_PER_WEEK = {monthly: 1, weekly: 2, daily: 7};
const WEEK_DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
  "Saturday"];
/** Used when the agency defined no calendar for the client's zone. */
const DEFAULT_DAYS = {
  monthly: ["Wednesday"],
  weekly: ["Tuesday", "Friday"],
  daily: WEEK_DAYS,
};
const DEFAULT_PICKUP_TIME = "07:00 — 08:00";

const BILLING_CYCLE_DAYS = 30;

// ------------------------------------------------------------
// Helpers
// ------------------------------------------------------------

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

/** Verifies the Firebase ID token and returns the caller's login profile. */
async function authenticate(req) {
  const header = req.get("Authorization") || "";
  const match = header.match(/^Bearer (.+)$/);
  if (!match) throw new HttpError(401, "Missing authentication.");
  let decoded;
  try {
    decoded = await getAuth().verifyIdToken(match[1]);
  } catch (_) {
    throw new HttpError(401, "Invalid or expired session. Log in again.");
  }
  const profile = await db.collection("auth_profiles").doc(decoded.uid).get();
  if (!profile.exists) throw new HttpError(403, "No profile for this account.");
  const data = profile.data();
  return {
    uid: decoded.uid,
    phone: data.phone || "",
    role: data.role || "",
    agenceId: data.agenceId || "",
    societeId: data.societeId || "",
  };
}

/** Same tenant scope as `inScope` in firestore.rules. */
function callerCanManage(caller, record) {
  if (caller.role === "super_admin") return true;
  if (caller.role === "general_admin") {
    return !!caller.societeId && record.societeId === caller.societeId;
  }
  if (caller.role === "agency_manager") {
    return !!caller.agenceId && record.agenceId === caller.agenceId;
  }
  return false;
}

/** Normalizes a Cameroon number for CamPay: `2376XXXXXXXX`. */
function campayPhone(raw) {
  const digits = String(raw || "").replace(/[^0-9]/g, "");
  if (digits.startsWith("237") && digits.length === 12) return digits;
  if (digits.length === 9 && digits.startsWith("6")) return `237${digits}`;
  return "";
}

/** Same lookup order as AuthService.canonicalKeys (canonical, then bare). */
async function resolveUserRef(phone) {
  const keys = [phone];
  if (phone.startsWith("+237")) keys.push(phone.substring(4));
  for (const key of keys) {
    const ref = db.collection("users").doc(key);
    if ((await ref.get()).exists) return ref;
  }
  return db.collection("users").doc(phone);
}

function stringList(value) {
  if (!Array.isArray(value)) return [];
  return value.filter((v) => typeof v === "string").slice(0, 7);
}

function shortString(value, max = 100) {
  return typeof value === "string" ? value.slice(0, max) : "";
}

function todayIso() {
  return new Date().toISOString().substring(0, 10);
}

let cachedToken = null;
let cachedTokenExpiry = 0;

/** CamPay access token (cached ~50 min; CamPay tokens last 60 min). */
async function campayToken() {
  if (cachedToken && Date.now() < cachedTokenExpiry) return cachedToken;
  // Secrets set via `echo ... | firebase functions:secrets:set` or copied
  // from the dashboard often carry a trailing newline/space, which CamPay
  // rejects as wrong credentials.
  const username = String(CAMPAY_USERNAME.value() || "").trim();
  const password = String(CAMPAY_PASSWORD.value() || "").trim();
  if (!username || !password) {
    console.error("CamPay: CAMPAY_USERNAME / CAMPAY_PASSWORD not configured.");
    throw new HttpError(503, "Payment service is not configured.");
  }
  let res;
  try {
    res = await fetch(`${campayBaseUrl()}/token/`, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({username, password}),
    });
  } catch (e) {
    console.error("CamPay: token request failed", e);
    throw new HttpError(502, "The payment provider is unreachable.");
  }
  const data = await res.json().catch(() => ({}));
  if (!data.token) {
    // Logged server-side only: tells whether the keys are wrong or belong
    // to the other environment (demo keys on www.campay.net or vice versa).
    console.error(`CamPay: token rejected (HTTP ${res.status}) by ` +
      `${campayBaseUrl()} [CAMPAY_ENV=${CAMPAY_ENV.value()}]`,
    JSON.stringify(data));
    throw new HttpError(502, "Payment provider authentication failed. " +
      "Check the CamPay API keys and CAMPAY_ENV (demo/production).");
  }
  cachedToken = data.token;
  cachedTokenExpiry = Date.now() + 50 * 60 * 1000;
  return cachedToken;
}

async function campayRequest(path, init = {}, retried = false) {
  const token = await campayToken();
  const res = await fetch(`${campayBaseUrl()}${path}`, {
    ...init,
    headers: {
      "Authorization": `Token ${token}`,
      "Content-Type": "application/json",
      ...(init.headers || {}),
    },
  });
  if (res.status === 401 && !retried) {
    // Token revoked/expired before our cache did: fetch a new one once.
    cachedToken = null;
    cachedTokenExpiry = 0;
    return campayRequest(path, init, true);
  }
  const data = await res.json().catch(() => ({}));
  return {ok: res.ok, status: res.status, data};
}

function sendError(res, error) {
  if (error instanceof HttpError) {
    return res.status(error.status).json({error: error.message});
  }
  console.error(error);
  return res.status(500).json({error: "Internal error."});
}

// ------------------------------------------------------------
// Fulfillment — the ONLY place a payment unlocks anything.
// ------------------------------------------------------------

/**
 * Re-queries CamPay for [txRef] and settles the transaction.
 * Idempotent: a transaction is fulfilled at most once, whether the
 * confirmation arrives via client polling or via the webhook.
 *
 * Returns the transaction's resulting status.
 */
/**
 * The agency's calendar for the client's zone ({days, pickupTime, name}),
 * or null when the agency defined none.
 */
async function zoneCalendarFor(clientRecord) {
  if (!clientRecord?.agenceId || !clientRecord.zone) return null;
  const zones = await db.collection("zones")
      .where("agenceId", "==", clientRecord.agenceId).get();
  const match = zones.docs.map((d) => d.data())
      .find((z) => zonesMatch(clientRecord.zone, z.name));
  if (!match || !(match.collectionDays || []).length) return null;
  return {
    days: match.collectionDays,
    pickupTime: match.standardPickupTime || DEFAULT_PICKUP_TIME,
    name: match.name || "",
  };
}

/** Spreads [count] days over [days] (e.g. 2 of Mon..Sat → Mon, Thu). */
function spreadDays(days, count) {
  if (count >= days.length) return [...days];
  const step = days.length / count;
  return Array.from({length: count}, (_, i) => days[Math.floor(i * step)]);
}

/**
 * Collection schedule of a paid plan — always valid, so a paying client is
 * always on their collector's tour:
 *   1. the days the client chose, if they fit the plan and the zone;
 *   2. else the current days, if enough for the plan (renewal / manager);
 *   3. else from the zone calendar (or defaults when there is none).
 */
function resolveSchedule({planKey, sent = {}, current = {}, zone}) {
  const perWeek = PLAN_DAYS_PER_WEEK[planKey] || 1;
  const allowed = zone ? zone.days : WEEK_DAYS;
  const pickupTime = zone?.pickupTime || current.pickup_time ||
    DEFAULT_PICKUP_TIME;
  const zoneName = zone?.name || current.zone_name || "";

  if (planKey === "daily") {
    return {collectionDays: [...allowed], pickupTime, zoneName};
  }
  const chosen = [...new Set(sent.collectionDays || [])]
      .filter((d) => allowed.includes(d));
  if (chosen.length) {
    return {collectionDays: chosen.slice(0, perWeek), pickupTime, zoneName};
  }
  // Current days (renewal, or set by the manager on the client card) are
  // kept when they are enough for the plan — extra ones dropped on a
  // downgrade.
  const currentDays = [...new Set(current.collection_days || [])]
      .filter((d) => allowed.includes(d));
  if (currentDays.length >= Math.min(perWeek, allowed.length)) {
    return {collectionDays: currentDays.slice(0, perWeek), pickupTime,
      zoneName};
  }
  return {
    collectionDays: zone ?
      spreadDays(allowed, perWeek) :
      DEFAULT_DAYS[planKey] || DEFAULT_DAYS.monthly,
    pickupTime,
    zoneName,
  };
}

/**
 * Activates a paid subscription inside transaction [t] — shared by mobile
 * money (`settle`) and cash recorded by the agency (`recordCashPayment`):
 * 30-day contract, login profile, subscription summary, paid invoice and
 * the client's backoffice record. [current] / [clientRecord] are the data
 * read in the same transaction; [zone] the client's zone calendar.
 *
 * Paying while a plan is still running schedules the new one to start when
 * it ends ("next period": the client may switch plan each month, no day is
 * lost); the daily `contractExpiry` job activates it.
 * Returns {contractId, startsAt, scheduled}.
 */
function writeSubscription(t, {tx, txRef, userRef, current, clientRef,
  clientRecord, zone}) {
  const now = new Date();
  const runningEnd = asDate(current.subscription_end);
  const start = current.isSubscribed === true && runningEnd &&
    runningEnd > now ? runningEnd : now;
  const scheduled = start > now;
  const next = new Date(start.getTime() + BILLING_CYCLE_DAYS * 864e5);
  const contractId = `CTR-${now.getTime()}`;
  const planKey = String(tx.planTitle || "").toLowerCase();
  const d = resolveSchedule({planKey, sent: tx.details || {}, current,
    zone});

  t.set(db.collection("contracts").doc(contractId), {
    contract_id: contractId,
    client_id: tx.phone,
    frequency_id: tx.planTitle,
    frequency_tier: tx.planTitle,
    collection_days: d.collectionDays,
    pickup_time: d.pickupTime,
    zone_name: d.zoneName,
    status: scheduled ? "Scheduled" : "Active",
    start_date: Timestamp.fromDate(start),
    expiry_date: Timestamp.fromDate(next),
    amount_paid: tx.displayAmount,
    payment_ref: txRef,
    created_at: FieldValue.serverTimestamp(),
  });

  if (scheduled) {
    // The running plan stays as is; the paid one is queued after it.
    t.set(userRef, {
      subscription_end: Timestamp.fromDate(next),
      next_plan: tx.planTitle,
      last_subscription_at: FieldValue.serverTimestamp(),
    }, {merge: true});
    t.set(db.collection("subscriptions").doc(tx.phone), {
      lastPaymentDate: FieldValue.serverTimestamp(),
      nextPaymentDate: Timestamp.fromDate(next),
      expiryDate: Timestamp.fromDate(next),
      nextPlanName: tx.planTitle,
      nextPlanStart: Timestamp.fromDate(start),
    }, {merge: true});
  } else {
    t.set(userRef, {
      active_contract_id: contractId,
      subscription_plan: tx.planTitle,
      subscription_end: Timestamp.fromDate(next),
      next_plan: FieldValue.delete(),
      collection_days: d.collectionDays,
      pickup_time: d.pickupTime,
      zone_name: d.zoneName,
      isSubscribed: true,
      needsPickup: true,
      last_subscription_at: FieldValue.serverTimestamp(),
    }, {merge: true});
    t.set(db.collection("subscriptions").doc(tx.phone), {
      planName: tx.planTitle,
      price: tx.displayAmount,
      startDate: FieldValue.serverTimestamp(),
      lastPaymentDate: FieldValue.serverTimestamp(),
      nextPaymentDate: Timestamp.fromDate(next),
      expiryDate: Timestamp.fromDate(next),
      status: "active",
      nextPlanName: FieldValue.delete(),
      nextPlanStart: FieldValue.delete(),
      collection_days: d.collectionDays,
      pickup_time: d.pickupTime,
      zone_name: d.zoneName,
    }, {merge: true});
  }

  // Mirrors FactureModel.toMap (lib/features/backoffice/models.dart).
  const factureId = `FCT-${contractId}`;
  t.set(db.collection("factures").doc(factureId), {
    id: factureId,
    client: tx.customerName || "",
    montant: Math.trunc(tx.displayAmount),
    echeance: "",
    status: "Paid",
    agenceId: tx.agenceId || "",
    societeId: tx.societeId || "",
    clientId: tx.phone,
    contractId,
    paymentRef: txRef,
    paidAt: todayIso(),
  });

  if (clientRef && clientRecord && !scheduled) {
    t.update(clientRef, {
      plan: tx.planTitle,
      // First paid subscription = the client enters this month's
      // subscription charts.
      ...(clientRecord.subscribedAt ? {} : {subscribedAt: todayIso()}),
    });
  }
  return {contractId, startsAt: start.toISOString(), scheduled};
}

/** The client's backoffice record (`clients`), by phone. */
async function clientRefByPhone(phone) {
  for (const key of [phone, phone.replace(/^\+237/, "")]) {
    const snap = await db.collection("clients")
        .where("phone", "==", key).limit(1).get();
    if (!snap.empty) return snap.docs[0].ref;
  }
  return null;
}

async function settle(txRef) {
  const txDoc = db.collection("transactions").doc(txRef);
  const snap = await txDoc.get();
  if (!snap.exists) throw new HttpError(404, "Unknown transaction.");
  const tx = snap.data();
  if (tx.status !== "pending") return tx.status;
  if (!tx.campayReference) return "pending";

  const {data} = await campayRequest(
      `/transaction/${encodeURIComponent(tx.campayReference)}/`,
      {method: "GET"},
  );
  const campayStatus = String(data.status || "").toUpperCase();

  if (campayStatus === "FAILED") {
    await txDoc.update({
      status: "failed",
      reason: shortString(data.reason, 200) || null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return "failed";
  }
  if (campayStatus !== "SUCCESSFUL") return "pending";

  // Never fulfill for less than what was requested.
  if (Number(data.amount) < Number(tx.amount)) {
    await txDoc.update({
      status: "failed",
      reason: "amount_mismatch",
      updatedAt: FieldValue.serverTimestamp(),
    });
    return "failed";
  }

  const userRef = await resolveUserRef(tx.phone);
  // The client's backoffice record: a paid subscription sets its plan and
  // subscription date (approval only grants access).
  const clientRef = tx.purpose === "subscription" ?
    await clientRefByPhone(tx.phone) :
    null;
  const zone = clientRef ?
    await zoneCalendarFor((await clientRef.get()).data()) :
    null;

  const outcome = await db.runTransaction(async (t) => {
    const fresh = await t.get(txDoc);
    if (fresh.data().status !== "pending") {
      return {status: fresh.data().status, settledNow: false};
    }
    const current = (await t.get(userRef)).data() || {};
    const clientRecord = clientRef ? (await t.get(clientRef)).data() : null;

    const now = new Date();
    const settled = {
      status: "successful",
      operator: shortString(data.operator) || null,
      operatorReference: shortString(data.operator_reference) || null,
      campayCode: shortString(data.code) || null,
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (tx.purpose === "subscription") {
      const written = writeSubscription(t,
          {tx, txRef, userRef, current, clientRef, clientRecord, zone});
      settled.contractId = written.contractId;
      settled.startsAt = written.startsAt;
      settled.scheduled = written.scheduled;
    } else if (tx.purpose === "extra_pickup") {
      const pickupId = `PKP-${now.getTime()}`;
      t.set(db.collection("pickups").doc(pickupId), {
        pickup_id: pickupId,
        client_id: tx.phone,
        collector_id: tx.collecteurId || "",
        type: "extra",
        status: "paid",
        amount: tx.displayAmount,
        currency: "XAF",
        payment_ref: txRef,
        timestamp: FieldValue.serverTimestamp(),
      });
      t.set(userRef, {needsPickup: true}, {merge: true});
      settled.pickupId = pickupId;
    }

    t.update(txDoc, settled);
    return {status: "successful", settledNow: true};
  });

  if (outcome.settledNow) {
    await deliver({
      phone: tx.phone,
      type: "payment_confirmation",
      title: "Payment confirmed",
      message: `Your payment of ${tx.amount} XAF (${tx.description}) ` +
        `is confirmed. Reference: ${txRef}.`,
      external: true,
    }).catch((error) => console.warn("payment notification", error.message));
  }
  return outcome.status;
}

// ------------------------------------------------------------
// Client endpoints (Authorization: Bearer <Firebase ID token>)
// ------------------------------------------------------------

/**
 * POST { purpose: 'subscription' | 'extra_pickup', plan?, momoPhone,
 *        collectionDays?, pickupTime?, zoneName? }
 * → { txRef, ussdCode, operator, amount, displayAmount, demo }
 */
exports.startPayment = onRequest(
    {cors: true, secrets: [CAMPAY_USERNAME, CAMPAY_PASSWORD]},
    async (req, res) => {
      try {
        if (req.method !== "POST") throw new HttpError(405, "POST only.");
        const caller = await authenticate(req);
        if (caller.role !== "client" || !caller.phone) {
          throw new HttpError(403, "Only client accounts can pay.");
        }

        const body = req.body || {};
        const purpose = body.purpose;
        let displayAmount;
        let planTitle = null;
        let description;
        if (purpose === "subscription") {
          const plan = PLANS[String(body.plan || "").toLowerCase()];
          if (!plan) throw new HttpError(400, "Unknown plan.");
          displayAmount = plan.price;
          planTitle = plan.title;
          description = `WastePro ${plan.title} subscription`;
        } else if (purpose === "extra_pickup") {
          displayAmount = EXTRA_PICKUP_PRICE;
          description = "Extra pickup";
        } else {
          throw new HttpError(400, "Unknown payment purpose.");
        }

        const from = campayPhone(body.momoPhone);
        if (!from) {
          throw new HttpError(400,
              "Use a Cameroon MoMo number like 6XX XXX XXX.");
        }

        const amount = isDemo() ?
          Math.min(DEMO_MAX_AMOUNT, displayAmount) :
          displayAmount;

        const userSnap = await (await resolveUserRef(caller.phone)).get();
        const user = userSnap.data() || {};

        const prefix = purpose === "subscription" ? "WP" : "PICKUP";
        const txRef = `${prefix}-${Date.now()}-` +
          Math.floor(Math.random() * 0xffffff).toString(16);
        const txDoc = db.collection("transactions").doc(txRef);

        await txDoc.set({
          txRef,
          uid: caller.uid,
          userId: caller.phone,
          phone: caller.phone,
          customerName: user.fullName || "",
          agenceId: user.agenceId || "",
          societeId: user.societeId || "",
          collecteurId: user.collecteurId || "",
          purpose,
          type: purpose === "subscription" ? "subscription" : "pickup",
          planTitle,
          description,
          amount,
          displayAmount,
          currency: "XAF",
          isDemoCharge: isDemo(),
          paymentMethod: "campay",
          momoPhone: from,
          details: {
            collectionDays: stringList(body.collectionDays),
            pickupTime: shortString(body.pickupTime, 40),
            zoneName: shortString(body.zoneName),
          },
          status: "pending",
          createdAt: FieldValue.serverTimestamp(),
        });

        let data;
        try {
          ({data} = await campayRequest("/collect/", {
            method: "POST",
            body: JSON.stringify({
              amount: String(amount),
              currency: "XAF",
              from,
              description,
              external_reference: txRef,
            }),
          }));
        } catch (error) {
          // Never leave a transaction pending when CamPay is unreachable.
          data = {message: error instanceof HttpError ? error.message :
            "The payment provider is unreachable."};
        }
        if (!data.reference) {
          const message = data.message || data.detail ||
            "The payment request could not be sent.";
          await txDoc.update({
            status: "failed",
            reason: shortString(String(message), 200),
            updatedAt: FieldValue.serverTimestamp(),
          });
          throw new HttpError(502, String(message));
        }

        await txDoc.update({campayReference: data.reference});

        return res.status(200).json({
          txRef,
          ussdCode: data.ussd_code || "",
          operator: data.operator || "",
          amount,
          displayAmount,
          demo: isDemo(),
        });
      } catch (error) {
        return sendError(res, error);
      }
    },
);

/**
 * POST { phone, plan: 'monthly' | 'weekly' | 'daily' } — staff record a
 * subscription paid in CASH at the agency. Same effect as a mobile money
 * payment (contract, subscription, paid invoice, transaction with
 * paymentMethod 'cash'), at the plan's server-side price.
 * → { txRef, contractId, amount }
 */
exports.recordCashPayment = onRequest({cors: true}, async (req, res) => {
  try {
    if (req.method !== "POST") throw new HttpError(405, "POST only.");
    const caller = await authenticate(req);
    if (!["super_admin", "general_admin", "agency_manager"]
        .includes(caller.role)) {
      throw new HttpError(403, "Staff only.");
    }
    const body = req.body || {};
    const phone = canonicalPhone(body.phone);
    const plan = PLANS[String(body.plan || "").toLowerCase()];
    if (!phone) throw new HttpError(400, "Missing phone number.");
    if (!plan) throw new HttpError(400, "Unknown plan.");

    const clientRef = await clientRefByPhone(phone);
    const clientRecord = clientRef ? (await clientRef.get()).data() : null;
    if (!clientRecord) throw new HttpError(404, "Unknown client.");
    if (!callerCanManage(caller, clientRecord)) {
      throw new HttpError(403, "This client belongs to another agency.");
    }
    const userRef = await resolveUserRef(phone);
    if (!(await userRef.get()).exists) {
      throw new HttpError(400,
          "This client has no login account yet: set a password first.");
    }

    const txRef = `CASH-${Date.now()}-` +
      Math.floor(Math.random() * 0xffffff).toString(16);
    const tx = {
      txRef,
      userId: phone,
      phone,
      customerName: clientRecord.name || "",
      agenceId: clientRecord.agenceId || "",
      societeId: clientRecord.societeId || "",
      purpose: "subscription",
      type: "subscription",
      planTitle: plan.title,
      description: `WastePro ${plan.title} subscription`,
      amount: plan.price,
      displayAmount: plan.price,
      currency: "XAF",
      isDemoCharge: false,
      paymentMethod: "cash",
      method: "Cash",
      recordedBy: caller.phone,
      status: "successful",
    };

    const zone = await zoneCalendarFor(clientRecord);
    const written = await db.runTransaction(async (t) => {
      const [user, client] = await Promise.all([t.get(userRef),
        t.get(clientRef)]);
      const w = writeSubscription(t, {tx, txRef, userRef,
        current: user.data() || {}, clientRef,
        clientRecord: client.data(), zone});
      t.set(db.collection("transactions").doc(txRef), {
        ...tx,
        uid: user.data()?.uid || "",
        contractId: w.contractId,
        startsAt: w.startsAt,
        scheduled: w.scheduled,
        createdAt: FieldValue.serverTimestamp(),
      });
      return w;
    });
    const contractId = written.contractId;

    await deliver({
      phone,
      type: "payment_confirmation",
      title: "Payment confirmed",
      message: `Your cash payment of ${plan.price} XAF (${plan.title} plan) ` +
        `is recorded. Reference: ${txRef}.`,
      external: true,
    }).catch((error) => console.warn("cash notification", error.message));

    return res.status(200).json({txRef, contractId, amount: plan.price,
      startsAt: written.startsAt, scheduled: written.scheduled});
  } catch (error) {
    return sendError(res, error);
  }
});

/**
 * POST { txRef } → { status: 'pending' | 'successful' | 'failed' }
 */
exports.checkPayment = onRequest(
    {cors: true, secrets: [CAMPAY_USERNAME, CAMPAY_PASSWORD]},
    async (req, res) => {
      try {
        if (req.method !== "POST") throw new HttpError(405, "POST only.");
        const caller = await authenticate(req);
        const txRef = shortString((req.body || {}).txRef, 120);
        if (!txRef) throw new HttpError(400, "Missing txRef.");

        const snap = await db.collection("transactions").doc(txRef).get();
        if (!snap.exists || snap.data().uid !== caller.uid) {
          throw new HttpError(404, "Unknown transaction.");
        }
        const status = await settle(txRef);
        // When the plan starts (later if it was queued after a running one).
        const settled = status === "successful" ?
          (await db.collection("transactions").doc(txRef).get()).data() :
          {};
        return res.status(200).json({
          status,
          startsAt: settled.startsAt || null,
          scheduled: settled.scheduled === true,
        });
      } catch (error) {
        return sendError(res, error);
      }
    },
);

// ------------------------------------------------------------
// Login account management (consoles)
// ------------------------------------------------------------

/** Roles each staff role may manage — mirrors `manageableRoles` in rules. */
const MANAGEABLE = {
  super_admin: ["super_admin", "general_admin", "agency_manager", "client",
    "collector", "pending_client", ""],
  general_admin: ["general_admin", "agency_manager", "client", "collector",
    "pending_client", ""],
  agency_manager: ["client", "collector", "pending_client", ""],
};

const emailFor = (phone) => `${phone.replace("+", "")}@wastepro.cm`;

function canonicalPhone(raw) {
  const cleaned = String(raw || "").trim().replace(/[\s-]/g, "");
  if (!cleaned) return "";
  if (cleaned.startsWith("+")) return cleaned;
  if (cleaned.startsWith("237")) return `+${cleaned}`;
  return `+237${cleaned}`;
}

async function authUserByEmail(email) {
  try {
    return await getAuth().getUserByEmail(email);
  } catch (error) {
    if (error.code === "auth/user-not-found") return null;
    throw error;
  }
}

/**
 * The caller may only act on an account whose current role (login profile
 * and rules profile) they are allowed to manage — otherwise a manager could
 * reset an administrator's password.
 */
async function assertCanManage(caller, phone, authUser) {
  const allowed = MANAGEABLE[caller.role] || [];
  const checks = [
    db.collection("users").doc(phone).get(),
    // Legacy profiles keyed by the bare number (no +237).
    db.collection("users").doc(phone.replace(/^\+237/, "")).get(),
  ];
  if (authUser) checks.push(db.collection("auth_profiles").doc(authUser.uid).get());
  for (const snap of await Promise.all(checks)) {
    if (snap.exists && !allowed.includes(String(snap.data().role || ""))) {
      throw new HttpError(403, "You are not allowed to manage this account.");
    }
  }
}

/**
 * POST { action: 'ensure' | 'disable' | 'delete' | 'move', phone,
 *        password?, newPhone? }
 *
 * - ensure: creates the Auth account (password required), or re-enables an
 *   existing one and sets the password if given → { uid, created }
 * - disable: suspension (the account and its uid are kept)
 * - delete: removes the account (missing account is not an error)
 * - move: phone number changed — the account keeps its uid and password
 *   and gets the new number's email → { uid } (null if no account)
 *
 * Replaces the consoles' old practice of storing passwords in Firestore to
 * act on accounts through the client SDK.
 */
exports.manageAccount = onRequest({cors: true}, async (req, res) => {
  try {
    if (req.method !== "POST") throw new HttpError(405, "POST only.");
    const caller = await authenticate(req);
    if (!MANAGEABLE[caller.role]) {
      throw new HttpError(403, "Staff only.");
    }
    const body = req.body || {};
    const phone = canonicalPhone(body.phone);
    if (!/^\+\d{8,15}$/.test(phone)) {
      throw new HttpError(400, "Invalid phone number.");
    }
    const password = typeof body.password === "string" ? body.password : "";
    const email = emailFor(phone);
    const existing = await authUserByEmail(email);
    await assertCanManage(caller, phone, existing);

    switch (body.action) {
      case "ensure": {
        if (existing) {
          const update = {disabled: false};
          if (password) update.password = password;
          await getAuth().updateUser(existing.uid, update);
          return res.status(200).json({uid: existing.uid, created: false});
        }
        if (password.length < 6) {
          throw new HttpError(400, password ?
            "Password must be at least 6 characters." :
            "password-required");
        }
        const created = await getAuth().createUser({email, password});
        return res.status(200).json({uid: created.uid, created: true});
      }
      case "disable":
        if (existing) {
          await getAuth().updateUser(existing.uid, {disabled: true});
        }
        return res.status(200).json({ok: true});
      case "delete":
        if (existing) await getAuth().deleteUser(existing.uid);
        return res.status(200).json({ok: true});
      case "move": {
        // Phone number changed: same account (uid + password), new email.
        const newPhone = canonicalPhone(body.newPhone);
        if (!/^\+\d{8,15}$/.test(newPhone)) {
          throw new HttpError(400, "Invalid new phone number.");
        }
        if (!existing) return res.status(200).json({uid: null});
        const taken = await authUserByEmail(emailFor(newPhone));
        if (taken && taken.uid !== existing.uid) {
          throw new HttpError(409, "email-already-in-use");
        }
        await assertCanManage(caller, newPhone, null);
        await getAuth().updateUser(existing.uid, {email: emailFor(newPhone)});
        return res.status(200).json({uid: existing.uid});
      }
      default:
        throw new HttpError(400, "Unknown action.");
    }
  } catch (error) {
    return sendError(res, error);
  }
});

// ------------------------------------------------------------
// SMS codes (forgotten password)
//
// SMS (Vonage) — functions/.env: VONAGE_API_KEY, VONAGE_API_SECRET,
// VONAGE_SENDER. Development only: SMS_DEV_CODE=<6 digits> is also
// accepted — NEVER set it in production.
// ------------------------------------------------------------
const VONAGE_API_KEY = defineString("VONAGE_API_KEY", {default: ""});
const VONAGE_API_SECRET = defineString("VONAGE_API_SECRET", {default: ""});
const VONAGE_SENDER = defineString("VONAGE_SENDER", {default: "WastePro"});
const SMS_DEV_CODE = defineString("SMS_DEV_CODE", {default: ""});

const OTP_RESEND_MS = 60 * 1000;
const OTP_MAX_ATTEMPTS = 5;
const OTP_LOCKOUT_MS = 15 * 60 * 1000;

function hashCode(uid, code) {
  return crypto.createHash("sha256").update(`${uid}:${code}`).digest("hex");
}

async function sendSms(phone, text) {
  const key = VONAGE_API_KEY.value();
  const secret = VONAGE_API_SECRET.value();
  if (!key || !secret) return false;
  const res = await fetch("https://rest.nexmo.com/sms/json", {
    method: "POST",
    headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body: new URLSearchParams({
      api_key: key,
      api_secret: secret,
      from: VONAGE_SENDER.value(),
      to: phone.replace(/[^0-9]/g, ""),
      text,
    }),
  });
  const data = await res.json().catch(() => ({}));
  return res.ok && data.messages?.[0]?.status === "0";
}

// ------------------------------------------------------------
// Forgotten password — reset with a code sent by SMS
//
// Logins use an internal email nobody receives, so Firebase's reset email
// cannot work. Safeguards: hashed code, 10 min validity,
// 5 attempts then 15 min lock, one code per minute and 5 per day. The
// answers never reveal whether a number has an account.
// ------------------------------------------------------------
const RESET_TTL_MS = 10 * 60 * 1000;
const RESET_MAX_PER_DAY = 5;
const RESET_SENT = "If this number has an account, a code was sent by SMS.";

/** POST { phone } → always { sent: true, message } (no enumeration). */
exports.passwordResetStart = onRequest({cors: true}, async (req, res) => {
  try {
    if (req.method !== "POST") throw new HttpError(405, "POST only.");
    const phone = canonicalPhone((req.body || {}).phone);
    if (!/^\+\d{8,15}$/.test(phone)) {
      throw new HttpError(400, "Enter a valid phone number.");
    }
    const answer = {sent: true, message: RESET_SENT};
    const account = await authUserByEmail(emailFor(phone));
    if (!account) return res.status(200).json(answer);

    const ref = db.collection("password_resets").doc(phone);
    const now = Date.now();
    const current = (await ref.get()).data() || {};
    if ((current.lockedUntil || 0) > now) return res.status(200).json(answer);
    if (now - (current.sentAt || 0) < OTP_RESEND_MS) {
      return res.status(200).json(answer);
    }
    const sameDay = (current.day || "") === todayIso();
    const count = sameDay ? (current.count || 0) : 0;
    if (count >= RESET_MAX_PER_DAY) return res.status(200).json(answer);

    const code = String(crypto.randomInt(0, 1000000)).padStart(6, "0");
    await ref.set({
      codeHash: hashCode(`reset:${phone}`, code),
      sentAt: now,
      expiresAt: now + RESET_TTL_MS,
      attempts: 0,
      lockedUntil: 0,
      day: todayIso(),
      count: count + 1,
    });
    await sendSms(phone, `Your WastePro password reset code is: ${code}. ` +
      "It expires in 10 minutes. If you did not ask for it, ignore this " +
      "message.").catch(() => false);
    return res.status(200).json(answer);
  } catch (error) {
    return sendError(res, error);
  }
});

/** POST { phone, code, newPassword } → { reset: true } or an error. */
exports.passwordResetConfirm = onRequest({cors: true}, async (req, res) => {
  try {
    if (req.method !== "POST") throw new HttpError(405, "POST only.");
    const body = req.body || {};
    const phone = canonicalPhone(body.phone);
    const code = String(body.code || "").trim();
    const newPassword = typeof body.newPassword === "string" ?
      body.newPassword : "";
    if (!/^\d{6}$/.test(code)) {
      throw new HttpError(400, "Please enter the full 6-digit code.");
    }
    if (newPassword.length < 6) {
      throw new HttpError(400, "Password must be at least 6 characters.");
    }
    const ref = db.collection("password_resets").doc(phone || "-");
    const now = Date.now();
    const invalid = "Invalid or expired code. Request a new one.";

    const result = await db.runTransaction(async (t) => {
      const data = (await t.get(ref)).data();
      if (!data || !data.codeHash) return {error: invalid};
      if ((data.lockedUntil || 0) > now) {
        return {error: "Too many failed attempts. Try again in 15 minutes."};
      }
      if ((data.expiresAt || 0) < now) return {error: invalid};
      const devCode = SMS_DEV_CODE.value();
      const ok = data.codeHash === hashCode(`reset:${phone}`, code) ||
        (devCode.length === 6 && code === devCode);
      if (ok) {
        t.update(ref, {codeHash: null, attempts: 0});
        return {ok: true};
      }
      const attempts = (data.attempts || 0) + 1;
      t.update(ref, attempts >= OTP_MAX_ATTEMPTS ?
        {attempts, codeHash: null, lockedUntil: now + OTP_LOCKOUT_MS} :
        {attempts});
      return {error: attempts >= OTP_MAX_ATTEMPTS ?
        "Too many failed attempts. Try again in 15 minutes." :
        `Incorrect code. ${OTP_MAX_ATTEMPTS - attempts} attempt(s) remaining.`};
    });
    if (result.error) throw new HttpError(400, result.error);

    const account = await authUserByEmail(emailFor(phone));
    if (!account) throw new HttpError(400, invalid);
    await getAuth().updateUser(account.uid, {password: newPassword});
    // Sessions opened with the old password are signed out.
    await getAuth().revokeRefreshTokens(account.uid);
    return res.status(200).json({reset: true});
  } catch (error) {
    return sendError(res, error);
  }
});

// ------------------------------------------------------------
// Notifications (in-app + push + SMS / WhatsApp), server-side only
//
// The app never holds SMS / WhatsApp credentials and never writes another
// user's notifications: it reports an EVENT ({event, pickupId}); the server
// checks the caller, reads the facts from Firestore and uses fixed
// templates (no free text can be sent from our numbers).
//
// functions/.env (optional): WHATSAPP_PHONE_NUMBER_ID, WHATSAPP_ACCESS_TOKEN
// ------------------------------------------------------------
const WHATSAPP_PHONE_NUMBER_ID =
  defineString("WHATSAPP_PHONE_NUMBER_ID", {default: ""});
const WHATSAPP_ACCESS_TOKEN =
  defineString("WHATSAPP_ACCESS_TOKEN", {default: ""});

async function sendWhatsApp(phone, text) {
  const id = WHATSAPP_PHONE_NUMBER_ID.value();
  const token = WHATSAPP_ACCESS_TOKEN.value();
  if (!id || !token) return false;
  // Free-form text: only delivered inside WhatsApp's 24 h session window.
  const res = await fetch(`https://graph.facebook.com/v19.0/${id}/messages`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      to: phone.replace(/[^0-9]/g, ""),
      type: "text",
      text: {body: text},
    }),
  });
  return res.ok;
}

/**
 * Delivers one notification to [phone]: in-app row (bell), FCM push to the
 * device token saved in `users/{phone}.fcmToken`, and optionally SMS +
 * WhatsApp. Best-effort per channel.
 */
async function deliver({phone, type, title, message, pickupId = "",
  external = false}) {
  if (!phone) return;
  await db.collection("notifications").add({
    id: `n${Date.now()}${Math.floor(Math.random() * 1000)}`,
    phone,
    type,
    title,
    message,
    pickupId,
    read: false,
    createdAt: todayIso(),
  });
  try {
    const user = (await (await resolveUserRef(phone)).get()).data() || {};
    if (user.fcmToken) {
      await getMessaging().send({
        token: user.fcmToken,
        notification: {title, body: message},
        data: {type, pickupId: String(pickupId)},
      });
    }
  } catch (error) {
    console.warn("push failed", phone, error.message);
  }
  if (external) {
    const text = `${message} - WastePro`;
    await sendSms(phone, text).catch(() => false);
    await sendWhatsApp(phone, text).catch(() => false);
  }
}

/** Phone of a collector from a pickup's `collector_id` (doc id or phone). */
async function collectorPhone(collectorId) {
  if (!collectorId) return "";
  if (collectorId.startsWith("+")) return collectorId;
  const snap = await db.collection("collecteurs").doc(collectorId).get();
  return canonicalPhone(snap.data()?.phone || "");
}

const kg = (poids) => `${Number(poids || 0).toFixed(1)} kg`;

/**
 * Issue lifecycle (see `notify`):
 *   - issue_assigned (the agency's staff) → collector + client
 *   - issue_started / issue_resolved (the assigned collector) → client
 * Each event is delivered once per issue (once per collector for
 * issue_assigned, so a reassignment notifies the new collector).
 */
async function notifyIssue(caller, event, issueId) {
  if (!issueId) throw new HttpError(400, "Missing issueId.");
  const ref = db.collection("issues").doc(issueId);
  const issue = (await ref.get()).data();
  if (!issue) throw new HttpError(404, "Unknown issue.");
  const collector = canonicalPhone(issue.assignedCollectorPhone || "");

  if (event === "issue_assigned") {
    if (!callerCanManage(caller, issue)) {
      throw new HttpError(403, "This issue belongs to another agency.");
    }
    if (!collector) throw new HttpError(400, "The issue is not assigned.");
  } else if (event === "issue_started" || event === "issue_resolved") {
    if (caller.role !== "collector" || !collector ||
        canonicalPhone(caller.phone) !== collector) {
      throw new HttpError(403, "This issue is not assigned to you.");
    }
  } else {
    throw new HttpError(400, "Unknown event.");
  }

  const key = event === "issue_assigned" ?
    `${event}_${collector.replace(/\D/g, "")}` : event;
  const already = await db.runTransaction(async (t) => {
    const fresh = (await t.get(ref)).data() || {};
    if ((fresh.notified || {})[key]) return true;
    t.update(ref, {[`notified.${key}`]: FieldValue.serverTimestamp()});
    return false;
  });
  if (already) return;

  const what = shortString(issue.category, 60) || "Your report";
  const name = shortString(issue.assignedCollectorName, 60) || "A collector";
  if (event === "issue_assigned") {
    await deliver({
      phone: collector,
      type: "issue_assigned",
      title: "New issue assigned to you",
      message: `${what} reported by ${issue.client_name || "a client"}` +
        (issue.location ? ` (${shortString(issue.location, 80)})` : "") +
        ". Open the app to start it.",
      external: true,
    });
    await deliver({
      phone: issue.client_id,
      type: "issue_assigned",
      title: "Your report is being handled",
      message: `${what}: ${name} has been assigned to it.`,
    });
  } else if (event === "issue_started") {
    await deliver({
      phone: issue.client_id,
      type: "issue_started",
      title: "Your report is in progress",
      message: `${name} has started working on: ${what}.`,
    });
  } else {
    await deliver({
      phone: issue.client_id,
      type: "issue_resolved",
      title: "Your report is resolved",
      message: `${what} has been resolved by ${name}. Thank you for ` +
        "reporting it!",
      external: true,
    });
  }
}

/**
 * POST { event, pickupId, reason? } — pickup lifecycle notifications.
 *   - pickup_confirmation_request (collector of the pickup) → client
 *   - pickup_confirmed (client of the pickup) → client + collector
 *   - pickup_disputed (client of the pickup) → client
 * Each event is delivered at most once per pickup.
 */
exports.notify = onRequest({cors: true}, async (req, res) => {
  try {
    if (req.method !== "POST") throw new HttpError(405, "POST only.");
    const caller = await authenticate(req);
    const body = req.body || {};
    const event = String(body.event || "");
    if (event.startsWith("issue_")) {
      await notifyIssue(caller, event, shortString(body.issueId, 120));
      return res.status(200).json({ok: true});
    }
    const pickupId = shortString(body.pickupId, 120);
    if (!pickupId) throw new HttpError(400, "Missing pickupId.");
    const ref = db.collection("pickups").doc(pickupId);
    const pickup = (await ref.get()).data();
    if (!pickup) throw new HttpError(404, "Unknown pickup.");

    const isClientOfPickup = caller.role === "client" &&
      pickup.client_id === caller.phone;
    let isCollectorOfPickup = false;
    if (caller.role === "collector") {
      const me = (await (await resolveUserRef(caller.phone)).get()).data() ||
        {};
      isCollectorOfPickup = [caller.phone, me.collecteurId]
          .filter(Boolean).includes(pickup.collector_id);
    }

    const allowed = {
      pickup_confirmation_request: isCollectorOfPickup,
      pickup_confirmed: isClientOfPickup,
      pickup_disputed: isClientOfPickup,
    };
    if (!(event in allowed)) throw new HttpError(400, "Unknown event.");
    if (!allowed[event]) throw new HttpError(403, "Not your pickup.");

    // At most once per pickup and event.
    const already = await db.runTransaction(async (t) => {
      const fresh = (await t.get(ref)).data() || {};
      if ((fresh.notified || {})[event]) return true;
      t.update(ref, {[`notified.${event}`]: FieldValue.serverTimestamp()});
      return false;
    });
    if (already) return res.status(200).json({ok: true, duplicate: true});

    const collectorName = pickup.collector_name || "Your collector";
    const date = pickup.date || todayIso();
    if (event === "pickup_confirmation_request") {
      await deliver({
        phone: pickup.client_id,
        type: "pickup_to_confirm",
        title: "Validate your pickup",
        message: `${collectorName} collected ${kg(pickup.poids)} from you ` +
          `(${date}). Open the app to scan the QR code and confirm, or ` +
          "report it if the pickup did not happen.",
        pickupId,
        external: true,
      });
    } else if (event === "pickup_confirmed") {
      await deliver({
        phone: pickup.client_id,
        type: "pickup_confirmed",
        title: "Pickup confirmed",
        message: `You validated the pickup of ${kg(pickup.poids)} by ` +
          `${collectorName}. Thank you!`,
        pickupId,
      });
      await deliver({
        phone: await collectorPhone(pickup.collector_id),
        type: "pickup_validated",
        title: "Pickup validated by the client",
        message: `The client confirmed the ${kg(pickup.poids)} collected ` +
          `on ${date}.`,
        pickupId,
      });
    } else {
      const reason = shortString(body.reason, 60);
      await deliver({
        phone: pickup.client_id,
        type: "pickup_disputed",
        title: "Pickup reported",
        message: `Your report about the pickup of ${date}` +
          (reason ? ` (${reason})` : "") +
          " has been submitted. The agency will review it.",
        pickupId,
      });
    }
    return res.status(200).json({ok: true});
  } catch (error) {
    return sendError(res, error);
  }
});

// ------------------------------------------------------------
// WasteBot AI (Hugging Face) — the token never leaves the server
//
// Secret: firebase functions:secrets:set HF_TOKEN
// functions/.env (optional): HF_MODEL
// ------------------------------------------------------------
const HF_TOKEN = defineSecret("HF_TOKEN");
const HF_MODEL = defineString("HF_MODEL",
    {default: "Qwen/Qwen2.5-7B-Instruct:fastest"});
const CHAT_MAX_PER_HOUR = 30;

const CHAT_PROMPTS = {
  fr: `Tu es WasteBot, l'assistant officiel de WastePro (collecte de dechets au Cameroun).
Reponds en francais, de facon courte, claire et amicale (3 a 8 phrases max).
N'utilise jamais d'emojis. Ne parle que de WastePro et de la gestion des dechets.
Tu connais :
- Plans : Monthly 3000 XAF (1 collecte/semaine), Weekly 5500 XAF (2/semaine), Daily 15000 XAF (tous les jours).
- Paiement CamPay (MTN MoMo / Orange Money).
- Collectes, QR, notifications, plaintes, ramassage supplementaire (1000 XAF).
- Support : WhatsApp / appel +237 696 713 899, email support@wastepro.cm.
Si tu ne sais pas, propose de contacter le support humain.
Ne demande jamais de mot de passe, PIN ou code.`,
  en: `You are WasteBot, the official WastePro assistant (waste collection in Cameroon).
Reply in English, short, clear and friendly (3 to 8 sentences max).
Never use emojis. Only discuss WastePro and waste management.
You know:
- Plans: Monthly 3000 XAF (1 pickup/week), Weekly 5500 XAF (2/week), Daily 15000 XAF (every day).
- CamPay payments (MTN MoMo / Orange Money).
- Pickups, QR, notifications, complaints, extra pickup (1000 XAF).
- Support: WhatsApp / call +237 696 713 899, email support@wastepro.cm.
If unsure, suggest contacting human support.
Never ask for passwords, PINs or codes.`,
};

/**
 * POST { message, french, history: [{role, content}] } → { answer }
 * Errors carry a `code`: not_configured | rate_limit | upstream.
 */
exports.chatbot = onRequest(
    {cors: true, secrets: [HF_TOKEN], timeoutSeconds: 90},
    async (req, res) => {
      try {
        if (req.method !== "POST") throw new HttpError(405, "POST only.");
        const caller = await authenticate(req);
        const body = req.body || {};
        const message = shortString(body.message, 500).trim();
        if (!message) throw new HttpError(400, "Empty message.");

        // Per-account hourly quota (protects the Hugging Face bill).
        const usageRef = db.collection("chatbot_usage").doc(caller.uid);
        const allowed = await db.runTransaction(async (t) => {
          const u = (await t.get(usageRef)).data() || {};
          const now = Date.now();
          const fresh = now - (u.windowStart || 0) > 3600 * 1000;
          const count = fresh ? 0 : (u.count || 0);
          if (count >= CHAT_MAX_PER_HOUR) return false;
          t.set(usageRef, {
            windowStart: fresh ? now : u.windowStart,
            count: count + 1,
          });
          return true;
        });
        if (!allowed) {
          return res.status(429).json({code: "rate_limit",
            error: "Too many questions. Try again later."});
        }

        const token = HF_TOKEN.value();
        if (!token.startsWith("hf_")) {
          return res.status(503).json({code: "not_configured",
            error: "WasteBot AI is not configured."});
        }
        const history = (Array.isArray(body.history) ? body.history : [])
            .slice(-10)
            .filter((m) => ["user", "assistant"].includes(m?.role))
            .map((m) => ({role: m.role, content: shortString(m.content, 1000)}));

        const upstream = await fetch(
            "https://router.huggingface.co/v1/chat/completions", {
              method: "POST",
              headers: {
                "Authorization": `Bearer ${token}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({
                model: HF_MODEL.value(),
                messages: [
                  {role: "system",
                    content: body.french ? CHAT_PROMPTS.fr : CHAT_PROMPTS.en},
                  ...history,
                  {role: "user", content: message},
                ],
                max_tokens: 450,
                temperature: 0.4,
              }),
            });
        const data = await upstream.json().catch(() => ({}));
        const answer = data.choices?.[0]?.message?.content?.trim();
        if (!upstream.ok || !answer) {
          console.warn("chatbot upstream", upstream.status,
              JSON.stringify(data).slice(0, 300));
          return res.status(502).json({
            code: upstream.status === 429 ? "rate_limit" : "upstream",
            error: "WasteBot AI is temporarily unavailable.",
          });
        }
        return res.status(200).json({answer});
      } catch (error) {
        return sendError(res, error);
      }
    },
);

// ------------------------------------------------------------
// Contract expiry — daily, server-side (was swept from client devices)
// ------------------------------------------------------------
const REMINDER_DAYS = [3, 1];

function asDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  const d = new Date(value);
  return isNaN(d.getTime()) ? null : d;
}

/** Expires due contracts and sends J-3 / J-1 renewal reminders. */
async function contractExpirySweep(now = new Date()) {
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(),
      now.getUTCDate());
  const snap = await db.collection("contracts")
      .where("status", "==", "Active").get();
  let expired = 0;
  let reminded = 0;
  let activated = 0;
  for (const doc of snap.docs) {
    const c = doc.data();
    const expiry = asDate(c.expiry_date);
    const phone = c.client_id || "";
    if (!expiry || !phone) continue;
    const expiryDay = Date.UTC(expiry.getUTCFullYear(), expiry.getUTCMonth(),
        expiry.getUTCDate());
    const daysLeft = Math.round((expiryDay - today) / 864e5);

    if (daysLeft < 0) {
      const userRef = await resolveUserRef(phone);
      const user = (await userRef.get()).data() || {};
      await doc.ref.update({
        status: "Expired",
        expired_at: FieldValue.serverTimestamp(),
      });
      expired++;
      // Only the ACTIVE contract decides the subscription.
      if (user.active_contract_id && user.active_contract_id !== doc.id) {
        continue;
      }
      // A plan paid in advance takes over; otherwise the subscription ends.
      const next = await nextScheduledContract(phone);
      if (next) {
        await activateScheduledContract(next, phone);
        activated++;
        continue;
      }
      const batch = db.batch();
      batch.set(userRef, {
        isSubscribed: false,
        active_contract_id: FieldValue.delete(),
      }, {merge: true});
      const subRef = db.collection("subscriptions").doc(phone);
      if ((await subRef.get()).exists) {
        batch.update(subRef, {status: "expired"});
      }
      await batch.commit();
      continue;
    }

    // Already renewed (plan queued after this one): no reminder.
    if (REMINDER_DAYS.includes(daysLeft) &&
        await nextScheduledContract(phone)) {
      continue;
    }
    const sent = (c.expiry_reminders_sent || []).map(String);
    if (REMINDER_DAYS.includes(daysLeft) && !sent.includes(String(daysLeft))) {
      await deliver({
        phone,
        type: "subscription_expiry",
        title: "Subscription expiring",
        message: `Your WastePro subscription expires in ${daysLeft} ` +
          "day(s). Renew now to avoid service interruption.",
        external: true,
      });
      await doc.ref.update({
        expiry_reminders_sent: FieldValue.arrayUnion(String(daysLeft)),
      });
      reminded++;
    }
  }

  // Safety net: a queued plan whose start has passed while the client has
  // no running subscription (e.g. paid just after the previous one ended).
  const queued = await db.collection("contracts")
      .where("status", "==", "Scheduled").get();
  for (const doc of queued.docs) {
    const c = doc.data();
    const start = asDate(c.start_date);
    if (!start || start > now || !c.client_id) continue;
    const user = (await (await resolveUserRef(c.client_id)).get()).data() || {};
    if (user.isSubscribed === true && user.active_contract_id) {
      const running = await db.collection("contracts")
          .doc(user.active_contract_id).get();
      if (running.data()?.status === "Active") continue;
    }
    const next = await nextScheduledContract(c.client_id);
    if (next) {
      await activateScheduledContract(next, c.client_id);
      activated++;
    }
  }
  return {expired, reminded, activated};
}

/** Earliest plan paid in advance for [phone] (status 'Scheduled'). */
async function nextScheduledContract(phone) {
  const snap = await db.collection("contracts")
      .where("client_id", "==", phone)
      .where("status", "==", "Scheduled").get();
  return snap.docs
      .sort((a, b) => (asDate(a.data().start_date)?.getTime() || 0) -
        (asDate(b.data().start_date)?.getTime() || 0))[0] || null;
}

/** The queued plan becomes the client's running subscription. */
async function activateScheduledContract(contractDoc, phone) {
  const c = contractDoc.data();
  const userRef = await resolveUserRef(phone);
  const clientRef = await clientRefByPhone(phone);
  const stillQueued = (await db.collection("contracts")
      .where("client_id", "==", phone)
      .where("status", "==", "Scheduled").get()).size > 1;
  const batch = db.batch();
  batch.update(contractDoc.ref, {
    status: "Active",
    activated_at: FieldValue.serverTimestamp(),
  });
  batch.set(userRef, {
    active_contract_id: contractDoc.id,
    subscription_plan: c.frequency_id,
    collection_days: c.collection_days || [],
    pickup_time: c.pickup_time || "",
    zone_name: c.zone_name || "",
    isSubscribed: true,
    needsPickup: true,
    ...(stillQueued ? {} : {next_plan: FieldValue.delete()}),
  }, {merge: true});
  batch.set(db.collection("subscriptions").doc(phone), {
    planName: c.frequency_id,
    price: c.amount_paid ?? 0,
    startDate: c.start_date ?? FieldValue.serverTimestamp(),
    expiryDate: c.expiry_date,
    status: "active",
    collection_days: c.collection_days || [],
    pickup_time: c.pickup_time || "",
    zone_name: c.zone_name || "",
    ...(stillQueued ? {} : {
      nextPlanName: FieldValue.delete(),
      nextPlanStart: FieldValue.delete(),
    }),
  }, {merge: true});
  if (clientRef) batch.update(clientRef, {plan: c.frequency_id});
  await batch.commit();
}

exports.contractExpiry = onSchedule(
    {schedule: "every day 07:00", timeZone: "Africa/Douala"},
    async () => {
      const result = await contractExpirySweep();
      console.log("contractExpiry", result);
    },
);

// ------------------------------------------------------------
// Tenant scope stamping — pickups / issues get the client's agency
//
// They are created by collectors and clients (app) without an agency; the
// rules restrict staff to their own agency / company, and the backoffice
// queries them by `agenceId`. The scope is copied from the client's
// `clients` record (fallback: login profile).
// ------------------------------------------------------------
async function scopeOfClient(phone) {
  const canonical = canonicalPhone(phone);
  if (!canonical) return null;
  for (const key of [canonical, canonical.replace(/^\+237/, "")]) {
    const snap = await db.collection("clients")
        .where("phone", "==", key).limit(1).get();
    if (!snap.empty) {
      const c = snap.docs[0].data();
      if (c.agenceId) return {agenceId: c.agenceId, societeId: c.societeId || ""};
    }
  }
  const user = (await (await resolveUserRef(canonical)).get()).data() || {};
  return user.agenceId ?
    {agenceId: user.agenceId, societeId: user.societeId || ""} :
    null;
}

async function stampScope(event) {
  const data = event.data?.data();
  if (!data || data.agenceId) return;
  const scope = await scopeOfClient(data.client_id || data.clientPhone || "");
  if (scope) await event.data.ref.update(scope);
}

exports.stampPickupScope =
  onDocumentCreated("pickups/{id}", stampScope);
exports.stampIssueScope =
  onDocumentCreated("issues/{id}", stampScope);

// ------------------------------------------------------------
// Client "track my collector" route — anonymised
//
// The client sees their collector's tour WITHOUT other clients' identity:
// other stops come back as unnamed points rounded to ~100 m.
// ------------------------------------------------------------
const roundCoord = (v) => Math.round(Number(v) * 1000) / 1000;

/** POST → { collecteurId, stops: [{lat, lng, isDone, isMine, name?, address?}], stopsBeforeMe } */
exports.collectorRoute = onRequest({cors: true}, async (req, res) => {
  try {
    if (req.method !== "POST") throw new HttpError(405, "POST only.");
    const caller = await authenticate(req);
    if (caller.role !== "client") throw new HttpError(403, "Clients only.");

    const me = (await (await resolveUserRef(caller.phone)).get()).data() || {};
    const collecteurId = me.collecteurId || "";
    if (!collecteurId) {
      return res.status(200).json({collecteurId: "", stops: [],
        stopsBeforeMe: 0});
    }
    const today = todayIso();

    // Zones from today's active assignments + directly assigned clients.
    const assignments = await db.collection("assignments")
        .where("collecteurId", "==", collecteurId)
        .where("date", "==", today)
        .where("status", "==", "Active").get();
    const zones = [...new Set(assignments.docs
        .map((d) => d.data().zoneName).filter(Boolean))].slice(0, 30);

    const byId = new Map();
    const direct = await db.collection("clients")
        .where("collecteurId", "==", collecteurId)
        .where("status", "==", "Active").get();
    direct.docs.forEach((d) => byId.set(d.id, d.data()));
    if (zones.length) {
      const zoneClients = await db.collection("clients")
          .where("status", "==", "Active")
          .where("zone", "in", zones).get();
      zoneClients.docs
          .filter((d) => !me.agenceId || d.data().agenceId === me.agenceId)
          .forEach((d) => byId.set(d.id, d.data()));
    }

    const stops = [];
    for (const c of byId.values()) {
      const lat = Number(c.latitude);
      const lng = Number(c.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
      const isMineCandidate = canonicalPhone(c.phone) === caller.phone;
      // Like the collector's tour: only paying clients are visited.
      if (!isMineCandidate) {
        const u = (await (await resolveUserRef(canonicalPhone(c.phone)))
            .get()).data() || {};
        if (u.isSubscribed !== true) continue;
      }
      const verified = await db.collection("pickups")
          .where("client_id", "==", c.phone || "")
          .where("status", "==", "verified").get();
      const isDone = verified.docs.some((p) => p.data().date === today);
      const isMine = canonicalPhone(c.phone) === caller.phone;
      stops.push(isMine ?
        {lat, lng, isDone, isMine: true, name: c.name || "",
          address: [c.adresse, c.quartier].filter(Boolean).join(", ")} :
        {lat: roundCoord(lat), lng: roundCoord(lng), isDone, isMine: false});
    }
    // Pending first, then done.
    stops.sort((a, b) => Number(a.isDone) - Number(b.isDone));
    const mine = stops.find((s) => s.isMine);
    const stopsBeforeMe = mine && !mine.isDone ?
      stops.filter((s) => !s.isDone && !s.isMine).length :
      0;
    return res.status(200).json({collecteurId, stops, stopsBeforeMe});
  } catch (error) {
    return sendError(res, error);
  }
});

// ------------------------------------------------------------
// Automatic approval of applications + collector assignment
//
// When a client submits an application, the system approves it and picks
// a collector of the chosen agency, in this order:
//   1. a collector serving the applicant's zone (collector zone or an
//      active zone assignment);
//   2. otherwise, the collector nearest to the applicant's GPS point;
//   then, among equals, the nearest and the least busy (fewest active
//   clients). Collectors at the agency's capacity limit are skipped.
// If no collector fits, the application stays pending for the agency
// manager, with the reason. Per-agency settings in
// `agency_settings/{agenceId}`: autoApproval (default ON),
// maxClientsPerCollector (empty = no limit). The manager can still
// approve by hand and change any client's collector.
// ------------------------------------------------------------
function normalizeZone(value) {
  return String(value || "")
      .normalize("NFD").replace(/[̀-ͯ]/g, "")
      .toLowerCase().replace(/\s+/g, " ").trim();
}

/** "Yaoundé: Bastos" → ["yaounde: bastos", "bastos"] */
function zoneKeys(value) {
  const full = normalizeZone(value);
  if (!full) return [];
  const last = full.includes(":") ? full.split(":").pop().trim() : full;
  return [...new Set([full, last])].filter(Boolean);
}

function zonesMatch(applicantZone, collectorZone) {
  const a = zoneKeys(applicantZone);
  const c = normalizeZone(collectorZone);
  if (!a.length || !c) return false;
  return a.some((k) => k === c || k.includes(c) || c.includes(k));
}

/**
 * True when (lat, lng) lies inside a collector's `zoneArea` (drawn on the
 * map by the manager): polygon (ray casting) or circle (radius in metres).
 * Same logic as ZoneArea.contains in lib/features/backoffice/models.dart.
 */
function zoneAreaContains(area, lat, lng) {
  if (!area || typeof area !== "object") return false;
  const points = (Array.isArray(area.points) ? area.points : [])
      .filter((p) => p && Number.isFinite(p.lat) && Number.isFinite(p.lng));
  if (area.kind === "polygon" && points.length >= 3) {
    let inside = false;
    for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
      const yi = points[i].lat; const xi = points[i].lng;
      const yj = points[j].lat; const xj = points[j].lng;
      if ((yi > lat) !== (yj > lat) &&
          lng < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
    }
    return inside;
  }
  const radius = Number(area.radiusMeters);
  if (!Number.isFinite(radius) || radius <= 0) return false;
  return distanceKm(lat, lng, Number(area.centerLat),
      Number(area.centerLng)) * 1000 <= radius;
}

function distanceKm(lat1, lng1, lat2, lng2) {
  const rad = (d) => d * Math.PI / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 6371 * 2 * Math.asin(Math.sqrt(a));
}

const isActiveStatus = (s) => ["active", "actif"]
    .includes(String(s || "").toLowerCase());

/**
 * Picks the collector for [reg] in its agency.
 * → { collector, reason } (collector null when the manager must decide).
 */
async function pickCollector(reg, settings, exclude = new Set()) {
  const agenceId = reg.agenceId;
  const [collecteursSnap, clientsSnap, assignmentsSnap] = await Promise.all([
    db.collection("collecteurs").where("agenceId", "==", agenceId).get(),
    db.collection("clients").where("agenceId", "==", agenceId).get(),
    db.collection("assignments").where("agenceId", "==", agenceId).get(),
  ]);

  const load = new Map();
  for (const c of clientsSnap.docs) {
    const data = c.data();
    if (data.collecteurId && isActiveStatus(data.status)) {
      load.set(data.collecteurId, (load.get(data.collecteurId) || 0) + 1);
    }
  }
  const max = Number(settings.maxClientsPerCollector);
  const hasLimit = Number.isFinite(max) && max > 0;

  const active = collecteursSnap.docs
      .map((d) => ({id: d.id, ...d.data()}))
      .filter((c) => isActiveStatus(c.status));
  if (!active.length) {
    return {collector: null, reason: "No active collector in this agency."};
  }
  const available = active
      .filter((c) => !exclude.has(c.id))
      .filter((c) => !hasLimit || (load.get(c.id) || 0) < max);
  if (!available.length) {
    return {collector: null,
      reason: `All collectors have reached the limit of ${max} clients.`};
  }

  // Zones each collector serves: own zone + active zone assignments.
  const today = todayIso();
  const assignedZones = new Map();
  for (const a of assignmentsSnap.docs) {
    const data = a.data();
    if (data.status !== "Active" || (data.date && data.date < today)) continue;
    const list = assignedZones.get(data.collecteurId) || [];
    list.push(data.zoneName || "");
    assignedZones.set(data.collecteurId, list);
  }
  const servesZone = (c) => [c.zone, ...(assignedZones.get(c.id) || [])]
      .some((z) => zonesMatch(reg.zone, z));

  const lat = Number(reg.latitude);
  const lng = Number(reg.longitude);
  const regHasGps = reg.latitude != null && reg.longitude != null &&
    Number.isFinite(lat) && Number.isFinite(lng);
  const distanceTo = (c) => {
    const cLat = Number(c.latitude);
    const cLng = Number(c.longitude);
    return regHasGps && c.latitude != null && c.longitude != null &&
      Number.isFinite(cLat) && Number.isFinite(cLng) ?
      distanceKm(lat, lng, cLat, cLng) :
      Infinity;
  };

  // 1. The applicant's GPS point lies inside the zone circled on the map
  //    for a collector; 2. zone name; 3. nearest collector.
  const areaMatches = regHasGps ?
    available.filter((c) => zoneAreaContains(c.zoneArea, lat, lng)) :
    [];
  const zoneMatches = available.filter(servesZone);
  const pool = areaMatches.length ? areaMatches : zoneMatches.length ?
    zoneMatches :
    available.filter((c) => distanceTo(c) !== Infinity);
  if (!pool.length) {
    return {collector: null, reason: regHasGps ?
      "No collector matches the zone and no collector position is known." :
      "No collector matches the zone and the applicant gave no GPS point."};
  }
  pool.sort((a, b) => (distanceTo(a) - distanceTo(b)) ||
      ((load.get(a.id) || 0) - (load.get(b.id) || 0)));
  const chosen = pool[0];
  return {
    collector: chosen,
    reason: areaMatches.length ? "zone_area" :
      zoneMatches.length ? "zone" : "nearest",
    load: load.get(chosen.id) || 0,
  };
}

async function autoApproveRegistration(ref, reg) {
  if (reg.status !== "pending") return {status: "skipped"};
  const markManual = (reason) => ref.update({
    autoApproval: {status: "manual", reason, at: FieldValue.serverTimestamp()},
  }).then(() => ({status: "manual", reason}));

  if (!reg.agenceId) {
    return markManual("Agency typed by name: choose it manually.");
  }
  const settings = (await db.collection("agency_settings")
      .doc(reg.agenceId).get()).data() || {};
  if (settings.autoApproval === false) return {status: "disabled"};

  const phone = canonicalPhone(reg.phone);
  const userRef = await resolveUserRef(phone);
  const max = Number(settings.maxClientsPerCollector);
  const hasLimit = Number.isFinite(max) && max > 0;

  // Simultaneous applications: the capacity is re-checked INSIDE the
  // transaction (the query on the collector's clients conflicts with a
  // concurrent approval), and another collector is picked if the chosen
  // one just became full.
  const fullNow = new Set();
  for (let attempt = 0; attempt < 5; attempt++) {
    const picked = await pickCollector(reg, settings, fullNow);
    if (!picked.collector) return markManual(picked.reason);
    const outcome = await approveWith(ref, reg, userRef, phone,
        picked.collector, picked.reason, hasLimit ? max : 0);
    if (outcome !== "full") {
      return outcome === "approved" ?
        {status: "approved", collecteurId: picked.collector.id,
          reason: picked.reason} :
        {status: "skipped"};
    }
    fullNow.add(picked.collector.id);
  }
  return markManual("Collectors filled up while assigning: choose manually.");
}

/** → "approved" | "full" | "skipped" (already decided). */
async function approveWith(ref, reg, userRef, phone, collector, reason,
    max) {
  const clientId = `b${Date.now()}${Math.floor(Math.random() * 1000)}`;
  return db.runTransaction(async (t) => {
    const [fresh, user] = await Promise.all([t.get(ref), t.get(userRef)]);
    // The manager may have decided in the meantime.
    if (fresh.data()?.status !== "pending") return "skipped";
    if (max > 0) {
      const current = await t.get(db.collection("clients")
          .where("agenceId", "==", reg.agenceId)
          .where("collecteurId", "==", collector.id));
      const activeCount = current.docs
          .filter((d) => isActiveStatus(d.data().status)).length;
      if (activeCount >= max) return "full";
    }
    const uid = user.data()?.uid || "";

    t.set(db.collection("clients").doc(clientId), {
      id: clientId,
      name: reg.fullName || "",
      phone: reg.phone || phone,
      zone: reg.zone || "",
      // Approval = access only: plan + subscription date are set when
      // the client pays (`settle`).
      plan: "None",
      status: "Active",
      agenceId: reg.agenceId,
      societeId: reg.societeId || "",
      collecteurId: collector.id,
      adresse: reg.zone || "",
      quartier: reg.zone || "",
      latitude: reg.latitude ?? null,
      longitude: reg.longitude ?? null,
      photoUrl: reg.photoUrl || "",
      housingType: "",
      subscribedAt: "",
    });
    t.set(userRef, {
      phoneNumber: phone,
      fullName: reg.fullName || "",
      role: "client",
      uid,
      registrationStatus: "approved",
      subscription_plan: "",
      isSubscribed: false,
      agenceId: reg.agenceId,
      agenceName: reg.agenceName || "",
      societeId: reg.societeId || "",
      collecteurId: collector.id,
      ...(reg.latitude != null ? {latitude: reg.latitude} : {}),
      ...(reg.longitude != null ? {longitude: reg.longitude} : {}),
      consoleCreated: true,
    }, {merge: true});
    if (uid) {
      t.set(db.collection("auth_profiles").doc(uid), {
        uid,
        phone,
        role: "client",
        status: "approved",
        societeId: reg.societeId || "",
        agenceId: reg.agenceId,
      });
    }
    t.update(ref, {
      status: "approved",
      collecteurId: collector.id,
      autoApproval: {
        status: "approved",
        reason,
        collecteurName: collector.name || "",
        at: FieldValue.serverTimestamp(),
      },
    });
    // Same deterministic id as a manual decision (one decision, one row).
    t.set(db.collection("notifications").doc(`notif${ref.id}`), {
      id: `notif${ref.id}`,
      phone,
      type: "approved",
      title: "Application approved",
      message: "Your application was approved. Choose and pay your plan " +
        "in the app to start your pickups." +
        (collector.name ? ` Your collector is ${collector.name}.` : ""),
      read: false,
      createdAt: todayIso(),
    });
    return "approved";
  });
}

exports.autoApproveRegistration = onDocumentCreated(
    "registrations/{id}",
    async (event) => {
      const reg = event.data?.data();
      if (!reg) return;
      try {
        const result = await autoApproveRegistration(event.data.ref, reg);
        console.log("autoApproveRegistration", event.params.id, result);
      } catch (error) {
        console.error("autoApproveRegistration failed", event.params.id,
            error);
      }
    },
);

// ------------------------------------------------------------
// One-off repair of subscriptions written by the old app code
//
// Super admin only. For every client account:
//   - plan names unified (Essential → Monthly, Standard → Weekly,
//     Premium → Daily; the paid plan wins when records disagree);
//   - a subscription without contract (granted at approval, never paid)
//     gets a 30-day grace contract, after which the normal expiry and
//     renewal reminders apply;
//   - missing / invalid collection days are set with the same rules as a
//     payment (zone calendar, else defaults), so the client is on the tour;
//   - subscription end date and agency name filled in.
// POST { apply: false } → report only; { apply: true } → write.
// ------------------------------------------------------------
const LEGACY_PLANS = {essential: "monthly", standard: "weekly",
  premium: "daily", basic: "monthly"};

function planKeyOf(...names) {
  for (const raw of names) {
    const key = String(raw || "").trim().toLowerCase();
    if (PLANS[key]) return key;
    if (LEGACY_PLANS[key]) return LEGACY_PLANS[key];
  }
  return "";
}

async function repairClient(userDoc, apply) {
  const user = userDoc.data();
  const phone = canonicalPhone(user.phoneNumber || userDoc.id);
  const actions = [];
  const userPatch = {};
  const now = new Date();

  const sub = (await db.collection("subscriptions").doc(phone).get()).data();
  let contract = null;
  if (user.active_contract_id) {
    const c = await db.collection("contracts")
        .doc(user.active_contract_id).get();
    if (c.exists && c.data().status === "Active") contract = c;
  }
  const planKey = planKeyOf(contract?.data().frequency_id, sub?.planName,
      user.subscription_plan);
  const planTitle = planKey ? PLANS[planKey].title : "";

  if (planTitle && user.subscription_plan !== planTitle) {
    userPatch.subscription_plan = planTitle;
    actions.push(`plan ${user.subscription_plan || "-"} → ${planTitle}`);
  }

  if (!user.agenceName && user.agenceId) {
    const ag = (await db.collection("agences").doc(user.agenceId).get())
        .data();
    if (ag?.ville) {
      userPatch.agenceName = ag.ville;
      actions.push("agency name");
    }
  }

  const clientRef = await clientRefByPhone(phone);
  const clientRecord = clientRef ? (await clientRef.get()).data() : null;
  let batch = null;

  if (user.isSubscribed === true) {
    const effectivePlan = planKey || "monthly";
    const title = PLANS[effectivePlan].title;
    const zone = await zoneCalendarFor(clientRecord);
    const schedule = resolveSchedule({planKey: effectivePlan,
      current: user, zone});
    const daysChanged = JSON.stringify(schedule.collectionDays) !==
      JSON.stringify(user.collection_days || []);
    batch = db.batch();

    if (!contract) {
      // Granted without payment by the old approval: 30-day grace.
      const end = new Date(now.getTime() + BILLING_CYCLE_DAYS * 864e5);
      const contractId = `CTR-GRACE-${now.getTime()}-${phone.slice(-4)}`;
      batch.set(db.collection("contracts").doc(contractId), {
        contract_id: contractId,
        client_id: phone,
        frequency_id: title,
        frequency_tier: title,
        collection_days: schedule.collectionDays,
        pickup_time: schedule.pickupTime,
        zone_name: schedule.zoneName,
        status: "Active",
        start_date: Timestamp.fromDate(now),
        expiry_date: Timestamp.fromDate(end),
        amount_paid: 0,
        payment_ref: "GRACE",
        created_at: FieldValue.serverTimestamp(),
      });
      Object.assign(userPatch, {
        active_contract_id: contractId,
        subscription_plan: title,
        subscription_end: Timestamp.fromDate(end),
      });
      batch.set(db.collection("subscriptions").doc(phone), {
        planName: title,
        price: PLANS[effectivePlan].price,
        startDate: Timestamp.fromDate(now),
        nextPaymentDate: Timestamp.fromDate(end),
        expiryDate: Timestamp.fromDate(end),
        status: "active",
        collection_days: schedule.collectionDays,
        pickup_time: schedule.pickupTime,
        zone_name: schedule.zoneName,
      }, {merge: true});
      actions.push(`30-day grace (${title}) until ${end.toISOString()
          .substring(0, 10)}`);
    } else {
      if (!user.subscription_end && contract.data().expiry_date) {
        userPatch.subscription_end = contract.data().expiry_date;
        actions.push("subscription end date");
      }
      if (daysChanged) {
        batch.update(contract.ref, {
          collection_days: schedule.collectionDays,
          pickup_time: schedule.pickupTime,
          zone_name: schedule.zoneName,
        });
      }
    }
    if (daysChanged) {
      Object.assign(userPatch, {
        collection_days: schedule.collectionDays,
        pickup_time: schedule.pickupTime,
        zone_name: schedule.zoneName,
      });
      if (contract && sub) {
        batch.set(db.collection("subscriptions").doc(phone), {
          planName: title,
          collection_days: schedule.collectionDays,
          pickup_time: schedule.pickupTime,
          zone_name: schedule.zoneName,
        }, {merge: true});
      }
      actions.push(`days ${schedule.collectionDays.join(", ")}`);
    }
    if (clientRef && clientRecord?.plan !== title) {
      batch.update(clientRef, {plan: title});
    }
  } else if (clientRef && planKeyOf(clientRecord?.plan) &&
      !user.isSubscribed && !contract) {
    // Not subscribed: the backoffice must not show a plan.
    if (clientRecord.plan !== "None") {
      batch = db.batch();
      batch.update(clientRef, {plan: "None"});
      actions.push(`backoffice plan ${clientRecord.plan} → None`);
    }
  }

  if (!actions.length) return null;
  if (apply) {
    batch = batch || db.batch();
    if (Object.keys(userPatch).length) {
      batch.set(userDoc.ref, userPatch, {merge: true});
    }
    await batch.commit();
  }
  return {phone, name: user.fullName || "", actions};
}

exports.repairSubscriptions = onRequest(
    {cors: true, timeoutSeconds: 540},
    async (req, res) => {
      try {
        if (req.method !== "POST") throw new HttpError(405, "POST only.");
        const caller = await authenticate(req);
        if (caller.role !== "super_admin") {
          throw new HttpError(403, "Super admin only.");
        }
        const apply = (req.body || {}).apply === true;
        const clients = await db.collection("users")
            .where("role", "==", "client").get();
        const changes = [];
        for (const doc of clients.docs) {
          const change = await repairClient(doc, apply);
          if (change) changes.push(change);
        }
        return res.status(200).json({
          applied: apply,
          scanned: clients.size,
          changed: changes.length,
          changes: changes.slice(0, 500),
        });
      } catch (error) {
        return sendError(res, error);
      }
    },
);

// ------------------------------------------------------------
// Public directory for pre-registration
// ------------------------------------------------------------

/**
 * GET → { agences: [ <agences doc>, ... ] }
 *
 * Only agencies covered by an active Agency Manager, so applications never
 * go to an agency without a backoffice. Runs with the Admin SDK so that
 * signed-out visitors never read `utilisateurs` (staff accounts).
 */
exports.publicAgencies = onRequest({cors: true}, async (req, res) => {
  try {
    const [agences, managers, zoneDocs] = await Promise.all([
      db.collection("agences").get(),
      db.collection("utilisateurs").get(),
      db.collection("zones").get(),
    ]);
    const managed = new Set();
    for (const d of managers.docs) {
      const u = d.data();
      const role = String(u.role || "").toLowerCase().replace(/'/g, "");
      const status = String(u.status || "").toLowerCase();
      const isManager = role === "agency manager" ||
        role === "responsable dagence";
      if (isManager && (status === "active" || status === "actif") &&
          u.agenceId) {
        managed.add(u.agenceId);
      }
    }
    const list = agences.docs
        .filter((d) => managed.has(d.id))
        .map((d) => d.data());
    // Neighbourhoods each listed agency serves (active zones only), so the
    // registration screen can find the applicant's agency from their zone.
    const zones = {};
    for (const d of zoneDocs.docs) {
      const z = d.data();
      const status = String(z.status || "active").toLowerCase();
      if (!managed.has(z.agenceId) || !z.name ||
          status === "inactive" || status === "inactif") continue;
      (zones[z.agenceId] = zones[z.agenceId] || []).push(shortString(z.name));
    }
    res.set("Cache-Control", "public, max-age=300");
    return res.status(200).json({
      agences: list,
      zones,
      hasManagerlessAgencies: agences.size > 0 && list.length === 0,
    });
  } catch (error) {
    return sendError(res, error);
  }
});

// ------------------------------------------------------------
// CamPay webhook
//
// Configure in the CamPay dashboard:
//   https://<region>-waste-pro-f67a5.cloudfunctions.net/campayWebhook
// ------------------------------------------------------------
exports.campayWebhook = onRequest(
    {
      secrets: [CAMPAY_WEBHOOK_KEY, CAMPAY_USERNAME, CAMPAY_PASSWORD],
      invoker: "public",
    },
    async (req, res) => {
      try {
        const params = {...(req.query || {}), ...(req.body || {})};
        const signature = params.signature;
        if (!signature) return res.status(400).send("Missing signature");

        let decoded;
        try {
          decoded = jwt.verify(signature, CAMPAY_WEBHOOK_KEY.value(), {
            algorithms: ["HS256"],
          });
        } catch (err) {
          console.warn("Invalid CamPay signature", err.message);
          return res.status(401).send("Invalid signature");
        }
        if (String((decoded && decoded.source) || "").toLowerCase() !==
            "campay") {
          return res.status(401).send("Invalid webhook source");
        }

        // `external_reference` is our txRef = the transactions doc id.
        const txRef = shortString(params.external_reference, 120);
        const exists = txRef &&
          (await db.collection("transactions").doc(txRef).get()).exists;

        await db.collection("webhook_events").add({
          provider: "campay",
          campayStatus: String(params.status || "").toUpperCase(),
          externalReference: txRef || null,
          reference: shortString(params.reference, 120) || null,
          receivedAt: FieldValue.serverTimestamp(),
          matched: Boolean(exists),
        });
        if (!exists) return res.status(202).send("Accepted (unmatched)");

        // The payload only triggers a check: the status is re-read from
        // the CamPay API before anything is unlocked.
        await settle(txRef);
        return res.status(200).send("OK");
      } catch (error) {
        console.error("campayWebhook error", error);
        return res.status(500).send("Internal error");
      }
    },
);