# How-To Voiceover Scripts

Two narrated walkthroughs for the Carry app. Built for ElevenLabs TTS + ScreenFlow screen capture.

- **Tone**: warm, calm, confidence-of-a-friend. Not "tutorial energy." Think narrating a recipe, not a classroom.
- **Pace**: ~150 words/minute (ElevenLabs default). Both scripts are deliberately short — under 90 seconds — because golfers won't watch longer.
- **Format**: each line is a beat. Line breaks are natural pauses for the model. `[pause]` is a longer pause when you need the screen to do something visible (sheet opening, picker animating in).
- **`[shot:]` cues**: notes to the ScreenFlow editor for what should be on screen during that line. Not narrated.

---

## Script 1 — Quick Game → Skins Group (≈75 sec)

[shot: Carry app icon on home screen, then opens to Games tab]

Welcome to Carry.
Let's set up a Quick Game and turn it into a recurring Skins Group.

[shot: zoom into "+ New" button bottom of Games tab]

On the Games tab, tap Plus New, then Quick Game.

[shot: course picker, search field highlighted]

Pick your course. Search by name, then choose your tee box.

[pause]

[shot: PlayerGroupsSheet, slot grid with one filled, others empty]

Add players. Search Carry users by name, or invite anyone by phone — they'll get a text with a link.

[shot: Scorer pill highlighted on each tee-time row]

For each tee-time group, pick a scorer. They're the only person in that group who needs the app.
You're locked in as scorer for your own group.

[shot: buy-in slider moving]

Set your buy-in with the slider. Tap Start Round.

[pause]

[shot: scorecard, finger taps on a hole, score appears]

Score holes by tapping. Carry handles skins and carries automatically — your crew just plays.

[shot: End Round button at bottom of last hole]

After the last hole, tap End Round. You'll see the final results.

[shot: invite sheet — Share Invite tab with results card preview]

Carry shows your invite sheet. One tap sends your results card and invite link to the crew.

[shot: name sheet auto-appears after invite, "Skins Game" placeholder]

Carry then asks if you want to turn this into a recurring Skins Group. Name the group, and tap Create.

[shot: GroupManagerView opens with the new group]

Your new Skins Group is ready for next round.

---

## Script 2 — Skins Group from scratch (≈60 sec)

[shot: Games tab, empty or with one card]

Setting up a Skins Group from scratch.

[shot: + New menu, Skins Group highlighted]

On the Games tab, tap Plus New, then Skins Group.

[shot: name field with blinking cursor]

Name your group. Pick your course and tee box.

[pause]

[shot: PlayerGroupsSheet with two tee-time groups visible, drag handle]

Add players to each tee-time group. Drag to rearrange.
Search Carry users, or invite by phone if they're not on the app yet.

[shot: tee time picker wheel, each group with its own time]

Set tee times. Each group can have its own start time.

[shot: Game Options sheet — buy-in, HC allowance, winnings display]

Open Game Options. Set your buy-in, handicap allowance, and how winnings show up. Tap Save.

[pause]

[shot: GroupManagerView — pending member with "Invited" badge]

Your group is created. Players you invited get a push or text.
When they accept, they show as Active members.

[shot: scheduled round card → Start Round CTA]

When you're ready to play, schedule a round and tap Start Round.
Everyone scores on their own phone — no single scorekeeper required.

---

## ElevenLabs production checklist

**Voice**
Default starting points from the public library:
- *Adam* — deep, neutral male narrator (good "founder voice" feel)
- *Bella* — clear, friendly female narrator
- *Daniel* (UK) — calm, instructional. Good fit for app tutorials.

If you want your own voice, the Voice Cloning tier needs ~1 minute of clean reference audio. Not necessary for v1.

**Settings**
- Stability: **55** (consistent reads, still natural)
- Similarity: **75**
- Style: **0** (neutral; raise to 20–30 if voice sounds flat)
- Speaker Boost: **on**

**Output**
- Format: **MP3 128 kbps**
- Sample rate: 44.1 kHz (default)

**Process**
1. Use the **paste-ready scripts at the bottom of this file** (pauses pre-baked, cues stripped). Skip the annotated versions above — those are for the ScreenFlow editor.
2. Generate. Listen. Re-roll any line that sounds off — ElevenLabs lets you regenerate single segments.
3. If the whole take still feels rushed, drop the **Speed** slider from 1.0 to 0.9 (or 0.85 for a slower, more "explainer" feel).
4. Export MP3 per script. Name them `vo-quick-game.mp3` and `vo-skins-group.mp3`.

**Pause sizing reference**
- Between major beats (paragraph breaks in the scripts below): `<break time="1.0s" />`
- Between sentences in the same beat: `<break time="0.5s" />`
- After a tap instruction so the viewer can follow: `<break time="0.7s" />`
- Tiny breath between phrases: `<break time="0.3s" />`

**Pronunciation gotchas to watch for**
- "Carry" — should be fine, but listen to ensure it's not "carry" as in heavy lifting (same word, but emphasis can drift)
- "skins" — sometimes drifts to a softer "skinz"; not wrong, just style preference
- Numbers in copy: none in current scripts, but if you add them, write "twenty-nine ninety-nine" not "$29.99" — TTS reads symbols inconsistently

---

## ScreenFlow workflow

The recommended order saves the most editing time:

1. **Generate VO first** in ElevenLabs.
2. **Import the MP3 into ScreenFlow** as the audio bed.
3. **Record screen capture** in the simulator while playing the VO back at low volume — this naturally times your taps to the narration.
4. **Add Touch Callouts** in ScreenFlow on every tap. These are the white circle pulses — non-negotiable for tutorial clarity.
5. **Use Zoom & Pan actions** on UI moments (course picker, scorecard tap, buy-in slider). 1.5–2× zoom is plenty; aggressive zoom feels nauseating on small phone UI.
6. **Captions**: ScreenFlow can auto-generate from the audio. Edit any "Carry" / "skins" misreads. Caption file also helps Apple Review and accessibility.

**Simulator vs device**
- Simulator: cleaner pixels (no battery, no notch overlap), arbitrary frame rate, easy to script. Best for marketing-quality output.
- Real device: feels real, but you'll have to clean up notifications and battery state.
- Recommendation: simulator for these two how-to videos. Use `xcrun simctl io booted recordVideo carry-flow.mp4` to capture, or just ScreenFlow's window-capture mode.

---

## Where these get shown (deferred — Build 50+)

Out of scope for Build 49. When ready:
- Host on YouTube unlisted (simplest), Mux, or Bunny.net
- Add a "How it works" card on the Home tab → opens a Safari sheet or in-app WebView
- 30–60s clips per flow; full HD, vertical 9:16 (Stories-friendly) or 16:9 (landing-page-friendly), pick one

---

_Last updated: 2026-04-25_
