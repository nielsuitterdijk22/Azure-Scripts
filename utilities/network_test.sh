nslookup api.das.nl

# Next - CRM
ping crmt1.das.local
ping crma1.das.local
ping crmp1.das.local

# VIS + 
ping dasamsdbso1.das.local
# ping dasamsdbst1.das.local -- ze hebben geen T
ping dasamsdbac1.das.local
ping dasamsdbpr1.das.local

# Semlab - CoE AI - Dossier Classificatie
ping dasamsjbts1.das.local
ping dasamsjbpr1.das.local
ping semlaba1.das.local

# Datek - 'op de nominatie om er uit te gaan' - brieven / tekstcreatie
# ping dateko1.das.local
# ping datekt1.das.local -- geen T
ping dateka1.das.local
ping datekp1.das.local

# DD3
ping dd3dbt1.das.local

# DMS
ping dms-dev.das.local
ping api-dms-auth.das.local

# JWP
ping jwpappo1.das.local
ping jwpappt1.das.local
ping jwpappa1.das.local
ping jwpappp1.das.local

ping jwpio.das.local
ping jwpit.das.local
ping jwpia.das.local
ping jwpip.das.local

ping jwpmailo1.das.local
ping jwpmailt1.das.local
ping jwpmaila1.das.local
ping jwpmailp1.das.local

ping jwptomo1.das.local
ping jwptomt1.das.local
ping jwptoma1.das.local
ping jwptomp1.das.local

ping jwpwebo1.das.local
ping jwpwebt1.das.local
ping jwpweba1.das.local
ping jwpwebp1.das.local

# OSB
ping weblogico1.das.local
ping weblogict1.das.local
ping weblogica1.das.local
ping weblogicp1.das.local

# Polis DB
ping polisdbo1.das.local
ping polisdbt1.das.local
ping polisdba1.das.local
ping polisdbp1.das.local

# Internet
curl https://google.com

sas=""
curl -v https://apim-shared-s-we-001.azure-api.net/storagetest/test/securityData.csv?$sas -H 'Ocp-Apim-Subscription-Key: b75ead522027404fbf588a2bd38a8498'
curl https://api-d.das.nl/stat

curl -v --max-time 1 -X GET "https://api-d.das.nl/claims/v1/claims" -H "Ocp-Apim-Subscription-Key: 04d975f212764f45aa036688f6704d0c" -H "'Authorization: test.mijndas"