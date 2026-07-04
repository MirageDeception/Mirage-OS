# Scenario 9

Deception Scenario 9 - IAM Role Chain Loop: three IAM roles in a circular assumption chain (A→B→C→A). Each role has read access to a themed SSM parameter containing fake credentials. Every hop generates CloudTrail events.
