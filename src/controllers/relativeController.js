const Relative = require("../models/Relative");
const asyncHandler = require("../middleware/async");
const ErrorResponse = require("../utils/errorResponse");
const fs = require("fs");
const path = require("path");

const UPLOAD_BASE_DIR = path.join(
  __dirname,
  "..",
  "..",
  "uploads",
  "relatives"
);

const saveBase64Image = (base64Data, patientId, relativeName) => {
  if (!fs.existsSync(UPLOAD_BASE_DIR)) {
    fs.mkdirSync(UPLOAD_BASE_DIR, { recursive: true });
  }
  let data = base64Data;
  if (data.includes(",")) {
    data = data.split(",")[1];
  }
  const extMatch = base64Data.match(/^data:image\/(\w+);base64,/);
  const ext = extMatch ? `.${extMatch[1]}` : ".jpg";

  const sanitizedName = relativeName.replace(/\s/g, "_");
  const filename = `${patientId}_${sanitizedName}_${Date.now()}${ext}`;
  const filePath = path.join(UPLOAD_BASE_DIR, filename);
  fs.writeFileSync(filePath, Buffer.from(data, "base64"));

  return path.join("uploads", "relatives", filename);
};

exports.createRelative = asyncHandler(async (req, res, next) => {
  const {
    patient,
    recognitionKey,
    name,
    relation,
    messageForPatient,
    image_data,
  } = req.body;
  if (!image_data) {
    return next(new ErrorResponse("image data field is required", 400));
  }
  if (!patient || !recognitionKey || !name || !relation || !messageForPatient) {
    return next(new ErrorResponse("missing required relative field", 400));
  }
  let localImagePath;
  try {
    localImagePath = saveBase64Image(image_data, patient, recognitionKey);

    const relative = await Relative.create({
      patient,
      recognitionKey,
      name,
      relation,
      messageForPatient,
      imageURL: localImagePath,
    });
    res.status(201).json({ success: true, data: relative });
  } catch (error) {
    if (localImagePath && fs.existsSync(localImagePath)) {
      // fs.unlinkSync(localImagePath);
    }
    console.error("error creating relative pr saving image", error);
    return next(
      new ErrorResponse("could not process image or save relative", 500)
    );
  }
});

exports.getRelativesByPatient = asyncHandler(async (req, res, next) => {
  const relatives = await Relative.find({ patient: req.params.patientId });
  res
    .status(200)
    .json({ success: true, count: relatives.length, data: relatives });
});

exports.upload = this.upload;
