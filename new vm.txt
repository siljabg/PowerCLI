# ------vSphere Targeting Variables tracked below------
$vCenterInstance = "emeazrhvcenterpfb.devpfb.local"
$vCenterUser = "administrator@vsphere.local"
$vCenterPass = "PFBVCenterP4ss!"
# This section logs on to the defined vCenter instance above
Connect-VIServer $vCenterInstance -User $vCenterUser -Password $vCenterPass -WarningAction SilentlyContinue
$StartingIp = “10.244.15.81”
$SubNetMask = “255.255.255.128”
$DefaultGateway = “10.244.15.1”
$DNS = “10.244.15.5"
$NumVMs = 5
$DataStore = “LUN112 RSKP”
$VMNamePrefix = "EMEAZRHTEST1”
$Folder = “Focus”
$Template = "2016ServerTemp"
$Cluster = “DEVPFB”
$OSCustSpec = "Server2016"

# This should be the same local credentials as defined within the template that you are using for the VM. 
$VMLocalUser = "$VMName\Administrator"
$VMLocalPWord = ConvertTo-SecureString -String "PFBVmP4ss" -AsPlainText -Force
$VMLocalCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $VMLocalUser, $VMLocalPWord

# Scriptblock is used to add domain group to local admin group
$AddGroup = '$DomainName = "DEVPFB.local";
             $GroupName = "Developers";
             #$VMName2 = $VMName;
             $AdminGroup = [ADSI]"WinNT://$VMName2/Administrators,group";
             $Group = [ADSI]"WinNT://$DomainName/$GroupName,Group";
             $AdminGroup.Add($Group.Path)'

# This Scriptblock is used to add new VMs to the domain by first defining the domain creds on the machine and then using Add-Computer
$JoinNewDomain = '$DomainUser = "devpfb\Administrator";
                  $DomainPWord = ConvertTo-SecureString -String "PFBVmP4ss" -AsPlainText -Force;
                  $DomainCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DomainUser, $DomainPWord;
                  Add-Computer -DomainName devpfb.local -Credential $DomainCredential;
                  Start-Sleep -Seconds 20;
                  Shutdown /r /t 0'
#Deploy VMs
$VMIP = $StartingIp
For ($count=1;$count -le $NumVMs; $count++) {
    $VMName = $VMNamePrefix + $count
    Get-OSCustomizationSpec -name $OSCustSpec | Get-OSCustomizationNICMapping | Set-OSCustomizationNICMapping -IPMode UseStaticIP -IPAddress $VMIP -SubNetMask $SubNetMask -DefaultGateway $DefaultGateway -dns $DNS
    New-VM -Name $VMName -Template $Template -Datastore $DataStore -ResourcePool $Cluster -Location $Folder -OSCustomizationSpec $OSCustSpec -RunAsync
    $NextIP = $VMIP.Split(“.”)
    $NextIP[3] = [INT]$NextIP[3]+1
    $VMIP = $NextIP -Join“.”
    Start-Sleep -Seconds 20
    
}
#Start VMs
For ($count=1;$count -le $NumVMs; $count++) {
    $VMName = $VMNamePrefix + $count
    While ((Get-VM $VMName).Version -eq “Unknown”) {Write-Host “Waiting to start $VMName”}
    Start-VM $VMName
    Start-Sleep -Seconds 20
   

    # We first verify that the guest customization has finished on on the new VM by using the below loops to look for the relevant events within vCenter. 
 
Write-Verbose -Message "Verifying that Customization for VM $VMName has started ..." -Verbose
	while($True)
	{
		$DCvmEvents = Get-VIEvent -Entity $VMName 
		$DCstartedEvent = $DCvmEvents | Where { $_.GetType().Name -eq "CustomizationStartedEvent" }
 
		if ($DCstartedEvent)
		{
			break	
		}
 
		else 	
		{
			Start-Sleep -Seconds 5
		}
	}
 
Write-Verbose -Message "Customization of VM $VMName has started. Checking for Completed Status......." -Verbose
	while($True)
	{
		$DCvmEvents = Get-VIEvent -Entity $VMName 
		$DCSucceededEvent = $DCvmEvents | Where { $_.GetType().Name -eq "CustomizationSucceeded" }
        $DCFailureEvent = $DCvmEvents | Where { $_.GetType().Name -eq "CustomizationFailed" }
 
		if ($DCFailureEvent)
		{
			Write-Warning -Message "Customization of VM $VMName failed" -Verbose
            return $False	
		}
 
		if ($DCSucceededEvent) 	
		{
            break
		}
        Start-Sleep -Seconds 5
	}
Write-Verbose -Message "Customization of VM $VMName Completed Successfully!" -Verbose

# NOTE - The below Sleep command is to help prevent situations where the post customization reboot is delayed slightly causing
# the Wait-Tools command to think everything is fine and carrying on with the script before all services are ready. Value can be adjusted for your environment. 
Start-Sleep -Seconds 30
Write-Verbose -Message "Waiting for VM $VMName to complete post-customization reboot." -Verbose 
Wait-Tools -VM $VMName -TimeoutSeconds 300
# NOTE - Another short sleep here to make sure that other services have time to come up after VMware Tools are ready. 
Start-Sleep -Seconds 30

# The Below Cmdlets actually add the VM to the newly deployed domain.
Invoke-VMScript -ScriptText $JoinNewDomain -VM $VMName -GuestCredential $VMLocalCredential

# Below sleep command is in place as the reboot needed from the above command doesn't always happen before the wait-tools command is run
Start-Sleep -Seconds 30
Wait-Tools -VM $VMName -TimeoutSeconds 300
Write-Verbose -Message "VM $VMName Added to Domain and Successfully Rebooted." -Verbose

Invoke-VMScript -ScriptText $AddGroup -VM $VMName -GuestCredential $VMLocalCredentia
#Write-verbose -Message "Successfully Added $GroupName to local administrators group of $VMName" -Verbose
Write-Verbose -Message "Environment Setup Complete" -Verbose
# End of Script