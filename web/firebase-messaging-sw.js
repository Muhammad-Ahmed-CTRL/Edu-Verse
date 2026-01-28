/*
  Firebase Messaging service worker for web.

  Place this file at `web/firebase-messaging-sw.js` so the Flutter dev server
  and production build serve it with the correct MIME type (application/javascript).

  IMPORTANT: Replace the firebase config below with your project's web config
  (you can copy it from the Firebase Console -> Project settings -> Your apps -> SDK snippet),
  or use the auto-init script provided by Firebase Hosting (__/firebase/init.js).

  Example usage (dev):
    copy your Firebase config values into the object below and run `flutter run -d chrome`.

*/

importScripts('https://www.gstatic.com/firebasejs/9.22.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.2/firebase-messaging-compat.js');

// Firebase web config (taken from lib/firebase_options.dart)
const firebaseConfig = {
  apiKey: 'AIzaSyBdgmYim3IN5UmNUo3LPlDHdLEkt_WEXys',
  authDomain: 'my-project-859f5.firebaseapp.com',
  projectId: 'my-project-859f5',
  storageBucket: 'my-project-859f5.appspot.com',
  messagingSenderId: '772886464594',
  appId: '1:772886464594:web:4348ea3497c5b4625c378b',
  measurementId: 'G-FQQH5HNB61',
};

try {
  firebase.initializeApp(firebaseConfig);
} catch (e) {
  // ignore if already initialized
}

const messaging = firebase.messaging();

// Handle background messages and show a notification
messaging.onBackgroundMessage(function(payload) {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);

  const title = (payload.notification && payload.notification.title) || (payload.data && payload.data.title) || 'Notification';
  const options = {
    body: (payload.notification && payload.notification.body) || (payload.data && payload.data.body) || '',
    icon: '/icons/Icon-192.png',
    data: payload.data || {},
  };

  return self.registration.showNotification(title, options);
});

// When notification is clicked, focus or open the app and navigate if a URL provided
self.addEventListener('notificationclick', function(event) {
  const data = (event.notification && event.notification.data) || {};
  event.notification.close();
  const url = data.url || '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(windowClients => {
      for (let i = 0; i < windowClients.length; i++) {
        const client = windowClients[i];
        if (client.url === url && 'focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(url);
      }
    })
  );
});
