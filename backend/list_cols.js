const mongoose = require('mongoose');

async function listCols() {
  await mongoose.connect('mongodb://127.0.0.1:27017/smart_parcel_dropbox');
  const collections = await mongoose.connection.db.listCollections().toArray();
  console.log(collections.map(c => c.name));
  process.exit(0);
}

listCols();
