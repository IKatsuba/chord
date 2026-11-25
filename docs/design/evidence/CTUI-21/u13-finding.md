# U13 armed-quit finding

Acceptance commit234c189 adds tests to U11 source4e3bafb. At120x40 and80x24,
original577b58167 shows only `Press ctrl+c again to quit`; port also shows
right-hand model/effort/context facts. See u13-armed paired and comparison
captures. Original Status.tsx explicitly makes armed status stand alone.

Finding sent to developer and lead. Section3 incorrectly retained facts;
corrected to original after the live comparison. Developer accepted it.
No U13 pass at this checkpoint. The warning expires after the two-second
wait; spaces keep Ctrl+D inert, and Ctrl+C clears them. Those observations
do not supersede the armed-status finding. Subsequent signed fix427d6f7
requires its own isolated visual recheck because U14 is now WIP.
