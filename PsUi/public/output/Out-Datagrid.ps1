function Out-Datagrid {
    <#
    .SYNOPSIS
        Like Out-GridView, but you can read it and theme it.
    .DESCRIPTION
        Pipe objects in and receive a sortable filterable grid. Add -PassThru and you get the
        selected rows back on OK. Closing the window or clicking Cancel returns nothing.

        Filter, copy, export to CSV, and a column picker are in the toolbar. Sort by
        clicking column headers.

        Opens the window in place when the calling session can host one directly (ISE, PsUi -NoAsync
        actions). From a console session that can't, spins up a dedicated UI host and shows
        the window there. Either way the call blocks until you close it.

        Can't be called from inside an async button action. Use -NoAsync on the button.
    .PARAMETER Data
        The objects to show. Take from the pipeline or pass directly.
    .PARAMETER TitleText
        Window title.
    .PARAMETER IsFilterable
        Show the filter textbox.
    .PARAMETER PassThru
        Return the selected rows on OK.
    .PARAMETER OutputMode
        How many rows can be selected: None, Single, or Multiple (default - Ctrl/Shift to extend).
    .PARAMETER Theme
        Color theme. See Get-UiThemeTemplate for the list.
    .PARAMETER Width
        Window width in pixels (400-2000).
    .PARAMETER Height
        Window height in pixels (300-1500).
    .PARAMETER IconFont
        Which icon font to use for the toolbar: Inherit (default), Auto, SegoeMDL2 (Win10),
        or SegoeFluentIcons (Win11). Only matters when this is the top-level window. When
        hosted inside another PsUi window, that window's font wins.
    .PARAMETER NoIconFontFallback
        Don't fall back to other icon fonts for missing glyphs. Mostly useful for tightening
        Tab completion on -Icon parameters.
    .PARAMETER RowBackground
        Scriptblock that colors rows. Returns a color string (e.g. '#33FF6B6B') or $null.
        `$_` is the row inside the scriptblock. Runs as rows scroll into view.
    .PARAMETER DefaultSort
        Sort the grid before showing it. Accepts:
          - 'PropName'
          - 'PropName -Descending'
          - @{ Property = 'PropName'; Direction = 'Descending' }
          - an array of any of the above for multi-key sorting
    .PARAMETER NoSafeWrap
        Skip the protective wrapping done on input items. Faster, but if a property getter
        on one of your objects throws, the whole grid blows up.
    .EXAMPLE
        Get-Process | Out-Datagrid -TitleText 'Processes' -IsFilterable
    .EXAMPLE
        Get-Service | Out-Datagrid -PassThru | Restart-Service
    .EXAMPLE
        Get-ChildItem $env:WINDIR\System32 -Filter *.dll | Out-Datagrid -PassThru -OutputMode Single
    .EXAMPLE
        $rowBg   = { if ($_.Status -eq 'Stopped') { '#33FF6B6B' } }
        $dgSplat = @{ RowBackground = $rowBg; DefaultSort = 'Status' }
        Get-Service | Out-Datagrid @dgSplat
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [object[]]$Data,

        [Alias('Title')]
        [string]$TitleText = 'Data Grid',

        [switch]$IsFilterable,

        [switch]$PassThru,

        [ValidateSet('None', 'Single', 'Multiple')]
        [string]$OutputMode = 'Multiple',

        [ArgumentCompleter({ [PsUi.ThemeEngine]::GetAvailableThemes() })]
        [string]$Theme = 'Light',

        [ValidateRange(400, 2000)]
        [int]$Width = 900,

        [ValidateRange(300, 1500)]
        [int]$Height = 600,

        [ValidateSet('Inherit', 'Auto', 'SegoeMDL2', 'SegoeFluentIcons')]
        [string]$IconFont = 'Inherit',

        [switch]$NoIconFontFallback,

        [scriptblock]$RowBackground,

        $DefaultSort,

        [switch]$NoSafeWrap
    )

    begin {
        $accumulated = [System.Collections.Generic.List[object]]::new()
    }

    process {
        # $null -ne, not truthiness: a piped 0/''/$false binds as a one element array that PS evaluates falsy.
        if ($null -ne $Data) {
            foreach ($item in $Data) { [void]$accumulated.Add($item) }
        }
    }

    end {
        if ($accumulated.Count -eq 0) {
            Write-Warning 'No data to display'
            return
        }

        # ShowDialog needs the UI thread. Match Out-CSVDataGrid's stance and bounce with a clear error rather than freezing your button action partway through.
        if ([PsUi.AsyncExecutor]::CurrentExecutor) {
            Write-Error 'Out-Datagrid cannot be called from an async button action (ShowDialog requires the UI thread). Use -NoAsync on the button.'
            return
        }

        $effectiveSelectionMode = switch ($OutputMode) {
            'Single' { 'Single' }
            'None'   { 'None' }
            default  { 'Extended' }
        }

        # Carry everything the worker needs. Hashtables travel tghrough runspace boundaries by reference so OK button writes to SharedResult are visible in this scope after the worker returns.
        $sharedResult = @{ OK = $false; Selection = $null }
        $ctx = @{
            Items               = $accumulated
            TitleText           = $TitleText
            Width               = $Width
            Height              = $Height
            Theme               = $Theme
            IconFont            = $IconFont
            NoIconFontFallback  = $NoIconFontFallback.IsPresent
            IsFilterable        = $IsFilterable.IsPresent
            PassThru            = $PassThru.IsPresent
            EffSelMode          = $effectiveSelectionMode
            RowBackground       = $RowBackground
            DefaultSort         = $DefaultSort
            NoSafeWrap          = $NoSafeWrap.IsPresent
            ThemeBound          = $PSBoundParameters.ContainsKey('Theme')
            IconFontBound       = $PSBoundParameters.ContainsKey('IconFont')
            NoIconFontFbBound   = $PSBoundParameters.ContainsKey('NoIconFontFallback')
            SharedResult        = $sharedResult
        }

        # For the injected function cleanup inside buildAndShow. $PSCmdlet.SessionState is the calling script's (outside the module) session state. Removing a global function that shadows a module private one only works from a session state outside the module - a plain Remove-Item in module scope hits the shadow and silently leaks the global. Null inside the spawned MTA runspace, which is disposed anyway.
        $callerSessionState = $PSCmdlet.SessionState
        $fnRemover = [scriptblock]::Create("Remove-Item -LiteralPath ('Function:' + `$args[0]) -Force -ErrorAction SilentlyContinue")

        # Window construction + ShowDialog packaged as one closure. Runs inline when the calling script is STA (keeps its UI thread the same as the Application's so theme switches don't cross threads), shipped onto a spawned STA runspace when it's MTA.
        $buildAndShow = {
            param($context)

            # Create the WPF Application on this thread (the one that will ShowDialog) before any theme call. Does nothing if one exists. Without it, Initialize-UITheme below would create the App via ThemeEngine, which no longer does so - and a later New-UiWindow that inherited a cross thread App would lose all content theming. Must live inside the closure: the MTA path reparses this from a string and runs it on a fresh STA thread.
            [void][PsUi.ThemeEngine]::EnsureApplication()

            # Inheriting from parent's __WPFThemeColors only makes sense in a runspace that HAS it in scope. The spawned STA runspace path won't.
            $isStandalone = !(Test-Path variable:__WPFThemeColors)
            $themeName    = $context.Theme
            if (!$context.ThemeBound) {
                $active = [PsUi.ModuleContext]::ActiveTheme
                if (![string]::IsNullOrWhiteSpace($active)) { $themeName = $active }
            }
            if ($isStandalone) {
                $colors = Initialize-UITheme -Theme $themeName
            }
            else {  $colors = Get-Variable -Name __WPFThemeColors -ValueOnly -ErrorAction SilentlyContinue    }
            if (!$colors) { $colors = Initialize-UITheme -Theme $themeName }

            # Synthesise BoundParameters for Push-UiIconFontOverride from the bound flags.
            $bp = @{}
            if ($context.IconFontBound)     { $bp['IconFont']           = $context.IconFont }
            if ($context.NoIconFontFbBound) { $bp['NoIconFontFallback'] = $context.NoIconFontFallback }
            $overrideParams = @{
                IsStandalone       = $isStandalone
                BoundParameters    = $bp
                IconFont           = $context.IconFont
                NoIconFontFallback = [bool]$context.NoIconFontFallback
            }
            $iconFontSnap = Push-UiIconFontOverride @overrideParams

            # Full teardown on the error path. No try/finally around the build+ShowDialog below: this closure runs outside the pipeline (inline STA branch, called from a -NoAsync click delegate) where PS's CheckActionPreference NREs on try block exit. The tail block after ShowDialog mirrors this for the success path. Guards cover an early throw before the session exists.
            trap {
                foreach ($fnName in $injectedFns) {
                    if ($callerSessionState) { $ExecutionContext.InvokeCommand.InvokeScript($callerSessionState, $fnRemover, @($fnName)) }
                }
                if ($null -ne $sessionId -and $sessionId -ne [Guid]::Empty) { [PsUi.SessionManager]::DisposeSession($sessionId)  }
                if ($null -ne $priorSessionId -and $priorSessionId -ne [Guid]::Empty) { [PsUi.SessionManager]::SetCurrentSession($priorSessionId) }
                
                if ($null -ne $priorGlobalId) {  $Global:__PsUiSessionId = $priorGlobalId  }
                else { Remove-Variable -Name __PsUiSessionId -Scope Global -ErrorAction SilentlyContinue }
                
                if ($iconFontSnap) {
                    [PsUi.ModuleContext]::RestoreIconFontState($iconFontSnap)
                    $iconFontSnap = $null
                }

                break
            }

            $window = [System.Windows.Window]@{
                Title                 = $context.TitleText
                Width                 = $context.Width
                Height                = $context.Height
                MinWidth              = 400
                MinHeight             = 300
                WindowStartupLocation = 'CenterScreen'
                FontFamily            = [System.Windows.Media.FontFamily]::new('Segoe UI')
                ResizeMode            = 'CanResizeWithGrip'
            }

            # Pin owner / center BEFORE the session swap below - after it $session.Window is THIS window, and CenterOnParent($window, $window) NullRefs reading the bounds of an unshown self owner.
            if (!$isStandalone) {
                Set-UiDialogPosition -Dialog $window
            }
            else {
                $null = Set-WindowOwner -Window $window
            }

            $window.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'WindowBackgroundBrush')
            $window.SetResourceReference([System.Windows.Window]::ForegroundProperty, 'ControlForegroundBrush')

            Set-UIResources -Window $window -Colors $colors

            try {
                $appId = "PsUi.OutDatagrid." + [Guid]::NewGuid().ToString("N").Substring(0, 8)
                [PsUi.WindowManager]::SetWindowAppId($window, $appId)
            }
            catch { Write-Debug "SetWindowAppId failed: $_" }

            $datagridIcon = $null
            try {
                $datagridIcon = New-WindowIcon -Colors $colors
                if ($datagridIcon) { $window.Icon = $datagridIcon }
            }
            catch { Write-Verbose "Failed to create window icon: $_" }

            $capturedWindow = $window
            $capturedIcon   = $datagridIcon
            $window.Add_Loaded({
                if ($capturedIcon) {
                    try { [PsUi.WindowManager]::SetTaskbarIcon($capturedWindow, $capturedIcon) }
                    catch { Write-Debug "SetTaskbarIcon failed: $_" }
                }
            }.GetNewClosure())

            $mainPanel = [System.Windows.Controls.DockPanel]@{ LastChildFill = $true }
            $window.Content = $mainPanel

            $headerBorder = [System.Windows.Controls.Border]@{
                Padding = [System.Windows.Thickness]::new(16, 12, 16, 12)
                Tag     = 'HeaderBorder'
            }
            $headerBorder.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'HeaderBackgroundBrush')
            [System.Windows.Controls.DockPanel]::SetDock($headerBorder, 'Top')

            $headerGrid = [System.Windows.Controls.Grid]::new()
            [void]$headerGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]@{  Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })
            [void]$headerGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]@{  Width = [System.Windows.GridLength]::Auto  })

            $headerStack = [System.Windows.Controls.StackPanel]@{ Orientation = 'Horizontal' }
            [System.Windows.Controls.Grid]::SetColumn($headerStack, 0)

            $headerIcon = [System.Windows.Controls.TextBlock]@{
                Text              = [PsUi.ModuleContext]::GetIcon('GridView')
                FontFamily        = [PsUi.ModuleContext]::ActiveIconFontFamily
                FontSize          = 24
                VerticalAlignment = 'Center'
                Width             = 32
                TextAlignment     = 'Center'
                Margin            = [System.Windows.Thickness]::new(0, 0, 12, 0)
                Tag               = 'HeaderText'
            }
            $headerIcon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'HeaderForegroundBrush')
            [void]$headerStack.Children.Add($headerIcon)

            $headerTitle = [System.Windows.Controls.TextBlock]@{
                Text              = $context.TitleText
                FontSize          = 18
                FontWeight        = [System.Windows.FontWeights]::SemiBold
                VerticalAlignment = 'Center'
                Tag               = 'HeaderText'
            }
            $headerTitle.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'HeaderForegroundBrush')
            [void]$headerStack.Children.Add($headerTitle)

            [void]$headerGrid.Children.Add($headerStack)

            if ($isStandalone) {
                $themeButtonData = New-ThemePopupButton -Container $window -CurrentTheme $themeName
                [System.Windows.Controls.Grid]::SetColumn($themeButtonData.Button, 1)
                [void]$headerGrid.Children.Add($themeButtonData.Button)
            }

            $headerBorder.Child = $headerGrid
            [void]$mainPanel.Children.Add($headerBorder)

            $bodyGrid = [System.Windows.Controls.Grid]@{  Margin = [System.Windows.Thickness]::new(12)  }
            [void]$bodyGrid.RowDefinitions.Add([System.Windows.Controls.RowDefinition]@{  Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })
            [void]$bodyGrid.RowDefinitions.Add([System.Windows.Controls.RowDefinition]@{  Height = [System.Windows.GridLength]::Auto })
            [void]$mainPanel.Children.Add($bodyGrid)

            $gridHost = [System.Windows.Controls.Grid]::new()
            [System.Windows.Controls.Grid]::SetRow($gridHost, 0)
            [void]$bodyGrid.Children.Add($gridHost)

            $buttonBar = [System.Windows.Controls.StackPanel]@{
                Orientation         = 'Horizontal'
                HorizontalAlignment = 'Right'
                Margin              = [System.Windows.Thickness]::new(0, 8, 0, 0)
            }
            [System.Windows.Controls.Grid]::SetRow($buttonBar, 1)
            [void]$bodyGrid.Children.Add($buttonBar)

            # Get-UiSession checks $Global:__PsUiSessionId BEFORE SessionManager.Current. Without an override on the global, New-UiDataGrid finds the parent's session and adds the grid to the parent's CurrentParent (the wrong window) instead of this gridHost.
            $priorSessionId = [PsUi.SessionManager]::CurrentSessionId
            $priorGlobalId  = if (Test-Path variable:Global:__PsUiSessionId) { $Global:__PsUiSessionId } else { $null }

            $sessionId = [PsUi.SessionManager]::CreateSession()
            [PsUi.SessionManager]::SetCurrentSession($sessionId)
            $Global:__PsUiSessionId = $sessionId.ToString()

            $session = [PsUi.SessionManager]::Current
            $session.Window        = $window
            $session.CurrentParent = $gridHost

            # Grid handlers and the OK button are GetNewClosure scriptblocks - WPF resolves their calls against the runspace GLOBAL scope. New-UiWindow injects private functions for exactly this. These paths get none, so copy/export/PassThru died CommandNotFound.
            $injectedFns = [System.Collections.Generic.List[string]]::new()
            $privFns     = [PsUi.ModuleContext]::PrivateFunctions
            if ($privFns) {
                foreach ($fnName in @($privFns.Keys)) {
                    # Add only what's missing so cleanup can't take out a preexisting global
                    if (!(Test-Path -LiteralPath "function:global:$fnName")) {
                        Set-Item -LiteralPath "function:global:$fnName" -Value ([scriptblock]::Create([string]$privFns[$fnName]))
                        [void]$injectedFns.Add($fnName)
                    }
                }
            }

            $gridArgs = @{
                Items              = $context.Items
                Variable           = 'picked'
                SelectionMode      = $context.EffSelMode
                FullWidth          = $true
                CaptureScrollWheel = $true
            }
            if (!$context.IsFilterable) { $gridArgs.NoFilter      = $true }
            if ($context.RowBackground) { $gridArgs.RowBackground = $context.RowBackground }
            if ($context.DefaultSort)   { $gridArgs.DefaultSort   = $context.DefaultSort }
            if ($context.NoSafeWrap)    { $gridArgs.NoSafeWrap    = $true }

            New-UiDataGrid @gridArgs

            $session.CurrentParent = $buttonBar

            # Direct refs for the click actions - Get-UiSession comes back null in WPF click scopes (and isn't resolvable at all on the inline path), which made (Get-UiSession).Window.Close() NullRef at OK time.
            $winRef    = $window
            $resultRef = $context.SharedResult
            $gridRef   = $session.GetControl('picked')

            if ($context.PassThru) {
                New-UiButton -Text 'OK' -NoAsync -Action {
                    # -NoAsync skips variable hydration so $picked is empty - read SelectedItems off the captured grid ref, then close via the captured window ref.
                    try {
                        if ($gridRef -and $resultRef) {
                            $resultRef.OK        = $true
                            $resultRef.Selection = @($gridRef.SelectedItems | ForEach-Object {
                                if ($null -ne $_._BaseObject) { $_._BaseObject } else { $_ }
                            })
                        }
                    }
                    catch { Write-Debug "Out-Datagrid OK action selection capture failed: $_" }
                    if ($winRef) { $winRef.Close() }
                }.GetNewClosure()
                New-UiButton -Text 'Cancel' -NoAsync -Action {
                    if ($winRef) { $winRef.Close() }
                }.GetNewClosure()
            }
            else {
                New-UiButton -Text 'Close' -NoAsync -Action {
                    if ($winRef) { $winRef.Close() }
                }.GetNewClosure()
            }

            for ($i = 1; $i -lt $buttonBar.Children.Count; $i++) {
                $buttonBar.Children[$i].Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
            }

            [void]$window.ShowDialog()

            # Success path teardown, mirroring the trap above. Plain statements, not a finally - outside the pipeline the finally would NRE on exit. The trap covers the error path.
            foreach ($fnName in $injectedFns) {
                # A plain Remove-Item runs in module scope and hits the module's own shadow, never the injected global copy (leaks). Run it in the calling session state (outside the module) where Function:name resolves to the global one. Null in the spawned MTA runspace (disposed).
                if ($callerSessionState) { $ExecutionContext.InvokeCommand.InvokeScript($callerSessionState, $fnRemover, @($fnName)) }
            }
            [PsUi.SessionManager]::DisposeSession($sessionId)
            if ($priorSessionId -ne [Guid]::Empty) {  [PsUi.SessionManager]::SetCurrentSession($priorSessionId)   }
            
            if ($null -ne $priorGlobalId) {  $Global:__PsUiSessionId = $priorGlobalId  }
            else {  Remove-Variable -Name __PsUiSessionId -Scope Global -ErrorAction SilentlyContinue  }
            
            if ($iconFontSnap) {
                [PsUi.ModuleContext]::RestoreIconFontState($iconFontSnap)
                $iconFontSnap = $null
            }

            # Emit the final result after cleanup. The MTA path reads this through $ps.Invoke() output. AddArgument passes $context.SharedResult in the same process so the hashtable mutation usually round-trips, but the emit is the guarantee.
            [PSCustomObject]@{
                OK        = [bool]$context.SharedResult.OK
                Selection = $context.SharedResult.Selection
            }
        }

        # The build scriptblock owns its cleanup. This catch logs breadcrumbs and rethrows.
        # Swallowing made any build/ShowDialog failure look exactly like Cancel - no window, no error, -PassThru empty. A mistitled parent error popup beats silent.
        $emitted = $null
        try {
            if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA) {
                $emitted = & $buildAndShow $ctx
            }
            else {
                # MTA host (typically pwsh.exe console). Window construction requires STA - spawn one. No parent UI thread to block in this case so the original cross thread theme bug doesn't apply.
                $modulePath = (Get-Module -Name PsUi).Path
                if (!$modulePath) {
                    Write-Error "Out-Datagrid: PsUi module path not resolvable; can't spawn STA runspace."
                    return
                }

                $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
                $rs.ApartmentState = [System.Threading.ApartmentState]::STA
                $rs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
                $rs.Open()
                $ps = $null
                try {
                    $ps = [System.Management.Automation.PowerShell]::Create()
                    $ps.Runspace = $rs
                    [void]$ps.AddCommand('Import-Module').AddArgument($modulePath).AddParameter('Force', $true)
                    [void]$ps.Invoke()
                    $ps.Commands.Clear()

                    # Pass the scriptblock as a string - ScriptBlock objects are pinned to their creation runspace. The $wrapper reparses it inside the module's session state so private functions resolve. Otherwise the first private call dies.
                    $wrapper = {
                        param($scriptText, $context)
                        # Two PsUi modules load in the spawned runspace: binary (PsUi.dll) and script (PsUi.psm1). Only the script one can be invoked with & - the binary throws "Cannot use '&' to invoke in the context of binary module".
                        $mod = Get-Module PsUi | Where-Object { $_.ModuleType -eq 'Script' } | Select-Object -First 1
                        if (!$mod) { throw "PsUi script module not loaded in spawned runspace" }
                        & $mod {
                            param($text, $ctx)
                            $sb = [scriptblock]::Create($text)
                            & $sb $ctx
                        } $scriptText $context
                    }
                    [void]$ps.AddScript($wrapper.ToString()).AddArgument($buildAndShow.ToString()).AddArgument($ctx)
                    $emitted = $ps.Invoke()

                    foreach ($errorRecord in $ps.Streams.Error) { $Host.UI.WriteErrorLine($errorRecord.ToString()) }
                }
                finally {
                    if ($ps) { $ps.Dispose() }
                    $rs.Close()
                    $rs.Dispose()
                }
            }
        }
        catch {
            Write-Debug "Out-Datagrid dispatch caught: $($_.Exception.GetType().Name): $($_.Exception.Message)"
            Write-Debug "Stack: $($_.ScriptStackTrace)"
            throw
        }

        # Pick the emitted result object out of whatever buildAndShow streamed. Picks last so any intermediate writes from inner code don't take precedence over the final summary.
        $result = $emitted |
            Where-Object { $_ -is [System.Management.Automation.PSObject] -and $_.PSObject.Properties['OK'] } |
            Select-Object -Last 1

        if ($PassThru -and $result -and $result.OK) { return $result.Selection }
    }
}
