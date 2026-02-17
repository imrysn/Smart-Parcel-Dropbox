const mongoose = require('mongoose');

const doorStateSchema = new mongoose.Schema({
  userId: {
    type: String,
    required: true,
    default: 'system'
  },
  parcelDoorOpen: {
    type: Boolean,
    default: false
  },
  userDoorOpen: {
    type: Boolean,
    default: false
  },
  status: {
    type: String,
    enum: ['idle', 'processing'],
    default: 'idle'
  },
  parcelDetected: {
    type: Boolean,
    default: false
  },
  lastUpdate: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true
});

// Ensure only one document exists (singleton pattern)
doorStateSchema.statics.getInstance = async function() {
  let state = await this.findOne();
  if (!state) {
    state = await this.create({});
  }
  return state;
};

module.exports = mongoose.model('DoorState', doorStateSchema);
