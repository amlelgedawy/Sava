const Patient = require("../models/Patient");
const Reminder = require("../models/Reminder");
const SensorLog = require("../models/SensorLog");
const asyncHandler = require("../middleware/async");

// const asyncHandler = fn =>(req, res, next)=>{
//     Promise.resolve(fn(req, res, next)).catch(next);
// };

//patient montitring
exports.getPatientStatus = asyncHandler(async (req, res) => {
  const { patientId } = req.params;

  const patient = await Patient.findById(patientId).lean();
  if (!patient) {
    return res
      .status(404)
      .json({ success: false, message: "patitent not found" });
  }
  const lastLocation = await SensorLog.findOne({
    patient: patientId,
    dataType: "location",
  })
    .sort({ timestamp: -1 })
    .limit(1)
    .select("value timestamp")
    .lean();

  res.status(200).json({
    success: true,
    data: {
      patient: patient,
      lastLocation: lastLocation || null,
    },
  });
});

exports.getPatientAlerts = asyncHandler(async (req, res) => {
  const { patientId } = req.params;

  const alerts = await SensorLog.find({
    patient: patientId,
    isAlert: true,
  })
    .sort({ timestamp: -1 })
    .select("dataType value timestamp")
    .lean();

  res.status(200).json({ success: true, count: alerts.length, data: alerts });
});

exports.createReminder = asyncHandler(async (req, res) => {
  const reminder = await Reminder.create(req.body);

  res.status(201).json({ success: true, data: reminder });
});

exports.updateReminder = asyncHandler(async (req, res) => {
  const { reminderId } = req.params;

  let reminder = await Reminder.findById(reminderId);
  if (!reminder) {
    return res
      .status(404)
      .json({ success: false, message: "rminder not found" });
  }
  reminder = await Reminder.findByIdAndUpdate(reminderId, req.body, {
    new: true,
    runValidators: true,
  });
  res.status(200).json({ success: true, data: reminder });
});

exports.getReminders = asyncHandler(async (req, res) => {
  const { patientId } = req.params;
  const reminders = await Reminder.find({ patient: patientId })
    .sort({ scheduledTime: 1 })
    .lean();
  res
    .status(200)
    .json({ success: true, count: reminders.length, data: reminders });
});

exports.deleteReminders = asyncHandler(async (req, res) => {
  const { reminderId } = req.params;

  const reminder = await Reminder.findByIdAndDelete(reminderId);

  if (!reminder) {
    return res
      .status(400)
      .json({ success: false, message: "reminder not found" });
  }
  res.status(204).json({ success: true, data: {} });
});

exports.deleteAlerts = asyncHandler(async (req, res) => {
  const { alertId } = req.params;

  const alert = await SensorLog.findByIdAndDelete(alertId);

  if (!alert) {
    return res.status(400).json({ success: false, message: "alert not found" });
  }
  res.status(204).json({ success: true, data: {} });
});
