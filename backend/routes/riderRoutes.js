const express = require('express');
const router = express.Router();
const Rider = require('../models/Rider');

// Get all riders
router.get('/', async (req, res) => {
    try {
        const riders = await Rider.find().sort({ createdAt: -1 });
        res.json(riders);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
});

// Add a new rider
router.post('/', async (req, res) => {
    const rider = new Rider({
        riderId: req.body.riderId,
        name: req.body.name
    });

    try {
        const newRider = await rider.save();
        res.status(201).json(newRider);
    } catch (error) {
        // Check for duplicate key
        if (error.code === 11000) {
            return res.status(400).json({ message: 'Rider ID already exists' });
        }
        res.status(400).json({ message: error.message });
    }
});

// Delete a rider
router.delete('/:id', async (req, res) => {
    try {
        const rider = await Rider.findByIdAndDelete(req.params.id);
        if (!rider) return res.status(404).json({ message: 'Rider not found' });
        res.json({ message: 'Rider deleted' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
});

module.exports = router;
