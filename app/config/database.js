const { Pool } = require('pg');
require('dotenv').config();

const writeDbConfig = {
  host: process.env.WRITE_DB_HOST || 'localhost',
  port: process.env.WRITE_DB_PORT || 6000,
  database: process.env.DB_NAME || 'postgres',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'password',
};

const readDbConfig = {
  host: process.env.READ_DB_HOST || 'localhost',
  port: process.env.READ_DB_PORT || 6001,
  database: process.env.DB_NAME || 'postgres',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'password',
};

const writePool = new Pool(writeDbConfig);
const readPool = new Pool(readDbConfig);

writePool.on('error', (err) => {
  console.error('Unexpected error on write pool:', err);
});

readPool.on('error', (err) => {
  console.error('Unexpected error on read pool:', err);
});

module.exports = {
  writePool,
  readPool,
};