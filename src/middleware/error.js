const errorResponse = require("../utils/errorResponse");

const errorHandler = (err, req, res, next) => {
  let error = { ...err };
  error.message = error.message;

  console.log(err.stack);

  if (error.name === "CastError") {
    const message = `resourse not found wth id${error.value}`;
    error = new errorResponse(message, 404);
  }
  if (err.code === "ValidationError") {
    const message = Object.values(err.errors).map((val) => val.message);
    error = new errorResponse(message.join(", "), 400);
  }

  res.status(error.statusCode || 500).json({
    success: false,
    error: error.message || "server Error",
  });
};

module.exports = errorHandler;
