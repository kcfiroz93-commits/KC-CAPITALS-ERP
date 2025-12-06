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
