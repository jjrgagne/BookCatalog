# Firestore security rules tests

Runs `../firestore.rules` against the Firestore emulator. CI runs these on every
push. Locally (needs Node.js and Java):

```bash
npm install -g firebase-tools
```

```bash
cd firestore-tests; npm install --no-save @firebase/rules-unit-testing firebase; cd ..
```

```bash
firebase emulators:exec --only firestore --project demo-bookcatalog "npm --prefix firestore-tests test"
```
