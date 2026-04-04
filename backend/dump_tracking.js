const mongoose = require('mongoose');
const Tracking = require('./models/Tracking');

async function main() {
  await mongoose.connect('mongodb://localhost:27017/smart-parcel'); // or check .env
  const t = await Tracking.findOne({});
  console.log(JSON.stringify(t, null, 2));
  process.exit(0);
}
main();
