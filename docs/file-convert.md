# File Convert

Enable **Settings → Utilities → File Convert → Enable File Convert**, or the
File Convert row in Feature Management. The feature is off by default. Once
enabled, **Convert** appears in the main tab row next to Shelf and can be
reordered like the other tabs.

## Using it

Drop up to 20 files on the Convert tab and choose a format. Only formats every
dropped file can reach are offered, and a file's own format is never listed.
Files convert one at a time; each row shows its result or the reason it failed.
**Show in Finder** selects the results, **Stop** cancels the current file, and
**Clear** empties the list. Folders are skipped.

Getting files to the tab while dragging:

- Resting a drag on a tab icon for a moment opens that tab, the way Finder's
  spring-loaded folders work. Dropping straight onto the Convert icon also works.
- On a closed notch a drag opens Shelf, as before. With Shelf off, it opens Convert.
- An open Convert tab keeps its own drops, as Extra Space does.

## Where results go

A result is saved in the same folder as the original, with the original's name
and the new extension: a file on the Desktop converts onto the Desktop, a file
in Downloads into Downloads. A name already in use gets a number
(`report 2.pdf`); nothing is ever replaced. PDF pages become `name-1.png`,
`name-2.png`, … Writing into Desktop, Documents or Downloads may ask for
folder access once.

**Keep original** is on by default. The same setting appears as a switch in the
Convert tab and in settings. When it is off, the original moves to the Trash
only after every result is in place, so a failed or cancelled conversion leaves
the original untouched, and a converted one can still be restored from the
Trash. If the Trash refuses the file, it is kept and the row says so.

## Formats

| Input | Built in | With LibreOffice | With FFmpeg |
| --- | --- | --- | --- |
| Images | JPEG, PNG, HEIC, TIFF, GIF, BMP, PDF | | WebP |
| PDF | PNG or JPEG per page | | |
| Word, ODT, RTF, HTML, text | Word, ODT, RTF, HTML, text | PDF with layout | |
| Excel, PowerPoint, ODS, ODP | | PDF | |
| Audio | M4A, WAV, AIFF | | MP3, FLAC |
| MOV, MP4 video | MP4, MOV, M4A audio | | WebM, MP3, GIF |

Built-in conversions use ImageIO, PDFKit, NSAttributedString and AVFoundation.
Video is remuxed without re-encoding when the codecs fit the new container.
HEIC appears only where the Mac can encode it. Text-document conversions keep
text and basic formatting; layout-heavy documents should go through LibreOffice.

LibreOffice and FFmpeg are optional and never downloaded. They are found at
their standard locations (`/Applications/LibreOffice.app`, Homebrew and MacPorts
prefixes), because apps opened from Finder don't inherit the shell's `PATH`.
When FFmpeg converts the same format as a built-in converter, the built-in one
is used. Engines run as child processes with an argument list, never through a
shell, and without the app's loader or test-injection environment variables.

## Resource limits

| Resource | Limit |
| --- | --- |
| Files per drop | 20 |
| Text documents | 50 MB |
| PDF pages | 100 per file |
| Image frames (GIF/TIFF/PDF) | 500 |
| GIF from video | First 60 seconds, 12 fps, at most 720 px wide |
| LibreOffice run | 3 minutes |
| FFmpeg run | 1 hour |
| Staging | One private folder per conversion in this run's temporary area, removed when it finishes or fails |
| LibreOffice profile | About 0.5 MB in the same temporary area, kept for the run so later conversions start faster |

The temporary area is removed when the app quits, and areas left by a crashed
run are swept on the next launch. Quit and Restart first stop a running
conversion, so no LibreOffice or FFmpeg process outlives the app. No conversion
history is stored.

## Code

Contract, converters, registry and application layer are separate:

- `components/FileConvert/Conversion/FileConverter.swift`: formats, routes and
  the `FileConverter` contract.
- `ImageConverters.swift`, `DocumentConverters.swift`, `MediaConverters.swift`:
  one type per converter. `ExternalConversionTool.swift` runs the optional engines.
- `FileConverterRegistry.swift`: a new converter is its own type plus one line here.
- `FileConversionService.swift`: chooses converters, stages, places results and
  handles the original. `FileConvertModel.swift`: the tab's state.

`DynamicIslandTests/FileConvertTests.swift` tests the shared mechanism once
with stand-in converters, and each converter's own conversion separately. The
LibreOffice and FFmpeg tests are skipped where those tools are not installed.
