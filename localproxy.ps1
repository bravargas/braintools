param (
    [int]$LocalPort = 8082 # Default port for the proxy
)

try {
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $LocalPort)
    $listener.Start()
    Write-Host "Proxy is listening on port $LocalPort..."
} catch {
    Write-Host "Error: Unable to start listener on port $LocalPort. $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Graceful stop mechanism
$stopProxy = $false
Register-EngineEvent -SourceIdentifier ConsoleCancelEvent -Action {
    Write-Host "Stopping proxy..." -ForegroundColor Yellow
    $stopProxy = $true
}

while (-not $stopProxy) {
    try {
        # Accept incoming connection
        if ($listener.Pending()) {
            $client = $listener.AcceptTcpClient()
            $clientEndpoint = $client.Client.RemoteEndPoint
            Write-Host "Incoming connection accepted from ${clientEndpoint.Address}:${clientEndpoint.Port}"

            # Extract the destination host and port from the incoming connection
            $remoteEndpoint = $client.Client.RemoteEndPoint
            $remoteHost = $remoteEndpoint.Address.ToString()
            $remotePort = $remoteEndpoint.Port
            Write-Host "Forwarding connection to ${remoteHost}:${remotePort}"

            # Create a new TCP connection to the same host and port
            $remote = New-Object System.Net.Sockets.TcpClient
            try {
                $remote.Connect($remoteHost, $remotePort)
                Write-Host "Connection established with ${remoteHost}:${remotePort}"
            } catch {
                Write-Host "Error: Unable to connect to ${remoteHost}:${remotePort}. $($_.Exception.Message)" -ForegroundColor Red
                $client.Close()
                continue
            }

            # Get the streams for both connections
            $clientStream = $client.GetStream()
            $remoteStream = $remote.GetStream()

            # Buffer for reading and writing data
            $buffer = New-Object byte[] 1024
            $bytesRead = 0

            # Log and copy data from client to remote server
            Write-Host "Starting data transfer from client to remote server..."
            while (($bytesRead = $clientStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $data = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
                Write-Host "Data from client: $data"
                $remoteStream.Write($buffer, 0, $bytesRead)
                $remoteStream.Flush()
            }

            # Log and copy data from remote server to client
            Write-Host "Starting data transfer from remote server to client..."
            while (($bytesRead = $remoteStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $data = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
                Write-Host "Data from server: $data"
                $clientStream.Write($buffer, 0, $bytesRead)
                $clientStream.Flush()
            }

            # Close connections
            $client.Close()
            $remote.Close()
        }
    } catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Stop the listener
$listener.Stop()
Write-Host "Proxy stopped."