BASE_URL="https://apim-shared-d-we-001.azure-api.net"

curl $BASE_URL/status-0123456789abcdef --max-time 1 -fv 2>&1 | grep "200 OK" >/dev/null

curl https://apim-shared-d-we-001.azure-api.net/claims/v1/claims -H 'Authorization: Bearer test.mijndas' -H 'Ocp-Apim-Subscription-Key: cf20569d12b145fd9f49677c2594e34e' -f -v
curl https://apim-shared-d-we-001.azure-api.net/dmscontent/v1/ping -H 'Ocp-Apim-Subscription-Key: fa5a1d2615294117a5c661c4d2d0e4e1' -f -v