# Force-load the local module so we test the latest code
$ModulePath = Join-Path $PSScriptRoot "PsUi\PsUi.psd1"
if (Test-Path $ModulePath) {
    Write-Host "Importing module from: $ModulePath" -ForegroundColor Cyan
    Import-Module $ModulePath -Force
}
else {
    Import-Module PsUi -Force
}

# Verify C# types loaded
try {
    $SafeLog = [PsUi.AsyncObservableCollection[string]]::new()
    $SafeLog.Add("System Ready.")
}
catch {
    Write-Error "CRITICAL: PsUi types not found. C# compilation failed."
    return
}

# Demo variables for auto-capture (used in Advanced tab)
$configPath = "C:\App\Settings\config.json"
$maxRetries = 3
$appVersion = "2.5.1"

function Format-Greeting ([string]$Name) { "Hello, $Name! Welcome to PsUi." }

function Search-FileSystem {
    <#
    .SYNOPSIS
        Searches for files matching a pattern with size, age, and type filters.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Pattern = '*',

        [ValidateRange(0, 10000)]
        [int]$MinSizeKB = 0,

        [ValidateRange(1, 365)]
        [int]$MaxAgeDays = 30,

        [ValidateSet('All', 'Documents', 'Images', 'Scripts', 'Logs')]
        [string]$Type = 'All',

        [switch]$Recurse,

        [switch]$Hidden
    )

    $typePatterns = @{
        'All'       = '*'
        'Documents' = '*.txt', '*.doc*', '*.pdf', '*.md'
        'Images'    = '*.jpg', '*.jpeg', '*.png', '*.gif', '*.bmp'
        'Scripts'   = '*.ps1', '*.psm1', '*.py', '*.bat', '*.cmd'
        'Logs'      = '*.log', '*.txt'
    }

    $cutoffDate = (Get-Date).AddDays(-$MaxAgeDays)
    $minBytes   = $MinSizeKB * 1KB

    $params = @{
        Path   = $Path
        Filter = $Pattern
        File   = $true
    }
    if ($Recurse) { $params.Recurse = $true }
    if ($Hidden)  { $params.Force = $true }

    Get-ChildItem @params -ErrorAction SilentlyContinue |
        Where-Object {
            $file = $_
            $file.LastWriteTime -ge $cutoffDate -and
            $file.Length -ge $minBytes -and
            ($Type -eq 'All' -or ($typePatterns[$Type] | Where-Object { $file.Name -like $_ }))
        } |
        Select-Object Name,
            @{N='SizeKB';   E={[math]::Round($_.Length / 1KB, 1)}},
            @{N='Modified'; E={$_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')}},
            @{N='Type';     E={$_.Extension.TrimStart('.').ToUpper()}},
            FullName
}

function Test-ConnectionStatus {
    <#
    .SYNOPSIS
        Tests network connectivity using ICMP, TCP, or HTTP.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target,

        [ValidateRange(1, 10)]
        [int]$Count = 3,

        [ValidateRange(100, 5000)]
        [int]$TimeoutMs = 1000,

        [ValidateSet('ICMP', 'TCP', 'HTTP')]
        [string]$Protocol = 'ICMP',

        [switch]$Quiet
    )

    $results = [System.Collections.Generic.List[object]]::new()

    for ($i = 1; $i -le $Count; $i++) {
        if (!$Quiet) {
            Write-Progress -Activity "Testing $Target" -Status "Attempt $i of $Count" -PercentComplete (($i / $Count) * 100)
        }

        $start = Get-Date
        $success = $false
        $latency = 0

        try {
            switch ($Protocol) {
                'ICMP' {
                    $ping = Test-Connection -ComputerName $Target -Count 1 -ErrorAction Stop
                    $success = $true
                    $latency = $ping.ResponseTime
                }
                'TCP' {
                    $tcp = [System.Net.Sockets.TcpClient]::new()
                    $connect = $tcp.BeginConnect($Target, 80, $null, $null)
                    $success = $connect.AsyncWaitHandle.WaitOne($TimeoutMs)
                    if ($success) {
                        try { $tcp.EndConnect($connect) } catch { $success = $false }
                    }
                    $latency = ((Get-Date) - $start).TotalMilliseconds
                    $tcp.Close()
                }
                'HTTP' {
                    $uri = if ($Target -match '^https?://') { $Target } else { "http://$Target" }
                    $response = Invoke-WebRequest -Uri $uri -TimeoutSec ($TimeoutMs / 1000) -UseBasicParsing -ErrorAction Stop
                    $success = $response.StatusCode -eq 200
                    $latency = ((Get-Date) - $start).TotalMilliseconds
                }
            }
        }
        catch {
            $success = $false
            $latency = $TimeoutMs
        }

        $results.Add([PSCustomObject]@{
            Attempt  = $i
            Target   = $Target
            Protocol = $Protocol
            Success  = $success
            LatencyMs = [math]::Round($latency, 0)
            Time     = (Get-Date).ToString('HH:mm:ss')
        })

        Start-Sleep -Milliseconds 200
    }

    Write-Progress -Activity "Testing $Target" -Completed

    $successCount = ($results | Where-Object Success).Count
    $avgLatency   = ($results | Where-Object Success | Measure-Object LatencyMs -Average).Average

    Write-Host "Results: $successCount/$Count successful" -ForegroundColor $(if ($successCount -eq $Count) { 'Green' } else { 'Yellow' })
    if ($avgLatency) {
        Write-Host "Average latency: $([math]::Round($avgLatency, 0))ms" -ForegroundColor Cyan
    }

    return $results
}

New-UiWindow -Title "PsUi - Feature Showcase" -LayoutMode Responsive -Theme Dark -Width 1000 -Height 750 -Splash -Debug -Content {

    # Window-level keyboard shortcuts
    Register-UiHotkey -Key "Ctrl+S" -NoAsync -Action {
        Show-UiDialog -Title "Save" -Message "Ctrl+S pressed! In a real app, this would save your work." -Type Info -Buttons OK
    }
    
    Register-UiHotkey -Key "F5" -NoAsync -Action {
        Show-UiDialog -Title "Refresh" -Message "F5 pressed! Refresh action would go here." -Type Info -Buttons OK
    }
    
    # Escape to cancel running async operations
    Register-UiHotkey -Key "Escape" -NoAsync -Action {
        $session = Get-UiSession
        if ($session.ActiveExecutor -and $session.ActiveExecutor.IsRunning) {
            $confirm = Show-UiConfirmDialog -Title "Cancel Operation" -Message "Cancel the running task?"
            # Re-check after dialog - task may have finished while waiting for user
            if ($confirm -and $session.ActiveExecutor -and $session.ActiveExecutor.IsRunning) {
                Stop-UiAsync
            }
        }
    }

    # TAB: Introduction
    New-UiTab -Header "Welcome" -Content {
        New-UiLabel -Text "Welcome to PsUi" -Style Title -FullWidth
        New-UiLabel -Text "For building UIs in PowerShell without the misery." -Style Note -FullWidth
        New-UiSeparator -FullWidth

        New-UiPanel -Header "What Is PsUi?" -FullWidth -Content {
            New-UiLabel -Text "PsUi lets you create Windows GUIs with a declarative PowerShell syntax. Write New-UiButton and New-UiInput instead of wrestling with XAML. The module handles threading, theming, and control registration automatically." -Style Body -FullWidth
        }

        New-UiPanel -Header "Core Concepts" -FullWidth -Content {
            New-UiLabel -Text "Controls and Variables" -Style Header
            New-UiLabel -Text "Every input control takes a -Variable parameter that becomes a PowerShell variable in button actions." -Style Body -FullWidth

            New-UiLabel -Text "Async by Default" -Style Header
            New-UiLabel -Text "Button actions run in background threads. Write-Host and Write-Progress output appears in the window automatically." -Style Body -FullWidth
        }

        New-UiPanel -Header "Getting Started" -Content {
            New-UiLabel -Text "Explore the tabs, then try:" -Style Body -FullWidth
            New-UiLabel -Text "  Import-Module PsUi" -Style Note -FullWidth
            New-UiLabel -Text "  New-UiWindow -Title 'Hello' -Content { New-UiButton -Text 'Click' -Action { Write-Host 'Hi!' } }" -Style Note -FullWidth
        }
    }

    # TAB: Controls Gallery
    New-UiTab -Header "Controls" -Content {
        New-UiLabel -Text "Controls Gallery" -Style Title -FullWidth
        New-UiLabel -Text "Input controls, labels, cards, grids, and buttons for building forms." -Style Note -FullWidth
        New-UiSeparator -FullWidth

        New-UiPanel -Header "Text Inputs" -ShowSourceButton -Content {
            New-UiInput -Label "Project Name" -Variable "ProjectName" -Placeholder "Enter project name..."
            New-UiInput -Label "Tags" -Variable "Tags" -Placeholder "tag1, tag2, tag3..."
            New-UiTextArea -Label "Description" -Variable "Description" -Rows 3 -Placeholder "Enter description..."
        }

        New-UiPanel -Header "Selection Controls" -ShowSourceButton -Content {
            New-UiDropdown -Label "Priority" -Variable "Priority" -Items @('Low', 'Medium', 'High', 'Critical') -Default 'Medium'
            New-UiToggle -Label "Mark as Favorite" -Variable "IsFavorite" -Checked
            New-UiToggle -Label "Send Email Notification" -Variable "SendEmail"
            New-UiRadioGroup -Label "Status" -Variable "Status" -Items @('Draft', 'Active', 'Complete') -Default 'Draft'
        }

        New-UiPanel -Header "Dropdown Buttons" -ShowSourceButton -Content {
            New-UiLabel -Text "New-UiDropdownButton creates compact toolbar-style buttons with popup menus:" -Style Body -FullWidth

            New-UiCard -Header "File Browser Toolbar" -Icon "FolderOpen" -Stretch -Content {
                New-UiPanel -Orientation Horizontal -Content {
                    New-UiGlyph -Name 'FolderOpen' -Size 18
                    New-UiLabel -Text "C:\Projects\MyApp" -Style Body -WPFProperties @{ Margin = [System.Windows.Thickness]::new(8,0,16,0); VerticalAlignment = 'Center' }
                    New-UiDropdownButton -Items @('Name', 'Date Modified', 'Type', 'Size') -Default 'Name' -Icon 'Sort' -Tooltip "Sort by" -Variable 'fileSortBy'
                    New-UiDropdownButton -Items @('Ascending', 'Descending') -Default 'Ascending' -Icon 'Up' -Tooltip "Sort order" -Variable 'fileSortOrder'
                    New-UiDropdownButton -Items @('Large Icons', 'Medium Icons', 'Small Icons', 'List', 'Details', 'Tiles') -Default 'Details' -Icon 'View' -Tooltip "Change view" -ShowText -Variable 'fileViewMode'
                }
            }

            New-UiCard -Header "Theme Selector" -Icon "ColorBackground" -Stretch -Content {
                New-UiPanel -Orientation Horizontal -Content {
                    New-UiLabel -Text "Quick theme:" -Style Body -WPFProperties @{ VerticalAlignment = 'Center'; Margin = [System.Windows.Thickness]::new(0,0,8,0) }
                    New-UiDropdownButton -Items @('Light', 'Dark', 'Nord', 'Solarized Light', 'Solarized Dark', 'High Contrast') -Default 'Dark' -Icon 'Brightness' -Tooltip "Switch theme" -ShowText -Variable 'quickTheme' -OnChange {
                        param($theme)
                        Write-Host "Theme selected: $theme" -ForegroundColor Cyan
                    }
                }
            }

            New-UiButton -Text "Show Current Selections" -Icon "Info" -Action {
                Write-Host "=== Dropdown Button Values ===" -ForegroundColor Cyan
                Write-Host "File View: $fileViewMode"
                Write-Host "Sort By: $fileSortBy"
                Write-Host "Sort Order: $fileSortOrder"
                Write-Host "Quick Theme: $quickTheme"
            }
        }

        New-UiPanel -Header "Collapsible Sections" -ShowSourceButton -Content {
            New-UiLabel -Text "New-UiExpander creates collapsible sections - click headers to toggle:" -Style Body -FullWidth

            New-UiExpander -Header "Basic Options" -IsExpanded -Content {
                New-UiToggle -Label "Enable feature" -Variable "expanderFeature"
                New-UiInput -Label "Value" -Variable "expanderValue" -Placeholder "Enter value..."
            }

            New-UiExpander -Header "Advanced Options (collapsed by default)" -Content {
                New-UiToggle -Label "Debug mode" -Variable "expanderDebug"
                New-UiToggle -Label "Verbose logging" -Variable "expanderVerbose"
                New-UiInput -Label "Custom path" -Variable "expanderPath" -Placeholder "C:\..."
            }
        }

        New-UiPanel -Header "Links and Hyperlinks" -ShowSourceButton -Content {
            New-UiLabel -Text "New-UiLink creates clickable hyperlinks with browser or custom actions:" -Style Body -FullWidth
            New-UiLink -Url 'https://github.com' -Text 'GitHub - Opens in browser'
            New-UiLink -Text 'Run Custom Action' -Action {
                Show-UiDialog -Title 'Custom Action' -Message 'Links can run any scriptblock, not just open URLs.' -Type Info -Buttons OK
            }
        }

        New-UiPanel -Header "Conditional Enabling (-EnabledWhen)" -ShowSourceButton -Content {
            New-UiLabel -Text "Controls can enable/disable based on other control values:" -Style Body -FullWidth

            # Top-level toggle - controls the advanced settings toggle
            New-UiToggle -Label "Show Configuration Options" -Variable "showConfig"

            # This toggle depends on the one above; unchecked when disabled
            New-UiToggle -Label "Enable Advanced Settings" -Variable "enableAdvanced" -EnabledWhen 'showConfig' -ClearIfDisabled

            # Input enabled only when toggle is checked; cleared when disabled
            New-UiInput -Label "Server URL" -Variable "serverUrl" -Placeholder "https://..." -EnabledWhen 'enableAdvanced' -ClearIfDisabled

            # Button enabled only when input has content
            New-UiButton -Text "Connect" -Icon "Globe" -Accent -EnabledWhen 'serverUrl' -Action {
                Write-Host "Connecting to: $serverUrl" -ForegroundColor Cyan
            }
        }

        New-UiPanel -Header "Date, Time and Sliders" -ShowSourceButton -Content {
            New-UiDatePicker -Label "Due Date" -Variable "DueDate"
            New-UiTimePicker -Label "Start Time" -Variable "StartTime" -Default "09:00"
            New-UiSlider -Label "Completion" -Variable "Completion" -Minimum 0 -Maximum 100 -Default 25 -ShowValueLabel -ValueLabelFormat "{0:N0}%"
        }

        New-UiPanel -Header "Credential Input" -ShowSourceButton -Content {
            New-UiLabel -Text "New-UiCredential creates a username/password pair that hydrates as PSCredential:" -Style Body -FullWidth

            New-UiCredential -Variable "demoCreds" -Label "Service Account"

            New-UiButton -Text "Show Credential" -Icon "Key" -Action {
                if ($demoCreds) {
                    Write-Host "Username: $($demoCreds.UserName)" -ForegroundColor Cyan
                    Write-Host "Password: (SecureString, length $($demoCreds.Password.Length))" -ForegroundColor Gray
                }
                else {
                    Write-Host "No credentials entered" -ForegroundColor Yellow
                }
            }
        }

        New-UiPanel -Header "Glyphs and Images" -ShowSourceButton -LayoutStyle Wrap -Content {
            New-UiLabel -Text "New-UiGlyph displays icons from Segoe MDL2 Assets. New-UiImage displays files or base64:" -Style Body -FullWidth

            New-UiCard -Header "Glyph Icons" -Icon "Tiles" -Stretch -Content {
                New-UiPanel -Orientation Horizontal -Content {
                    New-UiGlyph -Name 'Heart' -Size 24 -Color 'Red'
                    New-UiGlyph -Name 'Star' -Size 24 -Color 'Gold'
                    New-UiGlyph -Name 'CheckMark' -Size 24 -Color 'Green'
                    New-UiGlyph -Name 'Warning' -Size 24 -Color 'Orange'
                    New-UiGlyph -Name 'Error' -Size 24 -Color 'Red'
                }
                New-UiLabel -Text "Use Show-UiGlyphBrowser to find icon names" -Style Note
            }

            New-UiCard -Header "Base64 Image" -Icon "Photo" -Stretch -Content {
                New-UiLabel -Text "Icon extracted and displayed as base64 PNG:" -Style Body

                # Extract the PowerShell icon from the running executable and convert to base64
                # This demonstrates dynamic image loading without shipping external files
                $psExe = (Get-Process -Id $PID).Path
                $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($psExe)
                $bmp = $icon.ToBitmap()
                $ms = [System.IO.MemoryStream]::new()
                $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                $iconBase64 = [Convert]::ToBase64String($ms.ToArray())
                $ms.Dispose()
                $bmp.Dispose()
                $icon.Dispose()

                New-UiImage -Base64 $iconBase64 -Width 48
            }

            New-UiCard -Header "Progress Bars" -Icon "Sync" -Stretch -Content {
                New-UiLabel -Text "Static progress bars via New-UiProgress:" -Style Body
                New-UiProgress -Variable "staticProgress" -Height 16
                New-UiAction -Text "Set to 75%" -Icon "Accept" -NoAsync -Action {
                    Set-UiProgress -Variable "staticProgress" -Value 75
                }
            }
        }

        New-UiPanel -Header "Validated Inputs" -ShowSourceButton -Content {
            New-UiLabel -Text "These inputs validate as you type:" -Style Body -FullWidth

            New-UiInput -Label "Email" -Variable "ctrlEmail" -Placeholder "user@domain.com" `
                -ValidatePattern "^[\w\.-]+@[\w\.-]+\.\w+$" `
                -ErrorMessage "Invalid email format" `
                -ValidateOnChange

            New-UiInput -Label "Age (18-120)" -Variable "ctrlAge" -Placeholder "Enter age" `
                -Validate {
                    $n = 0
                    if ([int]::TryParse($args[0], [ref]$n)) {
                        return $n -ge 18 -and $n -le 120
                    }
                    return $false
                } `
                -ErrorMessage "Age must be 18-120" `
                -ValidateOnChange
        }

        New-UiPanel -Header "Lists and Cards" -ShowSourceButton -LayoutStyle Wrap -MaxColumns 2 -Content {
            New-UiCard -Header "System Status" -Icon "Info" -Stretch -Content {
                New-UiLabel -Text "All systems operational" -Style Body
                New-UiLabel -Text "Last checked: Just now" -Style Note
            }
            New-UiCard -Header "Active Users" -Icon "User" -Accent -Stretch -Content {
                New-UiLabel -Text "142 online" -Style Header
            }
        }

        New-UiPanel -Header "Grid Layouts (New-UiGrid)" -ShowSourceButton -Content {
            New-UiLabel -Text "Use -FormLayout for clean label/control pairs (2-column: labels left, inputs right):" -Style Body -FullWidth

            New-UiGrid -FormLayout -RowSpacing 6 -Content {
                New-UiInput -Label "First Name" -Variable "gridFirstName" -Placeholder "John"
                New-UiInput -Label "Last Name" -Variable "gridLastName" -Placeholder "Doe"
                New-UiInput -Label "Email" -Variable "gridEmail" -Placeholder "john.doe@example.com"
                New-UiDropdown -Label "Department" -Variable "gridDept" -Items @('Engineering', 'Sales', 'Marketing', 'HR')
            }

            New-UiSeparator

            New-UiLabel -Text "Use -AutoLayout for mixed control types (toggles, sliders handle their own labels):" -Style Body -FullWidth

            New-UiGrid -AutoLayout -RowSpacing 6 -Content {
                New-UiToggle -Label "Enable notifications" -Variable "gridNotify"
                New-UiToggle -Label "Auto-save drafts" -Variable "gridAutoSave"
                New-UiSlider -Label "Volume" -Variable "gridVolume" -Minimum 0 -Maximum 100 -ShowValueLabel
            }

            New-UiSeparator

            New-UiLabel -Text "Use explicit columns for multi-column layouts:" -Style Body -FullWidth

            New-UiGrid -Columns 3 -RowSpacing 4 -Content {
                New-UiLabel -Text "Option A"
                New-UiLabel -Text "Option B"
                New-UiLabel -Text "Option C"
                New-UiToggle -Label "Enable A" -Variable "gridOptA"
                New-UiToggle -Label "Enable B" -Variable "gridOptB"
                New-UiToggle -Label "Enable C" -Variable "gridOptC"
            }
        }

        New-UiPanel -Header "Buttons and Actions" -ShowSourceButton -LayoutStyle Wrap -Content {
            New-UiLabel -Text "Standalone buttons with hydration/dehydration:" -Style Body -FullWidth

            New-UiButton -Text "Get Form Values" -Icon "Clipboard" -Action {
                Write-Host "=== Current Form Values ===" -ForegroundColor Cyan
                Write-Host "Project: $ProjectName"
                Write-Host "Priority: $Priority"
                Write-Host "Status: $Status"
                Write-Host "Favorite: $IsFavorite"
                Write-Host "Completion: $Completion%"
            }

            New-UiAction -Text "Fill Sample Data" -Icon "Import" -Accent -Action {
                $ProjectName = 'Demo Project'
                $Tags = 'powershell, wpf, demo'
                $Description = 'Sample project description.'
                $Priority = 'High'
            }

            New-UiAction -Text "Clear Form" -Icon "Clear" -Action {
                $ProjectName = ''
                $Tags = ''
                $Description = ''
            }
        }

        New-UiPanel -Header "Icon Gallery" -ShowSourceButton -Content {
            New-UiLabel -Text "Browse 400+ icons from the Segoe MDL2 Assets font. Click any icon to copy its name." -Style Body
            New-UiActionCard -Header "Glyph Browser" -Icon "Tiles" -NoAsync -Accent -ButtonText "Browse" -Description "Opens a searchable grid of all available icons" -Action {
                Show-UiGlyphBrowser
            }
        }

        New-UiPanel -Header "Multi-Window Test" -ShowSourceButton -Content {
            New-UiLabel -Text "Test that multiple windows maintain independent sessions." -Style Body
            New-UiButton -Text "Open Second Window" -Icon "NewWindow" -NoAsync -Action {
                New-UiChildWindow -Title "Second Window" -Width 400 -Height 300 -Content {
                    New-UiLabel -Text "Independent Session Test" -Style Title -FullWidth
                    New-UiLabel -Text "This window has its own session context." -Style Note -FullWidth
                    New-UiSeparator -FullWidth
                    
                    New-UiInput -Label "Window 2 Input" -Variable "window2Input" -Placeholder "Type here..."
                    New-UiDropdown -Label "Window 2 Dropdown" -Variable "window2Choice" -Items @('Alpha', 'Beta', 'Gamma')
                    
                    New-UiButton -Text "Show Values" -Icon "Info" -Accent -Action {
                        Write-Host "Window 2 Input: $window2Input" -ForegroundColor Cyan
                        Write-Host "Window 2 Choice: $window2Choice" -ForegroundColor Cyan
                    }
                    
                    New-UiButton -Text "Check Session ID" -Icon "Info" -Action {
                        $session = Get-UiSession
                        Write-Host "Session ID: $($session.Id)" -ForegroundColor Green
                        Write-Host "Session GUID: $($session.SessionId)" -ForegroundColor Green
                        Write-Host "Active sessions: $([PsUi.SessionManager]::ActiveSessionCount)" -ForegroundColor Yellow
                    }
                }
            }
            
            New-UiButton -Text "Check Main Session" -Icon "Info" -Action {
                $session = Get-UiSession
                Write-Host "Main Window Session ID: $($session.Id)" -ForegroundColor Cyan
                Write-Host "Main Window GUID: $($session.SessionId)" -ForegroundColor Cyan
                Write-Host "Active sessions: $([PsUi.SessionManager]::ActiveSessionCount)" -ForegroundColor Yellow
            }
        }
    }

    # TAB 2: Data Output
    New-UiTab -Header "Data Output" -Content {
        New-UiLabel -Text "Data Output and Result Actions" -Style Title -FullWidth
        New-UiLabel -Text "Pipeline objects become interactive DataGrids with filtering, sorting, and custom action buttons." -Style Note -FullWidth
        New-UiSeparator -FullWidth

        New-UiPanel -Header "Process Management" -ShowSourceButton -Content {
            New-UiLabel -Text "Get running processes with actions to inspect or stop them:" -Style Body

            New-UiButtonCard -Header "Get Processes" -Icon "Gear" -Accent -ButtonText "Fetch" -Description "View running processes" -Action {
                Get-Process | Where-Object { $_.Id -ne $PID }
            } -ResultActions @(
                @{
                    Text   = 'Stop Process'
                    Icon   = 'Stop'
                    Confirm = 'Stop {0} selected process(es)?'
                    Action = {
                        param($SelectedItems)
                        foreach ($proc in $SelectedItems) {
                            Write-Host "Would stop: $($proc.Name) (PID: $($proc.Id))" -ForegroundColor Yellow
                        }
                    }
                }
                @{
                    Text   = 'Get Info'
                    Icon   = 'Info'
                    Action = {
                        param($SelectedItems)
                        foreach ($proc in $SelectedItems) {
                            Write-Host "Process: $($proc.Name)" -ForegroundColor Cyan
                            Write-Host "  PID: $($proc.Id)"
                            Write-Host "  CPU: $($proc.CPU)"
                            Write-Host "  Memory: $([math]::Round($proc.WorkingSet64 / 1MB, 2)) MB"
                        }
                    }
                }
            )
        }

        New-UiPanel -Header "Service Management" -ShowSourceButton -Content {
            New-UiLabel -Text "Manage Windows services with Start/Stop/Restart actions:" -Style Body

            New-UiButtonCard -Header "Get Services" -Icon "Services" -Accent -ButtonText "Fetch" -Description "View services with management actions" -Action {
                Get-Service
            } -ResultActions @(
                @{
                    Text   = 'Start'
                    Icon   = 'Play'
                    Action = {
                        param($SelectedItems)
                        foreach ($svc in $SelectedItems) {
                            Write-Host "Would start: $($svc.Name) ($($svc.DisplayName))" -ForegroundColor Green
                        }
                    }
                }
                @{
                    Text   = 'Stop'
                    Icon   = 'Stop'
                    Confirm = 'Stop {0} selected service(s)?'
                    Action = {
                        param($SelectedItems)
                        foreach ($svc in $SelectedItems) {
                            Write-Host "Would stop: $($svc.Name) ($($svc.DisplayName))" -ForegroundColor Yellow
                        }
                    }
                }
                @{
                    Text   = 'Restart'
                    Icon   = 'Refresh'
                    Confirm = 'Restart {0} selected service(s)?'
                    Action = {
                        param($SelectedItems)
                        foreach ($svc in $SelectedItems) {
                            Write-Host "Would restart: $($svc.Name) ($($svc.DisplayName))" -ForegroundColor Cyan
                        }
                    }
                }
            )
        }

        New-UiPanel -Header "Multi-Type Output" -ShowSourceButton -Content {
            New-UiLabel -Text "Return different object types - each gets its own sub-tab in Results:" -Style Body

            New-UiButtonCard -Header "Mixed Objects" -Icon "Shuffle" -Accent -ButtonText "Fetch" -Description "Processes + Services = 2 sub-tabs with typed actions" -Action {
                Write-Host "Returning processes and services..." -ForegroundColor Cyan
                Get-Process | Where-Object { $_.Id -ne $PID }
                Get-Service
                Write-Host "Check the Results tab - click sub-tabs to switch!" -ForegroundColor Green
            }
        }

        New-UiPanel -Header "Hierarchical Tree View" -ShowSourceButton -Content {
            New-UiLabel -Text "New-UiTree displays nested data. Build trees from paths, parent-child IDs, or nested objects:" -Style Body -FullWidth

            # Static nested data demo - always visible
            $treeData = @(
                @{ Name = 'Project Alpha'; Children = @(
                    @{ Name = 'Documentation' }
                    @{ Name = 'Source Code'; Children = @(
                        @{ Name = 'Frontend' }
                        @{ Name = 'Backend' }
                    )}
                    @{ Name = 'Tests' }
                )}
                @{ Name = 'Project Beta'; Children = @(
                    @{ Name = 'Design' }
                    @{ Name = 'Implementation' }
                )}
            )
            New-UiTree -Variable 'demoTree' -Items $treeData -Height 150 -ExpandAll

            New-UiButton -Text 'Show Selected' -Icon 'Info' -Action {
                # Tree controls hydrate SelectedHeader/SelectedItem properties
                if ($demoTree -and $demoTree.SelectedHeader) {
                    Write-Host "Selected: $($demoTree.SelectedHeader)" -ForegroundColor Cyan
                }
                else {
                    Write-Host "No item selected. Click a node in the tree first." -ForegroundColor Yellow
                }
            }
        }

        New-UiPanel -Header "Line Chart" -ShowSourceButton -Content {
            New-UiLabel -Text "New-UiChart renders data with theme-aware colors. Click to accumulate points:" -Style Body -FullWidth

            New-UiChart -Type Line -Variable 'demoLine' -Data ([ordered]@{ "0" = 50 }) -Title "Random Walk" -ShowValues -YAxisLabel "Value" -XAxisLabel "Sample"

            New-UiAction -Text 'Add Point' -Icon 'Add' -Action {
                $current = $demoLine
                $newData = [ordered]@{}
                $i = 0
                if ($current) {
                    foreach ($pt in $current) {
                        $newData["$i"] = $pt.Value
                        $i++
                    }
                }
                $last    = if ($i -gt 0) { $newData["$($i - 1)"] } else { 50 }
                $delta   = Get-Random -Min -15 -Max 16
                $newData["$i"] = [math]::Max(0, [math]::Min(100, $last + $delta))
                Update-UiChart -Variable 'demoLine' -Data $newData
            }
        }

        New-UiSeparator -FullWidth

        New-UiPanel -Header "Comprehensive Output Test" -ShowSourceButton -FullWidth -Content {
            New-UiLabel -Text "Exercises every output stream: console, warnings, errors, progress, and mixed object types with typed ResultActions." -Style Note

            New-UiButtonCard -Header "Full System Test" -Description "Unleash every output type at once" -Icon "PowerButton" -Accent -ButtonText "Execute" -Action {
                Write-Host "========================================" -ForegroundColor Cyan
                Write-Host "  COMPREHENSIVE OUTPUT TEST" -ForegroundColor White
                Write-Host "========================================" -ForegroundColor Cyan

                # Console output variety
                Write-Host ""
                Write-Host "--- Console Output ---" -ForegroundColor Yellow
                1..10 | ForEach-Object {
                    Write-Host "Console line $_`: The quick brown fox jumps over the lazy dog" -ForegroundColor Gray
                }
                Write-Host "Regular output without color"
                Write-Output "This is Write-Output (goes to pipeline)"
                Write-Host "Colored output: " -NoNewline
                Write-Host "RED " -ForegroundColor Red -NoNewline
                Write-Host "GREEN " -ForegroundColor Green -NoNewline
                Write-Host "BLUE " -ForegroundColor Blue -NoNewline
                Write-Host "YELLOW " -ForegroundColor Yellow -NoNewline
                Write-Host "MAGENTA " -ForegroundColor Magenta -NoNewline
                Write-Host "CYAN" -ForegroundColor Cyan

                # Warnings
                Write-Host ""
                Write-Host "--- Warnings ---" -ForegroundColor Yellow
                Write-Warning "Warning 1: Configuration file not found, using defaults"
                Write-Warning "Warning 2: Deprecated parameter detected"
                Write-Warning "Warning 3: Performance may be degraded"
                Write-Warning "Warning 4: SSL certificate expires in 7 days"
                Write-Warning "Warning 5: Memory usage exceeds 80%"

                # Errors
                Write-Host ""
                Write-Host "--- Errors ---" -ForegroundColor Red
                Write-Error "Error 1: Connection timeout after 30 seconds"
                Write-Error "Error 2: Access denied to protected resource"
                Write-Error "Error 3: Invalid parameter combination"

                try {
                    $null.NonExistentMethod()
                }
                catch {
                    Write-Error "Error 4: $_"
                }

                try {
                    throw "Error 5: Custom exception from throw statement"
                }
                catch {
                    Write-Error $_
                }

                # Progress
                Write-Host ""
                Write-Host "--- Progress Bar ---" -ForegroundColor Green
                1..100 | ForEach-Object {
                    Write-Progress -Activity "Processing items" -Status "Item $_ of 100" -PercentComplete $_
                    Start-Sleep -Milliseconds 20
                }
                Write-Progress -Activity "Processing items" -Completed
                Write-Host "Progress complete!" -ForegroundColor Green

                # Information stream
                Write-Host ""
                Write-Host "--- Information ---" -ForegroundColor Blue
                Write-Information "Info 1: Operation started at $(Get-Date)"
                Write-Information "Info 2: Using default configuration"
                Write-Information "Info 3: Connected to primary server"

                # Mixed object output
                Write-Host ""
                Write-Host "--- Object Output ---" -ForegroundColor Magenta
                Write-Host "Returning mixed objects to Results tab..." -ForegroundColor Gray

                Get-Process | Where-Object { $_.Id -ne $PID }
                Get-Service

                [PSCustomObject]@{
                    Type           = "Summary"
                    Errors         = 5
                    Warnings       = 5
                    ConsoleLines   = 15
                    ObjectsReturned = "All"
                }

                # Hashtable output to test dictionary rendering
                @{
                    TestName   = "Full System Test"
                    RunDate    = Get-Date -Format "yyyy-MM-dd"
                    Status     = "Complete"
                    Duration   = "00:05:32"
                    Passed     = $true
                    NestedData = @{ Foo = 'Bar'; Count = 42; Enabled = $true; Level = 'High'; Mode = 'Auto'; Retry = 3 }
                    TestArray  = @('this', 'is', 'a', 'test', 'array')
                }

                Write-Host ""
                Write-Host "========================================" -ForegroundColor Cyan
                Write-Host "  TEST COMPLETE!" -ForegroundColor Green
                Write-Host "  Check: Console, Warnings, Errors, Results tabs" -ForegroundColor White
                Write-Host "========================================" -ForegroundColor Cyan
            } -ResultActions @(
                @{
                    Text       = 'Stop Process'
                    Icon       = 'Stop'
                    ObjectType = 'Process'
                    Confirm    = 'Stop {0} selected process(es)?'
                    Action     = {
                        param($SelectedItems)
                        foreach ($proc in $SelectedItems) {
                            Write-Host "Would stop process: $($proc.Name) (PID: $($proc.Id))" -ForegroundColor Yellow
                        }
                    }
                }
                @{
                    Text       = 'Get Process Info'
                    Icon       = 'Info'
                    ObjectType = 'Process'
                    Action     = {
                        param($SelectedItems)
                        foreach ($proc in $SelectedItems) {
                            Write-Host "Process: $($proc.Name)" -ForegroundColor Cyan
                            Write-Host "  PID: $($proc.Id)"
                            Write-Host "  CPU: $($proc.CPU)"
                            Write-Host "  Memory: $([math]::Round($proc.WorkingSet64 / 1MB, 2)) MB"
                        }
                    }
                }
                @{
                    Text       = 'Start Service'
                    Icon       = 'Play'
                    ObjectType = 'ServiceController'
                    Action     = {
                        param($SelectedItems)
                        foreach ($svc in $SelectedItems) {
                            Write-Host "Would start service: $($svc.Name) ($($svc.DisplayName))" -ForegroundColor Green
                        }
                    }
                }
                @{
                    Text       = 'Stop Service'
                    Icon       = 'Stop'
                    ObjectType = 'ServiceController'
                    Confirm    = 'Stop {0} selected service(s)?'
                    Action     = {
                        param($SelectedItems)
                        foreach ($svc in $SelectedItems) {
                            Write-Host "Would stop service: $($svc.Name) ($($svc.DisplayName))" -ForegroundColor Yellow
                        }
                    }
                }
                @{
                    Text       = 'View Summary'
                    Icon       = 'View'
                    ObjectType = 'PSCustomObject'
                    Action     = {
                        param($SelectedItems)
                        foreach ($obj in $SelectedItems) {
                            Write-Host "Summary Object:" -ForegroundColor Magenta
                            $obj | Format-List | Out-String | Write-Host
                        }
                    }
                }
                @{
                    Text   = 'Test Success'
                    Icon   = 'Accept'
                    Action = {
                        param($SelectedItems)
                        Write-Host "Running successful action on $($SelectedItems.Count) items..." -ForegroundColor Green
                        Start-Sleep -Milliseconds 500
                        Write-Host "Action completed successfully!" -ForegroundColor Green
                    }
                }
                @{
                    Text   = 'Test Error'
                    Icon   = 'Error'
                    Action = {
                        param($SelectedItems)
                        Write-Host "Running action that will fail..." -ForegroundColor Yellow
                        Start-Sleep -Milliseconds 500
                        throw "This is a deliberate test error to verify error handling!"
                    }
                }
                @{
                    Text   = 'Test Progress'
                    Icon   = 'Sync'
                    Action = {
                        param($SelectedItems)
                        Write-Host "Testing Write-Progress on $($SelectedItems.Count) items..." -ForegroundColor Cyan
                        for ($i = 0; $i -lt $SelectedItems.Count; $i++) {
                            $pct = [math]::Round((($i + 1) / $SelectedItems.Count) * 100)
                            $item = $SelectedItems[$i]
                            $itemName = if ($item.Name) { $item.Name } elseif ($item.ProcessName) { $item.ProcessName } else { "Item $($i+1)" }
                            Write-Progress -Activity "Processing items" -Status "Item $($i+1) of $($SelectedItems.Count): $itemName" -PercentComplete $pct
                            Write-Host "  Processing: $itemName" -ForegroundColor Cyan
                            Start-Sleep -Milliseconds 800
                        }
                        Write-Progress -Activity "Processing items" -Completed
                        Write-Host "Progress test complete!" -ForegroundColor Green
                    }
                }
            )

            New-UiButtonCard -Header "Rapid Fire Console" -Description "100 lines of console output as fast as possible" -Icon "Terminal" -ButtonText "Fire" -Action {
                Write-Host "RAPID FIRE MODE - 100 lines incoming!" -ForegroundColor Red
                1..100 | ForEach-Object {
                    $colors = @('Red','Green','Blue','Yellow','Cyan','Magenta','White','Gray')
                    $color = $colors[$_ % 8]
                    Write-Host "[$_] $(Get-Date -Format 'HH:mm:ss.fff') - Rapid fire line with $color color" -ForegroundColor $color
                }
                Write-Host "DONE!" -ForegroundColor Green
            }

            New-UiButtonCard -Header "Long Running Progress" -Description "10-second progress bar with status updates" -Icon "Timer" -ButtonText "Start" -Action {
                $steps = @(
                    "Initializing...",
                    "Loading configuration...",
                    "Connecting to server...",
                    "Authenticating...",
                    "Fetching data...",
                    "Processing records...",
                    "Validating results...",
                    "Generating report...",
                    "Cleaning up...",
                    "Finalizing..."
                )

                for ($i = 0; $i -lt 100; $i++) {
                    $step = $steps[[math]::Floor($i / 10)]
                    Write-Progress -Activity "Long Running Operation" -Status $step -PercentComplete ($i + 1) -CurrentOperation "Step $([math]::Floor($i / 10) + 1) of 10"
                    Start-Sleep -Milliseconds 100
                }
                Write-Progress -Activity "Long Running Operation" -Completed
                Write-Host "Operation completed successfully!" -ForegroundColor Green
            }

            New-UiButtonCard -Header "Error Variety Pack" -Description "Different error types with stack traces" -Icon "Debug" -ButtonText "Generate" -Action {
                Write-Host "Generating variety of error types..." -ForegroundColor Yellow

                Write-Error "Simple Write-Error message"
                Write-Error -Message "Error with category" -Category InvalidOperation
                Write-Error -Message "Error with target" -TargetObject "SomeObject" -Category ObjectNotFound

                try { Get-Item "C:\This\Path\Does\Not\Exist\At\All.txt" -ErrorAction Stop }
                catch { Write-Error $_ }

                try { [int]::Parse("not a number") }
                catch { Write-Error $_ }

                try { 1/0 }
                catch { Write-Error $_ }

                try {
                    function Inner-Function { throw "Error from nested function" }
                    function Outer-Function { Inner-Function }
                    Outer-Function
                }
                catch { Write-Error $_ }

                Write-Host "Check Errors tab for full details on each!" -ForegroundColor Cyan
            }
        }
    }

    # TAB 3: Async
    New-UiTab -Header "Async" -Content {
        New-UiLabel -Text "Async Execution and Progress" -Style Title -FullWidth
        New-UiLabel -Text "Background threads, progress bars, and thread-safe collections." -Style Note -FullWidth
        New-UiSeparator -FullWidth

        New-UiPanel -Header "Progress Bars" -ShowSourceButton -Content {
            New-UiButtonCard -Header "Simple Progress" -Icon "Sync" -Accent -ButtonText "Start" -Description "Basic progress bar with status updates" -Action {
                for ($i = 1; $i -le 10; $i++) {
                    Write-Progress -Activity "Processing" -Status "Step $i of 10" -PercentComplete ($i * 10)
                    Start-Sleep -Milliseconds 300
                }
                Write-Progress -Activity "Processing" -Completed
                Start-Sleep -Milliseconds 250
                Write-Host "[OK] Complete!" -ForegroundColor Green
            }

            New-UiButtonCard -Header "Nested Progress" -Icon "MapLayers" -ButtonText "Start" -Description "Parent/child progress bars" -Action {
                for ($i = 1; $i -le 3; $i++) {
                    Write-Progress -Id 1 -Activity "Main Task" -Status "Batch $i of 3" -PercentComplete (($i / 3) * 100)
                    for ($j = 1; $j -le 5; $j++) {
                        Write-Progress -Id 2 -ParentId 1 -Activity "Sub-task" -Status "Item $j of 5" -PercentComplete (($j / 5) * 100)
                        Start-Sleep -Milliseconds 100
                    }
                    Write-Progress -Id 2 -ParentId 1 -Activity "Sub-task" -Completed
                }
                Write-Progress -Id 1 -Activity "Main Task" -Completed
                Start-Sleep -Milliseconds 250
                Write-Host "[OK] Nested progress complete!" -ForegroundColor Green
            }

            New-UiButtonCard -Header "Three-Level Deep" -Icon "TreeView" -Accent -ButtonText "Start" -Description "Triple-nested progress with time remaining" -Action {
                for ($i = 1; $i -le 2; $i++) {
                    Write-Progress -Id 1 -Activity "Batch Processing" -Status "Batch $i of 2" -PercentComplete (($i / 2) * 100)

                    for ($j = 1; $j -le 3; $j++) {
                        Write-Progress -Id 2 -ParentId 1 -Activity "Category" -Status "Group $j of 3" -PercentComplete (($j / 3) * 100)

                        for ($k = 1; $k -le 4; $k++) {
                            $remaining = (2 - $i) * 12 + (3 - $j) * 4 + (4 - $k)
                            Write-Progress -Id 3 -ParentId 2 -Activity "Processing" -Status "Item $k of 4" -CurrentOperation "Analyzing data..." -PercentComplete (($k / 4) * 100) -SecondsRemaining $remaining
                            Start-Sleep -Milliseconds 100
                        }
                        Write-Progress -Id 3 -ParentId 2 -Activity "Processing" -Completed
                    }
                    Write-Progress -Id 2 -ParentId 1 -Activity "Category" -Completed
                }
                Write-Progress -Id 1 -Activity "Batch Processing" -Completed
                Start-Sleep -Milliseconds 250
                Write-Host "[OK] Three-level nested progress complete!" -ForegroundColor Green
            }
        }

        New-UiPanel -Header "Real-Time Output" -ShowSourceButton -Content {
            New-UiButtonCard -Header "Stream Output" -Icon "Terminal" -ButtonText "Watch" -Description "Watch Write-Host output in real-time" -Action {
                Write-Host "Starting..." -ForegroundColor Cyan
                Start-Sleep -Milliseconds 500
                Write-Host "Processing data..." -ForegroundColor Green
                Start-Sleep -Milliseconds 500
                Write-Host "Analyzing results..." -ForegroundColor Yellow
                Start-Sleep -Milliseconds 500
                Write-Host "Complete!" -ForegroundColor Green
            }

            New-UiButtonCard -Header "Event Flood Test" -Icon "Speed" -ButtonText "Flood" -Description "500 rapid events to test UI responsiveness" -Action {
                Write-Host "Starting event flood..." -ForegroundColor Cyan
                for ($i = 1; $i -le 500; $i++) {
                    Write-Progress -Activity "Stress Test" -Status "Event $i" -PercentComplete (($i / 500) * 100)
                    if ($i % 50 -eq 0) { Write-Host "Batch $i..." }
                    Start-Sleep -Milliseconds 2
                }
                Write-Host "[OK] Flood complete!" -ForegroundColor Green
            }
        }

        New-UiPanel -Header "Thread-Safe Collections" -ShowSourceButton -Content {
            New-UiLabel -Text "AsyncObservableCollection allows safe updates from background threads:" -Style Body

            New-UiList -Variable "SafeLogList" -ItemsSource $SafeLog -Height 150

            New-UiButton -Text "Add Items (Async)" -Icon "Add" -Accent -Action {
                1..5 | ForEach-Object {
                    $timestamp = Get-Date -Format "HH:mm:ss.fff"
                    $SafeLog.Add("[$timestamp] Item $_ from background thread")
                    Start-Sleep -Milliseconds 200
                }
                Write-Host "[OK] Items added from background thread" -ForegroundColor Green
            }

            New-UiAction -Text "Clear Log" -Icon "TrashCan" -Action {
                $SafeLog.Clear()
            }
        }

        New-UiPanel -Header "Cancellation (Stop-UiAsync)" -ShowSourceButton -Content {
            New-UiLabel -Text "Long-running tasks can be cancelled programmatically or via Escape key:" -Style Body

            New-UiActionCard -Header "Cancellable Task" -Icon "Timer" -Accent -ButtonText "Start" -Description "20-second task - press Escape or click Cancel" -Action {
                Write-Host "Starting long task (press Escape to cancel)..." -ForegroundColor Cyan
                for ($i = 1; $i -le 20; $i++) {
                    Write-Progress -Activity "Working" -Status "Step $i of 20" -PercentComplete ($i * 5)
                    Start-Sleep -Seconds 1
                    Write-Host "  Step $i done" -ForegroundColor Gray
                }
                Write-Progress -Activity "Working" -Completed
                Write-Host "[OK] Task completed!" -ForegroundColor Green
            }

            New-UiButton -Text "Cancel" -Icon "Cancel" -NoAsync -Action {
                Stop-UiAsync
            }
        }

        New-UiPanel -Header "Manual Async (Invoke-UiAsync)" -ShowSourceButton -Content {
            New-UiLabel -Text "Run code asynchronously from anywhere using Invoke-UiAsync:" -Style Body -FullWidth
            New-UiLabel -Text "Use -OnComplete to update the UI when background work finishes." -Style Note -FullWidth

            New-UiInput -Label "Status" -Variable "asyncStatus" -Placeholder "Click the button to start..." -ReadOnly
            
            New-UiButton -Text "Run with Invoke-UiAsync" -Icon "Play" -NoAsync -Action {
                # Update status before starting background work
                Set-UiValue -Variable 'asyncStatus' -Value "Working..."
                
                Invoke-UiAsync -ScriptBlock {
                    # Simulate background work
                    Start-Sleep -Seconds 2
                    
                    # Return a result
                    return "Completed at $(Get-Date -Format 'HH:mm:ss')"
                } -OnComplete {
                    param($result)
                    # Update the UI input when done (runs on UI thread)
                    Set-UiValue -Variable 'asyncStatus' -Value $result
                } -OnError {
                    param($err)
                    Set-UiValue -Variable 'asyncStatus' -Value "Error: $err"
                }
            }
        }
    }

    # TAB 4: Host Interception
    New-UiTab -Header "Host Interception" -Content {
        New-UiLabel -Text "PSHost Interception" -Style Title -FullWidth
        New-UiLabel -Text "Console commands like Read-Host and Get-Credential are automatically redirected to themed GUI dialogs." -Style Note -FullWidth
        New-UiSeparator -FullWidth

        New-UiPanel -Header "User Input Prompts" -ShowSourceButton -LayoutStyle Wrap -MaxColumns 2 -Content {
            New-UiCard -Header "Read-Host" -Icon "Terminal" -Stretch -Content {
                New-UiLabel -Text "Text and secure string input prompts become themed input dialogs." -Style Body
                New-UiButton -Text "Test Read-Host" -Icon "Input" -Action {
                    $name = Read-Host "Enter your name"
                    Write-Host "Hello, $name!" -ForegroundColor Green
                }
                New-UiButton -Text "Test Read-Host -AsSecureString" -Icon "Shield" -Action {
                    $secret = Read-Host "Enter a secret" -AsSecureString
                    Write-Host "Secret captured securely (length: $($secret.Length))" -ForegroundColor Green
                }
            }

            New-UiCard -Header "Get-Credential" -Icon "Key" -Stretch -Content {
                New-UiLabel -Text "Credential prompts show a themed dialog with secure password entry." -Style Body
                New-UiButton -Text "Test Get-Credential" -Icon "Key" -Action {
                    Write-Host "Requesting credentials..."
                    $cred = Get-Credential -Message "Enter credentials for remote server"
                    if ($cred) {
                        Write-Host "Got credentials for: $($cred.UserName)" -ForegroundColor Green
                        Write-Host "(Password securely stored as SecureString)" -ForegroundColor Cyan
                    }
                    else {
                        Write-Host "No credentials provided" -ForegroundColor Yellow
                    }
                }
            }

            New-UiCard -Header "Multi-Field Prompt" -Icon "BulletList" -Stretch -Content {
                New-UiLabel -Text "`$host.UI.Prompt() calls become dynamic multi-field dialogs." -Style Body
                New-UiButton -Text "Test Multi-Field Prompt" -Icon "BulletList" -Action {
                    Write-Host "Testing multi-field prompt..."
                    $fields = [System.Collections.ObjectModel.Collection[System.Management.Automation.Host.FieldDescription]]::new()
                    $fields.Add([System.Management.Automation.Host.FieldDescription]::new("ServerName"))
                    $fields.Add([System.Management.Automation.Host.FieldDescription]::new("PortNumber"))
                    $fields.Add([System.Management.Automation.Host.FieldDescription]::new("Protocol"))

                    $results = $host.UI.Prompt("Server Configuration", "Enter connection details:", $fields)

                    if ($results -and $results.Count -gt 0) {
                        Write-Host "Configuration received:" -ForegroundColor Green
                        foreach ($key in $results.Keys) {
                            Write-Host "  $key = $($results[$key])" -ForegroundColor Cyan
                        }
                    }
                    else {
                        Write-Host "No input provided" -ForegroundColor Yellow
                    }
                }
            }
        }

        New-UiPanel -Header "Write-Host and Console Output" -ShowSourceButton -LayoutStyle Wrap -MaxColumns 2 -Content {
            New-UiCard -Header "NoNewLine + Colors" -Icon "Highlight" -Stretch -Content {
                New-UiLabel -Text "Write-Host -NoNewLine with colors on the same line." -Style Body
                New-UiButton -Text "Rainbow Line" -Icon "Highlight" -Action {
                    Write-Host "R" -NoNewline -ForegroundColor Red
                    Write-Host "A" -NoNewline -ForegroundColor DarkYellow
                    Write-Host "I" -NoNewline -ForegroundColor Yellow
                    Write-Host "N" -NoNewline -ForegroundColor Green
                    Write-Host "B" -NoNewline -ForegroundColor Cyan
                    Write-Host "O" -NoNewline -ForegroundColor Blue
                    Write-Host "W" -ForegroundColor Magenta
                    Write-Host "All 7 letters should be on one line above!"
                }
                New-UiButton -Text "Progress Dots" -Icon "Timer" -Action {
                    Write-Host "Processing" -NoNewline -ForegroundColor White
                    for ($i = 0; $i -lt 10; $i++) {
                        Start-Sleep -Milliseconds 200
                        Write-Host "." -NoNewline -ForegroundColor Green
                    }
                    Write-Host " Done!" -ForegroundColor Green
                }
            }

            New-UiCard -Header "All Console Colors" -Icon "ColorBackground" -Stretch -Content {
                New-UiLabel -Text "Display every ConsoleColor supported by Write-Host." -Style Body
                New-UiButton -Text "Show All Colors" -Icon "ColorBackground" -Action {
                    $colors = [Enum]::GetValues([ConsoleColor])
                    Write-Host "=== All Console Colors ===" -ForegroundColor White
                    foreach ($color in $colors) {
                        Write-Host "  $color" -ForegroundColor $color
                    }
                    Write-Host "==========================" -ForegroundColor White
                }
            }

            New-UiCard -Header "Mixed Output" -Icon "Document" -Stretch -Content {
                New-UiLabel -Text "Write-Host, Write-Warning, Write-Error in sequence." -Style Body
                New-UiButton -Text "Mixed Stream Test" -Icon "Document" -Action {
                    Write-Host "[1] Starting operation..." -ForegroundColor Cyan
                    Write-Host "[2] Step 1 complete" -ForegroundColor Green
                    Write-Warning "[3] This is a warning"
                    Write-Host "[4] Continuing despite warning..." -ForegroundColor Yellow
                    Write-Error "[5] An error occurred"
                    Write-Host "[6] But we caught it and continued!" -ForegroundColor Green
                    Write-Host "[7] Operation complete." -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "Check Console, Warnings, and Errors tabs!"
                }
            }

            New-UiCard -Header "ASCII Art" -Icon "Grid" -Stretch -Content {
                New-UiLabel -Text "Multi-line output with varying colors." -Style Body
                New-UiButton -Text "Draw Box" -Icon "Grid" -Action {
                    Write-Host "+--------------------+" -ForegroundColor Cyan
                    Write-Host "|  PsUi Write-Host   |" -ForegroundColor Yellow
                    Write-Host "|   Test Complete    |" -ForegroundColor Green
                    Write-Host "+--------------------+" -ForegroundColor Cyan
                }
            }

            New-UiCard -Header "Rapid Fire" -Icon "Flashlight" -Stretch -Content {
                New-UiLabel -Text "High-volume output stress test." -Style Body
                New-UiButton -Text "100 Lines Fast" -Icon "Flashlight" -Action {
                    Write-Host "Starting rapid output test..." -ForegroundColor Yellow
                    $colors = @('Red', 'Green', 'Blue', 'Cyan', 'Magenta', 'Yellow', 'White')
                    for ($i = 1; $i -le 100; $i++) {
                        $color = $colors[$i % $colors.Count]
                        Write-Host "Line $i of 100" -ForegroundColor $color
                    }
                    Write-Host "Rapid fire complete!" -ForegroundColor Green
                }
                New-UiButton -Text "Spinner Simulation" -Icon "Sync" -Action {
                    $spinChars = '|/-\'
                    Write-Host "Working: " -NoNewline -ForegroundColor Cyan
                    for ($i = 0; $i -lt 20; $i++) {
                        $char = $spinChars[$i % 4]
                        Write-Host "`b$char" -NoNewline -ForegroundColor Yellow
                        Start-Sleep -Milliseconds 150
                    }
                    Write-Host "`b " -ForegroundColor Green
                    Write-Host "Done!" -ForegroundColor Green
                }
            }

            New-UiCard -Header "Table Formatting" -Icon "Table" -Stretch -Content {
                New-UiLabel -Text "Manual table with Write-Host for alignment." -Style Body
                New-UiButton -Text "Show Status Table" -Icon "Table" -Action {
                    Write-Host ""
                    Write-Host "SERVICE          STATUS     PID" -ForegroundColor White
                    Write-Host "-------------------------------" -ForegroundColor Gray
                    Write-Host "WebServer        Running    1234" -ForegroundColor Green
                    Write-Host "Database         Running    5678" -ForegroundColor Green
                    Write-Host "Cache            Stopped    -" -ForegroundColor Red
                    Write-Host "Scheduler        Warning    9012" -ForegroundColor Yellow
                    Write-Host "-------------------------------" -ForegroundColor Gray
                }
            }

            New-UiCard -Header "Separator Test" -Icon "Ellipsis" -Stretch -Content {
                New-UiLabel -Text "Test empty Write-Host for blank lines." -Style Body
                New-UiButton -Text "Blank Lines" -Icon "Ellipsis" -Action {
                    Write-Host "Line 1"
                    Write-Host ""
                    Write-Host "Line 3 (after blank)"
                    Write-Host ""
                    Write-Host ""
                    Write-Host "Line 6 (after 2 blanks)"
                    Write-Host "---" -ForegroundColor Gray
                    Write-Host "End of test"
                }
            }

            New-UiCard -Header "Long Line Test" -Icon "AlignLeft" -Stretch -Content {
                New-UiLabel -Text "Test horizontal scrolling with very long lines." -Style Body
                New-UiButton -Text "Long Lines" -Icon "AlignLeft" -Action {
                    Write-Host "Short line"
                    Write-Host ("=" * 200) -ForegroundColor Cyan
                    Write-Host "This is a very long line that should trigger horizontal scrolling in the console output when word wrap is disabled. It contains enough text to exceed typical window widths and test the no-wrap mode functionality. The line continues with more content to really push the boundaries." -ForegroundColor Yellow
                    Write-Host ("=" * 200) -ForegroundColor Cyan
                    Write-Host "End - toggle Wrap checkbox to test scroll"
                }
            }
        }

        New-UiPanel -Header "Non-Blocking Actions (-NoWait)" -ShowSourceButton -LayoutStyle Wrap -MaxColumns 2 -Content {
            New-UiCard -Header "Concurrent Actions" -Icon "TaskView" -Stretch -Content {
                New-UiLabel -Text "With -NoWait, multiple actions can run simultaneously without blocking the parent window." -Style Body
                New-UiButton -Text "Long Task A (NoWait)" -Icon "Clock" -NoWait -Action {
                    Write-Host "Task A started..." -ForegroundColor Cyan
                    for ($i = 1; $i -le 5; $i++) {
                        Write-Host "Task A: Step $i of 5" -ForegroundColor Yellow
                        Start-Sleep -Seconds 1
                    }
                    Write-Host "Task A complete!" -ForegroundColor Green
                }
                New-UiButton -Text "Long Task B (NoWait)" -Icon "Clock" -NoWait -Action {
                    Write-Host "Task B started..." -ForegroundColor Magenta
                    for ($i = 1; $i -le 5; $i++) {
                        Write-Host "Task B: Step $i of 5" -ForegroundColor White
                        Start-Sleep -Seconds 1
                    }
                    Write-Host "Task B complete!" -ForegroundColor Green
                }
            }

            New-UiCard -Header "Normal vs NoWait" -Icon "Compare" -Stretch -Content {
                New-UiLabel -Text "Compare blocking (normal) vs non-blocking (-NoWait) behavior." -Style Body
                New-UiButton -Text "Blocking (Normal)" -Icon "Lock" -Action {
                    Write-Host "This blocks the parent window until closed." -ForegroundColor Yellow
                    for ($i = 1; $i -le 3; $i++) {
                        Write-Host "Working... ($i/3)" -ForegroundColor Cyan
                        Start-Sleep -Seconds 1
                    }
                    Write-Host "Done! Close this window to unblock parent." -ForegroundColor Green
                }
                New-UiButton -Text "Non-Blocking" -Icon "Unlock" -NoWait -Action {
                    Write-Host "Parent window stays interactive!" -ForegroundColor Yellow
                    for ($i = 1; $i -le 3; $i++) {
                        Write-Host "Working... ($i/3)" -ForegroundColor Cyan
                        Start-Sleep -Seconds 1
                    }
                    Write-Host "Done! Parent was usable the whole time." -ForegroundColor Green
                }
            }
        }

        New-UiPanel -Header "Legacy Script Interceptions" -ShowSourceButton -LayoutStyle Wrap -MaxColumns 2 -Content {
            New-UiCard -Header "Pause Command" -Icon "Pause" -Stretch -Content {
                New-UiLabel -Text "Legacy Pause command waits for keypress." -Style Body
                New-UiButton -Text "Test Pause" -Icon "Pause" -Action {
                    Write-Host "About to pause..." -ForegroundColor Cyan
                    Pause
                    Write-Host "You pressed a key! Continuing..." -ForegroundColor Green
                }
            }

            New-UiCard -Header "Write-Information" -Icon "Message" -Stretch -Content {
                New-UiLabel -Text "PS 5+ information stream goes to Console." -Style Body
                New-UiButton -Text "Test Write-Information" -Icon "Message" -Action {
                    Write-Host "Sending info records..." -ForegroundColor Cyan
                    Write-Information "This is an information message"
                    Write-Information "Another info message with data" -Tags "Demo", "Test"
                    Write-Host "Done! Check Console tab for info messages." -ForegroundColor Green
                }
            }

            New-UiCard -Header "Out-Host" -Icon "CommandPrompt" -Stretch -Content {
                New-UiLabel -Text "Explicit Out-Host goes to Console tab." -Style Body
                New-UiButton -Text "Test Out-Host" -Icon "CommandPrompt" -Action {
                    Write-Host "Sending objects to Out-Host..." -ForegroundColor Cyan
                    @{ Name = "Test"; Value = 123 } | Out-Host
                    Get-Date | Out-Host
                    Write-Host "Done! Objects displayed via Out-Host." -ForegroundColor Green
                }
            }

            New-UiCard -Header "Window Title" -Icon "Caption" -Stretch -Content {
                New-UiLabel -Text "Setting \$host.UI.RawUI.WindowTitle shows as subtitle." -Style Body
                New-UiButton -Text "Set Window Title" -Icon "Caption" -Action {
                    Write-Host "Setting window title..." -ForegroundColor Cyan
                    $host.UI.RawUI.WindowTitle = "Processing Items..."
                    Start-Sleep -Seconds 2
                    $host.UI.RawUI.WindowTitle = "50% Complete"
                    Start-Sleep -Seconds 2
                    $host.UI.RawUI.WindowTitle = "Finishing Up"
                    Start-Sleep -Seconds 1
                    $host.UI.RawUI.WindowTitle = ""
                    Write-Host "Title sequence complete!" -ForegroundColor Green
                }
                New-UiButton -Text "Progress Simulation" -Icon "Processing" -Action {
                    Write-Host "Starting batch job..." -ForegroundColor Yellow
                    for ($i = 1; $i -le 5; $i++) {
                        $host.UI.RawUI.WindowTitle = "Processing item $i of 5"
                        Write-Host "  Item $i..." -ForegroundColor Gray
                        Start-Sleep -Milliseconds 800
                    }
                    $host.UI.RawUI.WindowTitle = ""
                    Write-Host "Batch complete!" -ForegroundColor Green
                }
            }

            New-UiCard -Header "Combined Legacy" -Icon "Admin" -Stretch -Content {
                New-UiLabel -Text "All legacy patterns together." -Style Body
                New-UiButton -Text "Full Legacy Demo" -Icon "Admin" -Action {
                    $host.UI.RawUI.WindowTitle = "Legacy Script Demo"
                    Write-Host "=== Legacy Script Simulation ===" -ForegroundColor Cyan
                    Write-Host ""
                    
                    Write-Information "Script starting at $(Get-Date)"
                    
                    Write-Host "Step 1: Gathering system info..." -ForegroundColor Yellow
                    $host.UI.RawUI.WindowTitle = "Step 1/3 - System Info"
                    @{ Computer = $env:COMPUTERNAME; User = $env:USERNAME } | Out-Host
                    
                    Write-Host ""
                    Write-Host "Step 2: Processing data..." -ForegroundColor Yellow
                    $host.UI.RawUI.WindowTitle = "Step 2/3 - Processing"
                    Start-Sleep -Seconds 1
                    Write-Information "Data processing complete"
                    
                    Write-Host ""
                    Write-Host "Step 3: Review results" -ForegroundColor Yellow
                    $host.UI.RawUI.WindowTitle = "Step 3/3 - Review"
                    Write-Host "Press any key to acknowledge..." -ForegroundColor Magenta
                    Pause
                    
                    $host.UI.RawUI.WindowTitle = ""
                    Write-Host ""
                    Write-Host "=== Script Complete ===" -ForegroundColor Green
                }
            }
        }

        New-UiPanel -Header "Confirmation and Choice Dialogs" -ShowSourceButton -LayoutStyle Wrap -MaxColumns 2 -Content {
            New-UiCard -Header "PromptForChoice" -Icon "MultiSelect" -Stretch -Content {
                New-UiLabel -Text "-Confirm prompts and ShouldProcess calls become choice dialogs." -Style Body
                New-UiButton -Text "Test -Confirm Pattern" -Icon "MultiSelect" -Action {
                    Write-Host "Simulating a -Confirm prompt..."
                    $result = $host.UI.PromptForChoice("Confirm", "Delete TestFile.txt?", @(
                        [System.Management.Automation.Host.ChoiceDescription]::new("&Yes", "Delete the file"),
                        [System.Management.Automation.Host.ChoiceDescription]::new("&No", "Keep the file")
                    ), 1)
                    if ($result -eq 0) {
                        Write-Host "User chose YES - file would be deleted" -ForegroundColor Green
                    }
                    else {
                        Write-Host "User chose NO - file kept" -ForegroundColor Yellow
                    }
                }
            }

            New-UiCard -Header "Choice with Help" -Icon "LightBulb" -Stretch -Content {
                New-UiLabel -Text "When choices have HelpMessage, a [?] button shows help for each option." -Style Body
                New-UiButton -Text "Test Choice with Help" -Icon "LightBulb" -Action {
                    Write-Host "Testing choice prompt with help messages..."
                    $choices = [System.Collections.ObjectModel.Collection[System.Management.Automation.Host.ChoiceDescription]]::new()
                    $choices.Add([System.Management.Automation.Host.ChoiceDescription]::new("&Install", "Install the application to the default location"))
                    $choices.Add([System.Management.Automation.Host.ChoiceDescription]::new("&Uninstall", "Remove the application and all settings"))
                    $choices.Add([System.Management.Automation.Host.ChoiceDescription]::new("&Repair", "Fix broken installation without losing data"))
                    $choices.Add([System.Management.Automation.Host.ChoiceDescription]::new("&Cancel", "Exit without making changes"))

                    $result = $host.UI.PromptForChoice("Setup Wizard", "Choose an action (click ? for help):", $choices, 3)

                    $actions = @("Install", "Uninstall", "Repair", "Cancel")
                    Write-Host "User chose: $($actions[$result])" -ForegroundColor Green
                }
            }
        }

        New-UiPanel -Header "Console Control" -ShowSourceButton -LayoutStyle Wrap -MaxColumns 2 -Content {
            New-UiCard -Header "Press Any Key" -Icon "Tap" -Stretch -Content {
                New-UiLabel -Text "ReadKey() calls become 'Press OK to continue' dialogs." -Style Body
                New-UiButton -Text "Test Press Any Key" -Icon "Tap" -Action {
                    Write-Host "About to prompt for keypress..."
                    Write-Host "Waiting for user input..."
                    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    Write-Host "User pressed OK! Continuing..." -ForegroundColor Green
                }
            }

            New-UiCard -Header "Clear-Host" -Icon "Clear" -Stretch -Content {
                New-UiLabel -Text "Clear-Host clears only the Console tab, not errors/warnings/results." -Style Body
                New-UiButton -Text "Test Clear-Host" -Icon "Clear" -Action {
                    Write-Host "Line 1"
                    Write-Host "Line 2"
                    Write-Host "Line 3"
                    Write-Warning "This warning will NOT be cleared"
                    Write-Error "This error will NOT be cleared"
                    Write-Host "Clearing console in 2 seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                    Clear-Host
                    Write-Host "Console cleared! Only this new output appears." -ForegroundColor Green
                    Write-Host "Check the Warnings and Errors tabs - they still have content!" -ForegroundColor Cyan
                }
            }

            New-UiCard -Header "Error Handling" -Icon "ShieldError" -Stretch -Content {
                New-UiLabel -Text "Errors captured with full diagnostics: line numbers, stack traces." -Style Body
                New-UiButton -Text "Test Error Display" -Icon "Warning" -Action {
                    Write-Host "Generating test errors..." -ForegroundColor Yellow
                    Write-Error "This is a simple Write-Error message"
                    try { $null.SomeMethod() } catch { Write-Error $_ }
                    Get-ChildItem "C:\NonExistent\Path" -ErrorAction Continue
                    Write-Host "Check the Errors tab - click on rows to see details!" -ForegroundColor Cyan
                }
            }
        }

        New-UiPanel -Header "File System Dialogs" -ShowSourceButton -Content {
            New-UiActionCard -Header "File Picker" -Icon "OpenFile" -ButtonText "Pick" -Action {
                $file = Show-UiFilePicker -Title "Select a File"
                if ($file) { Show-UiDialog -Message "Selected: $file" -Title "File" -Type Info }
            }
            New-UiActionCard -Header "Folder Picker" -Icon "OpenFolder" -ButtonText "Pick" -Action {
                $folder = Show-UiFolderPicker -Title "Select a Folder"
                if ($folder) { Show-UiDialog -Message "Selected: $folder" -Title "Folder" -Type Info }
            }
            New-UiActionCard -Header "Save Dialog" -Icon "Save" -ButtonText "Pick" -Action {
                $file = Show-UiSaveDialog -Title "Save As" -DefaultName "document.txt"
                if ($file) { Show-UiDialog -Message "Save to: $file" -Title "Save" -Type Info }
            }
        }

        New-UiPanel -Header "Input Dialogs (Direct)" -ShowSourceButton -LayoutStyle Wrap -Content {
            New-UiLabel -Text "Show-UiInputDialog provides direct input prompts without Read-Host interception:" -Style Body -FullWidth

            New-UiActionCard -Header "Simple Input" -Icon "Edit" -ButtonText "Ask" -Action {
                $name = Show-UiInputDialog -Title "Your Name" -Prompt "Please enter your name:"
                if ($name) {
                    Show-UiDialog -Message "Hello, $name!" -Title "Greeting" -Type Info
                }
            }

            New-UiActionCard -Header "Validated Input" -Icon "Shield" -ButtonText "Ask" -Action {
                $email = Show-UiInputDialog -Title "Email Required" -Prompt "Enter a valid email address:" -ValidatePattern '^[\w\.-]+@[\w\.-]+\.\w+$'
                if ($email) {
                    Show-UiDialog -Message "Email accepted: $email" -Title "Valid" -Type Info
                }
            }

            New-UiActionCard -Header "Password Input" -Icon "Key" -ButtonText "Ask" -Action {
                $secret = Show-UiInputDialog -Title "Secret" -Prompt "Enter a password:" -Password
                if ($secret) {
                    Show-UiDialog -Message "Password captured (length: $($secret.Length))" -Title "Secure" -Type Info
                }
            }
        }

        New-UiPanel -Header "Message Dialogs" -ShowSourceButton -LayoutStyle Wrap -Content {
            New-UiActionCard -Header "Info" -Icon "Info" -ButtonText "Show" -Action {
                Show-UiDialog -Message "This is an informational message." -Title "Information" -Type Info -Buttons OK
            }
            New-UiActionCard -Header "Warning" -Icon "Warning" -ButtonText "Show" -Action {
                Show-UiDialog -Message "This is a warning." -Title "Warning" -Type Warning -Buttons OK
            }
            New-UiActionCard -Header "Error" -Icon "Error" -ButtonText "Show" -Action {
                Show-UiDialog -Message "An error occurred." -Title "Error" -Type Error -Buttons OK
            }
            New-UiActionCard -Header "Question" -Icon "Help" -ButtonText "Show" -Action {
                $result = Show-UiDialog -Message "Proceed with operation?" -Title "Confirm" -Type Question -Buttons YesNo
                Write-Host "Result: $result"
            }
        }

        New-UiPanel -Header "Advanced Dialogs" -ShowSourceButton -Content {
            New-UiButtonCard -Header "HideEmptyOutput Demo" -Icon "Filter" -ButtonText "Test" -Description "Window only shows if there's output - cancel to see it hide" -HideEmptyOutput -Action {
                $name = Read-Host "Enter a name (or cancel for no output)"
                if ($name) {
                    Write-Host "You entered: $name" -ForegroundColor Cyan
                    Write-Host "This output window appears because there's data!"
                }
                # If user cancels or enters nothing, no output = window stays hidden
            }

            New-UiActionCard -Header "YesNoCancel Dialog" -Icon "Help" -ButtonText "Ask" -Action {
                $result = Show-UiDialog -Message "Save changes before closing?" -Title "Unsaved Changes" -Type Question -Buttons YesNoCancel
                switch ($result) {
                    'Yes'    { Write-Host "User chose to SAVE changes" -ForegroundColor Green }
                    'No'     { Write-Host "User chose to DISCARD changes" -ForegroundColor Yellow }
                    'Cancel' { Write-Host "User CANCELLED the operation" -ForegroundColor Gray }
                }
            }
        }

        New-UiPanel -Header "Why This Matters" -FullWidth -Content {
            New-UiLabel -Text "Zero Code Changes Required" -Style SubHeader
            New-UiLabel -Text "Existing scripts that use Read-Host, Get-Credential, -Confirm, or other console operations work automatically. The interception happens at the PSHost level, so your script code doesn't need any modifications." -Style Body
        }
    }

    # TAB 5: Windows
    New-UiTab -Header "Windows" -Content {
        New-UiLabel -Text "Child Windows" -Style Title -FullWidth
        New-UiLabel -Text "Modal and non-modal windows with variable passing and data binding." -Style Note -FullWidth
        New-UiSeparator -FullWidth

        New-UiPanel -Header "Window Types" -ShowSourceButton -LayoutStyle Wrap -MaxColumns 2 -Content {
            New-UiCard -Header "Modal" -Icon "Lock" -Stretch -Content {
                New-UiLabel -Text "Blocks parent until closed." -Style Body
                New-UiButton -Text "Open Modal" -Icon "Lock" -Accent -NoAsync -Action {
                    New-UiChildWindow -Title "Modal Dialog" -Modal -Width 400 -Height 200 -Content {
                        New-UiLabel -Text "This is a modal dialog." -Style Header
                        New-UiLabel -Text "Parent window is blocked." -Style Body
                    }
                }
            }

            New-UiCard -Header "Non-Modal" -Icon "NewWindow" -Stretch -Content {
                New-UiLabel -Text "Both windows remain interactive." -Style Body
                New-UiButton -Text "Open Window" -Icon "NewWindow" -NoAsync -Action {
                    New-UiChildWindow -Title "Non-Modal Window" -Width 400 -Height 200 -Content {
                        New-UiLabel -Text "This is non-modal." -Style Header
                        New-UiLabel -Text "Try clicking the parent window." -Style Body
                    }
                }
            }
        }

        New-UiPanel -Header "Variable Capture" -ShowSourceButton -Content {
            New-UiLabel -Text "Variables defined in parent scope are automatically captured:" -Style Body

            New-UiActionCard -Header "Test Variable Capture" -Icon "Code" -NoAsync -ButtonText "Open" -Description "Opens child window using parent variables" -Action {
                $testMessage = "If you see this, AST capture is working!"
                $testNumber = 42

                New-UiChildWindow -Title "Variable Capture Test" -Modal -Width 450 -Height 250 -Content {
                    New-UiLabel -Text "Captured from parent scope:" -Style Header
                    New-UiLabel -Text "testMessage: $testMessage" -Style Body
                    New-UiLabel -Text "testNumber: $testNumber" -Style Body
                }
            }
        }
    }

    # TAB 6: Standalone Tools
    New-UiTab -Header "Standalone" -Content {
        New-UiLabel -Text "Standalone Output Tools" -Style Title -FullWidth
        New-UiLabel -Text "These tools can run independently or from within a PsUi window." -Style Note -FullWidth
        New-UiSeparator -FullWidth

        New-UiPanel -Header "Data Grid" -ShowSourceButton -Content {
            New-UiLabel -Text "A better Out-GridView with filtering, export, copy, and -PassThru support." -Style Body

            New-UiActionCard -Header "View Processes" -Icon "Gear" -Accent -ButtonText "View" -Description "Display processes in a filterable grid" -Action {
                Get-Process | Select-Object Name, Id, CPU, WorkingSet, StartTime |
                    Out-Datagrid -TitleText "Running Processes" -IsFilterable
            }

            New-UiButtonCard -Header "Select Services" -Icon "Services" -ButtonText "Select" -HideEmptyOutput -Description "Pick services to restart (PassThru demo)" -Action {
                $selected = Get-Service | Select-Object Name, DisplayName, Status, StartType |
                    Out-Datagrid -TitleText "Select Services" -IsFilterable -PassThru

                if ($selected) {
                    $count = $selected.Count
                    Write-Host "You selected $count service(s):" -ForegroundColor Cyan
                    $selected | ForEach-Object {
                        $svcName = $_.Name
                        Write-Host "  - $svcName"
                    }
                }
                else {
                    Write-Host "No selection made" -ForegroundColor Yellow
                }
            }

            New-UiActionCard -Header "Multi-Tab DataSet" -Icon "MapLayers" -ButtonText "View" -Description "Multiple data types in one grid with tabs" -Action {
                Out-Datagrid -TitleText "System Overview" -IsFilterable -DataScriptBlock {
                    New-DataSet -Name "Processes" -Data (
                        Get-Process | Select-Object Name, Id, CPU, WorkingSet
                    )
                    New-DataSet -Name "Services" -Data (
                        Get-Service | Select-Object Name, DisplayName, Status
                    )
                    New-DataSet -Name "Drives" -Data (
                        Get-PSDrive -PSProvider FileSystem | Where-Object Used |
                            Select-Object Name, @{N='UsedGB';E={[math]::Round($_.Used/1GB,1)}}, @{N='FreeGB';E={[math]::Round($_.Free/1GB,1)}}
                    )
                }
            }
        }

        New-UiPanel -Header "Text Editor (Out-TextEditor)" -ShowSourceButton -Content {
            New-UiActionCard -Header "Open Text Editor" -Icon "Pencil" -Accent -ButtonText "Open" -Description "Syntax-aware text editor" -Action {
                $sampleLines = @(
                    '# Sample PowerShell Script'
                    '$info = Get-ComputerInfo'
                    'Write-Host "OS: $($info.OsVersion)"'
                    ''
                    'Get-Process | Where-Object CPU -gt 100 |'
                    '    Select-Object Name, CPU |'
                    '    Format-Table'
                )
                $sample = $sampleLines -join "`n"
                Out-TextEditor -InitialText $sample -TitleText "PowerShell Editor" -FontFamily "Consolas"
            }

            New-UiActionCard -Header "Empty Editor" -Icon "Page" -ButtonText "New" -Action {
                Out-TextEditor -TitleText "New Document"
            }
        }

        New-UiPanel -Header "CSV Editor (Out-CSVDataGrid)" -ShowSourceButton -Content {
            New-UiActionCard -Header "Edit CSV Data" -Icon "Edit" -Accent -ButtonText "Open" -Description "Grid editor with ComboBox columns" -Action {
                $csvPath = Join-Path $env:TEMP "sample_data.csv"
                @(
                    [PSCustomObject]@{ Name = 'Server1'; Type = 'Production'; Status = 'Online' }
                    [PSCustomObject]@{ Name = 'Server2'; Type = 'Development'; Status = 'Offline' }
                    [PSCustomObject]@{ Name = 'Server3'; Type = 'Staging'; Status = 'Online' }
                ) | Export-Csv -Path $csvPath -NoTypeInformation

                Out-CSVDataGrid -CSVFiles $csvPath -TitleText "Server Inventory" -IsFilterable -ColumnComboBoxes @{
                    Type = @('Production', 'Development', 'Staging')
                    Status = @('Online', 'Offline', 'Maintenance')
                }
            }
        }

        New-UiPanel -Header "AD Object Picker (Show-WindowsObjectPicker)" -ShowSourceButton -Content {
            New-UiLabel -Text "Native Windows dialog for selecting AD users, groups, or computers. Requires domain membership for computer picker." -Style Body

            New-UiActionCard -Header "Pick User" -Icon "Contact" -Accent -NoAsync -ButtonText "Pick" -Description "Select an AD user" -Action {
                try {
                    $user = Show-WindowsObjectPicker -ObjectType User
                    if ($user) {
                        Show-UiMessageDialog -Title "Selected User" -Message "You selected: $user" -Icon Info
                    }
                }
                catch {
                    Show-UiMessageDialog -Title "Error" -Message $_.Exception.Message -Icon Error
                }
            }

            New-UiActionCard -Header "Pick User or Group" -Icon "People" -NoAsync -ButtonText "Pick" -Description "Select users and/or groups" -Action {
                try {
                    $selection = Show-WindowsObjectPicker -ObjectType User, Group -MultiSelect
                    if ($selection) {
                        Show-UiMessageDialog -Title "Selected Objects" -Message "You selected:`n$($selection -join "`n")" -Icon Info
                    }
                }
                catch {
                    Show-UiMessageDialog -Title "Error" -Message $_.Exception.Message -Icon Error
                }
            }

            New-UiActionCard -Header "Pick Computer" -Icon "Device" -NoAsync -ButtonText "Pick" -Description "Select a computer (domain only)" -Action {
                try {
                    $computer = Show-WindowsObjectPicker -ObjectType Computer
                    if ($computer) {
                        Show-UiMessageDialog -Title "Selected Computer" -Message "You selected: $computer" -Icon Info
                    }
                }
                catch {
                    Show-UiMessageDialog -Title "Error" -Message $_.Exception.Message -Icon Error
                }
            }
        }
    }

    # TAB 7: New-UiTool
    New-UiTab -Header "UiTool" -Content {
        New-UiLabel -Text "New-UiTool: Auto-Generated GUIs" -Style Title -FullWidth
        New-UiLabel -Text "Transform any PowerShell command into a GUI automatically by introspecting its parameters." -Style Note -FullWidth
        New-UiSeparator -FullWidth

        New-UiPanel -Header "About New-UiTool" -FullWidth -Content {
            New-UiLabel -Text "New-UiTool introspects any PowerShell command - cmdlet, function, or script - and automatically generates a GUI form based on its parameters. Parameter attributes are mapped to appropriate controls:" -Style Body
            New-UiLabel -Text " " -Style Note
            New-UiLabel -Text "ValidateSet becomes Dropdown, switch becomes Checkbox, int with ValidateRange becomes Slider, datetime becomes DatePicker, PSCredential becomes Credential button" -Style Note
            New-UiLabel -Text " " -Style Note
            New-UiLabel -Text "Commands with multiple parameter sets get a dropdown to switch between them. Mandatory parameters are marked with an asterisk (*) and validated before execution." -Style Body
        }

        New-UiSeparator -FullWidth

        New-UiPanel -Header "Built-in Commands" -ShowSourceButton -LayoutStyle Wrap -MaxColumns 2 -Content {
            New-UiCard -Header "Get-Process" -Icon "Gear" -Stretch -Content {
                New-UiLabel -Text "View and filter running processes." -Style Body
                New-UiButton -Text "Launch" -Icon "Gear" -Accent -NoAsync -Action {
                    New-UiChildWindow -Title "Process Viewer" -Width 700 -Height 550 -Content {
                        New-UiTool -Command 'Get-Process' -LayoutStyle Wrap -MaxColumns 2 -ResultActions @(
                            @{
                                Text   = 'Details'
                                Icon   = 'Info'
                                Action = {
                                    param($Selected)
                                    $Selected | ForEach-Object {
                                        Write-Host "Process: $($_.Name) (PID: $($_.Id))" -ForegroundColor Cyan
                                        Write-Host "  CPU: $($_.CPU)" -ForegroundColor Gray
                                        Write-Host "  Memory: $([math]::Round($_.WorkingSet64 / 1MB, 1)) MB" -ForegroundColor Gray
                                    }
                                }
                            }
                        )
                    }
                }
            }

            New-UiCard -Header "Get-Service" -Icon "Services" -Stretch -Content {
                New-UiLabel -Text "View system services with param set switching." -Style Body
                New-UiButton -Text "Launch" -Icon "Services" -NoAsync -Action {
                    New-UiChildWindow -Title "Service Browser" -Width 700 -Height 550 -Content {
                        New-UiTool -Command 'Get-Service' -LayoutStyle Wrap -MaxColumns 2 -ResultActions @(
                            @{
                                Text   = 'Info'
                                Icon   = 'Info'
                                Action = {
                                    param($Selected)
                                    $Selected | ForEach-Object {
                                        Write-Host "Service: $($_.Name) - $($_.DisplayName)" -ForegroundColor Cyan
                                        Write-Host "  Status: $($_.Status)" -ForegroundColor Gray
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }

        New-UiPanel -Header "Custom Functions" -ShowSourceButton -LayoutStyle Wrap -MaxColumns 2 -Content {
            New-UiCard -Header "Search-FileSystem" -Icon "Find" -Stretch -Content {
                New-UiLabel -Text "Custom file search with filters." -Style Body
                New-UiButton -Text "Launch" -Icon "Find" -Accent -NoAsync -Action {
                    New-UiChildWindow -Title "File Search" -Width 750 -Height 600 -Content {
                        New-UiTool -Command 'Search-FileSystem' -LayoutStyle Wrap -MaxColumns 2 -ResultActions @(
                            @{
                                Text   = 'Open Folder'
                                Icon   = 'FolderOpen'
                                Action = {
                                    param($Selected)
                                    $Selected | ForEach-Object {
                                        $folder = Split-Path $_.FullName -Parent
                                        Start-Process explorer.exe -ArgumentList $folder
                                    }
                                }
                            },
                            @{
                                Text   = 'Copy Paths'
                                Icon   = 'Copy'
                                Action = {
                                    param($Selected)
                                    $paths = $Selected.FullName -join "`n"
                                    Set-Clipboard -Value $paths
                                    Write-Host "Copied $($Selected.Count) paths to clipboard" -ForegroundColor Green
                                }
                            }
                        )
                    }
                }
            }

            New-UiCard -Header "Test-ConnectionStatus" -Icon "Internet" -Stretch -Content {
                New-UiLabel -Text "Network connectivity tester." -Style Body
                New-UiButton -Text "Launch" -Icon "Internet" -NoAsync -Action {
                    New-UiChildWindow -Title "Connection Tester" -Width 700 -Height 550 -Content {
                        New-UiTool -Command 'Test-ConnectionStatus' -LayoutStyle Wrap -MaxColumns 2
                    }
                }
            }
        }
    }

    # TAB 8: Advanced
    New-UiTab -Header "Advanced" -Content {
        New-UiLabel -Text "Advanced Features" -Style Title -FullWidth
        New-UiLabel -Text "WPF properties, auto-captured variables, and power-user features." -Style Note -FullWidth
        New-UiSeparator -FullWidth

        New-UiPanel -Header "WPFProperties Parameter" -ShowSourceButton -Content {
            New-UiLabel -Text "Set any WPF property directly on controls. Every New-Ui* function accepts -WPFProperties hashtable:" -Style Body

            New-UiLabel -Text "Hover over me - custom cursor and tooltip!" -WPFProperties @{
                Cursor  = "Hand"
                ToolTip = "Custom tooltip via WPFProperties!"
            }

            New-UiLabel -Text "Text with Drop Shadow" -Style Header -WPFProperties @{
                Effect = ([System.Windows.Media.Effects.DropShadowEffect]@{
                    BlurRadius  = 8
                    ShadowDepth = 3
                    Color       = [System.Windows.Media.Colors]::Gray
                    Opacity     = 0.7
                })
            }

            New-UiLabel -Text "Rotated 15 degrees with blur effect" -Style SubHeader -WPFProperties @{
                RenderTransform = ([System.Windows.Media.RotateTransform]@{ Angle = -8 })
                Effect = ([System.Windows.Media.Effects.BlurEffect]@{ Radius = 1.5 })
                Margin = ([System.Windows.Thickness]::new(20, 10, 0, 10))
            }
        }

        New-UiPanel -Header "Transform and Layout Effects" -ShowSourceButton -Content {
            New-UiLabel -Text "Scale, rotate, skew, and translate any control:" -Style Body

            New-UiAction -Text "Scaled 1.2x" -Action {} -WPFProperties @{
                RenderTransform       = ([System.Windows.Media.ScaleTransform]@{ ScaleX = 1.2; ScaleY = 1.2 })
                RenderTransformOrigin = ([System.Windows.Point]::new(0.5, 0.5))
            }

            New-UiAction -Text "Skewed" -Accent -Action {} -WPFProperties @{
                RenderTransform = ([System.Windows.Media.SkewTransform]@{ AngleX = -10 })
            }

            New-UiInput -Label "Custom Border" -Variable "wpfBorderDemo" -Placeholder "Thick dashed border..." -WPFProperties @{
                BorderThickness = ([System.Windows.Thickness]::new(3))
                BorderBrush     = ([System.Windows.Media.Brushes]::DodgerBlue)
            }
        }

        New-UiPanel -Header "Rich Tooltips and Opacity" -ShowSourceButton -Content {
            New-UiLabel -Text "Create rich multi-line tooltips and control transparency:" -Style Body

            # Build rich tooltip outside of hashtable for PS 5.1 compatibility
            $richTooltip = {
                $sp = [System.Windows.Controls.StackPanel]::new()
                $header = [System.Windows.Controls.TextBlock]::new()
                $header.Text       = "Rich Tooltip Header"
                $header.FontWeight = "Bold"
                $header.FontSize   = 14
                $body = [System.Windows.Controls.TextBlock]::new()
                $timeStr = Get-Date -Format 'HH:mm:ss'
                $body.Text         = "This tooltip has multiple lines`nand custom formatting.`n`nHover time: $timeStr"
                $body.Opacity      = 0.8
                $sp.Children.Add($header) | Out-Null
                $sp.Children.Add($body) | Out-Null
                $sp
            }
            New-UiAction -Text "Hover for Rich Tooltip" -Icon "Info" -Action {} -WPFProperties @{
                ToolTip = (& $richTooltip)
            }

            New-UiLabel -Text "Semi-transparent at half opacity" -Style Body -WPFProperties @{
                Opacity = 0.5
            }

            New-UiLabel -Text "Faded background highlight" -Style Body -WPFProperties @{
                Background = ([System.Windows.Media.Brushes]::Yellow)
                Opacity    = 0.7
                Padding    = ([System.Windows.Thickness]::new(8, 4, 8, 4))
            }
        }

        New-UiPanel -Header "Gradient Backgrounds" -ShowSourceButton -Content {
            New-UiLabel -Text "Apply linear or radial gradients to any control:" -Style Body

            # Build gradient brushes outside hashtable for PS 5.1 compatibility
            $linearGradient = {
                $gradient = [System.Windows.Media.LinearGradientBrush]::new()
                $gradient.StartPoint = "0,0"
                $gradient.EndPoint   = "1,0"
                $gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Colors]::DodgerBlue, 0))
                $gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Colors]::MediumPurple, 1))
                $gradient
            }
            New-UiLabel -Text "Linear Gradient Background" -Style SubHeader -WPFProperties @{
                Background = (& $linearGradient)
                Foreground = ([System.Windows.Media.Brushes]::White)
                Padding    = ([System.Windows.Thickness]::new(16, 8, 16, 8))
            }

            $buttonGradient = {
                $gradient = [System.Windows.Media.LinearGradientBrush]::new()
                $gradient.StartPoint = "0,0"
                $gradient.EndPoint   = "0,1"
                $gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Colors]::ForestGreen, 0))
                $gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Colors]::DarkGreen, 1))
                $gradient
            }
            New-UiAction -Text "Gradient Button" -Action {} -WPFProperties @{
                Background  = (& $buttonGradient)
                Foreground  = ([System.Windows.Media.Brushes]::White)
                BorderBrush = ([System.Windows.Media.Brushes]::Transparent)
            }
        }

        New-UiPanel -Header "Custom Themes (Register-UiTheme)" -ShowSourceButton -Content {
            New-UiLabel -Text "Register custom color themes that appear in the theme picker. Get-UiThemeTemplate shows required keys." -Style Body -FullWidth

            New-UiActionCard -Header "Register 'Ocean' Theme" -Icon "ColorBackground" -Accent -ButtonText "Register" -Action {
                Register-UiTheme -Name 'Ocean' -BasedOn 'Dark' -Force -Colors @{
                    Type             = 'Dark'
                    WindowBg         = '#0D1B2A'
                    WindowFg         = '#E0E1DD'
                    ControlBg        = '#1B263B'
                    ControlFg        = '#E0E1DD'
                    ButtonBg         = '#415A77'
                    ButtonFg         = '#E0E1DD'
                    Accent           = '#00B4D8'
                    Border           = '#778DA9'
                    HeaderBackground = '#0D1B2A'
                    HeaderForeground = '#00B4D8'
                }
                Show-UiDialog -Title "Theme Registered" -Message "'Ocean' theme added! Click the palette icon in the titlebar to switch to it." -Type Info
            }

            New-UiActionCard -Header "Register 'Forest' Theme" -Icon "TreeView" -ButtonText "Register" -Action {
                Register-UiTheme -Name 'Forest' -BasedOn 'Dark' -Force -Colors @{
                    Type             = 'Dark'
                    WindowBg         = '#1A1D1A'
                    WindowFg         = '#D4E6D4'
                    ControlBg        = '#2D352D'
                    ControlFg        = '#D4E6D4'
                    ButtonBg         = '#3D4F3D'
                    ButtonFg         = '#D4E6D4'
                    Accent           = '#7CB87C'
                    Border           = '#5A6B5A'
                    HeaderBackground = '#1A1D1A'
                    HeaderForeground = '#7CB87C'
                }
                Show-UiDialog -Title "Theme Registered" -Message "'Forest' theme added! Click the palette icon in the titlebar to switch to it." -Type Info
            }
        }

        New-UiSeparator -FullWidth

        New-UiPanel -Header "Keyboard Shortcuts" -ShowSourceButton -Content {
            New-UiLabel -Text "Register window-level hotkeys with Register-UiHotkey:" -Style Body -FullWidth
            New-UiLabel -Text "This demo already has Ctrl+S (save), F5 (refresh), and Escape (cancel async) registered." -Style Note -FullWidth

            New-UiPanel -Orientation Horizontal -Content {
                New-UiAction -Text "Try Ctrl+S" -Icon "Save" -NoAsync -Action {
                    Show-UiDialog -Title "Hint" -Message "Press Ctrl+S on your keyboard instead of clicking this button!" -Type Info -Buttons OK
                }
                New-UiAction -Text "Try F5" -Icon "Refresh" -NoAsync -Action {
                    Show-UiDialog -Title "Hint" -Message "Press F5 on your keyboard!" -Type Info -Buttons OK
                }
            }
        }

        New-UiPanel -Header "Auto-Captured Variables" -ShowSourceButton -Content {
            New-UiLabel -Text "Variables defined OUTSIDE New-UiWindow are auto-captured in actions:" -Style Body

            New-UiButtonCard -Header "Test Auto-Capture" -Icon "Variable" -ButtonText "Test" -Description "Uses `$configPath and `$appVersion from script scope" -Action {
                Write-Host "=== Auto-Captured Variables ===" -ForegroundColor Cyan
                Write-Host "configPath: $configPath" -ForegroundColor Green
                Write-Host "maxRetries: $maxRetries" -ForegroundColor Green
                Write-Host "appVersion: $appVersion" -ForegroundColor Green
            }

            New-UiButtonCard -Header "Test Auto-Captured Function" -Icon "Code" -ButtonText "Test" -Description "Uses Format-Greeting defined at script start" -Action {
                $greeting = Format-Greeting -Name "World"
                Write-Host "Function result: $greeting" -ForegroundColor Green
            }
        }

        New-UiPanel -Header "Hydration and Dehydration" -ShowSourceButton -Content {
            New-UiLabel -Text "Control values are auto-injected as variables (hydration)." -Style Body
            New-UiLabel -Text "Changed variables sync back to controls (dehydration)." -Style Note

            New-UiInput -Label "Test Value" -Variable "advTestValue" -Default "Initial value"

            New-UiButton -Text "Read (Hydration)" -Icon "Sync" -Action {
                Write-Host "Value: $advTestValue" -ForegroundColor Cyan
            }

            New-UiAction -Text "Update (Dehydration)" -Icon "CloudUpload" -Action {
                $advTestValue = "Modified at $(Get-Date -Format 'HH:mm:ss')"
            }
        }

        New-UiPanel -Header "List Manipulation" -ShowSourceButton -Content {
            New-UiLabel -Text "Programmatically add, remove, and query list items:" -Style Body -FullWidth

            New-UiList -Variable "manipList" -Items @('Item 1', 'Item 2', 'Item 3') -Height 100

            # Horizontal button row for list actions
            New-UiPanel -Orientation Horizontal -Content {
                New-UiAction -Text "Add Item" -Icon "Add" -NoAsync -Action {
                    $timestamp = Get-Date -Format 'HH:mm:ss'
                    Add-UiListItem -Variable "manipList" -Item "Added at $timestamp"
                }
                New-UiAction -Text "Remove Selected" -Icon "Remove" -NoAsync -Action {
                    $selected = $manipList
                    if ($selected) { Remove-UiListItem -Variable "manipList" -Item $selected }
                }
                New-UiButton -Text "Get All" -Icon "List" -Action {
                    $items = Get-UiListItems -Variable "manipList"
                    Write-Host "List contains $($items.Count) items:" -ForegroundColor Cyan
                    $items | ForEach-Object { Write-Host "  - $_" }
                }
                New-UiAction -Text "Clear" -Icon "Clear" -NoAsync -Action {
                    Clear-UiList -Variable "manipList"
                }
            }
        }

        New-UiPanel -Header "Write-UiHostDirect" -ShowSourceButton -Content {
            New-UiLabel -Text "Bypass PsUi's Write-Host proxy to write directly to the PowerShell console:" -Style Body -FullWidth
            New-UiLabel -Text "Useful for logging to files or when you need real console output." -Style Note -FullWidth

            New-UiButton -Text "Compare Output" -Icon "Compare" -Action {
                Write-Host "This appears in the UI output panel" -ForegroundColor Cyan
                Write-UiHostDirect "This goes to the PowerShell console window" -ForegroundColor Green
                Write-Host "(Check both the output panel AND your PowerShell console)" -ForegroundColor Yellow
            }
        }

    }
}
