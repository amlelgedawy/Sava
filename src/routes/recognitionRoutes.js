const express = require("express");
const router = express.Router();
const recognitionController = require("../controllers/recognitionController");

// recognition/verify
router.post("/verify", recognitionController.verifyFace);

module.exports = router;
