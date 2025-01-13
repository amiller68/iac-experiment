const { Client } = require('pg')
const fs = require('fs')
const path = require('path')

async function migrate() {
  const client = new Client({
    host: process.env.DB_HOST,
    port: parseInt(process.env.DB_PORT || '5432'),
    database: process.env.DB_NAME || 'messages',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD
  })

  try {
    await client.connect()
    
    // Get all migration files
    const migrationsDir = path.join(__dirname, '../migrations')
    const migrations = fs.readdirSync(migrationsDir)
      .filter(f => f.endsWith('.sql'))
      .sort()
    
    // Run each migration
    for (const migration of migrations) {
      console.log(`Running migration: ${migration}`)
      const sql = fs.readFileSync(path.join(migrationsDir, migration), 'utf8')
      await client.query(sql)
    }

    console.log('Migration completed successfully')
  } catch (error) {
    console.error('Migration failed:', error)
    throw error
  } finally {
    await client.end()
  }
}

// Allow both Lambda and direct execution
if (require.main === module) {
  migrate().catch(err => {
    console.error(err)
    process.exit(1)
  })
} else {
  module.exports = { migrate }
} 