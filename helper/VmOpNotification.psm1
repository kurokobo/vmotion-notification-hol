function Invoke-vSphereSOAPRequest {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Request,
        [string[]] $Parameters,
        [switch] $Initiate = $false
    )

    $Headers = @{
        "Soapaction"   = "urn:vim25/8.0.0.1"
        "Content-Type" = 'text/xml; charset="utf-8"'
    }
    $Uri = "https://{0}/sdk" -f $env:VMWARE_HOST
    $XmlBodyTemplate = '<?xml version="1.0" encoding="UTF-8"?><Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/"><Body>{0}</Body></Envelope>'
    $XmlBodies = @{
        "RetrieveServiceContent"          = '<RetrieveServiceContent xmlns="urn:vim25"><_this type="ServiceInstance">ServiceInstance</_this></RetrieveServiceContent>'
        "Login"                           = '<Login xmlns="urn:vim25"><_this type="SessionManager">SessionManager</_this><userName>{0}</userName><password>{1}</password><locale>en_US</locale></Login>'
        "Logout"                          = '<Logout xmlns="urn:vim25"><_this type="SessionManager">SessionManager</_this></Logout>'
        "QueryOptions"                    = '<QueryOptions xmlns="urn:vim25"><_this type="OptionManager">{0}</_this><name>{1}</name></QueryOptions>'
        "UpdateOptions"                   = '<UpdateOptions xmlns="urn:vim25"><_this type="OptionManager">{0}</_this><changedValue xmlns:XMLSchema-instance="http://www.w3.org/2001/XMLSchema-instance" XMLSchema-instance:type="OptionValue"><key>{1}</key><value XMLSchema-instance:type="xsd:long">{2}</value></changedValue></UpdateOptions>'
        "ReconfigVM_Task"                 = '<ReconfigVM_Task xmlns="urn:vim25"><_this type="VirtualMachine">{0}</_this><spec>{1}</spec></ReconfigVM_Task>'
        "CreateContainerView"             = '<CreateContainerView xmlns="urn:vim25"><_this type="ViewManager">ViewManager</_this><container type="Folder">{0}</container><type>{1}</type><recursive>true</recursive></CreateContainerView>'
        "RetrieveContainerViewProperties" = '<RetrievePropertiesEx xmlns="urn:vim25"><_this type="PropertyCollector">propertyCollector</_this><specSet><propSet><type>ManagedEntity</type><pathSet>name</pathSet></propSet><objectSet><obj type="ContainerView">{0}</obj><skip>true</skip><selectSet xmlns:XMLSchema-instance="http://www.w3.org/2001/XMLSchema-instance" XMLSchema-instance:type="TraversalSpec"><type>ContainerView</type><path>view</path></selectSet></objectSet></specSet><options></options></RetrievePropertiesEx>'
        "DestroyContainerView"            = '<DestroyView xmlns="urn:vim25"><_this type="ContainerView">{0}</_this></DestroyView>'
        "RetrieveObjectProperties"        = '<RetrievePropertiesEx xmlns="urn:vim25"><_this type="PropertyCollector">propertyCollector</_this><specSet><propSet><type>{0}</type><pathSet>{1}</pathSet></propSet><objectSet><obj type="{2}">{3}</obj><skip>false</skip></objectSet></specSet><options></options></RetrievePropertiesEx>'
    }

    try {
        $ProgressPreference = "SilentlyContinue"
        $ConstructedBody = $XmlBodyTemplate -f ($XmlBodies[$Request] -f $Parameters)
        Format-XML -Content [xml]($ConstructedBody) | Write-Verbose

        if ($Initiate) {
            $result = Invoke-WebRequest -SessionVariable "global:DefaultVISoapSession" -Uri $Uri -Method "POST" -Headers $Headers -Body $ConstructedBody
        }
        else {
            $result = Invoke-WebRequest -WebSession $global:DefaultVISoapSession -Uri $Uri -Method "POST" -Headers $Headers -Body $ConstructedBody
        }
        $ProgressPreference = "Continue"
        Format-XML -Content [xml]($result.Content) | Write-Verbose

        return ([xml]($result.Content)).Envelope.Body
    }
    catch {
        $response = $_.Exception.Response
        $responseStream = $response.GetResponseStream()
        $responseStream.Position = 0
        $streamReader = [System.IO.StreamReader]::new($responseStream)
        $responseBody = $streamReader.ReadToEnd()
        $streamReader.Close()
        throw "Error({0}): {1}" -f $response.StatusCode.Value__ , $responseBody
    }
}

function New-vSphereSOAPSession {
    [cmdletbinding()]
    param()

    if (-not $global:DefaultVISoapSession) {
        try {
            $serviceContent = Invoke-vSphereSOAPRequest -Request "RetrieveServiceContent" -Initiate
            $global:DefaultVIRootFolder = $serviceContent.RetrieveServiceContentResponse.returnval.rootFolder.InnerText
            $null = Invoke-vSphereSOAPRequest -Request "Login" -Parameters $env:VMWARE_USER, $env:VMWARE_PASSWORD
        }
        catch {
            $global:DefaultVISoapSession = $null
        }
    }
}

function Remove-vSphereSOAPSession {
    $null = Invoke-vSphereSOAPRequest -Request "Logout"
}

function Get-vSphereSOAPMoProperties {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $PropertyType,
        [Parameter(Mandatory = $true)]
        [string] $PropertyPath,
        [Parameter(Mandatory = $true)]
        [string] $ObjectType,
        [Parameter(Mandatory = $true)]
        [string] $ObjectReference
    )
    New-vSphereSOAPSession

    $properties = Invoke-vSphereSOAPRequest -Request "RetrieveObjectProperties" -Parameters $PropertyType, $PropertyPath, $ObjectType, $ObjectReference

    return $properties.RetrievePropertiesExResponse.returnval.objects
}

function Get-vSphereSOAPMoRef {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Type,
        [Parameter(Mandatory = $true)]
        [string] $Name
    )
    New-vSphereSOAPSession

    $containerView = Invoke-vSphereSOAPRequest -Request "CreateContainerView" -Parameters $global:DefaultVIRootFolder, $Type
    $properties = Invoke-vSphereSOAPRequest -Request "RetrieveContainerViewProperties" -Parameters $containerView.CreateContainerViewResponse.returnval.InnerText
    $null = Invoke-vSphereSOAPRequest -Request "DestroyContainerView" -Parameters $containerView.CreateContainerViewResponse.returnval.InnerText

    foreach ($property in $properties.RetrievePropertiesExResponse.returnval.objects) {
        if ($property.propSet.val.InnerText -eq $Name) {
            return $property.obj.InnerText
        }
    }
}

function Get-VMHostVmOpNotification {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )
    New-vSphereSOAPSession

    $objectRef = Get-vSphereSOAPMoRef -Type "HostSystem" -Name $Name
    $advancedOptionRef = Get-vSphereSOAPMoProperties -PropertyType "HostSystem" -PropertyPath "configManager.advancedOption" -ObjectType "HostSystem" -ObjectReference $objectRef

    $queryOptions = Invoke-vSphereSOAPRequest -Request "QueryOptions" -Parameters $advancedOptionRef.propSet.val.InnerText, "VmOpNotificationToApp.Timeout"

    return [PSCustomObject]@{
        "Name"                          = $Name
        "VmOpNotificationToApp.Timeout" = [int]($queryOptions.QueryOptionsResponse.returnval.value.InnerText)
    }
}

function Set-VMHostVmOpNotification {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [int] $Timeout
    )
    New-vSphereSOAPSession

    $objectRef = Get-vSphereSOAPMoRef -Type "HostSystem" -Name $Name
    $advancedOptionRef = Get-vSphereSOAPMoProperties -PropertyType "HostSystem" -PropertyPath "configManager.advancedOption" -ObjectType "HostSystem" -ObjectReference $objectRef

    $null = Invoke-vSphereSOAPRequest -Request "UpdateOptions" -Parameters $advancedOptionRef.propSet.val.InnerText, "VmOpNotificationToApp.Timeout", $Timeout

    return Get-VMHostVmOpNotification -Name $Name
}

function Get-VMVmOpNotification {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )
    New-vSphereSOAPSession

    $objectRef = Get-vSphereSOAPMoRef -Type "VirtualMachine" -Name $Name
    $properties = Get-vSphereSOAPMoProperties -PropertyType "VirtualMachine" -PropertyPath "config" -ObjectType "VirtualMachine" -ObjectReference $objectRef

    return [PSCustomObject]@{
        "Name"                         = $Name
        "vmOpNotificationToAppEnabled" = [System.Convert]::ToBoolean($properties.propset.val.vmOpNotificationToAppEnabled)
        "vmOpNotificationTimeout"      = [int]($properties.propset.val.vmOpNotificationTimeout)
    }
}

function Set-VMVmOpNotification {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [ValidateSet("true", "false")]
        [string] $Enabled,
        [int] $Timeout = $null
    )
    New-vSphereSOAPSession

    $objectRef = Get-vSphereSOAPMoRef -Type "VirtualMachine" -Name $Name
    if ($Enabled) {
        $body += "<vmOpNotificationToAppEnabled>{0}</vmOpNotificationToAppEnabled>" -f $Enabled
    }
    if ($Timeout) {
        $body += "<vmOpNotificationTimeout>{0}</vmOpNotificationTimeout>" -f $Timeout
    }

    $task = Invoke-vSphereSOAPRequest -Request "ReconfigVM_Task" -Parameters $objectRef, $body
    while ($true) {
        $properties = Get-vSphereSOAPMoProperties -PropertyType "Task" -PropertyPath "info" -ObjectType "Task" -ObjectReference $task.ReconfigVM_TaskResponse.returnval.InnerText
        if ("success", "error" -contains $properties.propSet.val.state) {
            break
        }
        Start-Sleep -Milliseconds 500
    }

    return Get-VMVmOpNotification -Name $Name
}

# https://devblogs.microsoft.com/powershell/format-xml/
function Format-XML ([xml]$xml, $indent = 2) {
    $StringWriter = New-Object System.IO.StringWriter
    $XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter
    $xmlWriter.Formatting = "indented"
    $xmlWriter.Indentation = $Indent
    $xml.WriteContentTo($XmlWriter)
    $XmlWriter.Flush()
    $StringWriter.Flush()
    Write-Output $StringWriter.ToString()
}

Add-Type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
