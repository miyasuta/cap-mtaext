#!/bin/bash
set -e

echo "🚀 Starting .mtaext upload"

# Validate required variables
if [[ -z "$CTMS_SERVICE_KEY" || -z "$NODE_ID" || -z "$MTA_ID" || -z "$MTA_VERSION" || -z "$DESCRIPTION" || -z "$MTAEXT_NAME" ]]; then
  echo "❌ Required environment variables are missing"
  exit 1
fi

# Extract values from service key JSON
CLIENT_ID=$(echo "$CTMS_SERVICE_KEY" | sed -n 's/.*"clientid"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
CLIENT_SECRET=$(echo "$CTMS_SERVICE_KEY" | sed -n 's/.*"clientsecret"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
OAUTH_URL=$(echo "$CTMS_SERVICE_KEY" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')/oauth/token
TMS_URL=$(echo "$CTMS_SERVICE_KEY" | sed -n 's/.*"uri"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# Get OAuth token
ACCESS_TOKEN=$(curl -s -X POST "$OAUTH_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" \
  | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

if [[ -z "$ACCESS_TOKEN" ]]; then
  echo "❌ Failed to retrieve access token"
  exit 1
fi

echo "🔐 Access token retrieved"

# First attempt to upload .mtaext
echo "📤 Uploading .mtaext (initial attempt)..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$TMS_URL/v2/nodes/$NODE_ID/mtaExtDescriptors" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@${MTAEXT_NAME};type=application/octet-stream" \
  -F "mtaVersion=${MTA_VERSION}" \
  -F "description=${DESCRIPTION}")

if [[ "$HTTP_STATUS" == "201" ]]; then
  echo "✅ Upload succeeded (201 Created)"
  exit 0
elif [[ "$HTTP_STATUS" != "422" ]]; then
  echo "❌ Upload failed with unexpected status $HTTP_STATUS"
  exit 1
fi

echo "⚠️ Upload failed with 422 — checking for existing descriptor to delete..."

# Search for existing descriptor
EXISTING_ID=$(curl -s -X GET "$TMS_URL/v2/nodes/$NODE_ID/mtaExtDescriptors" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  | awk -v mtaid="$MTA_ID" -v version="$MTA_VERSION" '
    BEGIN { RS="{"; FS="," }
    {
      found_id=""
      found_mtaid=""
      found_version=""
      for (i=1; i<=NF; i++) {
        if ($i ~ /"id"[[:space:]]*:/) {
          gsub(/[^0-9]/, "", $i)
          found_id=$i
        }
        if ($i ~ /"mtaId"[[:space:]]*:/) {
          gsub(/.*:[[:space:]]*"/, "", $i)
          gsub(/"/, "", $i)
          found_mtaid=$i
        }
        if ($i ~ /"mtaVersion"[[:space:]]*:/) {
          gsub(/.*:[[:space:]]*"/, "", $i)
          gsub(/"/, "", $i)
          found_version=$i
        }
      }
      if (found_mtaid == mtaid && found_version == version) {
        print found_id
        exit
      }
    }')

if [[ -z "$EXISTING_ID" ]]; then
  echo "❌ Descriptor with mtaId=$MTA_ID and version=$MTA_VERSION not found, cannot resolve 422"
  exit 1
fi

echo "🗑️ Deleting existing descriptor ID $EXISTING_ID..."
curl -s -X DELETE "$TMS_URL/v2/nodes/$NODE_ID/mtaExtDescriptors/$EXISTING_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
echo "✅ Deleted descriptor"

# Re-upload after deletion
echo "📤 Retrying upload..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$TMS_URL/v2/nodes/$NODE_ID/mtaExtDescriptors" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@${MTAEXT_NAME};type=application/octet-stream" \
  -F "mtaVersion=${MTA_VERSION}" \
  -F "description=${DESCRIPTION}")

if [[ "$HTTP_STATUS" == "201" ]]; then
  echo "✅ Re-upload succeeded"
else
  echo "❌ Re-upload failed with status $HTTP_STATUS"
  exit 1
fi