#!/bin/bash
set -e

echo "🚀 Starting .mtaext upload"

# Check if required environment variables are set
if [[ -z "$CTMS_SERVICE_KEY" || -z "$NODE_ID" || -z "$MTA_VERSION" || -z "$DESCRIPTION" || -z "$MTAEXT_NAME" ]]; then
  echo "❌ Required environment variables are missing"
  exit 1
fi

# Extract authentication information from Service Key
CLIENT_ID=$(echo "$CTMS_SERVICE_KEY" | jq -r '.clientid')
CLIENT_SECRET=$(echo "$CTMS_SERVICE_KEY" | jq -r '.clientsecret')
OAUTH_URL=$(echo "$CTMS_SERVICE_KEY" | jq -r '.url')/oauth/token
TMS_URL=$(echo "$CTMS_SERVICE_KEY" | jq -r '.uri')

# Get access token
ACCESS_TOKEN=$(curl -s -X POST "$OAUTH_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" | jq -r '.access_token')

# Upload .mtaext
curl -s -X POST "$TMS_URL/v2/nodes/$NODE_ID/mtaExtDescriptors" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@${MTAEXT_NAME};type=application/octet-stream" \
  -F "mtaVersion=${MTA_VERSION}" \
  -F "description=${DESCRIPTION}"

echo "✅ Upload completed"
