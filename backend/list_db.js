const mongoose = require('mongoose');

async function listAll() {
  await mongoose.connect('mongodb://127.0.0.1:27017/smart_parcel_dropbox');
  const db = mongoose.connection.db;
  
  console.log('--- All Dropboxes ---');
  const all = await db.collection('dropboxes').find({}).toArray();
  console.log(JSON.stringify(all, null, 2));

  process.exit(0);
}

listAll();
