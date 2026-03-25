require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  const uri = process.env.MONGODB_URI;
  if (!uri) {
    console.error('No MONGODB_URI in .env');
    process.exit(1);
  }
  
  await mongoose.connect(uri);
  const db = mongoose.connection.db;
  
  console.log('--- Collections in Atlas parceldropbox ---');
  const collections = await db.listCollections().toArray();
  console.log(collections.map(c => c.name));

  const userId = '69947ba92ea19264d85f9eda';
  console.log(`\n--- Looking for userId: ${userId} ---`);
  
  const matches = await db.collection('dropboxes').find({ userId }).toArray();
  console.log('Matches:', JSON.stringify(matches, null, 2));

  process.exit(0);
}

debug();
