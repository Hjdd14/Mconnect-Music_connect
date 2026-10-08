# NetEase lyric payload — verified shapes

> Written 2026-10-08 during Wave 2 (task-20). Everything below was **observed on a real
> response** from the endpoint this repository already calls, not read from a blog or
> inferred. The payloads themselves are **not** committed: they are third-party lyric
> text and do not belong in this repository. What is committed is the *shape*, which is
> what a parser and its tests need; tests should build small synthetic payloads in the
> formats below rather than embedding a real song.

## The parameter set is what was wrong

`lib/platform/netease/netease_api.dart` sends `{id, lv: -1, tv: -1}`. That is why the
code only ever saw `lrc` and `tlyric`.

Against `GET https://music.163.com/api/song/lyric` (cookies `os=pc; appver=2.10.2.200154`,
desktop UA — the same headers `scripts/test_apis.dart` uses), adding parameters changes
which fields come back:

| Params | Fields in the response |
|---|---|
| `lv=-1&tv=-1` | `lrc`, `tlyric` |
| `lv=-1&tv=-1&yv=-1&yrv=-1` | `lrc`, `tlyric`, **`yrc`** (word-by-word) |
| `lv=-1&tv=-1&yv=-1&yrv=-1&rv=-1` | … plus **`romalrc`**, **`ytlrc`**, **`yromalrc`** |
| `lv=-1&kv=-1&tv=-1&rv=-1&yv=-1&ytv=-1&yrv=-1` | … plus **`klyric`** |

**`rv=-1` is the one that unlocks romanisation.** `yv`/`yrv` are accepted without `rv`,
but `romalrc` only appears once `rv=-1` is present — verified by running the same song
id with and without it and diffing the key set.

### Availability is per song, not per endpoint

Of eight popular tracks probed, **two** had `yrc` (and those two had no `romalrc`); the
Japanese track that had `romalrc` also had `yrc`. So every new field must be treated as
**optional**: a missing `yrc` is normal and must not be an error, and a word-by-word
parser must never be the only path to a usable document.

## Field shapes

**`yrc` — word-by-word.** One line per lyric line:

```
[startMs,durMs](chunkStartMs,chunkDurMs,flags)text
```

Real line structure (values replaced with placeholders — the numbers are the shape):

```
[0,232](0,232,0)<credit text>
[232,232](232,232,0)<credit text>
[464,232](464,232,0)<credit text>
```

* the leading `[start,dur]` is the line's window in milliseconds (note: **no colons**, so
  it is not LRC and the existing `[mm:ss.xx]` regex will not match it);
* each `(start,dur,flags)` triple is one chunk **relative to the line start**, and a line
  carries one triple per chunk — this is the word-by-word timing;
* the first lines of a real payload are **credits** (`制作人`, `作词`, `作曲`), not lyrics,
  i.e. the parser must not assume line 0 is the first sung line.

**`romalrc` / `ytlrc` / `yromalrc` — plain LRC.** Timestamps in the ordinary
`[mm:ss.xxx]` form:

```
[00:00.850]
[00:01.000]<romanised text>
```

Note the first line can be a **timestamp with an empty body** — the existing LRC parser
drops lines whose body is empty, which is the desired behaviour here, but a test should
pin it so an empty first line never becomes a visible blank row.

**`klyric`** was present as a key but **empty** on the one song where it appeared, so its
shape is **not verified** — treat it as unknown rather than guessing.

## What this means for the code

1. `netease_api.getLyric` must send `yv=-1`, `yrv=-1`, `rv=-1` (and `kv=-1` if `klyric` is
   wanted) — otherwise three of the four fields can never appear.
2. `LyricsBundle` (W2-A's shape) should carry `lrc`, `translation`, `yrc`, `romaji`
   separately instead of pre-concatenating, because `yrc` is a different *format*, not a
   richer LRC.
3. Word-by-word parsing needs its own parser: `[start,dur](chunkStart,chunkDur,flags)text`
   is not LRC, and the leading `[a,b]` will be silently swallowed by an LRC parser.

## Not verified

* **`klyric`** — key seen, body empty (above).
* **KRC `[language:]` translation sections** (Kugou) — no sample was obtained; per the
  repository's existing discipline (see the 3DES `.qrc` note in
  `docs/mconnect-improvement-plan.md`) the decoder must not be written from guesswork.
* Whether `yrc` coverage correlates with anything (region, recency, VIP) — eight songs is
  not a sample.
