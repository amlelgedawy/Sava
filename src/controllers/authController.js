const asyncHandler = require("../middleware/async");
const ErrorResponse = require("../utils/errorResponse");
const Caregiver = require("../models/Caregiver");
const Patient = require("../models/Patient");

const sendTokenResponse = (user, statusCode, res) => {
  const token = user.getSignedJwtToken();
  const expiresInMilliseconds =
    parseInt(process.env.JWT_COOKIE_EXPIRE, 10) * 24 * 60 * 60 * 1000;
  const options = {
    expires: new Date(Date.now() + expiresInMilliseconds),
    httpOnly: true,
  };
  res
    .status(statusCode)
    .cookie("token", token, options)
    .json({ success: true, token });
};

exports.register = asyncHandler(async (req, res, next) => {
  const { name, email, password, patientId } = req.body;

  let patient = await Patient.findById(patientId);

  if (!patient) {
    return next(
      new ErrorResponse(`patient with id ${patientId} not found`, 404)
    );
  }

  if (patient.caregiver) {
    return next(
      new ErrorResponse(
        `patient with id ${patientId} is alreday linked to a account`,
        400
      )
    );
  }
  const caregiver = await Caregiver.create({
    name,
    email,
    password,
    patient: patientId,
  });
  patient.caregiver = caregiver._id;
  await patient.save();

  sendTokenResponse(caregiver, 200, res);
});

exports.login = asyncHandler(async (req, res, next) => {
  const { email, password } = req.body;
  if (!email || !password) {
    return next(new ErrorResponse("please enter an email and password", 400));
  }
  const caregiver = await Caregiver.findOne({ email }).select("+password");
  if (!caregiver) {
    return next(new ErrorResponse("invalid credentials", 401));
  }
  const isMatch = await caregiver.matchPassword(password);
  if (!isMatch) {
    return next(new ErrorResponse("invalid credentials", 401));
  }

  sendTokenResponse(caregiver, 200, res);
});
