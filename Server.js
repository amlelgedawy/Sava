require("dotenv").config();

const express = require("express");
const connectDb = require("./src/config/database");

const cors = require('cors')

const caregiverRoutes = require("./src/routes/caregiverRoutes");
const iotRoutes = require("./src/routes/iotRoutes");
const authRoutes = require("./src/routes/authRoutes");
const errorHandler = require("./src/middleware/error");
const patientRoutes = require("./src/routes/patientRoutes");
const recognitionRoutes = require("./src/routes/recognitionRoutes");
const relativeRoutes = require("./src/routes/relativeRoutes");

const path = require("path");
const { METHODS } = require("http");
const app = express();
const PORT = process.env.PORT || 5000;

connectDb();

const corsOptions ={
  origin:'http://localhost:3000',
  methods: 'GET,HEAD,PUT,PATCH,POST,DELETE',
  credentials: true, 
  optionsSuccessStatus: 204 
}

app.use(cors(corsOptions));

app.use(express.json({ limit: "50mb" }));
app.use(express.urlencoded({ limit: "50mb", extended: true }));

app.use("/uploads", express.static(path.join(__dirname, "uploads")));

app.use("/caregiver", caregiverRoutes);
app.use("/iot", iotRoutes);
app.use("/auth", authRoutes);
app.use("/patient", patientRoutes);
app.use("/recognition", recognitionRoutes);
app.use("/relatives", relativeRoutes);

app.get("/", (req, res) => {
  res.send("AR-IoT Assistive System API is running...");
});

app.use(errorHandler);

app.listen(PORT, () => {
  console.log(`server running on port ${PORT}`);
  console.log(`Access the API at http://localhost:${PORT}`);
  console.log(`Static file serving from: ${path.join(__dirname, "uploads")}`);
});
