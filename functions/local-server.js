/**
 * Local server — runs the Cloud Functions of index.js on this PC, against
 * the REAL Firebase project, without deploying anything.
 *
 *   cd functions
 *   npm run local
 *
 * Needs (both gitignored, never commit them):
 *   - functions/service-account.json — Firebase console → Project settings →
 *     Service accounts → "Generate new private key";
 *   - functions/.env.server — settings + keys (copy .env.server.example).
 *
 * The app then calls http://localhost:5055 instead of the cloud:
 *   flutter run -d chrome --web-port 8080 \
 *     --dart-define=FUNCTIONS_URL=http://localhost:5055
 *
 * What the cloud would do on its own is done here too:
 *   - new registrations → automatic approval (autoApproveRegistration);
 *   - pickups / issues without an agency → stamped (stampPickupScope);
 *   - contract expiry → at start-up, then every day at 07:00.
 */
const fs = require("node:fs");
const path = require("node:path");

const PORT = Number(process.env.PORT || 5055);
const keyFile = path.join(__dirname, "service-account.json");
const envFile = path.join(__dirname, ".env.server");

function fail(message) {
  console.error(`\n✖ ${message}\n`);
  process.exit(1);
}

// Tests only: against the Firebase emulators, no key is needed.
const useEmulators = !!process.env.FIRESTORE_EMULATOR_HOST;
if (!useEmulators && !fs.existsSync(keyFile)) {
  fail("functions/service-account.json is missing.\n" +
    "  Firebase console → Project settings → Service accounts →\n" +
    "  \"Generate new private key\", save the file as\n" +
    "  functions/service-account.json");
}
const key = useEmulators ?
  {project_id: process.env.GCLOUD_PROJECT || "demo-wastepro"} :
  JSON.parse(fs.readFileSync(keyFile, "utf8"));

// Settings and keys (KEY=value lines) → process.env, read by index.js.
if (fs.existsSync(envFile)) {
  for (const line of fs.readFileSync(envFile, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m && !(m[1] in process.env)) {
      process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
    }
  }
} else {
  console.warn("⚠ functions/.env.server not found — CamPay, chatbot and SMS " +
    "keys are missing (copy .env.server.example).");
}
if (!useEmulators) process.env.GOOGLE_APPLICATION_CREDENTIALS = keyFile;
process.env.GCLOUD_PROJECT = key.project_id;
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: key.project_id});

const express = require("express");
const {getFirestore} = require("firebase-admin/firestore");
const fns = require("./index.js");
const db = getFirestore();

// ------------------------------------------------------------
// HTTP functions: POST/GET http://localhost:5055/<functionName>
// ------------------------------------------------------------
const app = express();
app.use(express.json({
  limit: "2mb",
  verify: (req, _res, buf) => {
    req.rawBody = buf;
  },
}));
app.use(express.urlencoded({extended: true}));
app.use((req, res, next) => {
  res.set("Access-Control-Allow-Origin", req.get("Origin") || "*");
  res.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  if (req.method === "OPTIONS") return res.status(204).end();
  next();
});

const httpNames = Object.keys(fns).filter((name) =>
  fns[name].__endpoint && fns[name].__endpoint.httpsTrigger);
app.all("/:name", (req, res) => {
  const name = req.params.name;
  if (!httpNames.includes(name)) {
    return res.status(404).json({error: `Unknown function ${name}.`});
  }
  return fns[name](req, res);
});
app.get("/", (_req, res) => res.json({ok: true, functions: httpNames}));

// ------------------------------------------------------------
// Firestore triggers (the cloud runs them on document creation)
// ------------------------------------------------------------
function watch(collection, fn, {includeExisting}) {
  let first = true;
  db.collection(collection).onSnapshot((snap) => {
    const changes = snap.docChanges().filter((c) => c.type === "added");
    const run = !first || includeExisting;
    first = false;
    if (!run) return;
    for (const c of changes) {
      fn.run({data: c.doc, params: {id: c.doc.id}})
          .catch((e) => console.error(`${collection}/${c.doc.id}:`, e.message));
    }
  }, (error) => console.error(`watch ${collection}:`, error.message));
}
// Only NEW applications (existing pending ones stay with the manager).
watch("registrations", fns.autoApproveRegistration, {includeExisting: false});
// Stamping is idempotent: also fixes past pickups / issues with no agency.
watch("pickups", fns.stampPickupScope, {includeExisting: true});
watch("issues", fns.stampIssueScope, {includeExisting: true});

// ------------------------------------------------------------
// Daily job: contract expiry (start-up, then every day at 07:00)
// ------------------------------------------------------------
function runExpiry() {
  fns.contractExpiry.run({})
      .then(() => console.log("contractExpiry done"))
      .catch((e) => console.error("contractExpiry:", e.message));
}
function scheduleExpiry() {
  const next = new Date();
  next.setHours(7, 0, 0, 0);
  if (next <= new Date()) next.setDate(next.getDate() + 1);
  setTimeout(() => {
    runExpiry();
    scheduleExpiry();
  }, next - new Date());
}
runExpiry();
scheduleExpiry();

app.listen(PORT, () => {
  console.log(`\n✔ WastePro local server — project ${key.project_id}`);
  console.log(`  http://localhost:${PORT}  (${httpNames.length} functions)`);
  console.log("  Start the app with:");
  console.log("  flutter run -d chrome --web-port 8080 " +
    `--dart-define=FUNCTIONS_URL=http://localhost:${PORT}\n`);
});
