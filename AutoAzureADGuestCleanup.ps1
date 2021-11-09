<#Automatic clean up for AzureAD/Office365 Guest/External accounts
Accounts that are older than 365 days and have not had any recent Azure AD sign-ins will be deleted.
#>

#You will need to install the AzureADPreview Module on whatever system needs to use this script

import-module AzureADPreview


<# Run this as the account that is going to use the password
# Exporting SecureString from Get-Credential

You'll want to create this first, has to be on the machine and account you intend to run the script from

$creds = Get-Credential
$csvcreds = New-Object psobject
$csvcreds | Add-Member -MemberType NoteProperty -name username -Value $creds.UserName
$csvcreds | Add-Member -MemberType NoteProperty -name password -Value ($creds.Password | ConvertFrom-SecureString)
$csvcreds  | export-csv "C:\AzureCredFile.csv" -NoTypeInformation
#>

# Load the credentials into PowerShell:
$CredFile = import-csv "C:\AzureCredFile.csv"
$MyCredential = New-Object -TypeName System.Management.Automation.PSCredential  -ArgumentList $CredFile.username, ($CredFile.password | ConvertTo-SecureString)

# Use the credential from above automatically
Connect-AzureAD -credential $MyCredential


$ReportPath = "C:\tmp\DeletedAzureGuestsLogs\" #Path of report, modify this to place it elsewhere, should be its own folder
$excludelist = Get-Content "C:\utils\excludelist.txt" #Path of email list of guest uesers to exclude

$timestamp = (Get-Date -Format "yyyy.MM.dd-HH.mm.ss")
$ReportName = "DeletedGuestAccounts-$timestamp.csv" #Report name with timestamp date for unique filenames
$OutputReport = "$ReportPath\$ReportName"
[int]$AgeThreshold = 364 #Modify if you want to change what age of accounts we are looking at to prune
$GuestUsers = Get-AzureADUser -All $true -Filter "UserType eq 'Guest'"  #Grabs all the guest users
$Report = [System.Collections.Generic.List[Object]]::new() #Creates our blank report
$i = $null

# Loop through the guest accounts looking for old accounts 
ForEach ($Guest in $GuestUsers) {

  $i++
  $ProgressBar = "Processing Guest Account " + $Guest.mail + " (" + $i + " of " + $GuestUsers.Count + ")"
  Write-Progress -Activity "Auditing Guest Account Age" -Status $ProgressBar -PercentComplete ($i / $GuestUsers.Count * 100)
  $UserObjectId = $Guest.ObjectId
  $created = ($Guest | Select-Object -ExpandProperty ExtensionProperty).createdDateTime
  $AADAccountAge = ($created | New-TimeSpan).Days
  If ($Guest.mail -notin $excludelist -Or $Guest.DisplayName -notlike "*.maryvale") {

    If ($AADAccountAge -gt $AgeThreshold) {
      start-sleep -Seconds (Get-Random -Minimum 1 -Maximum 15) #sleep a random amount to help avoid "too many requests"
      #    Find the last sign-in date for the guest account
      $UserLastLogonDate = $Null
      $UserLastLogonDate = (Get-AzureADAuditSignInLogs -Top 1  -Filter "userid eq '$UserObjectId' and status/errorCode eq 0").CreatedDateTime
      If ($Null -eq $UserLastLogonDate) {
        #Remove-AzureADUser -ObjectId $UserObjectId -ErrorAction SilentlyContinue #removes the Guest account if above conditions are met
        #Records what account was deleted to the Report
        $ReportLine = [PSCustomObject][Ordered]@{
          UPN               = $Guest.UserPrincipalName
          Name              = $Guest.DisplayName
          Age               = $AADAccountAge
          "Account created" = $created  
          Email             = $Guest.mail
          ObjectID          = $UserObjectId
        }         
        $Report.Add($ReportLine)
      }
    }
  }
}

#exports the Report so we can see what accounts were cleaned up.
$Report | Sort-Object Age | Export-CSV -NoTypeInformation $OutputReport
Disconnect-AzureAD
