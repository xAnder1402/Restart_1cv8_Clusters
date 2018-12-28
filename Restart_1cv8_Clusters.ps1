. .\classes\Onecv8Server.ps1
. .\classes\HaspServer.ps1
. .\classes\MssqlServer.ps1
. .\external\Write-Menu.ps1 # https://github.com/QuietusPlus/Write-Menu

$timestamp = Get-Date -Format yyyyMMdd-HHmm
Start-Transcript -Path ".\logs\$timestamp.log"

# 1cv8 Configuration
$1cv8_clusters = @( # , @("Version", "Server", Port, "Login", "Password", "WorkingServers", "SQLServers")
    @("8.2.19.80", "1C", 1540, "", ""),
    @("8.3.11.3034", "1C", 1740, "", ""),
    @("8.2.19.80", "DEV", 1540, "", ""),
    @("8.3.11.3034", "DEV", 1740, "", "")
)
$1cv8_objects = @()
# Hasp Configuration
$hasp_monitor = ".\hasp\HaspMonitor.exe"
$hasp_configs = ".\hasp\nethasp.ini"
$hasp_objects = @()
# Mssql Configuration
$mssql_objects = @()
# Menu Configuration
$menu_main_title = "Выберете {0} для перезапуска:"
$menu_main_entries = "Сервер 1С:Предприятия 8", "Сервер ключей HASP", "Сервер Microsoft SQL"
# Script Configuration
$text_service = "службы"
$text_service_start = "Служба {0} запущена на сервере {1}"
$text_service_notstart = "Служба {0} не запущена на сервере {1}"
$text_check_exit = "Выход через:"

# Draw menu
$menu_main_result = Write-Menu -Title ($menu_main_title -f $text_service) -Entries $menu_main_entries -MultiSelect
# Draw 1v8 servers menu
if ($menu_main_result.Contains($menu_main_entries[0])) {
    $menu_1cv8_entries = $1cv8_clusters | ForEach-Object { "$($_[1]):$($_[2]) - $($_[0])" }
    if ($menu_main_entries) {
        $menu_1cv8_result = Write-Menu -Title ($menu_main_title -f $menu_main_entries[0]) -Entries $menu_1cv8_entries -MultiSelect
        # Added only hecked items
        $result = @()
        foreach($menu in $menu_1cv8_result) {
            foreach($cluster in $1cv8_clusters) {
                if ($menu.Contains($cluster[0]) -and $menu.Contains($cluster[1]) -and $menu.Contains($cluster[2])) {
                    $result += , $cluster # https://stackoverflow.com/questions/6157179/append-an-array-to-an-array-of-arrays-in-powershell
                    break
                }
            }
        }
        Write-Host "`n$($menu_main_entries[0])`n"
        $1cv8_clusters = $result
        $1cv8_clusters | ForEach-Object {
            $1cv8_object = [Onecv8Server]::new($_[0], $_[1], $_[2], $_[3], $_[4])
            if ($1cv8_object.GetInstallLocation()) { $1cv8_objects += $1cv8_object }
            else { $1cv8_object = $null }
            Write-Host
        }
        $1cv8_wservers = @()
        $1cv8_objects | ForEach-Object {
            $1cv8_wservers += $_.GetWorkingServers()
        }
    }
}
# Draw hasp servers menu
if ($menu_main_result.Contains($menu_main_entries[1])) {
    $result = @()
    # Get hasp servers
    foreach($hasp_config in $hasp_configs) {
        $result += [HaspServer]::GetHASPServers($hasp_monitor, $hasp_config)
    }
    if ($result) { $hasp_servers = $result }
    if ($hasp_servers) {
        $menu_hasp_result = Write-Menu -Title ($menu_main_title -f $menu_main_entries[1]) -Entries $hasp_servers -MultiSelect
        Write-Host "`n$($menu_main_entries[1])`n"
        $menu_hasp_result | ForEach-Object {
            $hasp_objects += [HaspServer]::new($_)
        }
    }
}
# Draw mssql servers menu
if ($menu_main_result.Contains($menu_main_entries[2])) {
    $mssql_servers = ""
    if ($1cv8_objects) {
        $result = @()
		foreach($1cv8_object in $1cv8_objects) {
			$result += $1cv8_object.GetSQLServers()
		}
		if ($result) { $mssql_servers = $result.ToUpper() | Get-Unique }
    }
    if ($mssql_servers) {
        $menu_mssql_result = Write-Menu -Title ($menu_main_title -f $menu_main_entries[2]) -Entries $mssql_servers -MultiSelect
        Write-Host "`n$($menu_main_entries[2])`n"
        $menu_mssql_result | ForEach-Object {
            $mssql_objects += [MssqlServer]::new($_)
        }
    }
}

Clear-Host
# Stop 1cv8 services
if ($menu_main_result.Contains($menu_main_entries[0])) {
    $1cv8_objects | ForEach-Object {
        $_.StopServices()
        $_.StopProcesses()
        $_.ClearFolders()
    }
}
Write-Host
# Stop and start hasp services
if ($menu_main_result.Contains($menu_main_entries[1])) {
    $hasp_objects | ForEach-Object {
        $_.RestartServices()
    }
}
Write-Host
# Stop and start msql services
if ($menu_main_result.Contains($menu_main_entries[2])) {
    $mssql_objects | ForEach-Object {
        $_.RestartServices()
    }
}
Write-Host
# Start 1cv8 services
if ($menu_main_result.Contains($menu_main_entries[0])) {
    $1cv8_objects | ForEach-Object {
        $_.StartServices()
    }
}

Clear-Host
# Check services
$service_result = @()
$1cv8_objects | ForEach-Object {
    $service_result += $_.GetServices()
}
$hasp_objects | ForEach-Object {
    $service_result += $_.GetServices()
}
$mssql_objects | ForEach-Object {
    $service_result += $_.GetServices()
}
$1cv8_objects = $null
$hasp_objects = $null
$mssql_objects = $null

if ($service_result) {
    $service_result = $service_result | Where-Object { $_ }
    $service_result | ForEach-Object {
        if ($_.State -eq "Running") {
            Write-Host ($text_service_start -f $_.DisplayName, $_.PSComputerName) -ForegroundColor Green
        } else {
            Write-Host ($text_service_notstart -f $_.DisplayName, $_.PSComputerName) -ForegroundColor Red
        }
    }
    Write-Host
    if (($service_result | Where-Object { $_.State -ne "Running" }).Count) {
        $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } else {
        3..1 | ForEach-Object {
            Write-Host "`r$text_check_exit $_ " -NoNewline
            Start-Sleep -Seconds 1
        }
    }
}

Stop-Transcript