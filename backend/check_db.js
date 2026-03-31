const mongoose = require('mongoose');

async function check() {
  await mongoose.connect('mongodb://127.0.0.1:27017/smart_parcel_dropbox');
  const db = mongoose.connection.db;
  const userId = '69947ba92ea19264d85f9eda';
  
  console.log('--- Checking for userId (String) ---');
  const d1 = await db.collection('dropboxes').find({ userId: userId }).toArray();
  console.log('Matches (String):', JSON.stringify(d1, null, 2));

  console.log('\n--- Checking for userId (ObjectId) ---');
  try {
    const d2 = await db.collection('dropboxes').find({ userId: new mongoose.Types.ObjectId(userId) }).toArray();
    console.log('Matches (ObjectId):', JSON.stringify(d2, null, 2));
  } catch (e) {
    console.log('Invalid ObjectId');
  }

  process.exit(0);
}

check();
