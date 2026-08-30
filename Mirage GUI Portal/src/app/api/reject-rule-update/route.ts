import { NextResponse } from 'next/server';
import { getRules, saveRuleState } from '@/lib/db';

export async function POST(req: Request) {
  try {
    const { accountId, ruleName } = await req.json();

    if (!accountId || !ruleName) {
      return NextResponse.json({ error: 'Missing required fields' }, { status: 400 });
    }

    const rules = await getRules(accountId);
    const ruleRecord = rules.find(r => r.ruleName === ruleName);

    if (!ruleRecord) {
      return NextResponse.json({ error: 'Rule not found' }, { status: 404 });
    }

    if (!ruleRecord.deployedPattern) {
      return NextResponse.json({ error: 'No deployed snapshot to revert to' }, { status: 400 });
    }

    // Revert eventPattern back to the last deployed snapshot
    ruleRecord.eventPattern = ruleRecord.deployedPattern;
    ruleRecord.status = 'deployed';
    ruleRecord.charCount = ruleRecord.deployedPattern.length;
    await saveRuleState(ruleRecord);

    console.log(`[MIRAGE] Rejected update for rule ${ruleName} — reverted to deployed snapshot.`);

    return NextResponse.json({
      success: true,
      eventPattern: ruleRecord.deployedPattern,
      message: `Rule ${ruleName} reverted to last deployed state.`
    });
  } catch (error) {
    console.error('[MIRAGE] Error in /api/reject-rule-update:', error);
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
  }
}
