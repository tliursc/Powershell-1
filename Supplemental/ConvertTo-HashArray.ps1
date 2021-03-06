function ConvertTo-HashArray {
    <#
    .SYNOPSIS
    Convert an array of objects to a hash table based on a single property of the array.     
    .DESCRIPTION
    Convert an array of objects to a hash table based on a single property of the array.
    .PARAMETER InputObject
    An array of objects to convert to a hash table array.
    .PARAMETER PivotProperty
    The property to use as the key value in the resulting hash.
    .PARAMETER OverwriteDuplicates
    If the pivotproperty is found multiple times then overwrite the current hash value. Default is to skip duplicates.
    .EXAMPLE
    $test = @()
    $test += New-Object psobject -Property @{'Server' = 'Server1'; 'IP' = '1.1.1.1'}
    $test += New-Object psobject -Property @{'Server' = 'Server2'; 'IP' = '2.2.2.2'}
    $test += New-Object psobject -Property @{'Server' = 'Server2'; 'IP' = '3.3.3.3'}
    $test | ConvertTo-HashArray -PivotProperty Server
    
    Name                           Value                                                                                                                  
    ----                           -----                                                                                                                  
    Server1                        @{Server=Server1; IP=1.1.1.1}                                                                                          
    Server2                        @{Server=Server2; IP=2.2.2.2} 
    Description
    -----------
    Convert and output a hash array based on the server property (skipping duplicate values)
    
    .NOTES
    Author: Zachary Loeber
    Site: the-little-things.net
    #>
    [CmdLetBinding(DefaultParameterSetName='AsObjectArray')]
    param(
        [Parameter(ParameterSetName='AsObjectArray', Mandatory=$True, ValueFromPipeline=$True, Position=0)]
        [AllowEmptyCollection()]
        [PSObject[]]$InputObjects,
        [Parameter(ParameterSetName='AsObject', Mandatory=$True, ValueFromPipeline=$True, Position=0)]
        [AllowEmptyCollection()]
        [PSObject]$InputObject,
        [Parameter(Mandatory=$true)]
        [string]$PivotProperty,
        [Parameter()]
        [switch]$OverwriteDuplicates,
        [Parameter(HelpMessage='Property in the psobject to be the value that the hash key points to. If not specified, all properties in the psobject are used.')]
        [string]$LookupValue = ''
    )

    begin {
        Write-Verbose "$($MyInvocation.MyCommand): Begin"
        $allObjects = @()
        $Results = @{}
    }
    process {
        $allObjects += $inputObject
        switch ($PSCmdlet.ParameterSetName) {
            'AsObjectArray' {
                $allObjects = $InputObjects
            }
            'AsObject' {
                $allObjects = @($InputObject)
            }
        }
        foreach ($object in ($allObjects | where {$_ -ne $null}))
        {
            try {
                if ($object.PSObject.Properties.Match($PivotProperty).Count) 
                {
                    if ($LookupValue -eq '')
                    {
                        if (-not $Results.ContainsKey($object.$PivotProperty) -or $OverwriteDuplicates)
                        {
                            $Results[$object.$PivotProperty] = $object
                        }
                    }
                    else
                    {
                        if ($object.PSObject.Properties.Match($LookupValue).Count)
                        {
                            if (-not $Results.ContainsKey($object.$PivotProperty) -or $OverwriteDuplicates)
                            {
                                $Results[$object.$PivotProperty] = $object.$LookupValue
                            }
                        }
                        else
                        {
                            Write-Warning -Message "$($MyInvocation.MyCommand): LookupValue ($LookupValue) Not Found"
                        }
                    }
                }
                else
                {
                    Write-Warning -Message "$($MyInvocation.MyCommand): PivotProperty ($PivotProperty) Not found in object"
                }
            }
            catch {
                Write-Warning -Message "$($MyInvocation.MyCommand): Something weird happened!"
            }
        }
    }
    end {
        Write-Output -InputObject $Results
        Write-Verbose "$($MyInvocation.MyCommand): End"
    }
}