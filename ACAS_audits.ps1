#audit_templates 9 Mar 2022
#This script will use a csv containing a list of audits to load into SecurityCener and load them for you
#the $audits or $auditTemplates can be exported to csv and edited for review of installed audits and to create/update the IncomingAudits list. 
# review of 'replaces' field is showing invalid for DISA STIGS. Code utilizing it is commented out.

#Ignore self signed certificates 
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true} ; 
#Set Tls12
[Net.ServicePointManager]::Securityprotocol= [Net.SecurityProtocolType]::Tls12 

#variables 
$hostname = "https://acas.host/rest" 

#prompt for credentials 
#$LoginCreds = Get-Credential 
#$username = $LoginCreds.UserName 
#$password = $loginCreds.GetNetworkCredential().Password
 
#hardcode creds - not recommended, doing it anyway cause trusting in team 
$username = "<user_account>" 
$password = "<user_accout_PW>"


# Build credentials object 
$LoginData = (ConvertTo-json -compress @{username=$username; password=$password}) 

# Login to SC5 (Smartcard thumbprint is needed when using 2-factor login to ACAS)
$ret = Invoke-RestMethod -URI $hostname/token -Method POST -Body $LoginData -SessionVariable sv -CertificateThumbprint 123456789abcdefg123456789abcdefg12345678  

# extract the token 
$loginToken = $ret.response.token
Write-Host "Login Successful."

# get auditfile listing - for reference if unsure what you have currently loaded
$audits = Invoke-RestMethod -URI $hostname"/auditFile?fields=id,name,description,type,status,groups,creator,version,createdTime,modifiedTime,lastRefreshedTime,auditFileTemplate" -Headers @{"X-SecurityCenter"="$loginToken"} -Websession $sv
Write-Host "Audits retrieved."
$audits.response.usable | export-csv -NoTypeInformation -path "Loaded_audits_ddmmyy.csv"

# get auditfile template listing in feed - you can export this to csv and edit it to make your tailored csv for use in the code below
$auditTemplates = Invoke-RestMethod -URI $hostname"/auditFileTemplate?fields=id,name,type,version,replaces" -Headers @{"X-SecurityCenter"="$loginToken"} -Websession $sv
Write-Host "Audit templates retrieved."
$auditTemplates.response | export-csv -NoTypeInformation -path "Latest_feed_audits_ddmmyy.csv" #uncomment this to write the available auditlist from the sc feed

# load auditlist of templates to import from feed
$auditlist = Import-Csv -Path "IncomingAudits.csv"
write-host "Auditlist CSV Loaded."

foreach ($i in $auditlist) {
    Write-Host -NoNewline "ID: "$i.id
    if($audits.response.usable.auditfiletemplate.id.contains($i.id)){
        write-host -NoNewline " is loaded in SC already"
        $id = $audits.response.usable.auditFileTemplate.id.IndexOf($i.id) #index of the already loaded audit
        $tid=$auditTemplates.response.id.IndexOf($i.id) #index of the same audit in the feed
        if($auditTemplates.response.id.contains($i.id) -and (($audits.response.usable.name[$id] -ne $auditTemplates.response.name[$tid]) -or ($audits.response.usable.version[$id] -lt $auditTemplates.response.version[$tid]))) {
            write-host " and feed is newer. Refreshing Audit."
            write-host "compared items: " $audits.response.usable.name[$id] $id $auditTemplates.response.name[$tid]
            # FIXME - do a refresh of the audit
            $rid = $audits.response.usable.id[$id]
            $body  = (ConvertTo-json -compress @{name=$auditTemplates.response.name[$tid];description="Refreshed via scripting"}) #put in the new name of the refreshed audit
            $ret = Invoke-RestMethod —URI $hostname/auditFile/$rid/refresh —Method Post -Headers @{"X-SecurityCenter"="$loginToken"} -Websession $sv
            Start-Sleep -Second 1 #added delay to try and not overload the lame ass SQLite system.
            $ret = Invoke-RestMethod —URI $hostname/auditFile/$rid —Method Patch -Body $Body -Headers @{"X-SecurityCenter"="$loginToken"} -Websession $sv
            }
        else{write-host "."}
    }
    else{write-host -NoNewline " is NOT loaded in SC "
        if($auditTemplates.response.id.contains($i.id)){
            write-host "but is live in SC Feed. Adding Audit"
            #FIXME - do an audit add
            $uri = $hostname + "/auditFileTemplate/" + $i.id
            $audittmp = Invoke-RestMethod -URI $uri -Headers @{"X-SecurityCenter"="$loginToken"} -Websession $sv #gets the desired auditTemplate info
            $editor = $audittmp.response.editor | ConvertFrom-Json #extracts the varaiables for possible editing
            $variables = @()
            foreach($var in $editor) {
                $variables += New-Object psobject -property @{"name" = $var.id; "value" = $var.default}
                }
            # put it all back together and add to SC as a new audit
            $NewAudit = @{name=$audittmp.response.name; description="Uploaded via scripting"; auditFileTemplate=@{id=$audittmp.response.id};variables=$variables} 
	        $NewAudit = (ConvertTo-json —Compress $NewAudit)
	        $ret = Invoke-RestMethod —URI $hostname/auditFile —Method Post -body $NewAudit -Headers @{"X-SecurityCenter"="$loginToken"} -Websession $sv

        }
        else{write-host -NoNewline "and is NOT in SC Feed. "           
        }
    }
    

}


#logout when done
$ret = Invoke-RestMethod -URI $hostname/token -Method Delete -Headers @{"X-SecurityCenter"="$loginToken"} -Websession $sv

