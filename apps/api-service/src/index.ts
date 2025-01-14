declare global {
  namespace Express {
    interface Request {
      correlationId: string;
    }
  }
}

import express from 'express';
import { Pool } from 'pg';
import winston from 'winston';
import prometheus from 'prom-client';
import cors from 'cors';
import { v4 as uuidv4 } from 'uuid';

// Initialize Prometheus metrics
const metrics = {
  requestDuration: new prometheus.Histogram({
    name: 'http_request_duration_seconds',
    help: 'Duration of HTTP requests in seconds',
    labelNames: ['method', 'route', 'status_code']
  }),
  requestCount: new prometheus.Counter({
    name: 'http_requests_total',
    help: 'Total number of HTTP requests',
    labelNames: ['method', 'route', 'status_code']
  }),
  errorCount: new prometheus.Counter({
    name: 'http_request_errors_total',
    help: 'Total number of HTTP request errors',
    labelNames: ['method', 'route']
  }),
  dbConnectionPool: new prometheus.Gauge({
    name: 'db_connection_pool_size',
    help: 'Database connection pool size'
  })
};

// Initialize logger
const logger = winston.createLogger({
  format: winston.format.json(),
  transports: [
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
      )
    })
  ]
});

// Initialize database pool
const pool = new Pool({
  user: process.env.DB_USER,
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  password: process.env.DB_PASSWORD,
  port: parseInt(process.env.DB_PORT || '5432')
});

const app = express();

// Middleware
app.use(express.json());
app.use(cors());

// Add correlation ID middleware
app.use((req, res, next) => {
  const correlationHeader = req.headers['x-correlation-id'];
  req.correlationId = (Array.isArray(correlationHeader) ? correlationHeader[0] : correlationHeader) || uuidv4();
  res.setHeader('x-correlation-id', req.correlationId);
  next();
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', prometheus.register.contentType);
  res.send(await prometheus.register.metrics());
});

// Add a base path prefix to all routes
const basePath = process.env.BASE_PATH || '';

// Message endpoints
app.post(`${basePath}/messages`, async (req, res) => {
  const startTime = Date.now();
  try {
    const { message } = req.body;
    const result = await pool.query(
      'INSERT INTO messages (content) VALUES ($1) RETURNING *',
      [message]
    );
    
    logger.info('Message created', {
      correlationId: req.correlationId,
      messageId: result.rows[0].id
    });

    metrics.requestCount.inc({ method: 'POST', route: `/messages`, status_code: 200 });
    res.json(result.rows[0]);
  } catch (error) {
    logger.error('Error creating message', {
      correlationId: req.correlationId,
      error: error instanceof Error ? error.message : 'Unknown error'
    });
    
    metrics.errorCount.inc({ method: 'POST', route: `/messages` });
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    metrics.requestDuration.observe(
      { method: 'POST', route: `/messages`, status_code: res.statusCode },
      (Date.now() - startTime) / 1000
    );
  }
});

app.get(`${basePath}/messages`, async (req, res) => {
  const startTime = Date.now();
  try {
    const result = await pool.query('SELECT * FROM messages ORDER BY created_at DESC');
    
    logger.info('Messages retrieved', {
      correlationId: req.correlationId,
      count: result.rows.length
    });

    metrics.requestCount.inc({ method: 'GET', route: `/messages`, status_code: 200 });
    res.json(result.rows);
  } catch (error) {
    logger.error('Error retrieving messages', {
      correlationId: req.correlationId,
      error: error instanceof Error ? error.message : 'Unknown error'
    });
    
    metrics.errorCount.inc({ method: 'GET', route: `/messages` });
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    metrics.requestDuration.observe(
      { method: 'GET', route: `/messages`, status_code: res.statusCode },
      (Date.now() - startTime) / 1000
    );
  }
});

// Health check endpoint for ECS
app.get('/health', async (req, res) => {
  try {
    // Test database connection
    await pool.query('SELECT 1');
    
    metrics.requestCount.inc({ method: 'GET', route: '/health', status_code: 200 });
    
    res.status(200).json({ 
      status: 'healthy',
      database: 'connected',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    logger.error('Health check failed', {
      correlationId: req.correlationId,
      error: error instanceof Error ? error.message : 'Unknown error'
    });
    
    metrics.errorCount.inc({ method: 'GET', route: '/health' });
    
    res.status(503).json({ 
      status: 'unhealthy',
      database: 'disconnected',
      timestamp: new Date().toISOString()
    });
  }
});

// Health check endpoint with base path for external requests
app.get(`${basePath}/health`, async (req, res) => {
  // Reuse the same health check logic
  await handleHealthCheck(req, res);
});

logger.info('Starting API service with configuration', {
  basePath: process.env.BASE_PATH,
  port: process.env.PORT || 3000,
});

const port = process.env.PORT || 3000;
app.listen(port, () => {
  logger.info(`API Service listening on port ${port}`);
}); 