const asyncHandler = require("../middleware/async");
const Patient = require("../models/Patient");

exports.createPatient = asyncHandler(async (req, res, next) => {
  const patient = await Patient.create(req.body);

  res.status(201).json({ success: true, data: patient });
});
