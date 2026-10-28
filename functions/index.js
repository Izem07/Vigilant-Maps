// Deletes reports older than 30 minutes. Deploy with: firebase deploy --only functions
// Note: scheduled functions require the Blaze (pay-as-you-go) plan, though this
// workload stays well within the free usage allowance.
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

initializeApp();

exports.purgeOldReports = onSchedule("every 10 minutes", async () => {
  const db = getFirestore();
  const cutoff = Timestamp.fromMillis(Date.now() - 30 * 60 * 1000);

  let deleted = 0;
  while (true) {
    const snap = await db.collection("reports")
      .where("timestamp", "<", cutoff)
      .limit(400)
      .get();
    if (snap.empty) break;

    const batch = db.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    deleted += snap.size;
  }
  console.log(`Purged ${deleted} expired reports`);
});
