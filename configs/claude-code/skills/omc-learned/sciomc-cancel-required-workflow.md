# sciomc Skill Requires Explicit Cancel to Terminate Stop Hook

## The Insight
The `sciomc` (research orchestration) skill has a stop hook that fires **up to 5 times** to reinforce that the skill is still active. Emitting `[PROMISE:RESEARCH_COMPLETE]` in your response does NOT automatically satisfy the hook. You must explicitly invoke `/oh-my-claudecode:cancel` to clear the active mode state.

## Why This Matters
If you don't cancel, the stop hook will continue firing for 5 reinforcement rounds, causing 5 additional back-and-forth turns with the user that look like the skill is stuck.

## Recognition Pattern
- After completing sciomc research workflow (decompose → execute → verify → synthesize)
- Stop hook message appears: `[SKILL ACTIVE: sciomc] The "sciomc" skill is still executing (reinforcement N/5)`
- You've already emitted `[PROMISE:RESEARCH_COMPLETE]` but hook keeps firing

## The Required Steps

After completing all sciomc stages (research + verification + report written):

1. **Emit the completion promise** in your response:
   ```
   [PROMISE:RESEARCH_COMPLETE]
   ```

2. **Invoke the cancel skill** explicitly:
   ```
   /oh-my-claudecode:cancel
   ```

3. **The cancel skill will**:
   - Call `state_list_active` to find active modes
   - Find any stale `ralplan` or other state
   - Call `state_clear` to remove it
   - Report "No active OMC modes detected" when clean

## The Approach
Treat sciomc like ralph/ultrawork — it requires explicit mode cancellation, not just a completion signal in the response text. The stop hook is checking state files, not response content. Build cancel invocation into the sciomc completion checklist:

```
✓ All stages complete
✓ Verification passed
✓ Report written to file
✓ Session state saved to .omc/research/
✓ [PROMISE:RESEARCH_COMPLETE] emitted
✓ /oh-my-claudecode:cancel invoked → state cleared
```
