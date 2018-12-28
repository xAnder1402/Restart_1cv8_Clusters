Using module .\WinServer.psm1

class HaspServer : WinServer {
    hidden [string[]]$ServiceNames = "HASP Loader"

    hidden static [string]$HASPRegex = '\w*,ID=\d*,NAME=".*",PROT="UDP\(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\)",VER="\d*\.\d*",OS="\w*"'

    hidden static [string]$text_hasp_notfound = "Файлы {0} и {1} не найдены"
    hidden static [string]$text_hasp_empty = "Параметры пусты"

    HaspServer([string]$Hostname) {
        $this.Hostname = $Hostname
        $this.Initialization()
    }

    static [string[]]GetHASPServers([string]$Monitor, [string]$Config) {
        $result = @()
        if ($Monitor -and $Config) {
            if ((Test-Path $Monitor) -and (Test-Path $Config)) {
                $Config = 'set config,filename=' + $Config
                $servers = & $Monitor $Config 'scan servers' 'get serverinfo' | Where-Object { $_ -cmatch [HaspServer]::HASPRegex }
                $servers | ForEach-Object {
                    $server = $_.Split(",")
                    for ($i = 1; $i -lt $server.Count; $i++) {
                        $server.SetValue($server.Get($i).Split("=").Get(1).Trim('"'), $i)
                    }
                    $result += @($server.Get(2).Split(".").Get(0).ToUpper())
                }
            }
            else {
                Write-Host ([HaspServer]::text_hasp_notfound -f $Monitor, $Config) -ForegroundColor Red
                return $result
            }
        }
        else {
            Write-Host [HaspServer]::text_hasp_empty -ForegroundColor Red
            return $result
        }
        return $result
    }
}