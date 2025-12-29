#!/bin/bash

# DvA API curl commands for Dev Environment
# Generated from Postman collection

# Environment variables - replace with actual values
export API_BASE_URL="https://api-d.das.nl"
export TOKEN="test.mijndas"
export DVA_PORTAAL_SUBSCRIPTION_KEY="YOUR_DVA_PORTAAL_SUBSCRIPTION_KEY"
export OFFERS_API_SUBSCRIPTION_KEY="YOUR_OFFERS_API_SUBSCRIPTION_KEY"
export EMPLOYEE_EMAIL="yscheale29333@tdis.nl"
export DAS_DVA_RC="210100"
export CLAIM_ID="7.17.000588"
export AGREEMENT_ID="090406"

echo "# DvA API curl commands for Dev Environment"
echo "# Make sure to set the environment variables above with actual values"
echo ""

# Accounts API
echo "## Accounts API"
echo ""

echo "### Get Account By Account Name"
cat << 'EOF'
curl -X PATCH "${API_BASE_URL}/accounts/v1/dva/GetAccountByAccountName" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${DVA_PORTAAL_SUBSCRIPTION_KEY}" \
  -d '{
    "accountName": "test.dva@gmail.com"
  }'
EOF
echo ""

echo "### Create Account"
cat << 'EOF'
curl -X POST "${API_BASE_URL}/accounts/v1/dva/CreateAccount" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${DVA_PORTAAL_SUBSCRIPTION_KEY}" \
  -d '{
    "displayName": "Test User",
    "givenName": "Test",
    "surname": "User",
    "emailAddress": "test.user@example.com",
    "phoneNumber": "0612345678"
  }'
EOF
echo ""

echo "### Delete Account"
cat << 'EOF'
curl -X DELETE "${API_BASE_URL}/accounts/v1/dva/DeleteAccount/auth0|587aa17a-e10c-447b-8142-64f63418cf10" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${DVA_PORTAAL_SUBSCRIPTION_KEY}"
EOF
echo ""

# Agreements API
echo "## Agreements API"
echo ""

echo "### Get Agreements"
cat << 'EOF'
curl -X GET "${API_BASE_URL}/agreements/v1/agreements" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${DVA_PORTAAL_SUBSCRIPTION_KEY}" \
  -H "DAS-DvA-RC: ${DAS_DVA_RC}"
EOF
echo ""

echo "### Get Agreements By Search"
cat << 'EOF'
curl -X GET "${API_BASE_URL}/agreements/v1/agreements-by-search?searchParameter=&take=10&skip=0&orderBy=startingDate&sortBy=descending&skipCache=true" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${DVA_PORTAAL_SUBSCRIPTION_KEY}" \
  -H "DAS-DvA-RC: ${DAS_DVA_RC}"
EOF
echo ""

echo "### Get Agreement Details"
cat << 'EOF'
curl -X GET "${API_BASE_URL}/agreements/v1/agreements/details/${AGREEMENT_ID}" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${DVA_PORTAAL_SUBSCRIPTION_KEY}" \
  -H "DAS-DvA-RC: ${DAS_DVA_RC}"
EOF
echo ""

# Claims API
echo "## Claims API"
echo ""

echo "### Get Claims"
cat << 'EOF'
curl -X GET "${API_BASE_URL}/claims/v1/claims" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${DVA_PORTAAL_SUBSCRIPTION_KEY}" \
  -H "DAS-DvA-RC: ${DAS_DVA_RC}"
EOF
echo ""

echo "### Get Claims By Search"
cat << 'EOF'
curl -X GET "${API_BASE_URL}/claims/v1/claims-by-search?take=10&skip=0&orderBy=nummer&sortBy=descending" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${DVA_PORTAAL_SUBSCRIPTION_KEY}" \
  -H "DAS-DvA-RC: ${DAS_DVA_RC}"
EOF
echo ""

echo "### Get Claim Details"
cat << 'EOF'
curl -X GET "${API_BASE_URL}/claims/v1/claims/${CLAIM_ID}" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${DVA_PORTAAL_SUBSCRIPTION_KEY}" \
  -H "DAS-DvA-RC: ${DAS_DVA_RC}"
EOF
echo ""

# Deployteq API
echo "## Deployteq API"
echo ""

echo "### Send Email - Verzoek Van Adviseur Voor Inzage Dossier Klant"
cat << 'EOF'
curl -X POST "${API_BASE_URL}/deployteq-api/V1/SendEmail" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${DVA_PORTAAL_SUBSCRIPTION_KEY}" \
  -d '{
    "templateId": "VerzoekVanAdviseurVoorInzageDossierKlant",
    "to": "example@example.com",
    "data": {
      "adviseurNaam": "John Doe",
      "klantNaam": "Jane Doe"
    }
  }'
EOF
echo ""

# Documents API
echo "## Documents API"
echo ""

echo "### Get Claim Documents Metadata"
cat << 'EOF'
curl -X GET "${API_BASE_URL}/documents/V1/claims/${CLAIM_ID}/metadata" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${DVA_PORTAAL_SUBSCRIPTION_KEY}" \
  -H "DAS-DvA-RC: ${DAS_DVA_RC}"
EOF
echo ""

echo "### Get Agreement Documents Metadata"
cat << 'EOF'
curl -X GET "${API_BASE_URL}/documents/V1/agreements/${AGREEMENT_ID}/metadata" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${DVA_PORTAAL_SUBSCRIPTION_KEY}" \
  -H "DAS-DvA-RC: ${DAS_DVA_RC}"
EOF
echo ""

# Offers API
echo "## Offers API"
echo ""

echo "### Find AFD Codes"
cat << 'EOF'
curl -X GET "${API_BASE_URL}/offers-api/V1/find/afd-code?searchParameter=conc&take=5&skip=0" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${OFFERS_API_SUBSCRIPTION_KEY}" \
  -H "DAS-DvA-RC: ${DAS_DVA_RC}"
EOF
echo ""

echo "### Calculate Quote"
cat << 'EOF'
curl -X POST "${API_BASE_URL}/offers-api/V1/calculate" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${OFFERS_API_SUBSCRIPTION_KEY}" \
  -H "DAS-DvA-RC: ${DAS_DVA_RC}" \
  -d '{
    "productCode": "RECHTSBIJSTAND",
    "startDate": "2024-01-01",
    "endDate": "2024-12-31"
  }'
EOF
echo ""

# Parties API
echo "## Parties API"
echo ""

echo "### Search Parties"
cat << 'EOF'
curl -X GET "${API_BASE_URL}/parties/V1/search?query=test&take=10&skip=0" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${DVA_PORTAAL_SUBSCRIPTION_KEY}" \
  -H "DAS-DvA-RC: ${DAS_DVA_RC}"
EOF
echo ""

# Users API
echo "## Users API"
echo ""

echo "### Get User Info"
cat << 'EOF'
curl -X GET "${API_BASE_URL}/users-api/V1/dva/userinfo" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${DVA_PORTAAL_SUBSCRIPTION_KEY}" \
  -H "DAS-DvA-RC: ${DAS_DVA_RC}"
EOF
echo ""

echo "### Validate Employee"
cat << 'EOF'
curl -X POST "${API_BASE_URL}/users-api/V1/dva/validateEmployee" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${DVA_PORTAAL_SUBSCRIPTION_KEY}" \
  -d '{
    "emailAddress": "'${EMPLOYEE_EMAIL}'"
  }'
EOF
echo ""

# Client Coverage API (PDBi)
echo "## Client Coverage API (PDBi)"
echo ""

echo "### Get Client Coverage"
cat << 'EOF'
curl -X GET "${API_BASE_URL}/clientcoverage/V1/coverage?clientId=12345" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Ocp-Apim-Subscription-Key: ${DVA_PORTAAL_SUBSCRIPTION_KEY}" \
  -H "DAS-DvA-RC: ${DAS_DVA_RC}"
EOF
echo ""

echo "# Usage Instructions:"
echo "# 1. Set the environment variables at the top of this script with actual values"
echo "# 2. Source this script: source generate_curls.sh"
echo "# 3. Run any of the curl commands above"
echo "# 4. For tokens, get them from: https://api-d.das.nl/auth/access-token"