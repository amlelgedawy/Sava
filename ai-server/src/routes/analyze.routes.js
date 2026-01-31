const express = require('express');
const multer = require('multer');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { analyzeFace } = require('../services/face.service');

const router = express.Router();

const TEMP_DIR = path.join(process.cwd(), 'temp_frames');
if (!fs.existsSync(TEMP_DIR)) fs.mkdirSync(TEMP_DIR, { recursive: true });

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, TEMP_DIR),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    const name = `${Date.now()}-${crypto.randomBytes(6).toString('hex')}${ext}`;
    cb(null, name);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
});

router.post('/frame', upload.single('frame'), async (req, res) => {
  const file = req.file;

  if (!file) {
    return res
      .status(400)
      .json({ error: 'Missing frame file (field name must be "frame")' });
  }

  router.post('/frame', upload.single('frame'), async (req, res) => {
    console.log('/analyze/frame hit');

    const file = req.file;
    console.log('📦 file:', file?.originalname, 'saved as:', file?.path);

    if (!file) {
      console.log('Missing file');
      return res
        .status(400)
        .json({ error: 'Missing frame file (field name must be "frame")' });
    }

    const framePath = file.path;

    try {
      const { events, result } = await analyzeFace(framePath);
      console.log('python result:', result);
      console.log('mapped events:', events);
      return res.json({ events });
    } catch (err) {
      console.log('🔥 ERROR:', err?.message || err);
      return res
        .status(500)
        .json({ error: 'AI analysis failed', details: err.message });
    } finally {
      console.log('🧹 cleanup temp:', framePath);
      try {
        require('fs').unlinkSync(framePath);
      } catch (_) {}
    }
  });

  const framePath = file.path;

  try {
    const { events } = await analyzeFace(framePath);

    return res.json({ events });
  } catch (err) {
    return res.status(500).json({
      error: 'AI analysis failed',
      details: err.message,
    });
  } finally {
    try {
      fs.unlinkSync(framePath);
    } catch (_) {}
  }
});

module.exports = router;
