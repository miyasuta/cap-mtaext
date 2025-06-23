#!/bin/bash
set -e

echo "🚀 Starting .mtaext upload"

# Check if required environment variables are set
if [[ -z "$CTMS_SERVICE_KEY" || -z "$NODE_ID" || -z "$MTA_VERSION" || -z "$DESCRIPTION" || -z "$MTAEXT_NAME" ]]; then
  echo "❌ Required environment variables are missing"
  exit 1
fi

# Extract authentication information from Service Key (without jq)
CLIENT_ID=$(echo "$CTMS_SERVICE_KEY" | sed -n 's/.*"clientid"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
CLIENT_SECRET=$(echo "$CTMS_SERVICE_KEY" | sed -n 's/.*"clientsecret"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
OAUTH_URL=$(echo "$CTMS_SERVICE_KEY" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')/oauth/token
TMS_URL=$(echo "$CTMS_SERVICE_KEY" | sed -n 's/.*"uri"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# Get access token
ACCESS_TOKEN=$(curl -s -X POST "$OAUTH_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" \
  | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

if [[ -z "$ACCESS_TOKEN" ]]; then
  echo "❌ Failed to retrieve access token"
  exit 1
fi

# Upload .mtaext file
curl -s -X POST "$TMS_URL/v2/nodes/$NODE_ID/mtaExtDescriptors" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@${MTAEXT_NAME};type=application/octet-stream" \
  -F "mtaVersion=${MTA_VERSION}" \
  -F "description=${DESCRIPTION}"

echo "✅ Upload completed"