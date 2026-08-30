import { NextResponse } from 'next/server';
import { exec } from 'child_process';
import fs from 'fs/promises';
import path from 'path';
import util from 'util';

const execAsync = util.promisify(exec);

export const dynamic = 'force-dynamic';

export async function GET() {
  try {
    // 1. Sync the GitHub repo
    const scriptPath = path.join(process.cwd(), 'src', 'scripts', 'sync-scenarios.sh');
    await execAsync(`bash "${scriptPath}"`);

    // 2. Read the scenarios from the cloned GitHub repo
    const scenariosDir = path.join(process.cwd(), 'src', 'templates', 'mirage-os', 'aws', 'scenarios_terraform');
    
    // Check if dir exists and read its contents
    let folders: string[] = [];
    try {
      const entries = await fs.readdir(scenariosDir, { withFileTypes: true });
      folders = entries.filter(e => e.isDirectory() && e.name.startsWith('scenario-')).map(e => e.name);
    } catch (e) {
      console.error("Failed to read scenarios dir", e);
      return NextResponse.json({ error: 'Failed to read scenarios' }, { status: 500 });
    }

    const scenarios = [];

    // Sort folders nicely (e.g., scenario-1, scenario-2...)
    folders.sort((a, b) => {
      const numA = parseInt(a.replace('scenario-', ''));
      const numB = parseInt(b.replace('scenario-', ''));
      return numA - numB;
    });

    for (const folder of folders) {
      const detailsPath = path.join(scenariosDir, folder, 'details.md');
      try {
        const content = await fs.readFile(detailsPath, 'utf-8');
        const lines = content.split('\n');
        
        // Extract Name
        let name = lines[0].replace(/^#\s*/, '').trim();
        name = name.charAt(0).toUpperCase() + name.slice(1);
        
        // Extract Description
        let descLines = [];
        for (let i = 1; i < lines.length; i++) {
          if (!lines[i].trim().startsWith('#')) {
            descLines.push(lines[i]);
          }
        }
        let rawDescription = descLines.join('\n').trim();
        rawDescription = rawDescription.replace(/^Description:\s*/i, '');

        let description = rawDescription;
        let resources = "";
        
        const splitIndex = rawDescription.indexOf('**Resources Deployed:**');
        if (splitIndex !== -1) {
          description = rawDescription.substring(0, splitIndex).trim();
          resources = rawDescription.substring(splitIndex + '**Resources Deployed:**'.length).trim();
        }

        // Parameters logic removed for MVP
        const parameters: { label: string, hardcodedName: string }[] = [];

        // Add to our payload
        scenarios.push({
          id: folder,
          name,
          description,
          resources,
          parameters
        });
      } catch (err) {
        console.error(`Skipping ${folder}, no valid details.md found.`);
      }
    }

    return NextResponse.json(scenarios);
  } catch (error) {
    console.error("Error in /api/scenarios:", error);
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
  }
}
