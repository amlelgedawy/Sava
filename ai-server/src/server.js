const express = require('express');
const dotenv = require('dotenv');
const path = require('path');

dotenv.config();

const app = express();

app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  next();
});

app.use(express.json());
app.use(express.static(path.join(__dirname, '..', 'public')));

app.get('/health', (req, res) => {
  res.json({ status: 'AI server running' });
});

const analyzeRoutes = require('./routes/analyze.routes');
app.use('/analyze', analyzeRoutes);

const PORT = process.env.PORT || 8000;
app.listen(PORT, () => {
  console.log(`AI Server running on port ${PORT}`);
});
