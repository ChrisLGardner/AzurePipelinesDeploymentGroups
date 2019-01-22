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


$Credential = New-Object System.Management.Automation.PSCredential ($AdminUserName, (ConvertTo-SecureString $AdminPassword -AsPlainText -Force))

$InvokeCommandSplat = @{
    ComputerName = $ComputerName
    ArgumentList = @(
        $AgentPath
        $DeploymentGroupName
        $AccessToken
        $Project
        $ENV:System_TeamFoundationCollectionUri
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
        $Url
    )
    $ErrorActionPreference = "Stop"

    Write-Verbose -Message "Creating agent folder in $AgentPath"
    If (-not (Test-Path $AgentPath)) {
        New-Item -Path $AgentPath -ItemType Directory
    }
    Set-Location $AgentPath

    for ($i = 1; $i -lt 100; $i++) {
        $destFolder = "A" + $i.ToString()

        if (-not (Test-Path ($destFolder))) {
            New-Item -Path $destFolder -ItemType Directory
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

    if ([bool]::Parse($Replace)) {
        .\config.cmd --deploymentgroup --deploymentgroupname "$DeploymentGroupName" --agent "$env:COMPUTERNAME" --runasservice --work "_work" --url "$Url" --projectname "$Project" --auth PAT --token "$AccessToken" --replace
    }
    else {
        .\config.cmd --deploymentgroup --deploymentgroupname "$DeploymentGroupName" --agent "$env:COMPUTERNAME" --runasservice --work "_work" --url "$Url" --projectname "$Project" --auth PAT --token "$AccessToken"
    }
    Remove-Item $agentZip
}

Invoke-Command -ScriptBlock $InvokeCommandScript @InvokeCommandSplat
