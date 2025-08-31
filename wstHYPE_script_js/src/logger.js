const winston = require('winston');
const path = require('path');
const config = require('./config');

class Logger {
  constructor(component = 'WstHypeStrategy') {
    this.component = component;
    this.logger = winston.createLogger({
      level: config.monitoring.logLevel,
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.errors({ stack: true }),
        winston.format.json(),
        winston.format.printf(({ timestamp, level, message, component, ...meta }) => {
          return JSON.stringify({
            timestamp,
            level,
            component: component || this.component,
            message,
            ...meta
          });
        })
      ),
      defaultMeta: { component: this.component },
      transports: [
        // Console output
        new winston.transports.Console({
          format: winston.format.combine(
            winston.format.colorize(),
            winston.format.simple(),
            winston.format.printf(({ timestamp, level, message, component, ...meta }) => {
              const metaStr = Object.keys(meta).length ? JSON.stringify(meta, null, 2) : '';
              return `${timestamp} [${component}] ${level}: ${message} ${metaStr}`;
            })
          )
        }),
        
        // File output for all logs
        new winston.transports.File({
          filename: path.join(__dirname, '../logs/strategy.log'),
          maxsize: 10 * 1024 * 1024, // 10MB
          maxFiles: 5
        }),
        
        // Separate file for errors
        new winston.transports.File({
          filename: path.join(__dirname, '../logs/errors.log'),
          level: 'error',
          maxsize: 10 * 1024 * 1024, // 10MB
          maxFiles: 5
        })
      ]
    });

    // Create logs directory if it doesn't exist
    const fs = require('fs');
    const logsDir = path.join(__dirname, '../logs');
    if (!fs.existsSync(logsDir)) {
      fs.mkdirSync(logsDir, { recursive: true });
    }
  }

  info(message, meta = {}) {
    this.logger.info(message, meta);
  }

  warn(message, meta = {}) {
    this.logger.warn(message, meta);
  }

  error(message, meta = {}) {
    this.logger.error(message, meta);
  }

  debug(message, meta = {}) {
    this.logger.debug(message, meta);
  }

  // Strategy-specific logging methods
  logStrategyExecution(type, params, result) {
    this.info(`Strategy execution: ${type}`, {
      type,
      params,
      result,
      timestamp: new Date().toISOString()
    });
  }

  logHealthCheck(health) {
    this.info('Health check completed', {
      health,
      timestamp: new Date().toISOString()
    });
  }

  logAlert(level, message, data) {
    const logMethod = level === 'critical' ? 'error' : level === 'warning' ? 'warn' : 'info';
    this[logMethod](`ALERT [${level.toUpperCase()}]: ${message}`, {
      alertLevel: level,
      alertData: data,
      timestamp: new Date().toISOString()
    });
  }

  logTransaction(txHash, type, status, gasUsed) {
    this.info(`Transaction ${status}`, {
      txHash,
      type,
      status,
      gasUsed,
      timestamp: new Date().toISOString()
    });
  }
}

module.exports = Logger;
