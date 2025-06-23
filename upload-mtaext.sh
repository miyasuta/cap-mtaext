#!/bin/bash
set -e

echo "🚀 Starting .mtaext upload"

# Check if required environment variables are set
if [[ -z "$CTMS_SERVICE_KEY" || -z "$NODE_ID" || -z "$MTA_ID" || -z "$MTA_VERSION" || -z "$DESCRIPTION" || -z "$MTAEXT_NAME" ]]; then
  echo "❌ Required environment variables are missing"
  exit 1
fi

# Extract authentication information
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

echo "🔐 Access token retrieved"

# Check for existing descriptor
echo "🔍 Checking for existing descriptors..."
EXISTING_ID=$(curl -s -X GET "$TMS_URL/v2/nodes/$NODE_ID/mtaExtDescriptors" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  | awk -v mtaid="$MTA_ID" -v version="$MTA_VERSION" '
    BEGIN { RS="{"; FS="," }
    $0 ~ "\"mtaId\"" && $0 ~ mtaid && $0 ~ "\"mtaVersion\"" && $0 ~ version {
      for (i=1; i<=NF; i++) {
        if ($i ~ /"id"[[:space:]]*:/) {
          gsub(/[^0-9]/, "", $i);
          print $i;
          exit
        }
      }
    }')

# Delete existing if found
if [[ -n "$EXISTING_ID" ]]; then
  echo "🗑️ Found existing descriptor ID $EXISTING_ID — deleting..."
  curl -s -X DELETE "$TMS_URL/v2/nodes/$NODE_ID/mtaExtDescriptors/$EXISTING_ID" \
    -H "Authorization: Bearer $ACCESS_TOKEN"
  echo "✅ Deleted existing descriptor"
else
  echo "✅ No existing descriptor found"
fi

# Upload new .mtaext and check status
echo "📤 Uploading new .mtaext..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$TMS_URL/v2/nodes/$NODE_ID/mtaExtDescriptors" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@${MTAEXT_NAME};type=application/octet-stream" \
  -F "mtaVersion=${MTA_VERSION}" \
  -F "description=${DESCRIPTION}")

if [[ "$HTTP_STATUS" != "201" ]]; then
  echo "❌ Upload failed with status $HTTP_STATUS"
  exit 1
fi

echo "✅ Upload completed (201 Created)"
