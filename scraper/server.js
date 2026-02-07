require('dotenv').config();
const express = require('express');
const cors = require('cors');
const puppeteer = require('puppeteer');

const app = express();
const PORT = process.env.PORT || 3001;

app.use(cors({
    origin: ['http://localhost:3090', 'http://localhost:3000', 'https://imaluum-v2.vercel.app'], // Allow frontend ports & Vercel
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization']
}));
app.use(express.json());

// Log requests
app.use((req, res, next) => {
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
    next();
});

// Health check endpoint
app.get('/', (req, res) => {
    res.json({ status: 'ok', service: 'imaluum-scraper' });
});

// Login endpoint (placeholder for now)
app.post('/api/login', async (req, res) => {
    const { username, password } = req.body;

    if (!username || !password) {
        return res.status(400).json({ error: 'Username and password are required' });
    }

    console.log(`Attempting login for user: ${username}`);

    let browser = null;
    try {
        // Launch browser
        browser = await puppeteer.launch({
            headless: "new",
            args: ['--no-sandbox', '--disable-setuid-sandbox']
        });

        const page = await browser.newPage();

        // Navigate to i-Ma'luum
        console.log('Navigating to i-Ma\'luum...');

        // Go 1: Nav to main site
        await page.goto('https://imaluum.iium.edu.my/', { waitUntil: 'networkidle0' });

        // Go 2: Check for redirect to CAS
        if (page.url().includes('cas.iium.edu.my')) {
            console.log('Redirected to CAS login. Filling credentials...');

            // Wait for form to appear
            await page.waitForSelector('#username');

            // Type credentials
            await page.type('#username', username);
            await page.type('#password', password);

            // Click login and wait for navigation
            console.log('Clicking login...');
            await Promise.all([
                page.waitForNavigation({ waitUntil: 'networkidle0' }),
                page.click('.btn-submit')
            ]);
        }

        // Check if login was successful (i.e. we are back at imaluum.iium.edu.my)
        if (page.url().includes('imaluum.iium.edu.my')) {
            console.log('Login successful! URL:', page.url());

            // Get some basic data to prove it works
            const title = await page.title();
            const cookies = await page.cookies();

            res.json({
                success: true,
                message: 'Login successful',
                user: username,
                pageTitle: title,
                cookies: cookies // In a real app, you'd perform the scraping here
            });
        } else {
            console.log('Login failed (or redirected elsewhere). Final URL:', page.url());
            res.status(401).json({ error: 'Login failed. Check credentials.' });
        }

    } catch (error) {
        console.error('Login error:', error);
        res.status(500).json({ error: 'Login failed', details: error.message });
    } finally {
        if (browser) {
            await browser.close();
        }
    }
});

app.listen(PORT, () => {
    console.log(`Scraper server running on http://localhost:${PORT}`);
});
