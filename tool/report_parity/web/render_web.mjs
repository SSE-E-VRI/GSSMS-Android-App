/**
 * render_web.mjs
 * Renders all fixtures through Vite and Playwright (Chrome) to PDF.
 */

import { chromium } from 'playwright-core';
import { preview } from 'vite';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const ROOT_DIR = path.resolve(__dirname, '../../..');
const FIXTURES_DIR = path.resolve(__dirname, '../fixtures');
const OUT_DIR = path.resolve(ROOT_DIR, 'build/report_parity/web');

fs.mkdirSync(OUT_DIR, { recursive: true });

const FIXTURE_IDS = [
  'checklist_pm_full',
  'checklist_pm_minimal',
  'checklist_pm_long',
  'breakdown_deficiency',
  'breakdown_complaint',
  'breakdown_jobwork',
  'inspection_pointwise',
  'inspection_legacy',
  'rectification_mixed',
  'rectification_single',
  'checklist_pm_stress',
  'breakdown_long',
  'rectification_long',
];

async function main() {
  const args = process.argv.slice(2);
  let targetFixtures = FIXTURE_IDS;

  const fixtureArgIdx = args.indexOf('--fixture');
  if (fixtureArgIdx !== -1 && args[fixtureArgIdx + 1]) {
    targetFixtures = [args[fixtureArgIdx + 1]];
  }

  const printBackground = args.includes('--background');
  const displayHeaderFooter = args.includes('--header-footer');

  console.log(`Starting Vite preview server...`);
  const previewServer = await preview({
    root: __dirname,
    preview: {
      port: 4179,
    },
  });

  const urlBase = 'http://localhost:4179';
  console.log(`Preview server running at ${urlBase}`);

  console.log(`Launching Chrome...`);
  const browser = await chromium.launch({
    channel: 'chrome',
    headless: true,
  });

  const context = await browser.newContext({
    timezoneId: 'Asia/Kolkata',
    locale: 'en-IN',
  });

  const page = await context.newPage();

  for (const id of targetFixtures) {
    const fixturePath = path.join(FIXTURES_DIR, `${id}.json`);
    const fixtureData = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));

    console.log(`Rendering ${id}...`);
    if (page.clock && page.clock.setFixedTime) {
      await page.clock.setFixedTime(new Date(fixtureData.generatedAt));
    }

    await page.goto(`${urlBase}/?fixture=${id}`, { waitUntil: 'networkidle' });

    await page.waitForFunction(() => window.__REPORT_READY__ === true, {
      timeout: 10000,
    });

    // Short stabilization wait
    await page.waitForTimeout(200);

    const outPath = path.join(OUT_DIR, `${id}.pdf`);
    await page.pdf({
      path: outPath,
      format: 'A4',
      margin: {
        top: '1cm',
        right: '1cm',
        bottom: '1cm',
        left: '1cm',
      },
      printBackground,
      displayHeaderFooter,
    });

    console.log(`Saved ${outPath}`);
  }

  await browser.close();
  await previewServer.httpServer.close();
  console.log('All web PDFs rendered successfully.');
}

main().catch((err) => {
  console.error('Error rendering web reports:', err);
  process.exit(1);
});
