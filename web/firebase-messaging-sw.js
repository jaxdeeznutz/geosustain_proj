// Deployment supplies public Firebase app identifiers in firebase-config.js.
// Never place service-account credentials in this directory.
importScripts('firebase-config.js');
if (self.GEOSUSTAIN_FIREBASE && self.GEOSUSTAIN_FIREBASE.projectId) {
  importScripts('https://www.gstatic.com/firebasejs/12.3.0/firebase-app-compat.js');
  importScripts('https://www.gstatic.com/firebasejs/12.3.0/firebase-messaging-compat.js');
  firebase.initializeApp(self.GEOSUSTAIN_FIREBASE);
  firebase.messaging(); // FCM notification payloads display in the background.
}
