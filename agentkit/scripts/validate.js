/**
 * Validates rule files have correct frontmatter and structure
 *
 * Usage: node scripts/validate.js
 */

const fs = require('fs');
const path = require('path');
const matter = require('gray-matter');
const { glob } = require('glob');

const RULES_DIR = path.join(__dirname, '..', 'skills', 'documentdb-inspector', 'rules');

const VALID_IMPACTS = ['CRITICAL', 'HIGH', 'MEDIUM-HIGH', 'MEDIUM', 'LOW-MEDIUM', 'LOW'];

async function validateRules() {
    const files = await glob('*.md', { cwd: RULES_DIR });
    let errors = 0;
    let validated = 0;

    for (const file of files) {
        if (file.startsWith('_')) continue;

        const filepath = path.join(RULES_DIR, file);
        const content = fs.readFileSync(filepath, 'utf8');
        const { data, content: body } = matter(content);

        const fileErrors = [];

        // Required frontmatter
        if (!data.title) fileErrors.push('Missing title');
        if (!data.impact) fileErrors.push('Missing impact');
        else if (!VALID_IMPACTS.includes(data.impact)) {
            fileErrors.push(`Invalid impact "${data.impact}". Must be one of: ${VALID_IMPACTS.join(', ')}`);
        }
        if (!data.impactDescription) fileErrors.push('Missing impactDescription');
        if (!data.tags || !Array.isArray(data.tags)) fileErrors.push('Missing or invalid tags array');

        // Content structure — diagnostic rules use Symptom/Resolution or Incorrect/Correct
        const hasSymptom = body.includes('**Symptom') || body.includes('**Incorrect');
        const hasResolution = body.includes('**Resolution') || body.includes('**Correct');

        if (!hasSymptom) fileErrors.push('Missing **Symptom** or **Incorrect** section');
        if (!hasResolution) fileErrors.push('Missing **Resolution** or **Correct** section');

        // Must have code blocks
        if (!body.includes('```')) {
            fileErrors.push('Missing code examples');
        }

        if (fileErrors.length > 0) {
            console.error(`✗ ${file}:`);
            fileErrors.forEach(e => console.error(`  - ${e}`));
            errors += fileErrors.length;
        } else {
            validated++;
        }
    }

    console.log(`\n${validated} rules validated successfully`);
    if (errors > 0) {
        console.error(`${errors} errors found`);
        process.exit(1);
    }
}

validateRules().catch(console.error);
