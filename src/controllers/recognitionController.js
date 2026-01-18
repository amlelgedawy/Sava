const { spawn } = require("child_process");
const fs = require("fs");
const asyncHandler = require("../middleware/async");
const path = require("path");
const ErrorResponse = require("../utils/errorResponse");
const Relative = require("../models/Relative");

const findUserByRecognitionKey = async (key) => {
  const person = await Relative.findOne({ recognitionKey: key });
  return person;
};

exports.verifyFace = asyncHandler(async (req, res, next) => {
  console.log(
    "Received body for verifyFace:",
    req.body.patientId
      ? { patientId: req.body.patientId, hasImageData: !!req.body.imageData }
      : "No Body Received"
  );

  let { imageData, patientId } = req.body;
  const fileName = `temp_face_${patientId}_${Date.now()}.jpg`;
  const tempDir = path.join(__dirname, "..", "..", "temp_images");

  if (!imageData) {
    return next(
      new ErrorResponse("Image data is required for recogntion", 400)
    );
  }
  if (imageData.includes(",")) {
    imageData = imageData.split(",")[1];
  }
  if (!fs.existsSync(tempDir)) {
    fs.mkdirSync(tempDir, { recursive: true });
  }
  const pythonExecutablePath =
    "D:\\Mostafa's projects\\Gradution Project\\AlzheimerAR\\.venv\\Scripts\\python.exe";

  const inputImgPath = path.join(tempDir, fileName);
  let recognizedOutput = "";
  let recognizedUser = null;

  try {
    fs.writeFileSync(inputImgPath, Buffer.from(imageData, "base64"));

    const pythonProcess = spawn(pythonExecutablePath, [
      path.join(__dirname, "..", "recognition_script.py"),
      inputImgPath,
      patientId,
    ]);
    pythonProcess.stdout.on("data", (data) => {
      recognizedOutput += data.toString();
    });
    pythonProcess.stderr.on("data", (data) => {
      console.error(`python script stdrr: ${data.toString()}`);
    });
    const exitCode = await new Promise((resolve, reject) => {
      pythonProcess.on("close", (code) => {
        resolve(code);
      });
      pythonProcess.on("error", (err) => {
        reject(
          new ErrorResponse(
            `failed to spawn python process. check path: ${err.message}`,
            500
          )
        );
      });
    });
    if (exitCode !== 0) {
      const errorDetails = recognizedOutput || "no output captured.";
      return next(
        new ErrorResponse(
          `recgntion script failed with exit code 
                ${exitCode}. details:${errorDetails.trim()}`,
          500
        )
      );
    }
    const pythonOutput = recognizedOutput.trim();
    let recognizedResult;
    try {
      recognizedResult = JSON.parse(pythonOutput);
    } catch (e) {
      console.error(`failed to parse python json output: ${pythonOutput}`);
      return next(
        new ErrorResponse(`invalid json received from recogntion script`, 500)
      );
    }
    if (recognizedResult.status === "match") {
      const recognitionKey = recognizedResult.name_key;

      const recognizedPerson = await findUserByRecognitionKey(recognitionKey);

      if (!recognizedPerson) {
        return next(
          new ErrorResponse(
            `recognized persom data not found in databse for key: ${recognitionKey}`,
            404
          )
        );
      }
      recognizedUser = recognizedPerson;
    } else if (recognizedResult.status === "no_match") {
      return res
        .status(404)
        .json({
          success: false,
          message: "no known face recognized",
          recognizedUser: null,
        });
    } else {
      return next(
        new ErrorResponse(
          `recogntion script returned as invalid status: ${recognizedResult.status}`,
          500
        )
      );
    }
  } catch (error) {
    return next(error);
  } finally {
    if (fs.existsSync(inputImgPath)) {
      fs.unlinkSync(inputImgPath);
    }
  }
  res.status(200).json({ success: true, recognizedUser: recognizedUser });
});
