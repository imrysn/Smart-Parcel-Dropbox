/**
 * One-time migration: Dropbox single-userId → multi-user userIds array.
 *
 * Converts all existing Dropbox documents that have a `userId: String` but
 * an empty/missing `userIds: []` into the new multi-user format:
 *   { userId: "abc", userIds: [], primaryUserId: null }
 *   →
 *   { userId: "abc", userIds: ["abc"], primaryUserId: "abc" }
 *
 * Safe to run multiple times (idempotent). Documents that already have
 * a populated userIds array are skipped.
 *
 * Usage:
 *   node backend/scripts/migrate_dropbox_userids.js
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const mongoose = require('mongoose');
const Dropbox = require('../models/Dropbox');

async function migrate() {
  const mongoUri = process.env.MONGODB_URI || 'mongodb://localhost:27017/smart_parcel_dropbox';
  console.log('🔗 Connecting to MongoDB...');
  await mongoose.connect(mongoUri);
  console.log('✅ Connected.\n');

  // Find all documents that have a legacy userId but no userIds entries yet
  const legacyDocs = await Dropbox.find({
    userId: { $nin: [null, ''] },
    $or: [
      { userIds: { $exists: false } },
      { userIds: { $size: 0 } },
    ],
  });

  console.log(`📋 Found ${legacyDocs.length} document(s) needing migration.\n`);

  let migrated = 0;
  let skipped = 0;

  for (const doc of legacyDocs) {
    // Skip placeholder userIds set by old unregisterDevice logic
    const legacyId = doc.userId || '';
    if (legacyId.startsWith('unregistered_')) {
      console.log(`  ⏭️  Skipping unregistered placeholder doc: ${doc.deviceId}`);
      skipped++;
      continue;
    }

    await Dropbox.updateOne(
      { _id: doc._id },
      {
        $addToSet: { userIds: legacyId },
        $set: { primaryUserId: legacyId },
      }
    );

    console.log(`  ✅ Migrated: ${doc.deviceId} → userIds: ["${legacyId}"]`);
    migrated++;
  }

  console.log(`\n🎉 Migration complete. Migrated: ${migrated}, Skipped: ${skipped}.`);
  await mongoose.disconnect();
  process.exit(0);
}

migrate().catch((err) => {
  console.error('❌ Migration failed:', err.message);
  process.exit(1);
});
