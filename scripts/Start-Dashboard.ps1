<#
.SYNOPSIS
    Starts a local HTTP server to host the ShftRota dashboard.
.DESCRIPTION
    Uses Python's http.server (Python 3) or a .NET HttpListener fallback
    to serve the dashboard on localhost. Required because fetch() in app.js
    needs HTTP (not file://) to load config files.
.PARAMETER Port
    Port number to listen on. Default: 8080
.EXAMPLE
    .\Start-Dashboard.ps1
    .\Start-Dashboard.ps1 -Port 3000
#>
[CmdletBinding()]
param(
    [int]$Port = 8080
)

$root = Split-Path -Parent $PSScriptRoot  # Go up from /scripts to project root
if (-not $root) { $root = $PSScriptRoot }

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║  📞  ShftRota — On-Call Dashboard        ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Try Python first (most reliable cross-platform)
$python = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python -ErrorAction SilentlyContinue }

if ($python) {
    Write-Host "  Starting Python HTTP server on port $Port..." -ForegroundColor Green
    Write-Host "  Dashboard: " -NoNewline; Write-Host "http://localhost:$Port" -ForegroundColor Yellow
    Write-Host "  Press Ctrl+C to stop." -ForegroundColor DarkGray
    Write-Host ""
    Start-Process "http://localhost:$Port"
    Push-Location $root
    & $python.Source -m http.server $Port
    Pop-Location
    return
}

# Fallback: .NET HttpListener
Write-Host "  Python not found — using .NET HttpListener on port $Port..." -ForegroundColor Green
Write-Host "  Dashboard: " -NoNewline; Write-Host "http://localhost:$Port/" -ForegroundColor Yellow
Write-Host "  Press Ctrl+C to stop." -ForegroundColor DarkGray
Write-Host ""

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Start-Process "http://localhost:$Port"

$mimeTypes = @{
    '.html' = 'text/html'
    '.css'  = 'text/css'
    '.js'   = 'application/javascript'
    '.json' = 'application/json'
    '.csv'  = 'text/csv'
    '.svg'  = 'image/svg+xml'
    '.png'  = 'image/png'
    '.ico'  = 'image/x-icon'
}

try {
    while ($listener.IsListening) {
        $ctx      = $listener.GetContext()
        $request  = $ctx.Request
        $response = $ctx.Response
        $urlPath  = $request.Url.LocalPath

        if ($urlPath -eq '/') { $urlPath = '/index.html' }
        $filePath = Join-Path $root ($urlPath.TrimStart('/').Replace('/', [IO.Path]::DirectorySeparatorChar))

        if (Test-Path $filePath -PathType Leaf) {
            $ext = [IO.Path]::GetExtension($filePath)
            $response.ContentType = $mimeTypes[$ext] ?? 'application/octet-stream'
            $bytes = [IO.File]::ReadAllBytes($filePath)
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            Write-Host "  200  $urlPath" -ForegroundColor Green
        } else {
            $response.StatusCode = 404
            $msg = [Text.Encoding]::UTF8.GetBytes("404 Not Found: $urlPath")
            $response.OutputStream.Write($msg, 0, $msg.Length)
            Write-Host "  404  $urlPath" -ForegroundColor Red
        }
        $response.OutputStream.Close()
    }
} finally {
    $listener.Stop()
    Write-Host "`n  Server stopped." -ForegroundColor Yellow
}
