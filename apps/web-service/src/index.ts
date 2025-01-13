import express from 'express';
import winston from 'winston';
import prometheus from 'prom-client';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';
import fs from 'fs';

declare global {
  namespace Express {
    interface Request {
      correlationId: string;
    }
  }
}

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

const app = express();

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

// Serve main HTML page
app.get('/', (req, res) => {
  const startTime = Date.now();
  try {
    const html = `<!DOCTYPE html>
    <html>
    <head>
        <title>Message Service</title>
        <style>
            body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
            .message-form { margin-bottom: 20px; }
            .messages { border: 1px solid #ccc; padding: 10px; }
        </style>
    </head>
    <body>
        <h1>Message Service</h1>
        <div class="message-form">
            <h2>Post a Message</h2>
            <input type="text" id="messageInput" placeholder="Enter your message">
            <button onclick="postMessage()">Send</button>
        </div>
        <div class="messages">
            <h2>Messages</h2>
            <div id="messageList"></div>
        </div>
        <script>
            const API_URL = '${process.env.API_URL || 'http://localhost:3000'}';
            async function postMessage() {
                const input = document.getElementById('messageInput');
                const message = input.value;
                try {
                    const response = await fetch(\`\${API_URL}/messages\`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ message })
                    });
                    if (response.ok) {
                        input.value = '';
                        loadMessages();
                    }
                } catch (error) {
                    console.error('Error posting message:', error);
                }
            }
            async function loadMessages() {
                try {
                    const response = await fetch(\`\${API_URL}/messages\`);
                    const messages = await response.json();
                    const messageList = document.getElementById('messageList');
                    messageList.innerHTML = messages
                        .map(msg => \`<div>\${msg.content}</div>\`)
                        .join('');
                } catch (error) {
                    console.error('Error loading messages:', error);
                }
            }
            loadMessages();
        </script>
    </body>
    </html>`;

    logger.info('Serving main page', {
      correlationId: req.correlationId,
      apiUrl: process.env.API_URL
    });

    metrics.requestCount.inc({ method: 'GET', route: '/', status_code: 200 });
    res.send(html);
  } catch (error) {
    logger.error('Error serving main page', {
      correlationId: req.correlationId,
      error: error instanceof Error ? error.message : 'Unknown error'
    });
    
    metrics.errorCount.inc({ method: 'GET', route: '/' });
    res.status(500).send('Internal server error');
  } finally {
    metrics.requestDuration.observe(
      { method: 'GET', route: '/', status_code: res.statusCode },
      (Date.now() - startTime) / 1000
    );
  }
});

const port = process.env.PORT || 3001;
app.listen(port, () => {
  logger.info(`Web Service listening on port ${port}`);
}); 