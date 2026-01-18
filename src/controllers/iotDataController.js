const SensorLog = require("../models/SensorLog");
const asyncHandler = require("../middleware/async");

// const asyncHandler = fn =>(req, res, next)=>{
//     Promise.resolve(fn(req, res, next)).catch(next);
// };

const checkCriticalAlerts = (data) => {
  if (
    data.dataType == "fall_detection" &&
    data.value &&
    data.value.status === "Critical"
  ) {
    return true;
  }
  return false;
};

// POST /iot/data
exports.ingestSensorData = asyncHandler(async (req, res) => {
  const data = req.body;
  if (!data.patient || !data.dataType || data.value === undefined) {
    return res
      .status(400)
      .json({ success: false, message: "Missing required data firleds." });
  }

  const isAlert = checkCriticalAlerts(data);
  const newLog = await SensorLog.create({
    patient: data.patient,
    deviceId: data.deviceId,
    dataType: data.dataType,
    value: data.value,
    isAlert: isAlert,
    timestamp: data.timestamp || Date.now(),
  });

  res.status(201).json({
    success: true,
    message: "Data inngested successfully",
    alertGenrated: isAlert,
    logId: newLog._id,
  });
});
