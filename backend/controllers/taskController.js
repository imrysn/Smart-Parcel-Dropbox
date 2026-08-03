const Task = require('../models/Task');
const Tracking = require('../models/Tracking');
const Dropbox = require('../models/Dropbox');

/**
 * GET /api/tasks
 * Fetch all craft business tasks for logged-in user
 */
exports.getTasks = async (req, res) => {
  try {
    const userId = req.userId || req.user?.userId;
    const tasks = await Task.find({ userId }).sort({ createdAt: -1 });

    const grouped = {
      INQUIRY: tasks.filter(t => t.stage === 'INQUIRY'),
      CRAFTING: tasks.filter(t => t.stage === 'CRAFTING'),
      READY_FOR_BOX: tasks.filter(t => t.stage === 'READY_FOR_BOX'),
      SHIPPED: tasks.filter(t => t.stage === 'SHIPPED'),
    };

    res.json({
      success: true,
      data: grouped,
      all: tasks
    });
  } catch (err) {
    console.error('❌ getTasks error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};

/**
 * POST /api/tasks
 * Create a new craft task or customer lead
 */
exports.createTask = async (req, res) => {
  try {
    const userId = req.userId || req.user?.userId;
    const { title, stage, platform, customerName, customerPhone, trackingId, courierName, dueDate, notes } = req.body;

    if (!title) {
      return res.status(400).json({ success: false, message: 'Task title is required' });
    }

    const newTask = await Task.create({
      userId,
      title,
      stage: stage || 'INQUIRY',
      platform: platform || 'CUSTOM',
      customerName: customerName || 'Valued Customer',
      customerPhone: customerPhone || '',
      trackingId: trackingId || '',
      courierName: courierName || 'J&T Express',
      dueDate: dueDate ? new Date(dueDate) : null,
      notes: notes || ''
    });

    // Broadcast socket event
    const io = req.app.get('io');
    if (io) {
      io.to(userId).emit('taskUpdate', newTask);
    }

    res.status(201).json({
      success: true,
      message: 'Task created successfully',
      data: newTask
    });
  } catch (err) {
    console.error('❌ createTask error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};

/**
 * PATCH /api/tasks/:id/stage
 * Move task to a new stage. If moved to READY_FOR_BOX, triggers dropbox staging & door signal!
 */
exports.updateTaskStage = async (req, res) => {
  try {
    const userId = req.userId || req.user?.userId;
    const { id } = req.params;
    const { stage, openDoor } = req.body;

    const task = await Task.findOne({ _id: id, userId });
    if (!task) {
      return res.status(404).json({ success: false, message: 'Task not found' });
    }

    task.stage = stage;

    // If moved to READY_FOR_BOX, auto-create Tracking item & generate Courier OTP
    if (stage === 'READY_FOR_BOX') {
      const trackingId = task.trackingId || `CRAFT-${Math.floor(100000 + Math.random() * 900000)}`;
      task.trackingId = trackingId;

      const courierOtp = Math.floor(100000 + Math.random() * 900000).toString();
      task.courierOtp = courierOtp;

      await Tracking.deleteOne({ trackingId });
      await Tracking.create({
        trackingId,
        userId,
        shopName: task.title,
        direction: 'OUTBOUND_CUSTOMER',
        customerName: task.customerName,
        customerPhone: task.customerPhone,
        courierName: task.courierName || 'J&T Express',
        courierOtp,
        mode: 'pick_up',
        status: 'awaiting_pickup'
      });

      // Increment dropbox pickup count
      let dbQuery = { userIds: userId };
      let dropbox = await Dropbox.findOne(dbQuery);
      if (!dropbox) dbQuery = { userId };
      await Dropbox.updateOne(dbQuery, { $inc: { pickupCount: 1 } });

      // Signal ESP32 hardware door unlock if requested
      const io = req.app.get('io');
      if (openDoor && io) {
        console.log(`🚪 Task Stage READY_FOR_BOX → Unlocking Dropbox door for ${userId}`);
        io.to('esp32_device').emit('controlDoor', { type: 'pickup', action: 'open' });
      }
    }

    await task.save();

    const io = req.app.get('io');
    if (io) {
      io.to(userId).emit('taskUpdate', task);
    }

    res.json({
      success: true,
      message: `Task moved to ${stage}`,
      data: task
    });
  } catch (err) {
    console.error('❌ updateTaskStage error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};

/**
 * DELETE /api/tasks/:id
 * Archive / Delete a task
 */
exports.deleteTask = async (req, res) => {
  try {
    const userId = req.userId || req.user?.userId;
    const { id } = req.params;

    const task = await Task.findOneAndDelete({ _id: id, userId });
    if (!task) {
      return res.status(404).json({ success: false, message: 'Task not found' });
    }

    res.json({ success: true, message: 'Task deleted' });
  } catch (err) {
    console.error('❌ deleteTask error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};
