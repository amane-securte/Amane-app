/**
 * AMANE – notifications automatiques (Cloud Functions, nécessite le forfait Blaze).
 *
 * 1. Nouvelle alerte SOS  -> notification à tous les administrateurs.
 * 2. Réponse d'AMANE (patrouille, police, pompiers…) -> notification au client
 *    ou à l'agent qui a envoyé l'alerte.
 */
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({ region: "europe-west1", maxInstances: 5 });

const TYPES_AR = {
  assault: "اعتداء", intrusion: "اقتحام", fire: "حريق", medical: "حالة طبية", other: "أخرى",
  patrol: "طلب دورية", police: "سرقة / اعتداء", request: "طلب خدمة",
  accident: "حادث سير", breakdown: "عطل في السيارة",
};
const ACTIONS_AR = {
  patrol: "دورية أمان في الطريق إليك 🚓",
  roadside: "المساعدة في الطريق إليك 🛻",
  police: "تم إبلاغ الشرطة 👮",
  gendarmerie: "تم إبلاغ الدرك الوطني 🛡️",
  civil: "تم إبلاغ المطافئ 🚒",
  ambulance: "تم طلب الإسعاف 🚑",
};

async function adminTokens() {
  const snap = await admin.firestore().collection("users").where("role", "==", "admin").get();
  return snap.docs.map((d) => d.get("fcmToken")).filter((t) => typeof t === "string" && t);
}

async function send(tokens, title, body, data) {
  if (!tokens.length) return;
  await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data,
    android: { priority: "high", notification: { sound: "siren", channelId: "sos_siren", defaultVibrateTimings: false } },
  });
}

exports.onSosCreated = onDocumentCreated("alerts/{id}", async (event) => {
  const a = event.data && event.data.data();
  if (!a) return;
  const kind = TYPES_AR[a.type] || a.type || "SOS";
  const who = [a.name, a.siteName].filter(Boolean).join(" · ");
  const where = typeof a.Lat === "number" ? `\nhttps://maps.google.com/?q=${a.Lat},${a.Lng}` : "";
  await send(await adminTokens(), `🚨 SOS أمان: ${kind}`, `${who}${where}`, {
    alertId: event.params.id,
  });
});

exports.onSosAnswered = onDocumentUpdated("alerts/{id}", async (event) => {
  const before = event.data.before.data() || {};
  const after = event.data.after.data() || {};
  if (!after.action || after.action === before.action || !after.uid) return;
  const user = await admin.firestore().collection("users").doc(after.uid).get();
  const token = user.get("fcmToken");
  if (!token) return;
  await send([token], "AMANE – أمان", ACTIONS_AR[after.action] || "أمان تتكفّل بطلبك", {
    alertId: event.params.id,
  });
});
