#Script to copy API management settings from one instance 001 to instance 002 in the same subscription
#execution of this script is manually done under your admin account.
#this script is used to migrate the bulk of APIs from APIM v1 to APIM v2. 
# - it copies products, policies, subscription keys, named values and API definitions
# in same cases errors may occur, these should be checked/repared manually after the migration.
#you can toggle to call function on/off at the end of this script.
#please determine the order to execute the functions.


# Connect-AzAccount
# Set-AzContext -Subscription "DigitalFoundation-D"
# only need to change this variable
$environment = "a"


# rest of the variable does not need to be changed
Set-AzContext -Subscription "DigitalFoundation-$($environment.ToUpper())"
$rg = "rg-shared-$environment-we-001"
$apimv1 = "apim-shared-$environment-we-001"
$apimv2 = "apim-shared-$environment-we-002"

$apimCtxv1 = New-AzApiManagementContext -ResourceGroupName "$rg" -ServiceName "$apimv1"
$apimCtxv2 = New-AzApiManagementContext -ResourceGroupName "$rg" -ServiceName "$apimv2"

function Copy-Policies {
    Write-Host "============================================================="
    Write-Host "COPY POLICIES"
    Write-Host "============================================================="
    $srcPolicies = Get-AzApiManagementPolicy -Context $apimCtxv1
    Set-AzApiManagementPolicy -Context $apimCtxv2 -Policy $srcPolicies
}

function Copy-Certificates {
    Write-Host "============================================================="
    Write-Host "COPY CERTIFICATES"
    Write-Host "============================================================="

    $srcCerts = Get-AzApiManagementCertificate -Context $apimCtxv1
    $trgCerts = Get-AzApiManagementCertificate -Context $apimCtxv2 

    foreach ($srcCert in $srcCerts) {

        $trgCert = $trgCerts | Where-Object CertificateId -eq $srcCert.CertificateId

        if ($null -eq $trgCert) {
            New-AzApiManagementCertificate -Context $apimCtxv2 -CertificateId $srcCert.CertificateId -KeyVault $srcCert.KeyVault
            Write-Host "$($srcCert.CertificateId) - created "
        }
        else {
            Write-Host "$($srcCert.CertificateId) - already exists"
        }

    }
}
function Copy-OCPKeys {
    #To get a list of subscriptions:
    Write-Host ""
    Write-Host "============================================================="
    Write-Host "COPY OCP KEYS"
    Write-Host "============================================================="

    $srcSubs = Get-AzApiManagementSubscription -Context $apimCtxv1
    $trgSubs = Get-AzApiManagementSubscription -Context $apimCtxv2

    foreach ($srcSub in $srcSubs) {

        $trgSub = $trgSubs | Where-Object ProductId -eq $srcSub.ProductId

        if (($null -eq $trgSub) -or ("starter" -eq $trgSub.ProductId) -or ("unlimited" -eq $trgSub.ProductId) -or ($null -eq $trgSub.ProductId) -or ("1" -ne $srcSub.UserId)) {
            Write-Host "$($trgSub.ProductId) - skipped "
        }
        else {
            $keys = Get-AzApiManagementSubscriptionKey -Context $apimCtxv1 -SubscriptionId $srcSub.SubscriptionId
            Set-AzApiManagementSubscription -Context $apimCtxv2 -SubscriptionId $trgSub.SubscriptionId -PrimaryKey $keys.PrimaryKey -SecondaryKey $keys.SecondaryKey -State "Active"
            Write-Host "$($trgSub.ProductId) - updated - $($keys.PrimaryKey) - Owner: $($srcSub.UserId)"
        }

    }
}

function Copy-NamedValues {
    #Copy named values:
    Write-Host ""
    Write-Host "============================================================="
    Write-Host "COPY NAMED VALUES"
    Write-Host "============================================================="

    $srcNVs = Get-AzApiManagementNamedValue -Context $apimCtxv1
    $trgNVs = Get-AzApiManagementNamedValue -Context $apimCtxv2

    foreach ($srcNV in $srcNVs) {

        $trgNV = $trgNVs | Where-Object NamedValueId -eq $srcNV.NamedValueId
        if ("appinsights-key" -eq $trgNV.Name) {
            continue 
        }

        Write-Host $srcNV.Name

        if ($null -eq $srcNV.KeyVault) { #if source value is not a key vault reference
            if ($null -eq $trgNV) {
                if ($true -eq $srcNV.Secret) { #update value
                    $secret = Get-AzApiManagementNamedValueSecretValue -Context $apimCtxv1 -NamedValueId $srcNV.NamedValueId
                    New-AzApiManagementNamedValue -Context $apimCtxv2 -Name $srcNV.Name -NamedValueId $srcNV.NamedValueId -Value $secret -Secret
                    Write-Host "$($srcNV.NamedValueId) - secret value created "
                }
                else { # create new name/value
                    New-AzApiManagementNamedValue -Context $apimCtxv2 -Name $srcNV.Name -NamedValueId $srcNV.NamedValueId -Value $srcNV.Value 
                    Write-Host "$($srcNV.NamedValueId) - value created "
                }
            }
            else { #is keyvault reference
                if ($true -eq $srcNV.Secret) { #update reference
                    $secret = Get-AzApiManagementNamedValueSecretValue -Context $apimCtxv1 -NamedValueId $srcNV.NamedValueId
                    Set-AzApiManagementNamedValue -Context $apimCtxv2 -Name $srcNV.Name -NamedValueId $srcNV.NamedValueId -Value $secret -Secret $true
                    Write-Host "$($trgNV.NamedValueId) - secret value updated "
                }
                else { # create new reference
                    Set-AzApiManagementNamedValue -Context $apimCtxv2 -Name $srcNV.Name -NamedValueId $srcNV.NamedValueId -Value $srcNV.Value 
                    Write-Host "$($trgNV.NamedValueId) - value updated "
                }
            }
        }
        else {
            if ($null -eq $trgNV) {
                $keyvaultsecret = New-AzApiManagementKeyVaultObject -SecretIdentifier $srcNV.KeyVault.SecretIdentifier
                New-AzApiManagementNamedValue -Context $apimCtxv2 -Name $srcNV.Name -NamedValueId $srcNV.NamedValueId -KeyVault $keyvaultsecret -Secret
                Write-Host "$($srcNV.NamedValueId) - keyvault secret created "
            }
            else {
                Write-Host "$($trgNV.NamedValueId) - keyvault secret already exists, skipped "
            }
        }
    }
}

function Copy-Apis {
        #To get a list of subscriptions:
        Write-Host ""
        Write-Host "============================================================="
        Write-Host "COPY API's"
        Write-Host "============================================================="

        
        $srcApiVersionSets = Get-AzApiManagementApiVersionSet -Context $apimCtxv1  
        $trgApiVersionSets = Get-AzApiManagementApiVersionSet -Context $apimCtxv2 
        foreach ($srcApiVersionSet in $srcApiVersionSets) {
            $trgApiVersionSet = $trgApiVersionSets | Where-Object ApiVersionSetId -eq $srcApiVersionSet.ApiVersionSetId
            if ($null -ne $trgApiVersionSet) { # skip existing api's
                continue 
            }

            $srcApiVersionSet | New-AzApiManagementApiVersionSet -Context $apimCtxv2 -ApiVersionSetId $srcApiVersionSet.ApiVersionSetId -Name $srcApiVersionSet.ApiVersionSetId -Scheme Segment

        }

        $srcApis = Get-AzApiManagementApi -Context $apimCtxv1
        $trgApis = Get-AzApiManagementApi -Context $apimCtxv2
        foreach ($srcApi in $srcApis) {
            #$srcApiReleases = Get-AzApiManagementApiRelease -Context $apimCtxv1 -ApiId $srcApi.ApiId
            #$srcApiRevisions = Get-AzApiManagementApiRevision -Context $apimCtxv1 -ApiId $srcApi.ApiRevision 

             $trgApi = $trgApis | Where-Object ApiId -eq $srcApi.ApiId
             if (($null -ne $trgApi) -or ($null -eq $srcApi.ApiId)) { # skip existing api's
                 continue 
             }
    

            #if ($srcApi.Name -ne $srcApis[16].Name)
            #    { continue }

            Write-Host "Creating $($srcApi.Name)" 
            $srcApiProducts = (Get-AzApiManagementProduct -Context $apimCtxv1 -ApiId $srcApi.ApiId).ProductId
            if ($srcApi.SubscriptionRequired) {
                $trgApi = $srcApi | New-AzApiManagementApi -Context $apimCtxv2 -ProductIds $srcApiProducts -SubscriptionRequired
            }
            else {
                $trgApi = $srcApi | New-AzApiManagementApi -Context $apimCtxv2 -ProductIds $srcApiProducts
            }
            Write-Host "- Copying schemas $($trgApi.Name)" 
            $srcApiSchemas = Get-AzApiManagementApiSchema -Context $apimCtxv1 -ApiId $srcApi.ApiId
            foreach ($srcApiSchema in $srcApiSchemas) {
                $trgSchema = $srcApiSchema | New-AzApiManagementApiSchema -Context $apimCtxv2 -ApiId $trgApi.ApiId
            }

            Write-Host "- Copying policy $($trgApi.Name)" 
            $srcApiPolicy = Get-AzApiManagementPolicy -Context $apimCtxv1 -ApiId $srcApi.ApiId
            Set-AzApiManagementPolicy -Context $apimCtxv2 -ApiId $trgApi.ApiId -Policy $srcApiPolicy



            Write-Host "- Copying operations $($trgApi.Name)" 
            $srcApiOpers = Get-AzApiManagementOperation  -Context $apimCtxv1 -ApiId $srcApi.ApiId
            foreach ($srcApiOper in $srcApiOpers) {
                
                
                $trgApiOper = New-AzApiManagementOperation -Context $apimCtxv2 -ApiId $trgApi.ApiId -Name $srcApiOper.Name -OperationId $srcApiOper.OperationId -Method $srcApiOper.Method -UrlTemplate $srcApiOper.UrlTemplate -Description $srcApiOper.Description -TemplateParameters $srcApiOper.TemplateParameters -Responses $srcApiOper.Responses -Request $srcApiOper.Request

                #$srcApiOperPolicy = Get-AzApiManagementPolicy -Context $apimCtxv1 -ApiId $srcApi.ApiId -OperationId $srcApiOper.OperationId
                #Set-AzApiManagementPolicy -Context $apimCtxv2 -ApiId $trgApi.ApiId -OperationId $trgApiOper.OperationId -Policy $srcApiOperPolicy -PolicyFilePath $srcApiOper.  

                Write-Host "  - $($srcApi.Name).$($srcApiOper.Name)" 
            }
        }
    
}


# phase 1:
# Allow APIM identity access to shared keyvault (secrets and crypto officer)

# start copy actions
#Copy-Certificates
#Copy-Policies
#Copy-OCPKeys
#Copy-NamedValues


#phase 2:
# deploy APIs pipeline

#Phase 3:
Copy-Apis

#double check: -> subscription Required UIT
#-Keyprovider API
#-payments
#-paymentsod

#opnieuw uitrollen product koppelingen APIM-Add-APIs-to-Products
#kv-cm-keysprov-a-we-001 subnet van apim v2 niet toegevoegd. geldt dat voor alle key vaults?    


