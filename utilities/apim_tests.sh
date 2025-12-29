curl https://api-d.das.nl/claims/v1/claims \
    -H 'Authorization: bearer test.mijndas' \
    -H 'Ocp-Apim-Subscription-Key: cf20569d12b145fd9f49677c2594e34e' -f -v



curl https://apim-shared-d-we-001.azure-api.net/claims/v1/claims \
    -H 'Authorization: bearer test.mijndas' \
    -H 'Ocp-Apim-Subscription-Key: cf20569d12b145fd9f49677c2594e34e' -f -v

curl https://apim-shared-s-we-001.azure-api.net/claims/v1/claims \
    -H 'Authorization: bearer test.mijndas' \
    -H 'Ocp-Apim-Subscription-Key: 8c2a6b793ad841bba371ae495fffeb96' -f -v

curl https://apim-shared-d-we-001.azure-api.net/dmscontent/v1/ping -H 'Ocp-Apim-Subscription-Key: fa5a1d2615294117a5c661c4d2d0e4e1' -f -v

curl https://apim-shared-s-we-001.azure-api.net/status-0123456789abcef -v --max-time 1 -f
curl https://apim-shared-d-we-001.azure-api.net/status-0123456789abcef -v --max-time 1 -f
curl https://apim-shared-t-we-001.azure-api.net/status-0123456789abcef -v --max-time 1 -f
curl https://apim-shared-a-we-001.azure-api.net/status-0123456789abcef -v --max-time 1 -f
curl https://apim-shared-p-we-001.azure-api.net/status-0123456789abcef -v --max-time 1 -f