[cmdletbinding()]
$AgentPath = Get-VstsInput -Name AgentPath -Default "$env:SystemDrive\azagent"
$ComputerName = (Get-VstsInput -Name ComputerName) -Split ",|\s"
$AdminUserName = Get-VstsInput -Name AdminUserName
$AdminPassword = Get-VstsInput -Name AdminPassword
$Protocol = Get-VstsInput -Name Protocol
$TestCertificate = Get-VstsInput -Name testCertificate
$DeploymentGroupName = Get-VstsInput -Name DeploymentGroupName
$AccessToken = Get-VstsInput -Name AccessToken
$Project = Get-VstsInput -Name Project -Default $Env:System_TeamProject
$Replace = Get-VstsInput -Name Replace
$RunAsUserName = Get-VstsInput -Name RunAsUserName
$RunAsPassword = Get-VstsInput -Name RunAsPassword


$Credential = New-Object System.Management.Automation.PSCredential ($AdminUserName, (ConvertTo-SecureString $AdminPassword -AsPlainText -Force))

$InvokeCommandSplat = @{
    ComputerName = $ComputerName
    Credential = $Credential
    ArgumentList = @(
        $AgentPath
        $DeploymentGroupName
        $AccessToken
        $Project
        $ENV:System_TeamFoundationCollectionUri
        $Replace
        $RunAsUserName
        $RunAsPassword
    )
}

if ($Protocol -eq 'HTTPS') {
    $InvokeCommandSplat.Add('UseSSL', $true)
}

if ([Bool]::Parse($TestCertificate)) {
    $SessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
    $InvokeCommandSplat.Add('SessionOption', $SessionOption)
}

$InvokeCommandScript = {
    param (
        $AgentPath,
        $DeploymentGroupName,
        $AccessToken,
        $Project,
        $Url,
        $Replace,
        $RunAsUserName,
        $RunAsPassword
    )
    $ErrorActionPreference = "Stop"

    if (Get-Service -Name VSTS*$Env:ComputerName) {
        return $Env:ComputerName
    }

    Write-Verbose -Message "Creating agent folder in $AgentPath"
    If (-not (Test-Path $AgentPath)) {
        $null = New-Item -Path $AgentPath -ItemType Directory
    }
    Set-Location $AgentPath

    for ($i = 1; $i -lt 100; $i++) {
        $destFolder = "A" + $i.ToString()

        if (-not (Test-Path ($destFolder))) {
            $null = New-Item -Path $destFolder -ItemType Directory
            Set-Location $destFolder
            break
        }
    }

    $agentZip = "$PWD\agent.zip"

    Write-Verbose -Message "Setting TLS security to include 1.2 and existing protocols"
    $DefaultProxy = [System.Net.WebRequest]::DefaultWebProxy
    $securityProtocol = @()
    $securityProtocol += [Net.ServicePointManager]::SecurityProtocol
    $securityProtocol += [Net.SecurityProtocolType]::Tls12
    [Net.ServicePointManager]::SecurityProtocol = $securityProtocol

    Write-Verbose -Message "Downloading v2.144 of the Azure Pipelines agent."
    $WebClient = New-Object Net.WebClient
    $Uri = 'https://vstsagentpackage.azureedge.net/agent/2.144.0/vsts-agent-win-x64-2.144.0.zip'
    if ($DefaultProxy -and (-not $DefaultProxy.IsBypassed($Uri))) {
        $WebClient.Proxy = New-Object Net.WebProxy($DefaultProxy.GetProxy($Uri).OriginalString, $True)
    }
    $WebClient.DownloadFile($Uri, $agentZip)

    Write-Verbose -Message "Unzipping agent to current folder"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory( $agentZip, "$PWD")

    Write-Verbose -Message "Configuring agent with specified settings"

    $ConfigSettings = @(
        '--deploymentgroup'
        "--deploymentgroupname $DeploymentGroupName"
        "--agent $env:COMPUTERNAME"
        "--runasservice"
        "--work _work"
        "--url $Url"
        "--projectname $Project"
        "--auth PAT"
        "--token $AccessToken"
    )

    if ([bool]::Parse($Replace)) {
        $ConfigSettings += "--replace"
    }

    if (-not([String]::IsNullOrWhiteSpace($RunAsUserName)) -and -not([String]::IsNullOrWhiteSpace($RunAsPassword))) {
        $ConfigSettings += "--WindowsLogonAccount $RunAsUserName"
        $ConfigSettings += "--WindowsLogonPassword $RunAsPassword"
    }

    $null = cmd.exe /c "$pwd\config.cmd $($ConfigSettings -join ' ')"
    $null = Remove-Item $agentZip

    $env:COMPUTERNAME
}

Write-Host "Connecting to target computer(s) and configuring agent"
$AgentName = Invoke-Command -ScriptBlock $InvokeCommandScript @InvokeCommandSplat

Write-Host "Ensuring agent has been configured and appears online"
$DeploymentGroupListUrl = "$ENV:System_TeamFoundationCollectionUri$Project/_apis/distributedtask/deploymentgroups?api-version=5.0-preview.1"

Write-Host "Trying url: $DeploymentGroupListUrl"
$AuthToken = [Text.Encoding]::ASCII.GetBytes(('{0}:{1}' -f 'Anything', $AccessToken))
$AuthToken = [Convert]::ToBase64String($AuthToken)
$headers = @{Authorization = ("Basic $AuthToken")}

$DeploymentGroups = Invoke-RestMethod -Uri $DeploymentGroupListUrl -Headers $Headers | Select-Object -ExpandProperty Value

$DeploymentGroupId = $DeploymentGroups | Where-Object {$_.Name -eq $DeploymentGroupName}

$DeploymentGroupDetailsUrl = "$ENV:System_TeamFoundationCollectionUri/$Project/_apis/distributedtask/deploymentgroups/$($DeploymentGroupId.Id)?api-version=5.0-preview.1"

$DeploymentGroupDetails = Invoke-RestMethod -Uri $DeploymentGroupDetailsUrl -Headers $Headers

while (-not($DeploymentGroupDetails.machines.agent | Where-Object { $_.name -eq $AgentName -and $_.Status -eq 'Online'}) ) {
    Write-Host "Waiting to allow agent to connect and rechecking."
    Start-Sleep -Seconds 20
    $DeploymentGroupDetails = Invoke-RestMethod -Uri $DeploymentGroupDetailsUrl -Headers $Headers
}
