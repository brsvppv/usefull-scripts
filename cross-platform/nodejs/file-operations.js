#!/usr/bin/env node
/**
 * file-operations.js
 * Demonstrates basic file operations in Node.js
 * 
 * Usage: node file-operations.js
 */

const fs = require('fs').promises;
const path = require('path');

async function main() {
    console.log('=== Node.js File Operations Example ===\n');

    const testDir = path.join(__dirname, 'test-output');
    const testFile = path.join(testDir, 'example.txt');

    try {
        // Create directory
        console.log(`Creating directory: ${testDir}`);
        await fs.mkdir(testDir, { recursive: true });

        // Write to file
        console.log(`Writing to file: ${testFile}`);
        const content = 'Hello from Node.js!\nThis is a test file.\n';
        await fs.writeFile(testFile, content, 'utf8');

        // Read from file
        console.log(`Reading from file: ${testFile}`);
        const data = await fs.readFile(testFile, 'utf8');
        console.log('File contents:');
        console.log(data);

        // Get file stats
        const stats = await fs.stat(testFile);
        console.log('File statistics:');
        console.log(`  Size: ${stats.size} bytes`);
        console.log(`  Created: ${stats.birthtime}`);
        console.log(`  Modified: ${stats.mtime}`);

        // List directory contents
        console.log(`\nListing directory: ${testDir}`);
        const files = await fs.readdir(testDir);
        console.log('Files:', files);

        // Clean up
        console.log('\nCleaning up...');
        await fs.unlink(testFile);
        await fs.rmdir(testDir);
        console.log('Done!');

    } catch (error) {
        console.error('Error:', error.message);
        process.exit(1);
    }
}

main();
