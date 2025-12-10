const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.getServerTime = functions.https.onCall((data, context) => {
  return {time: new Date().toISOString()};
});
