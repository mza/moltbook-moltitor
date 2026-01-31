#!/usr/bin/env node
/**
 * Moltbook Browser Check
 * Uses Playwright to verify pages actually render content, not just shells
 */

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const TIMEOUT = 15000; // 15s max wait for content
const LOG_FILE = path.join(__dirname, 'logs', 'status.jsonl');

async function checkPage(page, url, contentSelector, contentCheck) {
    const start = Date.now();
    try {
        await page.goto(url, { timeout: TIMEOUT, waitUntil: 'domcontentloaded' });
        
        // Wait for either content to appear or "not found" / timeout
        try {
            await page.waitForSelector(contentSelector, { timeout: TIMEOUT });
            const content = await page.textContent(contentSelector);
            const elapsed = Date.now() - start;
            
            if (content && contentCheck(content)) {
                return { status: 'up', ms: elapsed, detail: 'content loaded' };
            } else if (content && (content.includes('not found') || content.includes('Not Found') || content.includes('404'))) {
                return { status: 'degraded', ms: elapsed, detail: 'not found error' };
            } else if (content && content.includes('Loading')) {
                return { status: 'degraded', ms: elapsed, detail: 'stuck on loading' };
            } else {
                return { status: 'degraded', ms: elapsed, detail: 'content empty or invalid' };
            }
        } catch (e) {
            const elapsed = Date.now() - start;
            // Check if page shows loading or error
            const body = await page.textContent('body').catch(() => '');
            if (body.includes('Loading')) {
                return { status: 'degraded', ms: elapsed, detail: 'stuck on loading' };
            }
            return { status: 'timeout', ms: elapsed, detail: 'content never appeared' };
        }
    } catch (e) {
        const elapsed = Date.now() - start;
        return { status: 'error', ms: elapsed, detail: e.message.slice(0, 100) };
    }
}

async function main() {
    const browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({
        userAgent: 'MoltbookMoltitor/1.0 (status checker)'
    });
    const page = await context.newPage();
    
    const results = {
        ts: new Date().toISOString(),
        overall: 'unknown',
        homepage: null,
        post_render: null,
        profile_render: null,
    };
    
    // Check 1: Homepage loads with post list
    console.log('Checking homepage...');
    results.homepage = await checkPage(
        page,
        'https://www.moltbook.com',
        'main', // Main content area
        (content) => content.includes('Posted by') || content.includes('m/general')
    );
    console.log('Homepage:', results.homepage);
    
    // Check 2: A known top post renders with actual content
    console.log('Checking post render...');
    results.post_render = await checkPage(
        page,
        'https://www.moltbook.com/post/74b073fd-37db-4a32-a9e1-c7652e5c0d59', // Shellraiser's post
        'main',
        (content) => content.includes('Shellraiser') || content.includes('Message') || content.includes('coronation')
    );
    console.log('Post render:', results.post_render);
    
    // Check 3: A user profile renders with actual content  
    console.log('Checking profile render...');
    results.profile_render = await checkPage(
        page,
        'https://www.moltbook.com/u/Shellraiser',
        'main',
        (content) => content.includes('Shellraiser') || content.includes('karma') || content.includes('posts')
    );
    console.log('Profile render:', results.profile_render);
    
    await browser.close();
    
    // Determine overall status
    const statuses = [results.homepage, results.post_render, results.profile_render];
    const allUp = statuses.every(s => s.status === 'up');
    const anyTimeout = statuses.some(s => s.status === 'timeout');
    const anyDegraded = statuses.some(s => s.status === 'degraded');
    const anyError = statuses.some(s => s.status === 'error');
    
    if (allUp) {
        results.overall = 'up';
    } else if (anyTimeout) {
        results.overall = 'slow';
    } else if (anyDegraded) {
        results.overall = 'degraded';
    } else if (anyError) {
        results.overall = 'down';
    }
    
    // Append to log
    fs.mkdirSync(path.dirname(LOG_FILE), { recursive: true });
    fs.appendFileSync(LOG_FILE, JSON.stringify(results) + '\n');
    
    // Trim log to last 500 entries
    const lines = fs.readFileSync(LOG_FILE, 'utf8').trim().split('\n');
    if (lines.length > 500) {
        fs.writeFileSync(LOG_FILE, lines.slice(-500).join('\n') + '\n');
    }
    
    console.log('\nResult:', JSON.stringify(results, null, 2));
    
    // Exit with appropriate code
    process.exit(results.overall === 'up' ? 0 : 1);
}

main().catch(e => {
    console.error('Fatal error:', e);
    process.exit(1);
});
