/**
 * Compiles individual rule files into AGENTS.md
 *
 * Usage: node scripts/compile.js
 */

const fs = require('fs');
const path = require('path');
const matter = require('gray-matter');
const { glob } = require('glob');

const SKILL_DIR = path.join(__dirname, '..', 'skills', 'documentdb-inspector');
const RULES_DIR = path.join(SKILL_DIR, 'rules');
const OUTPUT_FILE = path.join(SKILL_DIR, 'AGENTS.md');

const SECTIONS = [
    { prefix: 'check-', name: 'Diagnostic Checks', number: 1, impact: 'CRITICAL–HIGH' },
    { prefix: 'setup-', name: 'Setup Procedures',   number: 2, impact: 'MEDIUM' },
    { prefix: 'benchmark-', name: 'Benchmarking & Comparison', number: 3, impact: 'MEDIUM' },
    { prefix: 'testing-', name: 'Testing & Validation', number: 4, impact: 'MEDIUM' }
];

async function compileRules() {
    const metadata = JSON.parse(fs.readFileSync(path.join(SKILL_DIR, 'metadata.json'), 'utf8'));

    let output = `# DocumentDB Inspector — Rules Reference

**Version ${metadata.version}**
${metadata.organization}
${metadata.date}

> **Note:**
> This document is primarily for agents and LLMs to follow when diagnosing,
> setting up, or troubleshooting DocumentDB local containers.

---

## Abstract

${metadata.abstract}

---

## Table of Contents

`;

    const allRules = [];

    for (const section of SECTIONS) {
        const files = await glob(`${section.prefix}*.md`, { cwd: RULES_DIR });
        const rules = [];

        for (const file of files.sort()) {
            const content = fs.readFileSync(path.join(RULES_DIR, file), 'utf8');
            const { data, content: body } = matter(content);
            rules.push({ file, data, body });
        }

        allRules.push({ section, rules });

        const sectionAnchor = section.name.toLowerCase().replace(/[^a-z0-9]+/g, '-');
        output += `${section.number}. [${section.name}](#${section.number}-${sectionAnchor}) — **${section.impact}**\n`;

        rules.forEach((rule, index) => {
            const ruleNumber = `${section.number}.${index + 1}`;
            const ruleAnchor = rule.data.title.toLowerCase().replace(/[^a-z0-9]+/g, '-');
            output += `   - ${ruleNumber} [${rule.data.title}](#${ruleNumber.replace('.', '')}-${ruleAnchor})\n`;
        });
    }

    output += '\n---\n\n';

    for (const { section, rules } of allRules) {
        output += `## ${section.number}. ${section.name}\n\n`;
        output += `**Impact: ${section.impact}**\n\n`;

        rules.forEach((rule, index) => {
            const ruleNumber = `${section.number}.${index + 1}`;
            output += `### ${ruleNumber} ${rule.data.title}\n\n`;
            output += `**Impact: ${rule.data.impact}** (${rule.data.impactDescription})\n\n`;
            output += rule.body.trim() + '\n\n';
        });

        output += '---\n\n';
    }

    output += `## References

- [DocumentDB GitHub repository](https://github.com/documentdb/documentdb)
- [DocumentDB documentation](https://documentdb.io/docs)
- [DocumentDB sample data](https://github.com/documentdb/documentdb/tree/main/sample-data)
`;

    fs.writeFileSync(OUTPUT_FILE, output);
    console.log(`✓ Compiled ${allRules.reduce((sum, s) => sum + s.rules.length, 0)} rules to AGENTS.md`);
}

compileRules().catch(console.error);
