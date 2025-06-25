
const fs = require('fs');
const axios = require('axios');
const FormData = require('form-data');

// Validate required environment variables
const {
  CTMS_SERVICE_KEY,
  NODE_ID,
  MTA_ID,
  MTA_VERSION,
  DESCRIPTION,
  MTAEXT_NAME
} = process.env;

if (!CTMS_SERVICE_KEY || !NODE_ID || !MTA_ID || !MTA_VERSION || !DESCRIPTION || !MTAEXT_NAME) {
  console.error("❌ Required environment variables are missing");
  process.exit(1);
}

console.log("🚀 Starting .mtaext upload");

let serviceKey;
try {
  serviceKey = JSON.parse(CTMS_SERVICE_KEY);
} catch (err) {
  console.error("❌ Failed to parse CTMS_SERVICE_KEY as JSON");
  process.exit(1);
}

const CLIENT_ID = serviceKey.clientid;
const CLIENT_SECRET = serviceKey.clientsecret;
const OAUTH_URL = serviceKey.url + '/oauth/token';
const TMS_URL = serviceKey.uri;

async function getAccessToken() {
  try {
    const response = await axios.post(OAUTH_URL, new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET
    }), {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
    });
    return response.data.access_token;
  } catch (err) {
    console.error("❌ Failed to retrieve access token");
    process.exit(1);
  }
}

async function uploadMtaext(token) {
  const form = new FormData();
  form.append('file', fs.createReadStream(MTAEXT_NAME));
  form.append('mtaVersion', MTA_VERSION);
  form.append('description', DESCRIPTION);

  try {
    const response = await axios.post(`${TMS_URL}/v2/nodes/${NODE_ID}/mtaExtDescriptors`, form, {
      headers: {
        ...form.getHeaders(),
        Authorization: `Bearer ${token}`
      },
      validateStatus: () => true
    });

    return response.status;
  } catch (err) {
    console.error("❌ Upload request failed", err.message);
    process.exit(1);
  }
}

async function findAndDeleteExistingDescriptor(token) {
  try {
    const res = await axios.get(`${TMS_URL}/v2/nodes/${NODE_ID}/mtaExtDescriptors`, {
      headers: { Authorization: `Bearer ${token}` }
    });

    const match = res.data.mtaExtDescriptors.find(d => d.mtaId === MTA_ID && d.mtaVersion === MTA_VERSION);
    if (!match) {
      console.error(`❌ Descriptor with mtaId=${MTA_ID} and version=${MTA_VERSION} not found`);
      process.exit(1);
    }

    console.log(`🗑️ Deleting existing descriptor ID ${match.id}...`);
    await axios.delete(`${TMS_URL}/v2/nodes/${NODE_ID}/mtaExtDescriptors/${match.id}`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    console.log("✅ Deleted descriptor");
  } catch (err) {
    console.error("❌ Failed to find/delete existing descriptor", err.message);
    process.exit(1);
  }
}

async function main() {
  const token = await getAccessToken();
  console.log("🔐 Access token retrieved");

  console.log("📤 Uploading .mtaext (initial attempt)...");
  const status = await uploadMtaext(token);

  if (status === 201) {
    console.log("✅ Upload succeeded (201 Created)");
    process.exit(0);
  } else if (status !== 422) {
    console.error(`❌ Upload failed with unexpected status ${status}`);
    process.exit(1);
  }

  console.warn("⚠️ Upload failed with 422 — checking for existing descriptor to delete...");
  await findAndDeleteExistingDescriptor(token);

  console.log("📤 Retrying upload...");
  const retryStatus = await uploadMtaext(token);
  if (retryStatus === 201) {
    console.log("✅ Re-upload succeeded");
  } else {
    console.error(`❌ Re-upload failed with status ${retryStatus}`);
    process.exit(1);
  }
}

main();
