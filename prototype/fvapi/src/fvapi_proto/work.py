"""Idle library work — ITERATE stub (Decisions: shown as a visible stub; the real loop = IMPLEMENT).

No worker runs and no proof is produced: the top demand keys cycle queued → proving → added on a
wall-clock timer, each item offset by one step so the console shows every state at once.
Stdlib only ⇒ server.py + mock.py share it.
"""

import time
from datetime import datetime, timezone

STATES = ("queued", "proving", "added")
STEP_S = 30
ITEMS = 3
NOTE = "Stub: no worker runs and nothing is proved. States advance on a timer to show the idle-work loop."


def work(by_key, now=None, force=None):
    """by_key = /v0/demand `by_key`; force ∈ STATES pins the first item (console `?state=` drives)."""
    now = time.time() if now is None else now
    tick = int(now // STEP_S)
    items = []
    for i, row in enumerate(by_key[:ITEMS]):
        key, _, value = row["key"].partition(":")
        step = (tick + i) % len(STATES)
        if i == 0 and force in STATES:
            step = STATES.index(force)
        items.append({
            "key": key, "value": value, "demand_count": row["count"], "state": STATES[step],
            "since": datetime.fromtimestamp(tick * STEP_S, timezone.utc).isoformat(),
            "next_change_s": None if i == 0 and force in STATES else STEP_S - int(now % STEP_S),
        })
    return {"stub": True, "note": NOTE, "states": list(STATES), "step_s": STEP_S, "items": items}
