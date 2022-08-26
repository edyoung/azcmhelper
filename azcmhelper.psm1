
#Requires -Modules Az.Accounts

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

function Install-Azcmagent
{
    [CmdletBinding()]
    param()

    $installinfo = Get-AzcmagentInstallInfo   
    if ($installinfo -and ! $Force) {
        Write-Warning "Azcmagent $($installinfo.VersionString) already installed. Use -Force if desired"
        return        
    }

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    # Download the installation package
    Invoke-WebRequest -Uri "https://aka.ms/azcmagent-windows" -TimeoutSec 30 -OutFile "$env:TEMP\install_windows_azcmagent.ps1"

    # Install the hybrid agent
    & "$env:TEMP\install_windows_azcmagent.ps1"
    if($LASTEXITCODE -ne 0) {
        throw "Failed to install the hybrid agent: $Lastexitcode"
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
        $name
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

    Write-Verbose "Onboarding with $($params -join ' ')"
    
    $params = $params + @(
        "--access-token", 
        $token.token)

    $p = (Start-Process -FilePath azcmagent.exe -ArgumentList $params -NoNewWindow -Wait -Passthru)
    $result = $p.ExitCode
    Write-Verbose "Connect completed with $result"
}

function Get-AzcmResourceId {
    $p = (Start-Process -FilePath azcmagent.exe -ArgumentList @("show", "--json") -NoNewWindow -Wait -PassThru)
    $result = $p.ExitCode
    if ($result -eq 0) {
        $j = ($p.StandardOutput.ReadToEnd() | ConvertFrom-Json)
        $j
    }    
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

# Early in development, Azcmagent was called 'aha' (Azure Hybrid Agent). 
# Reintroduce that via alias just for fun
New-Alias -Name aha -Value azcmagent