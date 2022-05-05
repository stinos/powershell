<#
.SYNOPSIS
Helper for the boilerplate in DynamicParam blocks.
.DESCRIPTION
Create dynamic parameters into the given RuntimeDefinedParameterDictionary,
or create and return a new one if it doesn't exist.
.EXAMPLE
# Create a bunch of switches.
# Add-DynamicParameters will return a new dictionary here, which then in turn
# is returned from the block hence the conciseness.
DynamicParam {
  Add-DynamicParameters @('a', 'b', 'c') -Type ([Type]'Switch')
}
.EXAMPLE
# Create different parameters
DynamicParam {
  $paramDictionary = Add-DynamicParameters
  Add-DynamicParameters @('a', 'b') -Type ([Type]'Switch') -ParamDictionary $paramDictionary
  Add-DynamicParameters @('d') -ParamDictionary $paramDictionary
  $paramDictionary
}
.PARAMETER Names
Parameter name(s).
.PARAMETER Type
The type to create. Use like -Type ([Type]'String').
.PARAMETER ParameterSetName
Optional ParameterSetName fr the parameters.
.PARAMETER ParamDictionary
Dictionary to add the parameters to.
.OUTPUTS
A RuntimeDefinedParameterDictionary if $ParamDictionary was $null.
So just calling Add-DynamicParameters will return a new RuntimeDefinedParameterDictionary.
#>
function Add-DynamicParameters {
  param (
    [Parameter()] [String[]] $Names = @(),
    [Parameter()] [Type] $Type = [String],
    [Parameter()] [String] $ParameterSetName,
    [Parameter()] [Management.Automation.RuntimeDefinedParameterDictionary] $ParamDictionary
  )
  if (-not $ParamDictionary) {
    $ParamDictionary = [Management.Automation.RuntimeDefinedParameterDictionary]::new()
    $returnDict = $True
  }
  foreach ($name in $Names) {
    $attributeCollection = [Collections.ObjectModel.Collection[System.Attribute]]::new()
    $attribute = [Management.Automation.ParameterAttribute]::new()
    if ($ParameterSetName) {
      $attribute.ParameterSetName = $ParameterSetName
    }
    $attributeCollection.Add($attribute)
    $parameter = [System.Management.Automation.RuntimeDefinedParameter]::new($name, $Type, $attributeCollection)
    $paramDictionary.Add($name, $parameter)
  }
  if ($returnDict) {
    $paramDictionary
  }
}

<#
.SYNOPSIS
Get all non-dynamic parameters of the calling function, as opposed to just $PSBoundParameters.
.DESCRIPTION
$PSBoundParameters only contains parameters specified by the caller, meaning it
lacks parameters which have default values but are not specified so it is not
useful for splatting for instance.
This function adds 'unbound' parameters to a clone of the caller's bound ones, if:
- the value is not $null (which either indicates a parameter with default value $null,
  or typcially a parameter not specified in the param() block so not of interest)
- it is not a dynamic parameter, because there doesn't seem to be any way to get
  to their default value
As such this is a bit finicky and your mileage may vary.
.EXAMPLE
function Get-Stuff {
  [CmdletBinding(SupportsShouldProcess)]
  Param (
    [Parameter(Mandatory)] $A,
    [Parameter()] $B = 2,
    [Parameter()] $C,
    [Parameter()] [Switch] $D
  )
  Get-AllParameters $MyInvocation $PsBoundParameters {Get-Variable @args}
}

Get-Stuff -A 1  # Returns @{'A' = 1; 'B' = 2; 'D' = $False}

Get-Stuff -A 1 -Verbose -WhatIf  # Returns @{'A' = 1; 'B' = 2; 'D' = $False; 'Verbose' = $True; 'WhatIf' = $True}

Get-Stuff -A 1 -B 3 -C 1 -D # Returns @{'A' = 1; 'B' = 3; 'C' = 1; 'D' = $True}
.PARAMETER Invocation
Caller's MyInvocation variable, to get parameter names from.
.PARAMETER BoundParameters
Caller's $PSBoundParameters.
.PARAMETER GetVariable
Function resolving to Get-Variable in the caller's scope values,
normally {Get-Variable @args}. For unknown reasons using Get-Variable -Scope 1
directly does not find the parameters so this is the workaround.
#>
function Get-AllParameters {
  param (
    [Parameter(Mandatory)] [System.Management.Automation.InvocationInfo] $Invocation,
    [Parameter(Mandatory)] [Hashtable] $BoundParameters,
    [Parameter(Mandatory)] [Scriptblock] $GetVariable
  )
  $params = $BoundParameters.Clone()
  foreach ($p in $Invocation.MyCommand.Parameters.GetEnumerator()) {
    $name = $p.Key
    if (-not $params.ContainsKey($name) -and -not $p.Value.IsDynamic) {
      $var = & $GetVariable -Name $name -ValueOnly -ErrorAction Ignore
      if ($null -ne $var) {
        $params.Add($name, $var)
      }
    }
  }
  $params
}
