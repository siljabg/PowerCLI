#Technical Goals of the Script
#Must be FULLY automated from the moment you hit the enter key to start the script.
#Must provide verbose information for the administrators viewing if desired.
#Must Deploy 2 VMs from pre-existing templates and customization specs.
#Must customize each virtual machine according to the specified customization spec.
#Must be able to define static IP addresses.
#Must configure AD on one of the new VMs and provision a new AD Forest.
#Must create a new custom administrative account within the domain.
#2nd VM must be automatically joined to the newly defined domain.
#File Services must be installed on the second VM
#A new SMB share must be defined on the file server VM, once the file services role is present.

# This Script is Primarily a Deployment Script. It will first deploy a template from your vSphere environment, apply a customization specification, and then install and configure Active
# Directory Domain Services on one VM, and the File Services on another. Additionally the file server will be a member of the newly deployed VM, a new administrative user account will
# be created and a file share will be provisioned on the new file server. 
 
# Script was designed for PowerShell/PowerCLI Beginners who have not yet begun to work with functions and more advanced PowerShell features. 
# The below script first lists all user definable varibles and then executes the script's actions in an easy to follow sequential order. 
 
# Assumptions
# - You Have vCenter inside your environment
# - You have pre-configured templates and customization specifications inside of vCenter
# - Your PowerShell execution policy allows the execution of this script
 
# ------vCenter Targeting Varibles and Connection Commands Below------
# This section insures that the PowerCLI PowerShell Modules are currently active. The pipe to Out-Null can be removed if you desire additional
# Console output.
Get-Module -ListAvailable VMware* | Import-Module | Out-Null
 
# ------vSphere Targeting Variables tracked below------
$vCenterInstance = "VCENTER FQDN HERE"
$vCenterUser = "VCENTER USER ACCOUNT HERE"
$vCenterPass = "VCENTER PASSWORD HERE"
 
# This section logs on to the defined vCenter instance above
Connect-VIServer $vCenterInstance -User $vCenterUser -Password $vCenterPass -WarningAction SilentlyContinue 
 
 
######################################################-User-Definable Variables-In-This-Section-##########################################################################################
 
 
# ------Virtual Machine Targeting Variables tracked below------
 
# The Below Variables define the names of the virtual machines upon deployment, the target cluster, and the source template and customization specification inside of vCenter to use during
# the deployment of the VMs.
$DomainControllerVMName = "DESIRED DC NAME HERE"
$FSVMName = "DESIRED FS NAME HERE"
$TargetCluster = Get-Cluster -Name "TARGET CLUSTER IN VCENTER"
$SourceVMTemplate = Get-Template -Name "SOURCE TEMPLATE IN VCENTER"
$SourceCustomSpec = Get-OSCustomizationSpec -Name "SOURCE CUSTOMIZATION SPEC IN VCENTER"
 
 
 
# ------This section contains the commands for defining the IP and networking settings for the new virtual machines------
# NOTE: The below IPs and Interface Names need to be updated for your environment. 
 
# Domain Controller VM IPs Below
# NOTE: Insert IP info in IP SubnetMask Gateway Order
# NOTE: For the purposes of this script we do not define static DNS settings for this single DC VM as it will point to itself for DNS after provisioning of the new domain.
# You could add an additional netsh line below to assign static DNS settings in the event you need to do so. See the File Server Section below for further details. 
$DCNetworkSettings = 'netsh interface ip set address "Ethernet0" static x.x.x.x 255.255.255.0 x.x.x.x'
 
# FS VM IPs Below
# NOTE: Insert IP info in IP SubnetMask Gateway Order
$FSNetworkSettings = 'netsh interface ip set address "Ethernet0" static x.x.x.x 255.255.255.0 x.x.x.x'
# NOTE: DNS Server IP below should be the same IP as given to the domain controller in the $DCNetworkSettings Variable
$FSDNSSettings = 'netsh interface ip set dnsservers name="Ethernet0" static x.x.x.x primary'
 
 
 
# ------This Section Sets the Credentials to be used to connect to Guest VMs that are NOT part of a Domain------
 
# NOTE - Make sure you input the local credentials for your domain controller virtual machines below. This is used for logins prior to them being promoted to DCs.
# This should be the same local credentials as defined within the template that you are using for the domain controller VM. 
$DCLocalUser = "$DomainControllerVMName\DC LOCAL USER NAME HERE"
$DCLocalPWord = ConvertTo-SecureString -String "DC LOCAL PASSWORD HERE*" -AsPlainText -Force
$DCLocalCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DCLocalUser, $DCLocalPWord
 
# Below Credentials are used by the File Server VM for first login to be able to add the machine to the new Domain.
# This should be the same local credentials as defined within the template that you are using for the file server VM. 
$FSLocalUser = "$FSVMName\FS LOCAL USER NAME HERE"
$FSLocalPWord = ConvertTo-SecureString -String "FS LOCAL PASSWORD HERE" -AsPlainText -Force
$FSLocalCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $FSLocalUser, $FSLocalPWord
 
# The below credentials are used by operations below once the domain controller virtual machines and the new domain are in place. These credentials should match the credentials
# used during the provisioning of the new domain. 
$DomainUser = "TESTDOMAIN\administrator"
$DomainPWord = ConvertTo-SecureString -String "Password01" -AsPlainText -Force
$DomainCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DomainUser, $DomainPWord 
 
 
 
# ------This Section Contains the Scripts to be executed against new VMs Regardless of Role
 
# This Scriptblock is used to add new VMs to the newly created domain by first defining the domain creds on the machine and then using Add-Computer
$JoinNewDomain = '$DomainUser = "TESTDOMAIN\Administrator";
                  $DomainPWord = ConvertTo-SecureString -String "Password01" -AsPlainText -Force;
                  $DomainCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DomainUser, $DomainPWord;
                  Add-Computer -DomainName TestDomain.lcl -Credential $DomainCredential;
                  Start-Sleep -Seconds 20;
                  Shutdown /r /t 0'
 
 
 
# ------This Section Contains the Scripts to be executed against New Domain Controller VMs------
 
# This Command will Install the AD Role on the target virtual machine. 
$InstallADRole = 'Install-WindowsFeature -Name "AD-Domain-Services" -Restart'
 
# This Scriptblock will define settings for a new AD Forest and then provision it with said settings. 
# NOTE - Make sure to define the DSRM Password below in the line below that defines the $DSRMPWord Variable!!!!
$ConfigureNewDomain = 'Write-Verbose -Message "Configuring Active Directory" -Verbose;
                       $DomainMode = "Win2012R2";
                       $ForestMode = "Win2012R2";
                       $DomainName = "TestDomain.lcl";
                       $DSRMPWord = ConvertTo-SecureString -String "Password01" -AsPlainText -Force;
                       Install-ADDSForest -ForestMode $ForestMode -DomainMode $DomainMode -DomainName $DomainName -InstallDns -SafeModeAdministratorPassword $DSRMPWord -Force'
 
# This scriptblock creates a new administrative user account inside of the new domain
# NOTE - Be Sure to set the password using the $AdminUserPWord Below!
$NewAdminUser = '$AdminUserPWord = ConvertTo-SecureString -String "Password01" -AsPlainText -Force;
                 New-ADUser -Name "TestAdmin" -AccountPassword $AdminUserPWord;
                 Add-ADGroupMember -Identity "Domain Admins" -Members "TestAdmin";
                 Enable-ADAccount -Identity "TestAdmin"'
 
 
 
# ------This Section Contains the Scripts to be executed against file server VMs------
$InstallFSRole = 'Install-WindowsFeature -Name "FS-FileServer"'
 
# The below block of code first creates a new folder and then creates a new SMB Share with rights given to the defined user or group.
$NewFileShare = '$ShareLocation = "C:\ShareTest";
                 $FolderName = "Public";
                 New-Item -Path $ShareLocation -Name $FolderName -ItemType "Directory";
                 New-SmbShare -Name "Public" -Path "$ShareLocation\$FolderName" -FullAccess "TestDomain\TestAdmin"'
 
 
#########################################################################################################################################################################################
 
 
 
# Script Execution Occurs from this point down
 
# ------This Section Deploys the new VM(s) using a pre-built template and then applies a customization specification to it. It then waits for Provisioning To Finish------
 
Write-Verbose -Message "Deploying Virtual Machine with Name: [$DomainControllerVMName] using Template: [$SourceVMTemplate] and Customization Specification: [$SourceCustomSpec] on Cluster: [$TargetCluster] and waiting for completion" -Verbose
 
New-VM -Name $DomainControllerVMName -Template $SourceVMTemplate -ResourcePool $TargetCluster -OSCustomizationSpec $SourceCustomSpec
 
Write-Verbose -Message "Virtual Machine $DomainControllerVMName Deployed. Powering On" -Verbose
 
Start-VM -VM $DomainControllerVMName
 
Write-Verbose -Message "Deploying Virtual Machine with Name: [$FSVMName] using Template: [$SourceVMTemplate] and Customization Specification: [$SourceCustomSpec] on Cluster: [$TargetCluster] and waiting for completion" -Verbose
 
New-VM -Name $FSVMName -Template $SourceVMTemplate -ResourcePool $TargetCluster -OSCustomizationSpec $SourceCustomSpec
 
Write-Verbose -Message "Virtual Machine $FSVMName Deployed. Powering On" -Verbose
 
Start-VM -VM $FSVMName
 
 
# ------This Section Targets and Executes the Scripts on the New Domain Controller Guest VM------
 
# We first verify that the guest customization has finished on on the new DC VM by using the below loops to look for the relevant events within vCenter. 
 
Write-Verbose -Message "Verifying that Customization for VM $DomainControllerVMName has started ..." -Verbose
	while($True)
	{
		$DCvmEvents = Get-VIEvent -Entity $DomainControllerVMName 
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
 
Write-Verbose -Message "Customization of VM $DomainControllerVMName has started. Checking for Completed Status......." -Verbose
	while($True)
	{
		$DCvmEvents = Get-VIEvent -Entity $DomainControllerVMName 
		$DCSucceededEvent = $DCvmEvents | Where { $_.GetType().Name -eq "CustomizationSucceeded" }
        $DCFailureEvent = $DCvmEvents | Where { $_.GetType().Name -eq "CustomizationFailed" }
 
		if ($DCFailureEvent)
		{
			Write-Warning -Message "Customization of VM $DomainControllerVMName failed" -Verbose
            return $False	
		}
 
		if ($DCSucceededEvent) 	
		{
            break
		}
        Start-Sleep -Seconds 5
	}
Write-Verbose -Message "Customization of VM $DomainControllerVMName Completed Successfully!" -Verbose
 
# NOTE - The below Sleep command is to help prevent situations where the post customization reboot is delayed slightly causing
# the Wait-Tools command to think everything is fine and carrying on with the script before all services are ready. Value can be adjusted for your environment. 
Start-Sleep -Seconds 30
 
Write-Verbose -Message "Waiting for VM $DomainControllerVMName to complete post-customization reboot." -Verbose
 
Wait-Tools -VM $DomainControllerVMName -TimeoutSeconds 300
 
# NOTE - Another short sleep here to make sure that other services have time to come up after VMware Tools are ready. 
Start-Sleep -Seconds 30
 
# After Customization Verification is done we change the IP of the VM to the value defined near the top of the script
Write-Verbose -Message "Getting ready to change IP Settings on VM $DomainControllerVMName." -Verbose
Invoke-VMScript -ScriptText $DCNetworkSettings -VM $DomainControllerVMName -GuestCredential $DCLocalCredential
 
# NOTE - The Below Sleep Command is due to it taking a few seconds for VMware Tools to read the IP Change so that we can return the below output. 
# This is strctly informational and can be commented out if needed, but it's helpful when you want to verify that the settings defined above have been 
# applied successfully within the VM. We use the Get-VM command to return the reported IP information from Tools at the Hypervisor Layer. 
Start-Sleep 30
$DCEffectiveAddress = (Get-VM $DomainControllerVMName).guest.ipaddress[0]
Write-Verbose -Message "Assigned IP for VM [$DomainControllerVMName] is [$DCEffectiveAddress]" -Verbose
 
# Then we Actually install the AD Role and configure the new domain
Write-Verbose -Message "Getting Ready to Install Active Directory Services on $DomainControllerVMName" -Verbose
 
Invoke-VMScript -ScriptText $InstallADRole -VM $DomainControllerVMName -GuestCredential $DCLocalCredential
 
Write-Verbose -Message "Configuring New AD Forest on $DomainControllerVMName" -Verbose
 
Invoke-VMScript -ScriptText $ConfigureNewDomain -VM $DomainControllerVMName -GuestCredential $DCLocalCredential
 
# Script Block for configuration of AD automatically reboots the machine after provisioning
Write-Verbose -Message "Rebooting $DomainControllerVMName to Complete Forest Provisioning" -Verbose
 
# Below sleep command is in place as the reboot needed from the above command doesn't always happen before the wait-tools command is run
Start-Sleep -Seconds 60
 
Wait-Tools -VM $DomainControllerVMName -TimeoutSeconds 300
 
Write-Verbose -Message "Installation of Domain Services and Forest Provisioning on $DomainControllerVMName Complete" -Verbose
 
Write-Verbose -Message "Adding new administative user account to domain" -Verbose
 
Invoke-VMScript -ScriptText $NewAdminUser -VM $DomainControllerVMName -GuestCredential $DomainCredential
 
 
# ------This Section Targets and Executes the Scripts on the New FS VM.
 
# Just like the DC VM, we have to first modify the IP Settings of the VM
Write-Verbose -Message "Getting ready to change IP Settings on VM $FSVMName." -Verbose
Invoke-VMScript -ScriptText $FSNetworkSettings -VM $FSVMName -GuestCredential $FSLocalCredential
Invoke-VMScript -ScriptText $FSDNSSettings -VM $FSVMName -GuestCredential $FSLocalCredential
 
# NOTE - The Below Sleep Command is due to it taking a few seconds for VMware Tools to read the IP Change so that we can return the below output. 
# This is strctly informational and can be commented out if needed, but it's helpful when you want to verify that the settings defined above have been 
# applied successfully within the VM. We use the Get-VM command to return the reported IP information from Tools at the Hypervisor Layer.
Start-Sleep 30
$FSEffectiveAddress = (Get-VM $FSVMName).guest.ipaddress[0]
Write-Verbose -Message "Assigned IP for VM [$FSVMName] is [$FSEffectiveAddress]" -Verbose 
 
# The Below Cmdlets actually add the VM to the newly deployed domain. 
Invoke-VMScript -ScriptText $JoinNewDomain -VM $FSVMName -GuestCredential $FSLocalCredential
 
# Below sleep command is in place as the reboot needed from the above command doesn't always happen before the wait-tools command is run
Start-Sleep -Seconds 60
 
Wait-Tools -VM $FSVMName -TimeoutSeconds 300
 
Write-Verbose -Message "VM $FSVMName Added to Domain and Successfully Rebooted." -Verbose
 
Write-Verbose -Message "Installing File Server Role and Creating File Share on $FSVMName." -Verbose
 
# The below commands actually execute the script blocks defined above to install the file server role and then configure the new file share. 
Invoke-VMScript -ScriptText $InstallFSRole -VM $FSVMName -GuestCredential $DomainCredential
 
Invoke-VMScript -ScriptText $NewFileShare -VM $FSVMName -GuestCredential $DomainCredential
 
Write-Verbose -Message "Environment Setup Complete" -Verbose
 
# End of Script