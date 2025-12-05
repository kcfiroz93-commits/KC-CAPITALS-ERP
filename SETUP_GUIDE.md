# Drive-Backed Author Library — Setup & Deployment Guide

## ✅ What's Ready

Your repository now has the `content/drive-integration` branch with:

- **`api/driveFiles.js`** — Vercel serverless API for secure Drive file access
- **`public/kc-capitals/library/index.json`** — Master library metadata (includes local file paths and Drive folder IDs)
- **`public/kc-capitals/library/README.md`** — Library documentation
- **`deploy_author_library.sh`** — Automated deployment script (for use if needed)
- **`package.json`** — Dependencies pre-configured

## 🚀 Immediate Next Steps

### 1. **Vercel Auto-Deploy**
Vercel will automatically detect the new branch and deploy it. Check your Vercel dashboard:
- Project: KC Capitals ERP
- Branch: `content/drive-integration`
- Status: Building/Deployed

### 2. **Set Vercel Environment Variables**
Go to **Vercel > Project Settings > Environment Variables** and add these for all environments (Production, Preview, Development):

```
APP_ID=kc-capitals-default
FIREBASE_PROJECT_ID=<your-firebase-project-id>
GOOGLE_SA_KEY_JSON=<BASE64_ENCODED_SERVICE_ACCOUNT_JSON>
VERCEL_TARGET_DOMAIN=<your-vercel-domain>.vercel.app
```

**How to generate `GOOGLE_SA_KEY_JSON`:**
```bash
cat /path/to/service-account-key.json | base64 -w0 > sa_base64.txt
# Copy the entire output into GOOGLE_SA_KEY_JSON environment variable
```

### 3. **Share Drive Folders with Service Account**
Get your service account email:
1. GCP Console → IAM & Admin → Service Accounts
2. Copy the service account email (format: `xxx@xxx.iam.gserviceaccount.com`)

Then share each folder:
- Open Google Drive → Locate each folder
- Right-click → Share
- Paste service account email
- Give **Editor** (or **Viewer** if read-only)
- Save

**Folders to share:**
- Books: `15xytBltrBN7ikK4yTr8FS6mRUQzNeAKn`
- Audio: `1UOFQX_8l--aJ2127lv2_0ApZyrEvCO-I`
- Author: `1BpZVEKZ6QZDhyJywZxn50JvANnQEOpov`

### 4. **Configure Firestore Profiles**
Ensure user profiles exist at the correct path:

**Path:** `artifacts/kc-capitals-default/public/profiles/{uid}`

**Example document:**
```json
{
  "role": "admin",
  "email": "user@example.com",
  "name": "User Name"
}
```

Valid roles: `admin`, `member` (API will deny access otherwise)

### 5. **Test the API**
Once deployed, test with a valid Firebase ID token:

```bash
# Get a Firebase ID token from your client or use Admin SDK:
# firebase auth create-custom-token --uid=testuser

# List files in Books folder
curl "https://<your-vercel-domain>/api/driveFiles?action=list&folderId=15xytBltrBN7ikK4yTr8FS6mRUQzNeAKn" \
  -H "Authorization: Bearer <FIREBASE_ID_TOKEN>"

# Get file metadata
curl "https://<your-vercel-domain>/api/driveFiles?action=signedUrl&fileId=<FILE_ID>" \
  -H "Authorization: Bearer <FIREBASE_ID_TOKEN>"

# Stream file
curl "https://<your-vercel-domain>/api/driveFiles?action=get&fileId=<FILE_ID>" \
  -H "Authorization: Bearer <FIREBASE_ID_TOKEN>" \
  -o downloaded-file.pdf
```

### 6. **Local File Path References**
Your original files are referenced (not stored in repo to keep size small):

- `/mnt/data/KC Capitals_mockup.pdf`
- `/mnt/data/2025 THE YEAR OF MIRACLE_250106_032129.pdf`

These paths are in `index.json` under `localPath` so your pipeline can map them to Drive or hosted URLs.

## 📋 What Each Endpoint Does

### `/api/driveFiles?action=list&folderId=<FOLDER_ID>`
Lists all files in a Drive folder (requires auth + admin/member role)

**Response:**
```json
{
  "files": [
    {
      "id": "file-id-123",
      "name": "The Year of Miracle.pdf",
      "mimeType": "application/pdf",
      "size": 5242880,
      "webViewLink": "https://drive.google.com/file/d/...",
      "webContentLink": "https://drive.google.com/uc?id=..."
    }
  ]
}
```

### `/api/driveFiles?action=get&fileId=<FILE_ID>`
Streams file bytes (requires auth)

**Returns:** File binary data with correct Content-Type header

### `/api/driveFiles?action=signedUrl&fileId=<FILE_ID>`
Returns file metadata for building web links (requires auth)

**Response:**
```json
{
  "file": {
    "id": "file-id-123",
    "name": "book.pdf",
    "mimeType": "application/pdf",
    "webViewLink": "https://drive.google.com/file/d/...",
    "webContentLink": "https://drive.google.com/uc?id=..."
  }
}
```

## 🔒 Security

✅ All endpoints require Firebase ID token verification  
✅ Role-based access control (admin/member only)  
✅ Firestore profile check  
✅ CORS headers set appropriately  

## 📂 Library Index Structure

**File:** `public/kc-capitals/library/index.json`

Each item includes:
- `id` — Unique identifier
- `title` — Display name
- `file_pdf` — PDF path
- `localPath` — Original upload location
- `driveFolderId` — Google Drive folder ID
- `driveFileId` — Drive file ID (empty until synced)
- `file_epub` — EPUB path (for e-readers)
- `file_audio` — Audio/MP3 path
- `cover` — Cover image path
- `published_by` — Author/publisher name

## 🛠️ Manual Deployment (if needed)

If Vercel auto-deploy doesn't trigger or you need to deploy manually:

```bash
# Install Vercel CLI
npm i -g vercel

# Deploy from repo root
vercel --prod
```

## 📞 Troubleshooting

**401 Unauthorized:**
- Check Firebase ID token is valid and current
- Verify token is in Bearer format: `Authorization: Bearer <token>`

**403 Forbidden:**
- User doesn't have a profile in Firestore at the expected path
- User profile missing `role` field or role is not 'admin' or 'member'

**500 Internal Error:**
- `GOOGLE_SA_KEY_JSON` not set or malformed (must be base64)
- Service account lacks Drive read permissions
- Drive folder not shared with service account email

**Files not found:**
- Confirm folders are shared with the service account (not just your user)
- Check folder ID is correct in request

## 🎯 Next: Frontend Integration

When ready to consume the API from your React/Next.js app:

```javascript
// Example fetch with Firebase Auth token
const token = await user.getIdToken();
const response = await fetch(
  `/api/driveFiles?action=list&folderId=15xytBltrBN7ikK4yTr8FS6mRUQzNeAKn`,
  { headers: { Authorization: `Bearer ${token}` } }
);
const { files } = await response.json();
```

---

**Branch:** `content/drive-integration`  
**Deployed to:** Vercel (auto on push)  
**Status:** Ready for testing
