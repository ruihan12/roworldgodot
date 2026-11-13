Drop folder for official RoWorld / Roblox audio, once a public copy is available.

Expected layout (the director prefers these over sounds/play/ stand-ins, then
falls back if a file is missing; gating rules are unchanged):

  sounds/upstream/<event>.wav     16-bit PCM, 44.1 kHz  (ui_click, boat_launch, ...)
  sounds/upstream/menu.wav        optional looping menu theme
  sounds/upstream/war.wav         optional looping war theme
  sounds/upstream/<track_key>.wav optional soundtrack tracks (glory_of_the_nation, ...)
  sounds/upstream/raw/<id>.<ext>  untouched bytes from asset delivery

A public, unauthenticated fetch of all 104 Roblox asset ids in
ui_upstream/audio.json was attempted on 2026-11-09 (America/New_York):

  GET https://assetdelivery.roblox.com/v1/asset/?id=ID      -> HTTP 403
  GET https://assetdelivery.roblox.com/v2/assetId/ID        -> HTTP 200, JSON error code 403
  GET https://www.roblox.com/asset/?id=ID                   -> HTTP 404

Message on the delivery routes: "User is not authorized to access Asset."
No cookies, tokens, or other credentials were used. Downloaded: 0 / 104.
See download_report.json. raw/ is empty. Do not use sounds/rejected/ as a stand-in.

2026-11-09 (America/New_York): recovered from the owner's own Roblox cache (read-only copy of
rbx-storage.db + rbx-storage/ on RuihanPc). 62/62 sfx events installed as <event>.wav (16-bit PCM 44.1k),
33/33 soundtrack tracks as music/<track>.ogg (original Vorbis bytes), 4 overridden older ui_* ids in variants/.
Missing: menu, war themes; manifest countdown_tick (0.15s), spawn_confirm (2.4s), game_start (3.6s) - all
overridden upstream and never preloaded. Per-id method and confidence: cache_match_report.json.
