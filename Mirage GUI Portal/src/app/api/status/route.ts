import { NextResponse } from "next/server";
import { exec } from "child_process";
import { promisify } from "util";

const execAsync = promisify(exec);

export const dynamic = 'force-dynamic';

export async function GET() {
  try {
    // Check if deploy-hub.sh is running. The bracket trick prevents grep itself from matching.
    const { stdout: deployOut } = await execAsync(`ps aux | grep "[d]eploy-hub.sh" || true`);
    if (deployOut.trim().length > 0) {
      return NextResponse.json({ status: "deploying" });
    }

    // Check if remove-hub.sh is running
    const { stdout: removeOut } = await execAsync(`ps aux | grep "[r]emove-hub.sh" || true`);
    if (removeOut.trim().length > 0) {
      return NextResponse.json({ status: "removing" });
    }

    return NextResponse.json({ status: "idle" });
  } catch (error) {
    console.error("[MIRAGE] Error checking background status:", error);
    return NextResponse.json({ status: "idle" });
  }
}
