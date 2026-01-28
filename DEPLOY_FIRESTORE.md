# Deploying Firestore Rules & Indexes

This project includes `firestore.rules` and `firestore.indexes.json` at the repository root.
Use the Firebase CLI to deploy them. Below are steps and a helper script for Windows (PowerShell).

Prerequisites
- Node.js and npm
- `firebase-tools` installed globally: `npm install -g firebase-tools`
- Access to the Firebase project (you must be signed in to the Firebase CLI and have permissions)

Quick deploy (PowerShell)

1. Open PowerShell in the project root (`mad_project`)
2. Run the helper script:

```powershell
.\scripts\deploy_firestore.ps1 your-firebase-project-id
```

If you omit the project id the script will use the active project. The script will call `firebase login` if you are not already authenticated.

Manual deploy

```powershell
# login (opens browser)
firebase login
# set project (optional)
firebase use --add
# deploy rules
firebase deploy --only firestore:rules
# deploy indexes
firebase deploy --only firestore:indexes
```

Emulator testing (recommended before production)

1. Start emulators (auth + firestore):

```bash
firebase emulators:start --only auth,firestore
```

2. Point your app to the emulator (set FIRESTORE_EMULATOR_HOST or configure client SDK)
3. Test invite generation and other flows locally

Notes
- Deploying indexes can take several minutes for Firestore to build them.
- If you need me to create a `super_admins/{uid}` doc for testing, I can generate a sample script — you'll need to run it with your Firebase credentials.