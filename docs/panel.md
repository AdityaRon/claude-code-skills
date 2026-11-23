# The comms panel

A panel beside the comms session's chat (`skills/comms-hub/panel/`, a mod
`hub.py launch` loads into that session alone): what needs you, what goes
out and when, what is with other sessions, and what changed since you last
looked, one line each, from `hub.py panel` as each turn ends and each minute
while it is drawn, so it calls no model. `claude plugin test skills/comms-hub/panel`
runs its tests; `.github/workflows/panel.yml` runs them daily on the newest Claude Code.
