import {scryptSync, randomBytes} from 'node:crypto';
import {initializeApp} from 'firebase-admin/app';
import {FieldValue, getFirestore} from 'firebase-admin/firestore';

initializeApp();

const firestore = getFirestore();

function hashPasscode(passcode: string): string {
  const salt = randomBytes(16);
  const hash = scryptSync(passcode, salt, 64);
  return `${salt.toString('hex')}:${hash.toString('hex')}`;
}

async function migrateCollection(collectionName: string): Promise<void> {
  const snapshot = await firestore.collection(collectionName).get();
  let migratedCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const passcode = data['passcode'];
    if (typeof passcode != 'string' || passcode.trim().length === 0) {
      continue;
    }

    const prefix = collectionName.startsWith('test_') ? 'test_' : '';
    const credentialsCollection = `${prefix}private_member_credentials`;
    const length = data['passcodeLength'] ?? passcode.length;

    await firestore.collection(credentialsCollection).doc(doc.id).set({
      passcodeHash: hashPasscode(passcode),
      passcodeLength: length,
      migratedFromLegacyFieldAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    await doc.ref.update({
      passcode: FieldValue.delete(),
      passcodeLength: length,
      updatedAt: FieldValue.serverTimestamp(),
    });

    migratedCount += 1;
  }

  console.log(`Migrated ${migratedCount} legacy passcodes from ${collectionName}`);
}

async function main(): Promise<void> {
  await migrateCollection('teamMembers');
  await migrateCollection('test_teamMembers');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
