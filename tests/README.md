# API safety checks

Run `lua tests/api_safety.lua` from the repository root with Lua 5.1 or newer.
The checks cover readable progress, opaque secret substitutes, unavailable aura
data, objective fallbacks, Prey-only visibility, original alpha restoration,
combat/protected/forbidden frame guards, and duplicate hook prevention.

The substitutes do not reproduce WoW's native secret number, string, or boolean
types, secure execution, frame pools, or taint propagation. Verify in Retail
12.1.5 before publishing:

1. Enable script errors with `/console scriptErrors 1`, then `/reload`.
2. Accept, progress, complete, and replace a hunt. Check stages, percentages,
   trap text, zone visibility, and stale progress after changing hunts.
3. During a Nightmare hunt, check Bloody Command and Echo warnings inside and
   outside combat. Restricted aura data may omit a warning; it must not error.
4. Toggle Blizzard widget suppression outside combat and during combat. Combat
   changes apply on `PLAYER_REGEN_ENABLED`. Verify other widgets stay visible.
   Shared model-scene effects are deliberately left to Blizzard.
5. Change themes and reopen options. Check for blocked-action errors during
   combat. If needed, enable `/console taintLog 1`, reproduce, and inspect
   `Logs/taint.log`; disable it afterwards with `/console taintLog 0`.
