const express = require('express');
const app = express();
const PORT = process.env.PORT || 8080;

app.get('/', (req, res) => {
  res.json({
    service: 'otel-test-app',
    message: 'OpenTelemetry test app is running',
    endpoints: ['/', '/health', '/trace-test', '/nested'],
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.get('/trace-test', (req, res) => {
  // Simulate work - each request creates trace spans
  const delay = parseInt(req.query.delay) || 10;
  setTimeout(() => {
    res.json({
      message: 'Trace test complete',
      delayMs: delay,
      traceId: req.headers['x-trace-id'] || 'N/A',
    });
  }, delay);
});

app.get('/nested', (req, res) => {
  // Simulate nested async work - creates multiple spans
  setTimeout(() => {
    setTimeout(() => {
      res.json({
        message: 'Nested async work complete',
        spans: 'Check Grafana Tempo for trace details',
      });
    }, 20);
  }, 10);
});

app.listen(PORT, () => {
  console.log(`otel-test-app listening on port ${PORT}`);
});
