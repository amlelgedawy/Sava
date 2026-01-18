const express = require("express");
const router = express.Router();
const patientController = require("../controllers/patientController");

//post /patient
router.post("/", patientController.createPatient);

module.exports = router;
