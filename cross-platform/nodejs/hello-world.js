#!/usr/bin/env node
/**
 * hello-world.js
 * Simple Node.js example script
 * 
 * Usage: node hello-world.js [name]
 */

const name = process.argv[2] || 'World';

console.log(`Hello, ${name}!`);
console.log(`\nNode.js Version: ${process.version}`);
console.log(`Platform: ${process.platform}`);
console.log(`Architecture: ${process.arch}`);
console.log(`Current Directory: ${process.cwd()}`);

// Example: Read environment variable
const user = process.env.USER || process.env.USERNAME || 'Unknown';
console.log(`Current User: ${user}`);
