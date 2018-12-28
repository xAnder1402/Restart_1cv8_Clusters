class WinServer {
    hidden [string]$Hostname
    hidden [string[]]$ServiceNames = @()
    hidden [string]$ServicePath = ""
    hidden [psobject]$Services = @()
    hidden [string[]]$ProcessNames = @()
    hidden [string]$ProcessPath = ""
    hidden [string[]]$Folders = @()

    hidden [int]$TestConnections = 3

    hidden [string]$text_hostname_empty = "Данные о сервере {0} пусты"
    hidden [string]$text_hostname_notfound = "Сервер {0} не найден"
    hidden [string]$text_hostname_test = "Тест соединения с сервером {0}"
    hidden [string]$text_service_stop = "Останов службы {0} на сервере {1}"
    hidden [string]$text_service_start = "Запуск службы {0} на сервере {1}"
    hidden [string]$text_process_stop = "Останов процесса {0} на сервере {1}"
    hidden [string]$text_file_delete = "Удаление файлов {0} на сервере {1}"

    hidden WinServer() {}

    WinServer([string]$Hostname) {
        $this.Hostname = $Hostname
        $this.Initialization()
    }

    [void]Initialization() {
        if (!$this.Hostname) {
            Write-Host ($this.text_hostname_empty -f $this.Hostname) -ForegroundColor Red
            $this = [WinServer]::new()
            return
        }
        elseif (!$this.TestConnection()) {
            Write-Host ($this.text_hostname_notfound -f $this.Hostname) -ForegroundColor Red
            $this = [WinServer]::new()
            return
        }
    }

    [string]GetHostname() { return $this.Hostname }

    hidden [void]SetServices([string[]]$ServiceNames, [string]$ServicePath) {
        $this.ServiceNames = $ServiceNames
        $this.ServicePath = $ServicePath
    }

    [psobject]GetServices() {
        $result = @()
        if ($this.ServiceNames) {
            $this.ServiceNames | ForEach-Object {
                $ServiceName = $_
                $result += Invoke-Command -ComputerName $this.Hostname -ScriptBlock {
                    Get-WmiObject win32_service | Where-Object {
                        $_.Name.Contains($Using:ServiceName) -and $_.PathName.Contains($Using:this.ServicePath)
                    }
                }
            }
        }
        elseif ($this.ServicePath) {
            $result = Invoke-Command -ComputerName $this.Hostname -ScriptBlock {
                Get-WmiObject win32_service | Where-Object {
                    $_.PathName.Contains($Using:this.ServicePath)
                }
            }
        }
        return $result
    }

    hidden [void]SetProcesses([string[]]$ProcessNames, [string]$ProcessPath) {
        $this.ProcessNames = $ProcessNames
        $this.ProcessPath = $ProcessPath
    }

    hidden [void]SetFolders([string[]]$Folders) {
        $this.Folders = $Folders
    }

    [bool]TestConnection() { return $this.TestConnection($this.TestConnections) }

    [bool]TestConnection([int]$Count) {
        Write-Host ($this.text_hostname_test -f $this.Hostname)
        return @(Test-Connection $this.Hostname -Count $Count -BufferSize 256 -EA 0).Count -eq $Count
    }

    [void]StopServices() {
        $this.Services = $this.GetServices()
        $this.Services | Where-Object { $_.State -eq "Running" } | ForEach-Object {
            $Service = $_
            Write-Host ($this.text_service_stop -f $Service.DisplayName, $this.Hostname)
            Invoke-Command -ComputerName $this.Hostname -ScriptBlock { Stop-Service -Name $Using:Service.Name -Force }
        }
    }

    [void]StartServices() {
        $this.Services = $this.GetServices()
        $this.Services | Where-Object { $_.State -eq "Stopped" } | ForEach-Object {
            $Service = $_
            Write-Host ($this.text_service_start -f $Service.DisplayName, $this.Hostname)
            Invoke-Command -ComputerName $this.Hostname -ScriptBlock { Start-Service -Name $Using:Service.Name }
        }
    }

    [void]RestartServices() {
        $this.StopServices()
        $this.StartServices()
    }

    [psobject]GetProcesses() {
        $result = @()
        if ($this.ProcessNames) {
            $this.ProcessNames | ForEach-Object {
                $ProcessName = $_
                $result += Invoke-Command -ComputerName $this.Hostname -ScriptBlock {
                    Get-Process | Where-Object {
                        $_.Name.Contains($Using:ProcessName) -and $_.Path.Contains($Using:this.ProcessPath)
                    }
                }
            }
        }
        elseif ($this.ProcessPath) {
            $result = Invoke-Command -ComputerName $this.Hostname -ScriptBlock {
                Get-Process | Where-Object {
                    $_.Path.Contains($Using:this.ProcessPath)
                }
            }
        }
        return $result
    }

    [void]StopProcesses() {
        $Processes = $this.GetProcesses()
		if ($Processes.Count -ne 0) {
			$Processes | ForEach-Object {
                $Process = $_
                Write-Host ($this.text_process_stop -f $Process.Name, $this.Hostname)
                Invoke-Command -ComputerName $this.Hostname -ScriptBlock { Stop-Process -Id $Using:Process.Id -EA 0 -Force }
			}
		}
    }

    [void]ClearFolders() {
        $this.Folders | ForEach-Object {
            $Folder = $_
            Write-Host ($this.text_file_delete -f $Folder, $this.Hostname)
            Invoke-Command -ComputerName $this.Hostname -ScriptBlock { Remove-Item $Using:Folder -Recurse -Force }
        }
    }
}