// const os = require('os');

/**
 * Colyseus Cloud Deployment Configuration.
 * See documentation: https://docs.colyseus.io/deployment/cloud
 */

module.exports = {
  apps : [{
    name: "tank-battle",
    script: 'build/index.js',
    time: true,
    watch: false,
    instances: 2,
    exec_mode: 'fork',
    wait_ready: true,
  }],
};

