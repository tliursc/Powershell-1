function Get-RemoteRegistry {
    <#
    .SYNOPSIS
       Retrieves registry subkey information.
    .DESCRIPTION
       Retrieves registry subkey information. All subkeys and their values are returned as a custom psobject. Optionally
       an array of psobjects can be returned which contain extra information like the registry key type,computer, and datetime.
    .PARAMETER ComputerName
       Specifies the target computer for data query.
    .PARAMETER Hive
       Registry hive to retrieve from. By default this is 2147483650 (HKLM). Valid hives include:
          HKEY_CLASSES_ROOT = 2147483648
          HKEY_CURRENT_USER = 2147483649
          HKEY_LOCAL_MACHINE = 2147483650
          HKEY_USERS = 2147483651
          HKEY_CURRENT_CONFIG = 2147483653
          HKEY_DYN_DATA = 2147483654
    .PARAMETER Key
       Registry key to inspect (ie. SYSTEM\CurrentControlSet\Services\W32Time\Parameters)
    .PARAMETER AsHash
       Return a hash where the keys are the registry entries. This is only suitable for getting the regisrt
       values of one computer at a time.
    .PARAMETER ThrottleLimit
       Specifies the maximum number of systems to inventory simultaneously 
    .PARAMETER Timeout
       Specifies the maximum time in second command can run in background before terminating this thread.
    .PARAMETER ShowProgress
       Show progress bar information
    .EXAMPLE
       PS > $(Get-RemoteRegistry -AsHash -Key "SYSTEM\CurrentControlSet\Services\W32Time\Parameters")['Type']

       NT5DS
       
       Description
       -----------
       Return the value of the 'Type' subkey within SYSTEM\CurrentControlSet\Services\W32Time\Parameters of
       HKLM.
       
    .EXAMPLE
       PS > $(Get-RemoteRegistry -AsObject -Key "SYSTEM\CurrentControlSet\Services\W32Time\Parameters").Type

       NT5DS
       
       Description
       -----------
       Return the value of the 'Type' subkey within SYSTEM\CurrentControlSet\Services\W32Time\Parameters of
       HKLM from an object containing all registry keys in HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Parameters
       as individual object properties.
       
    .EXAMPLE
       PS > $b = Get-RemoteRegistry -Key "SYSTEM\CurrentControlSet\Services\W32Time\Parameters"
       PS > $b.Registry | Select Key,KeyValue,KeyType
       
        SubKey                                         SubKeyValue                                    SubKeyType
        ------                                         -----------                                    ----------                                   
        ServiceDll                                     C:\Windows\system32\w32time.dll                REG_EXPAND_SZ
        ServiceMain                                    SvchostEntry_W32Time                           REG_SZ
        ServiceDllUnloadOnStop                         1                                              REG_DWORD
        Type                                           NT5DS                                          REG_SZ
        NtpServer                                                                                     REG_SZ
       
       Description
       -----------
       Return subkeys and their values as well as key types within SYSTEM\CurrentControlSet\Services\W32Time\Parameters of
       HKLM.

    .EXAMPLE
        $keys = @('HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Windows\WindowsUpdate','HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer','HKEY_LOCAL_MACHINE\SYSTEM\Internet Communication Management\Internet Communication','HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate','HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Windows\WindowsUpdate\AU')
        $keys | Foreach {(Get-RemoteRegistry -Key $_).Registry | Where {$_.Keytype -ne 'Subkey'}} | fl
       
       Description
       -----------
       Get all the keys related to windows updates on the current system. Do not show subkey entries.
       
    .NOTES
       Author: Zachary Loeber
       Site: http://www.the-little-things.net/
       Requires: Powershell 2.0

       Version History
       1.0.4 - 05/20/2015
        - Updated parameters to make it easier to supply hive names
        - Updated parameter to allow including no hive name if it is at the begining of the key
        - Added some more examples and fixed others.
        - Included the key path in standard output.
       1.0.3 - 10/20/2013
        - Fixed resturning values of multi strings
       1.0.2 - 08/30/2013 
        - Changed AsArray option to be AsHash and restructured code to reflect this
        - Changed examples
        - Prefixed all warnings and verbose messages with function specific verbage
        - Forced STA apartement state before opening a runspace
       1.0.1 - 08/07/2013
        - Removed the explicit return of subkey values from output options
        - Fixed issue where only string values were returned
       1.0.0 - 08/06/2013
        - Initial release
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, Position=0, HelpMessage="Computer or computers to gather information from")]
        [ValidateNotNullOrEmpty()]
        [Alias('DNSHostName','PSComputerName')]
        [string[]]$ComputerName = $env:computername,
        
        [Parameter( HelpMessage='Registry Hive (Default is HKLM).')]
        [ValidateSet('HKLM','HKCU','HKEY_LOCAL_MACHINE','HKEY_CURRENT_USER','HKEY_CLASSES_ROOT','HKEY_USERS','HKEY_CURRENT_CONFIG','HKEY_DYN_DATA')]
        [string]$Hive,
        
        [Parameter( Mandatory=$true, HelpMessage='Registry Key to inspect.')]
        [string]$Key,
        
        [Parameter(HelpMessage='Return a hash with key value pairs representing the registry being queried.')]
        [switch]$AsHash,
        
        [Parameter(HelpMessage='Return an object wherein the object properties are the registry keys and the property values are their value.')]
        [switch]$AsObject,
        
        [Parameter(HelpMessage='Maximum number of concurrent threads.')]
        [ValidateRange(1,65535)]
        [int32]$ThrottleLimit = 32,
 
        [Parameter(HelpMessage='Timeout before a thread stops trying to gather the information.')]
        [ValidateRange(1,65535)]
        [int32]$Timeout = 120,
 
        [Parameter(HelpMessage='Display progress of function.')]
        [switch]$ShowProgress,
        
        [Parameter(HelpMessage='Set this if you want to provide your own alternate credentials.')]
        [System.Management.Automation.PSCredential]$Credential = [System.Management.Automation.PSCredential]::Empty
    )

    begin {
        $HiveTable = @{
            'HKLM' = 2147483650
            'HKEY_LOCAL_MACHINE' = 2147483650
            'HKCU' = 2147483649
            'HKEY_CURRENT_USER' = 2147483649
            'HKEY_CLASSES_ROOT' = 2147483648
            'HKEY_USERS' = 2147483651
            'HKEY_CURRENT_CONFIG' = 2147483653
            'HKEY_DYN_DATA' = 2147483654
        }
        
        if (($Hive -eq $null) -or ($Hive -eq '')) {
            $HiveTable.Keys | Foreach {
                if ($_ -eq ($key -split '\\')[0]) {
                    $Hive = $_
                    $Key = $Key.Replace("$($_)\",'')
                    Write-Verbose "Get-RemoteRegistry: Setting key to be $($_) for the key $($key)"
                }
            }
            if (($Hive -eq $null) -or ($Hive -eq '')) { $Hive = 'HKLM' }
        }

        # Gather possible local host names and IPs to prevent credential utilization in some cases
        Write-Verbose -Message 'Get-RemoteRegistry: Creating local hostname list'
        $IPAddresses = [net.dns]::GetHostAddresses($env:COMPUTERNAME) | Select-Object -ExpandProperty IpAddressToString
        $HostNames = $IPAddresses | ForEach-Object {
            try {
                [net.dns]::GetHostByAddress($_)
            } catch {
                # We do not care about errors here...
            }
        } | Select-Object -ExpandProperty HostName -Unique
        $LocalHost = @('', '.', 'localhost', $env:COMPUTERNAME, '::1', '127.0.0.1') + $IPAddresses + $HostNames
 
        Write-Verbose -Message 'Get-RemoteRegistry: Creating initial variables'
        $runspacetimers       = [HashTable]::Synchronized(@{})
        $runspaces            = New-Object -TypeName System.Collections.ArrayList
        $bgRunspaceCounter    = 0
        
        Write-Verbose -Message 'Get-RemoteRegistry: Creating Initial Session State'
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        foreach ($ExternalVariable in ('runspacetimers', 'Credential', 'LocalHost'))
        {
            Write-Verbose -Message "Get-RemoteRegistry: Adding variable $ExternalVariable to initial session state"
            $iss.Variables.Add((New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList $ExternalVariable, (Get-Variable -Name $ExternalVariable -ValueOnly), ''))
        }
        
        Write-Verbose -Message 'Get-RemoteRegistry: Creating runspace pool'
        $rp = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit, $iss, $Host)
        $rp.ApartmentState = 'STA'
        $rp.Open()
 
        # This is the actual code called for each computer
        Write-Verbose -Message 'Get-RemoteRegistry: Defining background runspaces scriptblock'
        $ScriptBlock = {
            [CmdletBinding()]
            param (
                [Parameter(Position=0)]
                [string]$ComputerName,
                [UInt32]$Hive = 2147483650,
                [String]$Key,
                [switch]$AsHash,
                [switch]$AsObject,
                [int]$bgRunspaceID
            )
            $runspacetimers.$bgRunspaceID = Get-Date
            $regtype = @('Placeholder','REG_SZ','REG_EXPAND_SZ','REG_BINARY','REG_DWORD','Placeholder','Placeholder','REG_MULTI_SZ','Placeholder','Placeholder','Placeholder','REG_QWORD')
            try {
                Write-Verbose -Message ('Get-RemoteRegistry: Runspace {0}: Start' -f $ComputerName)
                $WMIHast = @{
                    ComputerName = $ComputerName
                    ErrorAction = 'Stop'
                }
                if (($LocalHost -notcontains $ComputerName) -and ($Credential -ne [System.Management.Automation.PSCredential]::Empty))
                {
                    $WMIHast.Credential = $Credential
                }

                # General variables
                $PSDateTime = Get-Date
                
                #region Registry
                Write-Verbose -Message ('Get-RemoteRegistry: Runspace {0}: Gathering registry information' -f $ComputerName)

                # WMI data
                $wmi_data = Get-WmiObject @WMIHast -Class StdRegProv -Namespace 'root\default' -List:$true
                $allregkeys = $wmi_data.EnumValues($Hive,$Key)
                $allsubkeys = $wmi_data.EnumKey($Hive,$Key)

                $ResultHash = @{}
                $RegObjects = @() 
                $ResultObject = @{}
                       
                for ($i = 0; $i -lt $allregkeys.Types.Count; $i++) 
                {
                    switch ($allregkeys.Types[$i]) {
                        1 {$keyvalue = ($wmi_data.GetStringValue($Hive,$Key,$allregkeys.sNames[$i])).sValue}
                        2 {$keyvalue = ($wmi_data.GetExpandedStringValue($Hive,$Key,$allregkeys.sNames[$i])).sValue}
                        3 {$keyvalue = ($wmi_data.GetBinaryValue($Hive,$Key,$allregkeys.sNames[$i])).uValue}
                        4 {$keyvalue = ($wmi_data.GetDWORDValue($Hive,$Key,$allregkeys.sNames[$i])).uValue}
                        7 {$keyvalue = @(($wmi_data.GetMultiStringValue($Hive,$Key,$allregkeys.sNames[$i])).sValue)}
                        11 {$keyvalue = ($wmi_data.GetQWORDValue($Hive,$Key,$allregkeys.sNames[$i])).sValue}
                        default {break}
                    }
                    if ($AsHash -or $AsObject)
                    {
                        $ResultHash[$allregkeys.sNames[$i]] = $keyvalue
                    }
                    else
                    {
                        $RegProperties = @{
                            'Key' = $allregkeys.sNames[$i]
                            'KeyType' = $regtype[($allregkeys.Types[$i])]
                            'KeyValue' = $keyvalue
                            'KeyPath' = $Key
                        }
                        $RegObjects += New-Object PSObject -Property $RegProperties
                    }
                }
                foreach ($subkey in $allsubkeys.sNames) 
                {
                    if ($AsHash)
                    {
                        $ResultHash[$subkey] = ''
                    }
                    else
                    {
                        $RegProperties = @{
                            'Key' = $subkey
                            'KeyType' = 'SubKey'
                            'KeyValue' = ''
                            'KeyPath' = $Key
                        }
                        $RegObjects += New-Object PSObject -Property $RegProperties
                    }
                }
                if ($AsHash)
                {
                    $ResultHash
                }
                elseif ($AsObject)
                {
                    $ResultHash['PSComputerName'] = $ComputerName
                    $ResultObject = New-Object PSObject -Property $ResultHash
                    Write-Output -InputObject $ResultObject
                }
                else
                {
                    $ResultProperty = @{
                        'PSComputerName' = $ComputerName
                        'PSDateTime' = $PSDateTime
                        'ComputerName' = $ComputerName
                        'Registry' = $RegObjects
                    }
                    $Result = New-Object PSObject -Property $ResultProperty
                    Write-Output -InputObject $Result
                }
            }
            catch {
                Write-Warning -Message ('Get-RemoteRegistry: {0}: {1}' -f $ComputerName, $_.Exception.Message)
            }
            Write-Verbose -Message ('Get-RemoteRegistry: Runspace {0}: End' -f $ComputerName)
        }
 
        function Get-Result {
            [CmdletBinding()]
            param (
                [switch]$Wait
            )
            do
            {
                $More = $false
                foreach ($runspace in $runspaces)
                {
                    $StartTime = $runspacetimers.($runspace.ID)
                    if ($runspace.Handle.isCompleted)
                    {
                        Write-Verbose -Message ('Get-RemoteRegistry: Thread done for {0}' -f $runspace.IObject)
                        $runspace.PowerShell.EndInvoke($runspace.Handle)
                        $runspace.PowerShell.Dispose()
                        $runspace.PowerShell = $null
                        $runspace.Handle = $null
                    }
                    elseif ($runspace.Handle -ne $null)
                    {
                        $More = $true
                    }
                    if ($Timeout -and $StartTime)
                    {
                        if (((New-TimeSpan -Start $StartTime).TotalSeconds -ge $Timeout) -and $runspace.PowerShell)
                        {
                            Write-Warning -Message ('Get-RemoteRegistry: Timeout {0}' -f $runspace.IObject)
                            $runspace.PowerShell.Dispose()
                            $runspace.PowerShell = $null
                            $runspace.Handle = $null
                        }
                    }
                }
                if ($More -and $PSBoundParameters['Wait'])
                {
                    Start-Sleep -Milliseconds 100
                }
                foreach ($threat in $runspaces.Clone())
                {
                    if ( -not $threat.handle)
                    {
                        Write-Verbose -Message ('Get-RemoteRegistry: Removing {0} from runspaces' -f $threat.IObject)
                        $runspaces.Remove($threat)
                    }
                }
                if ($ShowProgress)
                {
                    $ProgressSplatting = @{
                        Activity = 'Getting asset info'
                        Status = '{0} of {1} total threads done' -f ($bgRunspaceCounter - $runspaces.Count), $bgRunspaceCounter
                        PercentComplete = ($bgRunspaceCounter - $runspaces.Count) / $bgRunspaceCounter * 100
                    }
                    Write-Progress @ProgressSplatting
                }
            }
            while ($More -and $PSBoundParameters['Wait'])
        }

        $ComputerNames = @()
    }
    process {
        $ComputerNames += $ComputerName
    }
    end {
        foreach ($Computer in $ComputerNames)
        {
            $bgRunspaceCounter++
            $psCMD = [System.Management.Automation.PowerShell]::Create().AddScript($ScriptBlock)
            $null = $psCMD.AddParameter('bgRunspaceID',$bgRunspaceCounter)
            $null = $psCMD.AddParameter('ComputerName',$Computer)
            $null = $psCMD.AddParameter('Hive',$HiveTable[$Hive])
            $null = $psCMD.AddParameter('Key',$Key)
            $null = $psCMD.AddParameter('AsHash',$AsHash)
            $null = $psCMD.AddParameter('AsObject',$AsObject)
            $null = $psCMD.AddParameter('Verbose',$VerbosePreference)
            $psCMD.RunspacePool = $rp
 
            Write-Verbose -Message ('Get-RemoteRegistry: Starting {0}' -f $Computer)
            [void]$runspaces.Add(@{
                Handle = $psCMD.BeginInvoke()
                PowerShell = $psCMD
                IObject = $Computer
                ID = $bgRunspaceCounter
           })
           #Get-Result
        }
        Get-Result -Wait
        if ($ShowProgress)
        {
            Write-Progress -Activity 'Get-RemoteRegistry: Getting share session information' -Status 'Done' -Completed
        }
        Write-Verbose -Message "Get-RemoteRegistry: Closing runspace pool"
        $rp.Close()
        $rp.Dispose()
    }
}