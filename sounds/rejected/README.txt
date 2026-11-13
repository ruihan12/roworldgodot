These two files are the previous music bed (roworld_menu.mp3, roworld_war.mp3).

The game does not open this directory. main.gd plays only res://sounds/music/frontline_pad.ogg.

Why they are rejected
- They are shortened mono 22050 Hz ~160 kbps encodes (82.86 s and 128.19 s). The RoWorld
  manifest's theme_menu / theme_war lengths are 106.666667 s and 160 s
  (src/shared/Assets/Audio.luau). A previous pass described them as clean spans cut out of
  those themes. That pass did not stop boat and country-conquer sounds at the start of a match.
- Waveform correlation against the real OpenFront transport-ship and conquered samples sits at
  the detector floor (see docs/AUDIO.md). That does not prove the files are clean: the sounds
  players named are the RoWorld boat_launch and conquer assets, which are Roblox asset ids in
  Audio.luau and are not downloadable without authorization (HTTP 403). The spans cannot be
  certified free of those events.
- OpenFront's own music is under proprietary/ and is not licensed for this port.
- The Rodrigo Flores soundtrack ids in src/shared/Assets/Soundtrack.luau (CC BY 4.0) are also
  private Roblox assets (HTTP 403). The bundle itself is not in this git tree
  (tools/assets/upload_soundtrack.py: "not in git").

Do not move these mp3s back into sounds/music/. Playback is an allow-list, not a folder scan,
but the files are still the contaminated bed.
