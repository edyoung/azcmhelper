
#Requires -Modules Az.Accounts, Az.ConnectedMachine

Set-StrictMode -Version latest
$ErrorActionPreference = "Stop"

function Save-AzcmState 
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $DestinationPath
    )

    $dataPath = "$($env:ProgramData)\AzureConnectedMachineAgent"
    $null = new-item -type Directory -Path $DestinationPath\Config -Force
    $null = new-item -type Directory -Path $DestinationPath\Certs -Force
    $null = Copy-Item $dataPath\Config\* -Destination $DestinationPath\Config -Force
    $null = Copy-Item $dataPath\Certs\* -Destination $DestinationPath\Certs -Force    
} 

function Stop-AzcmAgent
{
    [CmdletBinding()]
    param(

    )

    Stop-Service himds
    Stop-Service GCArcService
    Stop-Service ExtensionService
}

function Start-AzcmAgent
{
    [CmdletBinding()]
    param(

    )

    Start-Service himds
    Start-Service GCArcService
    Start-Service ExtensionService
}

function Restart-AzcmAgent
{
    [CmdletBinding()]
    param(

    )

    Restart-Service himds
    Restart-Service GCArcService
    Restart-Service ExtensionService
}

function Remove-AzcmState
{
    $dataPath = "$($env:ProgramData)\AzureConnectedMachineAgent"
    remove-item -Recurse -Force $dataPath\config\*
    remove-item -Recurse -Force $dataPath\certs\*
    
    Restart-AzcmAgent
}

function Restore-AzcmState
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $SourcePath
    )

    $dataPath = "$($env:ProgramData)\AzureConnectedMachineAgent"

    Copy-Item $sourcepath\Config\* -Destination $dataPath\Config -Force
    Copy-Item $SourcePath\Certs\* -Destination $dataPath\Certs -Force    

    Restart-AzcmAgent
}

function Uninstall-Azcmagent
{
    [CmdletBinding()]
    param()

    $installinfo = Get-AzcmagentInstallInfo   
    if (! $installinfo) {
        Write-Warning "Azcmagent not currently installed"
        return
    }
    Write-Verbose "Azcmagent $($installinfo.VersionString) installed with product code $($installInfo.ProductCode)"

    $exitCode = (Start-Process -FilePath msiexec.exe -ArgumentList @("/x", "$($installInfo.ProductCode)" , "/l*v", "uninstallationlog.txt", "/qn") -Wait -Passthru).ExitCode
    if ($exitCode -ne 0) {
        $message = (net helpmsg $exitCode)        
        throw "Installation failed: $message See uninstallationlog.txt for additional details."
    }
}

function Get-AzcmagentInstallInfo() {
    $Installer = New-Object -ComObject WindowsInstaller.Installer
    $InstallerProducts = $Installer.ProductsEx("", "", 7); 
    $InstalledProducts = ForEach($Product in $InstallerProducts){
        if ($Product.InstallProperty("ProductName") -eq "Azure Connected Machine Agent")  {
            return [PSCustomObject]@{
                ProductCode = $Product.ProductCode(); 
                LocalPackage = $Product.InstallProperty("LocalPackage"); 
                VersionString = $Product.InstallProperty("VersionString"); 
                ProductPath = $Product.InstallProperty("ProductName")
            }
        }
    }
}

function Install-Azcmagent
{
    [CmdletBinding()]
    param(
        $AltDownload
    )

    $installinfo = Get-AzcmagentInstallInfo   
    if ($installinfo) {
        Write-Verbose "Already Installed, uninstalling first"
        Uninstall-Azcmagent
    }

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    # Download the installation package
    Invoke-WebRequest -Uri "https://aka.ms/azcmagent-windows" -TimeoutSec 30 -OutFile "$env:TEMP\install_windows_azcmagent.ps1"

    $scriptParams=@{
        AltDownload=$AltDownload
    }
    # Install the hybrid agent
    & "$env:TEMP\install_windows_azcmagent.ps1" @scriptParams
    if($LASTEXITCODE -ne 0) {
        throw "Failed to install the hybrid agent: $Lastexitcode"
    }
}




<#
.DESCRIPTION Connect the agent to Azure. Uses the current subscription and tenant from 
#>
function Connect-AzcmAgent {
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$false)]
        $subscription,

        [Parameter(Mandatory=$false)]
        $tenant,

        [Parameter(Mandatory=$true)]
        $resourceGroup,

        [Parameter(Mandatory=$false)]
        $location,

        [Parameter(Mandatory=$false)]
        $name,

        [Parameter(Mandatory=$false)]
        $PrivateLinkScope
    )

    $context = Get-AzContext
    if(! $subscription) {
        # try the current subscription from Az module
        $subscription = $context.Subscription
    }
    if(! $tenant) {
        $tenant = $context.Tenant
    }

    if(! $location) {
        $location = (Get-AzResourceGroup -Name $resourceGroup).Location
    }

    $token = Get-AzAccessToken

    $params = @(
        "connect"
        "-t",
        $tenant,
        "-s",
        $subscription,
        "-g",
        $resourceGroup,
        "-l",
        $location)
    
    if($name) {
        $params = $params + @( "-n", $name)
    }

    if($PrivateLinkScope) {
        $params = $params + @("--private-link-scope", $PrivateLinkScope)
    }

    Write-Verbose "Onboarding with $($params -join ' ')"
    
    $params = $params + @(
        "--access-token", 
        $token.token)

    $p = (Start-Process -FilePath azcmagent.exe -ArgumentList $params -NoNewWindow -Wait -Passthru)
    $result = $p.ExitCode
    Write-Verbose "Connect completed with $result"
}

function Get-AzcmResourceId {
    [CmdletBinding()]
    param()

    $agentSettings = (& Azcmagent show --json) | ConvertFrom-Json
    $MachineName = $agentSettings.resourceName
    $ResourceGroup = $agentSettings.ResourceGroup
    $Location = $agentSettings.Location
    $Tenant = $agentSettings.TenantId
    $Subscription = $agentSettings.SubscriptionId

    $resourceId = "/subscriptions/$Subscription/resourceGroups/$ResourceGroup/providers/Microsoft.HybridCompute/machines/$MachineName" 
    return $resourceId
} 

function Get-AzcmResource {

    [CmdletBinding()]
    param(
        $ArmRegion,
        $ApiVersion="2022-11-10"
    )
    $resourceId = Get-AzcmResourceId
    
    if($ArmRegion) { $ArmRegion += "."}

    $url = "https://$($ArmRegion)management.azure.com/$($resourceId)?api-version=$apiversion"
    Write-Verbose "Checking URl $url"
    # Invoke-AzRestMethod doesn't allow us to override the ARM URL :-(
    & az rest --method get --url $url --resource https://management.azure.com/ | ConvertFrom-Json
}

<#
.DESCRIPTION Disconnect the agent from Azure
#>
function Disconnect-AzcmAgent {

    [CmdletBinding()]
    param(        
    )

    $token = Get-AzAccessToken
    $params = @("disconnect", "--access-token", $token.token)
    $p = (Start-Process -FilePath azcmagent.exe -ArgumentList $params -NoNewWindow -Wait -Passthru)
    $result = $p.ExitCode
    Write-Verbose "Disconnect completed with $result"
}

function Edit-AzcmExtensionLog {
    $editor = "notepad.exe"
    if ($env:EDITOR) {
        $editor = $env:EDITOR
    }
    & $editor $env:ProgramData\GuestConfig\ext_mgr_logs\gc_ext.log
}

function Edit-AzcmLog {
    $editor = "notepad.exe"
    if ($env:EDITOR) {
        $editor = $env:EDITOR
    }
    & $editor $env:ProgramData\AzureConnectedMachineAgent\Log\himds.log
}

function Edit-AzcmAgentLog {
    $editor = "notepad.exe"
    if ($env:EDITOR) {
        $editor = $env:EDITOR
    }
    & $editor $env:ProgramData\AzureConnectedMachineAgent\Log\azcmagent.log
}

function Invoke-AzcmScript {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ParameterSetName="othermachine")]
        $MachineName,

        [Parameter(Mandatory=$true,ParameterSetName="othermachine")]
        $ResourceGroup,

        [Parameter(Mandatory=$true,ParameterSetName="othermachine")]
        $Location,

        [Parameter(Mandatory=$true,ParameterSetName="local")]
        [switch]$Local,

        [Parameter(Mandatory=$false)]
        $ExtensionName="csetest",
        
        [Parameter(Mandatory=$false)]
        $Command="hostname"        
    )

    if($Local)
    {
        $agentSettings = (& Azcmagent show --json) | ConvertFrom-Json
        $MachineName = $agentSettings.resourceName
        $ResourceGroup = $agentSettings.ResourceGroup
        $Location = $agentSettings.Location
    }

    Write-Verbose "Running command '$command' on $MachineName in $ResourceGroup in $Location"
    $Settings = @{ "commandToExecute" = "$command" }
    New-AzConnectedMachineExtension -MachineName $MachineName -Name $ExtensionName -ResourceGroupName azcmagenttest -ExtensionType CustomScriptExtension -Settings $Settings -Publisher "Microsoft.Compute" -Location $Location -Verbose:$VerbosePreference
}

function Get-AzcmExtensionVersion {
    [CmdletBinding()]
    param(    
        [Parameter(Mandatory=$true)]
        $Location,

        [Parameter(Mandatory=$false)]
        $Publisher="Microsoft.Compute",

        [Parameter(Mandatory=$false)]
        $ExtensionType="CustomScriptExtension",
        
        [Parameter(Mandatory=$false)]
        $Subscription
    )

    $context = Get-AzContext
    if(! $subscription) {
        # try the current subscription from Az module
        $subscription = $context.Subscription
    }

    $token = (Get-AzAccessToken).Token
    $response = Invoke-WebRequest "https://management.azure.com/subscriptions/$subscription/providers/Microsoft.HybridCompute/locations/$location/publishers/$publisher/extensionTypes/$extensionType/versions/?api-version=2022-08-11-preview" -Headers @{Authorization="Bearer $token"}
    $json = ConvertFrom-Json $response.Content
    $json.properties
}

function Get-AzcmPortalUrl {
    [CmdletBinding()]
    param(

    )

    $agentSettings = (& Azcmagent show --json) | ConvertFrom-Json
    $MachineName = $agentSettings.resourceName
    $ResourceGroup = $agentSettings.ResourceGroup
    $Location = $agentSettings.Location
    $Tenant = $agentSettings.TenantId
    $Subscription = $agentSettings.SubscriptionId

    "https://portal.azure.com/#@$Tenant/resource/subscriptions/$Subscription/resourceGroups/$ResourceGroup/providers/Microsoft.HybridCompute/machines/$MachineName/overview"
}

function Invoke-AzcmPortal {
    [CmdletBinding()]
    param()

    $url = Get-AzcmPortalUrl
    Write-Verbose "Portal URL $url"
    & start $url
}


# Early in development, Azcmagent was called 'aha' (Azure Hybrid Agent). 
# Reintroduce that via alias just for fun
New-Alias -Name aha -Value azcmagent -ErrorAction SilentlyContinue