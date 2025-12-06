#!/usr/bin/env bash
set -euo pipefail

# ============================
# CONFIG - replace placeholders
# ============================
GIT_REPO="git@github.com:YOUR_GITHUB_USER/YOUR_REPO.git"   # <-- REPLACE
GIT_BRANCH="content/drive-integration"
VERCEL_TOKEN="VERCEL_TOKEN_HERE"                          # optional: create at https://vercel.com/account/tokens
VERCEL_PROJECT_DOMAIN="your-vercel-domain.vercel.app"     # e.g. kc-capitals.vercel.app (REPLACE)
APP_ID="kc-capitals-default"                              # Firestore path base
# Local files you uploaded (exact)
FILE1_LOCAL="/mnt/data/KC Capitals_mockup.pdf"
FILE2_LOCAL="/mnt/data/2025 THE YEAR OF MIRACLE_250106_032129.pdf"
# Drive folders you provided (already recorded)
DRIVE_BOOKS_FOLDER="15xytBltrBN7ikK4yTr8FS6mRUQzNeAKn"
DRIVE_AUDIO_FOLDER="1UOFQX_8l--aJ2127lv2_0ApZyrEvCO-I"
DRIVE_AUTHOR_FOLDER="1BpZVEKZ6QZDhyJywZxn50JvANnQEOpov"
# ============================
# End config
# ============================

# quick validation
if [ "$GIT_REPO" = "git@github.com:YOUR_GITHUB_USER/YOUR_REPO.git" ]; then
  echo ""
  echo "ERROR: Edit the script: set GIT_REPO to your repository (SSH or HTTPS). Aborting."
  exit 1
fi

if [ ! -f "$FILE1_LOCAL" ]; then
  echo "ERROR: Missing file: $FILE1_LOCAL"
  exit 1
fi
if [ ! -f "$FILE2_LOCAL" ]; then
  echo "ERROR: Missing file: $FILE2_LOCAL"
  exit 1
fi

# Create temp workspace
TMPDIR=$(mktemp -d)
cd "$TMPDIR"

echo "Cloning repository..."
git clone "$GIT_REPO" kc-repo
cd kc-repo

# create branch
git checkout -b "$GIT_BRANCH" || git checkout --orphan "$GIT_BRANCH"

# Ensure directories
mkdir -p public/kc-capitals/library/books
mkdir -p public/kc-capitals/library/audio
mkdir -p public/kc-capitals/library/epub
mkdir -p public/kc-capitals/library/branding
mkdir -p api

# Add local files placeholders (we do NOT modify your original uploaded local files; we copy them into repo only if you want)
# For now we will NOT copy heavy PDFs into the repo to keep repo size small. We will store localPath references.
# If you prefer commit the actual PDFs to repo, uncomment cp lines below.

# cp "$FILE1_LOCAL" "public/kc-capitals/library/branding/$(basename "$FILE1_LOCAL")"
# cp "$FILE2_LOCAL" "public/kc-capitals/library/books/$(basename "$FILE2_LOCAL")"

# Create index.json that includes drive folder IDs + localPath placeholders
cat > public/kc-capitals/library/index.json <<JSON
[
  {
    "id": "the-year-of-miracle",
    "title": "The Year of Miracle",
    "file_pdf": "/kc-capitals/library/books/the-year-of-miracle.pdf",
    "localPath": "$FILE2_LOCAL",
    "driveFolderId": "$DRIVE_BOOKS_FOLDER",
    "driveFileId": "",
    "file_epub": "/kc-capitals/library/epub/the-year-of-miracle.epub",
    "file_audio": "/kc-capitals/library/audio/the-year-of-miracle.mp3",
    "cover": "/kc-capitals/library/branding/the-year-of-miracle-cover.jpg",
    "published_by": "Firoz KC"
  },
  {
    "id": "kc-capitals-mockup",
    "title": "KC Capitals Mockup",
    "file_pdf": "/kc-capitals/library/branding/$(basename "$FILE1_LOCAL")",
    "localPath": "$FILE1_LOCAL",
    "driveFolderId": "$DRIVE_AUTHOR_FOLDER",
    "driveFileId": "",
    "file_epub": "/kc-capitals/library/epub/kc-capitals-mockup.epub",
    "file_audio": "/kc-capitals/library/audio/kc-capitals-mockup.mp3",
    "cover": "/kc-capitals/library/branding/kc-capitals-mockup-cover.jpg",
    "published_by": "KC Capitals"
  }
]
JSON

# Create a minimal README for folder mapping
cat > public/kc-capitals/library/README.LOCALPATH <<EOF
This file lists local source file locations used for index.json localPath entries.
Do not edit unless you know the original location on the host.
EOF

# Create Vercel serverless API for Drive listing + proxy (vercel-compatible)
cat > api/driveFiles.js <<'JS'
/**
 * api/driveFiles.js - Vercel Serverless
 * - List files in a Drive folder: ?action=list&folderId=<id>
 * - Stream file content: ?action=get&fileId=<id>
 * - Return file metadata: ?action=signedUrl&fileId=<id>
 *
 * Requires env:
 *  - GOOGLE_SA_KEY_JSON  (base64-encoded service account JSON)
 *  - APP_ID
 */
const { google } = require('googleapis');
const admin = require('firebase-admin');

const SA_BASE64 = process.env.GOOGLE_SA_KEY_JSON || '';
if (!admin.apps.length) {
  if (SA_BASE64) {
    const key = JSON.parse(Buffer.from(SA_BASE64, 'base64').toString('utf8'));
    admin.initializeApp({ credential: admin.credential.cert(key) });
  } else {
    admin.initializeApp();
  }
}

async function getDriveClient() {
  const keyJson = JSON.parse(Buffer.from(process.env.GOOGLE_SA_KEY_JSON, 'base64').toString('utf8'));
  const client = new google.auth.JWT({
    email: keyJson.client_email,
    key: keyJson.private_key,
    scopes: ['https://www.googleapis.com/auth/drive.readonly'],
  });
  await client.authorize();
  return google.drive({ version: 'v3', auth: client });
}

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    return res.status(204).end();
  }

  try {
    const authHeader = req.headers.authorization || '';
    if (!authHeader.startsWith('Bearer ')) return res.status(401).json({ error: 'unauthenticated' });
    const idToken = authHeader.split('Bearer ')[1];
    const decoded = await admin.auth().verifyIdToken(idToken);
    const uid = decoded.uid;

    const APP_ID = process.env.APP_ID || 'kc-capitals-default';
    const profileSnap = await admin.firestore().doc(`artifacts/${APP_ID}/public/profiles/${uid}`).get();
    if (!profileSnap.exists) return res.status(403).json({ error: 'no_profile' });
    const role = profileSnap.data().role;
    if (!['admin', 'member'].includes(role)) return res.status(403).json({ error: 'forbidden' });

    const drive = await getDriveClient();
    const { action } = req.query;

    if (action === 'list') {
      const folderId = req.query.folderId;
      if (!folderId) return res.status(400).json({ error: 'missing_folderId' });
      const q = `'${folderId}' in parents and trashed=false`;
      const resp = await drive.files.list({ q, fields: 'files(id,name,mimeType,size,thumbnailLink,webViewLink,webContentLink)', pageSize: 500 });
      return res.json({ files: resp.data.files });
    } else if (action === 'get') {
      const fileId = req.query.fileId;
      if (!fileId) return res.status(400).json({ error: 'missing_fileId' });
      const r = await drive.files.get({ fileId, alt: 'media' }, { responseType: 'stream' });
      res.setHeader('Content-Type', 'application/octet-stream');
      r.data.pipe(res);
      return;
    } else if (action === 'signedUrl') {
      const fileId = req.query.fileId;
      if (!fileId) return res.status(400).json({ error: 'missing_fileId' });
      const meta = await drive.files.get({ fileId, fields: 'id,name,mimeType,webViewLink,webContentLink' });
      return res.json({ file: meta.data });
    } else {
      return res.status(400).json({ error: 'unknown_action' });
    }
  } catch (err) {
    console.error('driveFiles err', err);
    return res.status(500).json({ error: err.message || 'internal' });
  }
};
JS

# minimal package.json to ensure dependencies installed on Vercel build
if [ ! -f package.json ]; then
  cat > package.json <<PKG
{
  "name": "kc-capitals-vercel",
  "private": true,
  "dependencies": {
    "firebase-admin": "^11.8.0",
    "googleapis": "^121.0.0"
  }
}
PKG
fi

# commit & push
git add -A
git commit -m "feat: drive-backed author library index + api/driveFiles serverless"
git push --set-upstream origin "$GIT_BRANCH"

echo "Branch pushed: $GIT_BRANCH"

# If vercel CLI + token available, trigger deploy
if [ "$VERCEL_TOKEN" != "VERCEL_TOKEN_HERE" ] && command -v vercel >/dev/null 2>&1; then
  echo "Triggering Vercel deploy..."
  vercel --token "$VERCEL_TOKEN" --prod --confirm
  echo "Vercel deploy triggered. Check Vercel dashboard for logs."
else
  echo "VERCEL_TOKEN not provided or vercel CLI not installed. Deployment will be triggered automatically by Vercel after push if project is connected to this repo."
fi

# Post-deploy instructions
cat <<EOF

DONE — branch created and pushed: $GIT_BRANCH

Post-deploy steps (must complete in Vercel dashboard and GCP console):

1) Vercel environment variables (Project Settings > Environment Variables):
   - GOOGLE_SA_KEY_JSON  = <base64 of service account JSON>   (required)
     generate: cat service-account.json | base64 -w0
   - APP_ID = $APP_ID
   - FIREBASE_PROJECT_ID = <your-firebase-project-id>
   - VERCEL_TARGET_DOMAIN = $VERCEL_PROJECT_DOMAIN

2) Share Drive folders with the service account:
   - Get service account email: GCP Console > IAM & Admin > Service Accounts (copy the service account you used to create the key)
   - Drive > Right-click folder > Share > paste SA email > Save
   Folders:
   - Books: $DRIVE_BOOKS_FOLDER
   - Audio: $DRIVE_AUDIO_FOLDER
   - Author data: $DRIVE_AUTHOR_FOLDER

3) Firestore security:
   - Ensure profiles exist at artifacts/$APP_ID/public/profiles/<uid> with role 'admin' or 'member'
   - Test a valid user ID token to call the API

4) Test endpoints after deploy:
   - Library index: https://$VERCEL_PROJECT_DOMAIN/kc-capitals/library/index.json
   - Drive list (example):
     curl "https://$VERCEL_PROJECT_DOMAIN/api/driveFiles?action=list&folderId=$DRIVE_BOOKS_FOLDER" -H "Authorization: Bearer <FIREBASE_ID_TOKEN>"
   - Stream file:
     curl "https://$VERCEL_PROJECT_DOMAIN/api/driveFiles?action=get&fileId=<fileId>" -H "Authorization: Bearer <FIREBASE_ID_TOKEN>" -o ebook.pdf

EOF

# cleanup
cd /
rm -rf "$TMPDIR"

exit 0
