const { Client } = require('pg')
const fs = require('fs')
const path = require('path')

// Only require AWS SDK when running in Lambda
const isLambda = !!process.env.AWS_LAMBDA_FUNCTION_NAME
const SSM = isLambda ? require('@aws-sdk/client-ssm').SSM : null
const SecretsManager = isLambda ? require('@aws-sdk/client-secrets-manager').SecretsManager : null

exports.migrate = async function() {
  // Log all environment variables at the start
  console.log('Environment variables:', {
    DB_HOST: process.env.DB_HOST,
    DB_NAME: process.env.DB_NAME,
    DB_USER: process.env.DB_USER,
    DB_PASSWORD_SECRET_ARN: process.env.DB_PASSWORD_SECRET_ARN,
    ENVIRONMENT: process.env.ENVIRONMENT
  })

  // Get DB password from Secrets Manager
  let dbPassword
  if (isLambda) {
    console.log('Running in Lambda, retrieving secret from:', process.env.DB_PASSWORD_SECRET_ARN)
    const secretsManager = new SecretsManager({})
    try {
      const secret = await secretsManager.getSecretValue({
        SecretId: process.env.DB_PASSWORD_SECRET_ARN
      })
      dbPassword = secret.SecretString
      console.log('Retrieved secret successfully')
    } catch (error) {
      console.error('Failed to retrieve secret:', error)
      throw error
    }
  } else {
    dbPassword = process.env.DB_PASSWORD
  }

  // Log connection details (without password)
  console.log('Attempting to connect with:', {
    host: process.env.DB_HOST.split(':')[0],
    port: parseInt(process.env.DB_PORT || '5432'),
    database: process.env.DB_NAME || 'messages',
    user: process.env.DB_USER || 'postgres'
  })

  const client = new Client({
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
} 