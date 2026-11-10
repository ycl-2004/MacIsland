# Lyrics sources, 2026-11-10

Commit `7a9837cb`. The owner plays music in NetEase Cloud Music and in the
YouTube Music Chrome app, and asked whether lyrics could be made to work for
both.

## What was wrong

- **NetEase.** `music.163.com/api/search/get/web` answers HTTP 200 with an
  encrypted `result` string, so the search that recovered a song id found
  nothing and the NetEase fallback returned empty for every track. The lyric
  endpoint `api/song/lyric?id=` still serves plain JSON.
- **LRCLIB.** Its search filters on the artist as spelled. Playing "Money
  Focused Freestyle" by 艾志恒Asen in YouTube Music returned two untimed rows;
  the timed row is filed under 艾志恆Asen and was neither returned nor, had it
  been, accepted by the local match.

## What changed

- The NetEase desktop app writes its play queue as plain JSON to
  `~/Library/Application Support/com.netease.163music/Documents/storage/file_storage/webdata/file/playingList`.
  `NetEaseLyrics` reads the playing track's id from it (title, artist and
  duration must agree) and asks the lyric endpoint. The file is read when the
  track changes, and once more 1.5 s later if the track is not in it yet. The
  search request and its parsing are gone.
- While NetEase is the player its lyrics are asked for first and LRCLIB is the
  fallback. Every other player uses LRCLIB only.
- `LyricsSearchResults.normalizedForMatching` folds traditional Chinese into
  simplified (`StringTransform("Hant-Hans")`), and a title-only LRCLIB search
  runs when the artist search has no timed row.

Lyrics are kept in memory only: at most 80 tracks, dropped when the app quits.
`URLCache.shared` has `diskCapacity: 0`, and the app's `Cache.db` held no rows.

## Checked

- `Tools/verify-stability.py --native-only` passed on the committed source.
- By hand, before the change: with "两 难" by 加木 playing in NetEase, the
  queue file gave id 2163210456 and the lyric endpoint returned 60 timed lines.
- Release build of `7a9837cb`, `dirty: false`, same identity and designated
  requirement; normal exit of the previous copy (pid 44830), no Atoll crash
  report; Shelf and Extra Space content unchanged; launched as pid 60254.

## Not checked

- The installed build was not watched showing lyrics for a NetEase track or
  for "Money Focused Freestyle"; YouTube Music was playing something else
  after the install.
- The 1.5 s second read rests on an assumption about when the app writes the
  queue. It was not observed.

## Still open

- A YouTube Music upload such as "Start Over - 冷刺「…」(…)【動態歌詞…】" by
  "WCY Music Studio" gets no lyrics. LRCLIB does not hold the song under any
  spelling tried, so cleaning the title would not have helped; with NetEase's
  search unusable there is no second source for players other than NetEase.
