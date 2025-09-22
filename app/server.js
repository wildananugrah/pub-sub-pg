const express = require('express');
const cors = require('cors');
require('dotenv').config();

const userRoutes = require('./routes/userRoutes');
const { writePool, readPool } = require('./config/database');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.get('/health', async (req, res) => {
  try {
    await readPool.query('SELECT 1');
    await writePool.query('SELECT 1');
    res.json({
      status: 'healthy',
      message: 'Both read and write databases are connected',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(503).json({
      status: 'unhealthy',
      message: 'Database connection error',
      error: error.message
    });
  }
});

app.use('/api', userRoutes);

app.use((err, req, res, next) => {
  console.error('Error:', err.stack);
  res.status(500).json({
    success: false,
    message: 'Internal server error',
    error: err.message
  });
});

app.use((req, res) => {
  res.status(404).json({
    success: false,
    message: 'Route not found'
  });
});

app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
  console.log(`Write DB: localhost:${process.env.WRITE_DB_PORT || 6000}`);
  console.log(`Read DB: localhost:${process.env.READ_DB_PORT || 6001}`);
});