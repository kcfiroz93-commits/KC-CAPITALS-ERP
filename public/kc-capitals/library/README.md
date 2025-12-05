# KC Capitals Digital Library

This directory contains metadata and configuration for the author library backend.

## Structure

- `index.json` — Master index of all library items (books, audio, EPUB, cover art)
- `books/` — PDF and document storage
- `audio/` — Audio files (MP3, audiobook content)
- `epub/` — EPUB format books
- `branding/` — Cover art, mockups, and branding assets

## Local File References

The following files are referenced in `index.json` with `localPath` entries that point to the source locations on the host machine:

- `/mnt/data/KC Capitals_mockup.pdf` — KC Capitals brand mockup
- `/mnt/data/2025 THE YEAR OF MIRACLE_250106_032129.pdf` — The Year of Miracle book

These paths are preserved in the index so your connector/transform pipeline can map them to Drive folder IDs or hosted URLs.

## Drive Folder IDs

- **Books**: `15xytBltrBN7ikK4yTr8FS6mRUQzNeAKn`
- **Audio**: `1UOFQX_8l--aJ2127lv2_0ApZyrEvCO-I`
- **Author Data**: `1BpZVEKZ6QZDhyJywZxn50JvANnQEOpov`

## API Endpoint

Access library files via `/api/driveFiles`:

```bash
# List files in a Drive folder
curl "https://<your-domain>/api/driveFiles?action=list&folderId=<FOLDER_ID>" \
  -H "Authorization: Bearer <FIREBASE_ID_TOKEN>"

# Stream file content
curl "https://<your-domain>/api/driveFiles?action=get&fileId=<FILE_ID>" \
  -H "Authorization: Bearer <FIREBASE_ID_TOKEN>" \
  -o output.pdf

# Get file metadata
curl "https://<your-domain>/api/driveFiles?action=signedUrl&fileId=<FILE_ID>" \
  -H "Authorization: Bearer <FIREBASE_ID_TOKEN>"
```

Requires valid Firebase ID token with user profile role in Firestore: `artifacts/kc-capitals-default/public/profiles/<uid>`
