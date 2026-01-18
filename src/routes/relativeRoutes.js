const express = require("express");
const RelativeController = require("../controllers/relativeController");
const router = express.Router();

router.route("/").post(RelativeController.createRelative);
router.route("/:patientId").get(RelativeController.getRelativesByPatient);

module.exports = router;
