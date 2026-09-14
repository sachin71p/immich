# S9 — (optional) Space-scoped People

Depends on: S6 · Reads: DECISIONS §11 · CODEMAP §D (People row).
Status: optional. The orchestrator should re-plan this with a scout pass over the facial-recognition job before
dispatching; the sketch below is the intended design, not a ready brief.

## Design sketch
- `person.spaceId uuid null` (FK CASCADE). A person belongs to a user (upstream) OR to a space.
- Facial recognition for faces on assets with spaceId clusters only against faces/persons of that space.
- Moving an asset between containers: detach its faces from persons of the old container, re-queue recognition.
- People list/explore/search-by-person for a user = own persons + persons of member spaces (with showInTimeline).
- Merge/rename of space persons: any member.
- Sync: `PeopleV1`/`AssetFacesV2` include space persons for members (or new SharedSpacePeopleV1 types).

## Risk
Touches the ML job pipeline and person queries broadly → highest merge-conflict surface in the fork. Do it last,
only if the per-contributor People limitation bothers you in practice.
