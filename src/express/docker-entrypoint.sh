#!/bin/sh
set -e

HTML_FILE="/usr/src/app/public/api-form-with-authentication-hostedUI.html"

envsubst '${COGNITO_DOMAIN} ${COGNITO_CLIENT_ID} ${APP_HOST} ${API_BASE_URL}' \
  < "$HTML_FILE" > "$HTML_FILE.tmp" && mv "$HTML_FILE.tmp" "$HTML_FILE"

exec node app.js
