const { Client } = require('pg');

exports.handler = async (event) => {
  const client = new Client({
    host: process.env.DB_HOST,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
  });

  try {
    await client.connect();
    
    // Run migration
    await client.query(`
      CREATE TABLE IF NOT EXISTS messages (
        id SERIAL PRIMARY KEY,
        content TEXT NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
    `);

    console.log('Migration completed successfully');
    return { statusCode: 200, body: 'Migration successful' };
  } catch (error) {
    console.error('Migration failed:', error);
    throw error;
  } finally {
    await client.end();
  }
}; 