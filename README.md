# azcmhelper
A powershell module with utilities for helping with Azure Connected Machine Agent. NOT AN OFFICIAL MICROSOFT PRODUCT

This is primarily useful while playing around with Azcmagent as a developer. It's not designed to be used as a general-purpose way to install or manage the agent.

Prerequisites:

This requires `Azure PowerShell`, and the `Az.ConnectedMachine` module to be installed. Many operations require you to have run `Connect-AzAccount` first. We try to reduce typing by using the default subscription and user account being used for Azure PowerShell. So run `Set-AzSubscription -Subscription foo` to set preferred subscription


Usage:

# installation
- `Install-Azcmagent` - download latest Azcmagent and install it
- `Uninstall-Azcmagent` - surprise! uninstall current agent

# Connect and Disconnect
- `Connect-Azcmagent -ResourceGroup foo` - Connect this machine to existing resource group foo in your currently selected azure subscription using your current account. Location of the resource group is used
- `Disconnect-Azcmagent` - surprise! disconnect current agent

# Start/Stop
- `Start-AzcmAgent` 
- `Stop-AzcmAgent`
- `Restart-AzcmAgent`

# State
You can delete, backup and restore current agent state. This can be useful if you want to switch between different locations/identities while using the same machine. Extension state is not managed so you can get into a mess doing this!
- `Remove-AzcmState` - delete local config, without removing the Azure resource if any
- `Save-AzcmState -DestinationPath c:\foo` - Copy current state into that directory
- `Restore-AzcmState -SourcePath c:\foo` - Surprise! copy it back and restart the agent 

# Extensions and Scripts
- `Invoke-AzcmScript -Local -Command 'dir'` - Invoke 'dir' via the custom script extension on the local machine
- `Invoke-AzcmScript -MachineName foo -ResourceGroup bar -Command 'hostname'` - Invoke 'hostname' via CSE on machine foo in resourcegroup bar

# Info
- `Get-AzcmResourceId` - print out resource id of current machine, assuming it is connected
- `Edit-AzcmAgentLog` - look at latest azcmagent log files
- `Edit-AzcmLog` - look at latest himds log file
- `Edit-AzcmExtensionLog` - look at latest extension service log
- `Get-AzcmAgentInstallInfo` - Print out info about currently installed version




