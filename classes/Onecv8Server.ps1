Using module .\WinServer.psm1

class Onecv8Server : WinServer {
    hidden [string[]]$ProcessNames = "ragent", "rmngr", "rphost", "ras", "rac"

    hidden [string]$Version
    hidden [int]$Port = 1540
    hidden [string]$Login = ""
    hidden [string]$Password = ""

    hidden [string]$VersionRegex = "8\.\d\.\d*\.\d*"
    hidden [string]$InstallLocation = ""
    hidden [string]$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    hidden [string[]]$RegValueNames = "InstallLocation", "DisplayName"
    hidden [int]$RegValueIndex = 0
    hidden [string[]]$WorkingServers = @()
    hidden [string[]]$SQLServers = @()

    hidden [string]$text_version_notfound = "Версия {0} не соотвествует версии 1С"
    hidden [string]$text_installlocation_get = "Получение каталога 1С версии {0} сервера {1}"
    hidden [string]$text_installlocation_notfound = "Каталог 1С на сервере {0} не найден"
    hidden [string]$text_workservers_get = "Получение рабочих серверов 1С версии {0} сервера {1}"
    hidden [string]$text_sqlservers_get = "Получение SQL серверов 1С версии {0} сервера {1}"
    hidden [string]$text_1cfolders_get = "Получение каталогов кеша 1С версии {0} сервера {1}"
    hidden [string]$text_object_notfound = "Объект {0} не создан"

    hidden Onecv8Server() {}

    Onecv8Server([string]$Version, [string]$Hostname) {
        $this.Version = $Version
        $this.Hostname = $Hostname
        $this.Initialization()
    }
	
    Onecv8Server([string]$Version, [string]$Hostname, [int]$Port) {
        $this.Version = $Version
        $this.Hostname = $Hostname
        $this.Port = $Port
        $this.Initialization()
    }
	
    Onecv8Server([string]$Version, [string]$Hostname, [int]$Port, [string]$Login, [string]$Password) {
        $this.Version = $Version
        $this.Hostname = $Hostname
        $this.Port = $Port
        $this.Login = $Login
        $this.Password = $Password
        $this.Initialization()
    }
	
    hidden [void]Initialization() {
        if (!$this.Version -or !$this.Hostname -or !$this.Port) {
            Write-Host ($this.text_hostname_empty -f $this.Hostname) -ForegroundColor Red
            $this = [Onecv8Server]::new()
            return
        }
        elseif ($this.Version -notmatch $this.VersionRegex) {
            Write-Host ($this.text_version_notfound -f $this.Version) -ForegroundColor Red
            $this = [Onecv8Server]::new()
            return
        }
        elseif (!$this.TestConnection()) {
            Write-Host ($this.text_hostname_notfound -f $this.Hostname) -ForegroundColor Red
            $this = [Onecv8Server]::new()
            return
        }
        Write-Host ($this.text_installlocation_get -f $this.Version, $this.Hostname)
        $this.SetInstallLocation()
        if (!$this.InstallLocation) {
            $this = [Onecv8Server]::new()
            return
        }
        Write-Host ($this.text_workservers_get -f $this.Version, $this.Hostname)
        $this.SetWorkingServers()
        Write-Host ($this.text_sqlservers_get -f $this.Version, $this.Hostname)
        $this.SetSQLServers()
        Write-Host ($this.text_1cfolders_get -f $this.Version, $this.Hostname)
        $this.SetFolders()
    }

    [string[]]GetWorkingServers() { return $this.WorkingServers }
	
    hidden [void]SetWorkingServers() {
        if ($this.Version -cmatch $this.VersionRegex) {
            $comObject = "V8{0}.COMConnector" -f $this.Version.Split(".")[1]
            $obj = $null
            try { $obj = New-Object -COMObject $comObject }
            catch { Write-Host ($this.text_object_notfound -f $comObject) -ForegroundColor Red }
            if ($obj) {
                $ServerAgent = $null
                try { $ServerAgent = $obj.ConnectAgent("tcp://" + $this.Hostname + ":" + $this.Port) }
                catch [System.Runtime.InteropServices.COMException] { Write-Host ($this.text_object_notfound -f $comObject) -ForegroundColor Red } 
                if ($ServerAgent) {
                    $Clusters = $ServerAgent.GetClusters()
                    $Clusters | ForEach-Object {
                        $ServerAgent.Authenticate($_, $Login, $Password)
                        $WorkingServers = $ServerAgent.GetWorkingServers($_)
                        $WorkingServers | ForEach-Object { $this.WorkingServers += @($_.HostName) }
                    }
                }
            }
            $obj = $null
        }
    }
	
    [string]GetInstallLocation() { return $this.InstallLocation }

    hidden [void]SetInstallLocation() {
        $this.InstallLocation = Invoke-Command -ComputerName $this.Hostname -ScriptBlock {
            $result = Get-ChildItem $Using:this.RegPath
            foreach ($ValueName in $Using:this.RegValueNames) {
                $result = $result | Where-Object { $_.GetValueNames().Contains($ValueName) }
                $result = $result | Where-Object { $_.GetValue($ValueName).Contains($Using:this.Version) }
            }
            if ($result) { return $result[0].GetValue(($Using:this.RegValueNames)[$Using:this.RegValueIndex]) }
            else { return $null }
        }
        if (!$this.InstallLocation) {
            Write-Host ($this.text_installlocation_notfound -f $this.Hostname) -ForegroundColor Red
        }
        $this.ServicePath = $this.InstallLocation
        $this.ProcessPath = $this.InstallLocation
    }

    [string[]]GetSQLServers() {	return $this.SQLServers }

    hidden [void]SetSQLServers() {
        $result = @()
        if ($this.InstallLocation) {
            if ($this.Version -cmatch $this.VersionRegex) {
                $filelist = ""
                switch ($this.Version.Split(".")[1]) {
                    2 { $filelist = "1CV8Reg.lst" }
                    3 { $filelist = "1CV8Clst.lst" }
                    default { return }
                }
                $path = Join-Path (Split-Path $this.InstallLocation -Parent) ("srvinfo\reg_$($this.Port + 1)\$filelist")
                $result = Invoke-Command -ComputerName $this.Hostname -ScriptBlock {
                    $filelist = Get-Content $Using:path
                    return $filelist | Where-Object { $_.Contains("MSSQLServer") } | ForEach-Object { $_.Split(",")[4].Trim("""") } | Get-Unique
                }
                $result.ToUpper()
            }
        }
        $this.SQLServers = $result
    }

    hidden [void]SetFolders() {
        $result = @()
        if ($this.InstallLocation) {
            $result += Join-Path (Split-Path $this.InstallLocation -Parent) ("srvinfo\reg_$($this.Port + 1)\snccntx*")
            $verfolder = ""
            switch ($this.Version.Split(".")[1]) {
                2 { $verfolder = "1Cv82" }
                3 { $verfolder = "1cv8" }
                default { return }
            }
            $result += Join-Path $env:ProgramData "1C\$verfolder\*.pfl"
        }
        $this.Folders = $result
    }
}