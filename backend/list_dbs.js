const mongoose = require('mongoose');

async function listDbs() {
  await mongoose.connect('mongodb://127.0.0.1:27017/admin');
  const admin = mongoose.connection.db.admin();
  const dbs = await admin.listDatabases();
  console.log(JSON.stringify(dbs, null, 2));
  process.exit(0);
}

listDbs();
