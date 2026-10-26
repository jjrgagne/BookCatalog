import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

const HID = 'house1';
const CODE = 'K7Q2XM';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-bookcatalog',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
});

const db = (uid) => env.authenticatedContext(uid).firestore();

/** Seeds a household owned by alice, with bob as a member. */
async function seedHousehold() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const fs = ctx.firestore();
    await setDoc(doc(fs, 'households', HID), { name: 'Our books', inviteCode: CODE, ownerUid: 'alice' });
    await setDoc(doc(fs, 'households', HID, 'members', 'alice'), { role: 'owner', inviteCode: CODE, displayName: 'Alice' });
    await setDoc(doc(fs, 'households', HID, 'members', 'bob'), { role: 'member', inviteCode: CODE, displayName: 'Bob' });
    await setDoc(doc(fs, 'invites', CODE), { householdId: HID });
    await setDoc(doc(fs, 'users', 'alice'), { householdId: HID });
    await setDoc(doc(fs, 'users', 'bob'), { householdId: HID });
  });
}

const book = { title: 'Dune', isbn13: '9780441013593', tagIds: [], notes: '' };

describe('creating a household', () => {
  test('owner can create household, membership, invite and user doc in one batch', async () => {
    const fs = db('alice');
    const batch = writeBatch(fs);
    batch.set(doc(fs, 'households', HID), { name: 'Our books', inviteCode: CODE, ownerUid: 'alice' });
    batch.set(doc(fs, 'households', HID, 'members', 'alice'), { role: 'owner', inviteCode: CODE, displayName: 'Alice' });
    batch.set(doc(fs, 'invites', CODE), { householdId: HID });
    batch.set(doc(fs, 'users', 'alice'), { householdId: HID });
    await assertSucceeds(batch.commit());
  });

  test('cannot create a household owned by someone else', async () => {
    await assertFails(setDoc(doc(db('mallory'), 'households', 'h2'), { name: 'x', inviteCode: 'AAAAAA', ownerUid: 'alice' }));
  });

  test('signed-out users can do nothing', async () => {
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'invites', CODE)));
  });
});

describe('joining', () => {
  beforeEach(seedHousehold);

  test('anyone signed in can look up a single invite code', async () => {
    await assertSucceeds(getDoc(doc(db('carol'), 'invites', CODE)));
  });

  test('invites cannot be listed', async () => {
    await assertFails(getDocs(collection(db('carol'), 'invites')));
  });

  test('joining with the current code succeeds', async () => {
    const fs = db('carol');
    const batch = writeBatch(fs);
    batch.set(doc(fs, 'households', HID, 'members', 'carol'), { role: 'member', inviteCode: CODE, displayName: 'Carol' });
    batch.set(doc(fs, 'users', 'carol'), { householdId: HID });
    await assertSucceeds(batch.commit());
  });

  test('joining with a wrong code fails', async () => {
    await assertFails(setDoc(doc(db('carol'), 'households', HID, 'members', 'carol'), { role: 'member', inviteCode: 'WRONG1' }));
  });

  test('cannot join as owner', async () => {
    await assertFails(setDoc(doc(db('carol'), 'households', HID, 'members', 'carol'), { role: 'owner', inviteCode: CODE }));
  });

  test('cannot point your user doc at a household you are not in', async () => {
    await assertFails(setDoc(doc(db('carol'), 'users', 'carol'), { householdId: HID }));
  });
});

describe('catalog access', () => {
  beforeEach(seedHousehold);

  test('members can read and write books', async () => {
    const fs = db('bob');
    await assertSucceeds(setDoc(doc(fs, 'households', HID, 'books', 'b1'), book));
    await assertSucceeds(getDocs(collection(fs, 'households', HID, 'books')));
    await assertSucceeds(deleteDoc(doc(fs, 'households', HID, 'books', 'b1')));
  });

  test('outsiders cannot read or write books', async () => {
    const fs = db('mallory');
    await assertFails(getDocs(collection(fs, 'households', HID, 'books')));
    await assertFails(setDoc(doc(fs, 'households', HID, 'books', 'b1'), book));
    await assertFails(getDoc(doc(fs, 'households', HID)));
  });

  test('books need a title', async () => {
    await assertFails(setDoc(doc(db('bob'), 'households', HID, 'books', 'b2'), { ...book, title: '' }));
  });

  test('locations must be a room or a person', async () => {
    const fs = db('bob');
    await assertSucceeds(setDoc(doc(fs, 'households', HID, 'locations', 'l1'), { name: 'Office', kind: 'room', sortOrder: 0 }));
    await assertSucceeds(setDoc(doc(fs, 'households', HID, 'locations', 'l2'), { name: 'Sam', kind: 'person', sortOrder: 0 }));
    await assertFails(setDoc(doc(fs, 'households', HID, 'locations', 'l3'), { name: 'Moon', kind: 'planet' }));
  });

  test('members can manage tags', async () => {
    await assertSucceeds(setDoc(doc(db('bob'), 'households', HID, 'tags', 't1'), { name: 'Fiction', color: 0 }));
  });
});

describe('membership management', () => {
  beforeEach(seedHousehold);

  test('members cannot promote themselves', async () => {
    await assertFails(updateDoc(doc(db('bob'), 'households', HID, 'members', 'bob'), { role: 'owner' }));
  });

  test('members cannot rename the household or take ownership', async () => {
    await assertFails(updateDoc(doc(db('bob'), 'households', HID), { name: 'Bob house' }));
    await assertFails(updateDoc(doc(db('alice'), 'households', HID), { ownerUid: 'bob' }));
  });

  test('owner can rename and rotate the invite code', async () => {
    const fs = db('alice');
    const batch = writeBatch(fs);
    batch.update(doc(fs, 'households', HID), { name: 'Renamed', inviteCode: 'NEWCDE' });
    batch.delete(doc(fs, 'invites', CODE));
    batch.set(doc(fs, 'invites', 'NEWCDE'), { householdId: HID });
    await assertSucceeds(batch.commit());
  });

  test('members cannot create invites', async () => {
    await assertFails(setDoc(doc(db('bob'), 'invites', 'BOBCDE'), { householdId: HID }));
  });

  test('owner can remove a member; member cannot remove owner', async () => {
    await assertFails(deleteDoc(doc(db('bob'), 'households', HID, 'members', 'alice')));
    await assertSucceeds(deleteDoc(doc(db('alice'), 'households', HID, 'members', 'bob')));
  });

  test('a member can leave; the owner cannot', async () => {
    await assertSucceeds(deleteDoc(doc(db('bob'), 'households', HID, 'members', 'bob')));
    await assertFails(deleteDoc(doc(db('alice'), 'households', HID, 'members', 'alice')));
  });

  test('a removed member loses access', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      deleteDoc(doc(ctx.firestore(), 'households', HID, 'members', 'bob')),
    );
    await assertFails(getDocs(collection(db('bob'), 'households', HID, 'books')));
  });
});
