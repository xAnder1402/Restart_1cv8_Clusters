Using module .\WinServer.psm1

class MssqlServer : WinServer {
    hidden [string[]]$ServiceNames = "MSSQLSERVER", "SQLSERVERAGENT"

    MssqlServer([string]$Hostname) {
        $this.Hostname = $Hostname
        $this.Initialization()
    }
}