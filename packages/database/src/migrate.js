const { Client } = require('pg')
const fs = require('fs')
const path = require('path')

// Only require AWS SDK when running in Lambda
const isLambda = !!process.env.AWS_LAMBDA_FUNCTION_NAME
const SSM = isLambda ? require('@aws-sdk/client-ssm').SSM : null
const SecretsManager = isLambda ? require('@aws-sdk/client-secrets-manager').SecretsManager : null

exports.migrate = async function() {
  // Get DB password from Secrets Manager
  let dbPassword
  if (isLambda) {
    const secretsManager = new SecretsManager({})
    const secret = await secretsManager.getSecretValue({
      SecretId: process.env.DB_PASSWORD_SECRET_ARN
    })
    dbPassword = secret.SecretString
  } else {
    dbPassword = process.env.DB_PASSWORD
  }

  const client = new Client({
    // Split host and port from DB_HOST (which comes in format: hostname:port)
    host: process.env.DB_HOST.split(':')[0],
    port: parseInt(process.env.DB_PORT || '5432'),
    database: process.env.DB_NAME || 'messages',
    user: process.env.DB_USER || 'postgres',
    password: dbPassword
  })

  try {
    await client.connect()
    console.log('Connected to database successfully')
    
    // Get all migration files
    const migrationsDir = path.join(__dirname, '../migrations')
    console.log('Looking for migrations in:', migrationsDir)
    const migrations = fs.readdirSync(migrationsDir)
      .filter(f => f.endsWith('.sql'))
      .sort()
    console.log('Found migrations:', migrations)
    
    // Run each migration
    for (const migration of migrations) {
      console.log(`Running migration: ${migration}`)
      const sql = fs.readFileSync(path.join(migrationsDir, migration), 'utf8')
      console.log('Migration SQL:', sql.substring(0, 100) + '...')
      await client.query(sql)
      console.log(`Completed migration: ${migration}`)
    }

    if (isLambda) {
      console.log('Updating SSM parameter...')
      const ssm = new SSM({})
      const paramName = `/${process.env.ENVIRONMENT}/migration-status`
      
      await ssm.putParameter({
        Name: paramName,
        Value: 'complete',
        Type: 'String',
        Overwrite: true
      })
      console.log('SSM parameter updated successfully')
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
  exports.migrate().catch(err => {
    console.error(err)
    process.exit(1)
  })
} else {
  // exports.migrate is already defined above
} 