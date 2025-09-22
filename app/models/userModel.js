const { readPool, writePool } = require('../config/database');
const bcrypt = require('bcrypt');

class UserModel {
  static async findAll() {
    const query = 'SELECT id, username, email, first_name, last_name, is_active, email_verified, created_at, updated_at FROM users ORDER BY created_at DESC';
    const result = await readPool.query(query);
    return result.rows;
  }

  static async findById(id) {
    const query = 'SELECT id, username, email, first_name, last_name, is_active, email_verified, created_at, updated_at FROM users WHERE id = $1';
    const result = await readPool.query(query, [id]);
    return result.rows[0];
  }

  static async findByEmail(email) {
    const query = 'SELECT id, username, email, first_name, last_name, is_active, email_verified, created_at, updated_at FROM users WHERE email = $1';
    const result = await readPool.query(query, [email]);
    return result.rows[0];
  }

  static async findByUsername(username) {
    const query = 'SELECT id, username, email, first_name, last_name, is_active, email_verified, created_at, updated_at FROM users WHERE username = $1';
    const result = await readPool.query(query, [username]);
    return result.rows[0];
  }

  static async create(userData) {
    const { username, email, first_name, last_name, password } = userData;

    const hashedPassword = await bcrypt.hash(password, 10);

    const query = `
      INSERT INTO users (username, email, first_name, last_name, password_hash)
      VALUES ($1, $2, $3, $4, $5)
      RETURNING id, username, email, first_name, last_name, is_active, email_verified, created_at, updated_at
    `;

    const values = [username, email, first_name, last_name, hashedPassword];
    const result = await writePool.query(query, values);
    return result.rows[0];
  }

  static async update(id, userData) {
    const updates = [];
    const values = [];
    let valueIndex = 1;

    const allowedFields = ['username', 'email', 'first_name', 'last_name', 'is_active', 'email_verified'];

    for (const field of allowedFields) {
      if (userData[field] !== undefined) {
        updates.push(`${field} = $${valueIndex}`);
        values.push(userData[field]);
        valueIndex++;
      }
    }

    if (userData.password) {
      const hashedPassword = await bcrypt.hash(userData.password, 10);
      updates.push(`password_hash = $${valueIndex}`);
      values.push(hashedPassword);
      valueIndex++;
    }

    if (updates.length === 0) {
      throw new Error('No fields to update');
    }

    values.push(id);

    const query = `
      UPDATE users
      SET ${updates.join(', ')}
      WHERE id = $${valueIndex}
      RETURNING id, username, email, first_name, last_name, is_active, email_verified, created_at, updated_at
    `;

    const result = await writePool.query(query, values);
    return result.rows[0];
  }

  static async delete(id) {
    const query = 'DELETE FROM users WHERE id = $1 RETURNING id, username, email';
    const result = await writePool.query(query, [id]);
    return result.rows[0];
  }

  static async validatePassword(plainPassword, hashedPassword) {
    return bcrypt.compare(plainPassword, hashedPassword);
  }

  static async getUserWithPassword(username) {
    const query = 'SELECT * FROM users WHERE username = $1';
    const result = await readPool.query(query, [username]);
    return result.rows[0];
  }
}

module.exports = UserModel;