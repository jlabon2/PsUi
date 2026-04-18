function New-UiButton {
    <#
    .SYNOPSIS
        Creates a styled button with async action support.
    .DESCRIPTION
        Creates a themed WPF button that executes actions asynchronously by default,
        with full output streaming, console interception, and result handling.
        Can be used standalone or as part of other layouts (toolbars, forms, etc.).
        
        Use -Action to provide an inline scriptblock, or -File to run an external
        script file. These parameters are mutually exclusive.
        
        Yeah, there's a lot of parameters here. Splitting them into separate cmdlets
        would mean more boilerplate for every button. They group logically:
        appearance (Text/Icon/Width), execution (Action/NoAsync/NoWait), data binding
        (LinkedVariables/Capture), and result handling (ResultActions). You configure
        all of these together when defining a button, not separately.
    .PARAMETER Text
        The button label text.
    .PARAMETER Action
        The scriptblock to execute when clicked. Mutually exclusive with -File.
    .PARAMETER File
        Path to a script file to execute when clicked. Supports .ps1, .bat, .cmd,
        .vbs, and .exe files. The file must exist at button creation time.
        Mutually exclusive with -Action.
    .PARAMETER ArgumentList
        Hashtable of arguments to pass to the script file. For .ps1 files, these
        are splatted as parameters. For other file types, values are passed as
        command-line arguments.
    .PARAMETER Icon
        Optional icon name from Segoe MDL2 Assets shown before the text.
    .PARAMETER Accent
        Use accent color styling for the button.
    .PARAMETER Width
        Button width in pixels. Defaults to auto-sizing.
    .PARAMETER Height
        Button height in pixels. Defaults to 28.
    .PARAMETER NoAsync
        Execute synchronously on the UI thread (blocks UI).
    .PARAMETER NoWait
        Execute async with output window, but don't block the parent window.
        Other buttons remain clickable while this action runs. The clicked button
        is still disabled to prevent duplicate execution of the same action.
    .PARAMETER NoOutput
        Execute async but don't show output window.
    .PARAMETER NoInteractive
        Use fast pooled execution. The action must not require interactive input
        (Read-Host, Get-Credential, etc.). If interactive input is attempted,
        an error is thrown. Use this for pure data-processing actions.
    .PARAMETER HideEmptyOutput
        Show output window only when there's actual content.
    .PARAMETER ResultActions
        Hashtable array defining actions for DataGrid results.
    .PARAMETER SingleSelect
        If specified, ResultActions work with single selection.
    .PARAMETER LinkedVariables
        Variable names to capture from caller's scope.
    .PARAMETER LinkedFunctions
        Function names to capture from caller's scope.
    .PARAMETER LinkedModules
        Module paths to import in the async runspace.
    .PARAMETER Capture
        Variable names to capture from the runspace after execution completes.
        Captured variables are stored in the session and available to subsequent
        button actions, and persist in global scope after the window closes.
    .PARAMETER Parameters
        Hashtable of parameters to pass to the action.
    .PARAMETER Variables
        Hashtable of variables to inject into the action.
    .PARAMETER OutputTitle
        Title for the output window. Defaults to button text.
    .PARAMETER GridColumn
        If specified, sets Grid.Column attached property.
    .PARAMETER GridRow
        If specified, sets Grid.Row attached property.
    .PARAMETER EnabledWhen
        Conditional enabling based on another control's state. Accepts either:
        - A control proxy (e.g., $toggleControl) - enables when that control is truthy
        - A scriptblock (e.g., { $toggle -and $userName }) - enables when expression is true
        Truthy values: CheckBox=checked, TextBox=non-empty, ComboBox=has selection.
    .PARAMETER Variable
        Optional name to register the button for -SubmitButton lookups.
        When specified, inputs using -SubmitButton with this name will trigger
        the button's click event when Enter is pressed.
    .PARAMETER ValidateScript
        ScriptBlock for custom validation. Runs before the action, receives control values as variables.
    .PARAMETER WPFProperties
        Hashtable of WPF properties to apply to the button.
    .EXAMPLE
        New-UiButton -Text "Save" -Icon "Save" -Accent -Action { Save-Data }
    .EXAMPLE
        New-UiButton -Text "Run Query" -Action { Get-Process } -HideEmptyOutput
    .EXAMPLE
        New-UiButton -Text "Deploy" -File "C:\Scripts\Deploy.ps1" -ArgumentList @{ Environment = 'Prod' }
    .EXAMPLE
        New-UiButton -Text "Backup" -File ".\scripts\backup.bat" -NoOutput
    .EXAMPLE
        # Capture variables for use in other buttons or after window closes
        New-UiButton -Text "Load" -Capture services, loadTime -Action {
            $services = Get-Service | Where-Object Status -eq 'Running'
            $loadTime = Get-Date
        }
        # In another button, $services and $loadTime are now available
    .EXAMPLE
        # In a custom layout
        $toolbar = [System.Windows.Controls.StackPanel]@{ Orientation = 'Horizontal' }
        New-UiButton -Text "Add" -Icon "Add" -Action { Add-Item }
        New-UiButton -Text "Delete" -Icon "Delete" -Action { Remove-Item }
    #>
    [CmdletBinding(DefaultParameterSetName = 'ScriptBlock')]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory, ParameterSetName = 'ScriptBlock')]
        [scriptblock]$Action,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$File,

        [Parameter(ParameterSetName = 'File')]
        [hashtable]$ArgumentList,

        [switch]$Accent,

        [int]$Width,

        [int]$Height = 28,

        # Action execution parameters
        [switch]$NoAsync,
        [switch]$NoWait,
        [switch]$NoOutput,
        [switch]$NoInteractive,
        [switch]$HideEmptyOutput,
        [switch]$ScrollToTop,
        [hashtable[]]$ResultActions,
        [switch]$SingleSelect,
        [string[]]$LinkedVariables,
        [string[]]$LinkedFunctions,
        [string[]]$LinkedModules,
        [string[]]$Capture,
        [hashtable]$Parameters,
        [hashtable]$Variables,
        [string]$OutputTitle,

        # Pre-action validation script - runs synchronously before Action
        # Should return $null or empty array on success, or array of error strings on failure
        [scriptblock]$ValidateScript,

        # Layout parameters
        [int]$GridColumn = -1,
        [int]$GridRow = -1,

        [Parameter()]
        [object]$EnabledWhen,

        [Parameter()]
        [string]$Variable,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    DynamicParam {
        Get-IconDynamicParameter -ParameterName 'Icon'
    }

    begin {
        $Icon = $PSBoundParameters['Icon']
    }

    process {

    # Can't use both - pick one
    if ($NoOutput -and $HideEmptyOutput) {
        throw "Parameters -NoOutput and -HideEmptyOutput are mutually exclusive. Use only one."
    }

    # Catch bad variable names early instead of failing mid-execution
    if ($Capture) {
        foreach ($varName in $Capture) {
            if (![PsUi.Constants]::IsValidIdentifier($varName)) {
                throw "Invalid variable name for -Capture: '$varName'. Names must start with a letter or underscore and contain only letters, numbers, underscores, or hyphens."
            }
        }
    }

    # Convert -File parameter to an Action scriptblock
    if ($PSCmdlet.ParameterSetName -eq 'File') {
        $Action = ConvertTo-UiFileAction -File $File -ArgumentList $ArgumentList
    }

    $session = Assert-UiSession -CallerName 'New-UiButton'
    Write-Debug "Text='$Text', Icon='$Icon', Accent=$Accent, NoAsync=$NoAsync"

    $colors  = Get-ThemeColors
    $parent  = $session.CurrentParent
    Write-Debug "Parent: $($parent.GetType().Name)"

    $btnWidth = if ($Width -gt 0) { $Width } else { [double]::NaN }
    $button = [PsUi.ControlFactory]::CreateButton($Text, $btnWidth, $Height)

    # Configure button content (icon + text or just text)
    $button.Padding = [System.Windows.Thickness]::new(8, 4, 8, 4)
    $button.Margin = [System.Windows.Thickness]::new(4)

    $iconText = if ($Icon) { [PsUi.ModuleContext]::GetIcon($Icon) } else { $null }

    if ($iconText) {
        # Create horizontal stack for icon + text
        $contentPanel = [System.Windows.Controls.StackPanel]@{
            Orientation = 'Horizontal'
            VerticalAlignment = 'Center'
        }

        $iconBlock = [System.Windows.Controls.TextBlock]@{
            Text = $iconText
            FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
            FontSize = 12
            FontWeight = 'Light'
            VerticalAlignment = 'Center'
            Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
        }

        # Accent buttons use contrasting foreground, regular buttons use accent color for icon
        if ($Accent) {
            $iconBlock.Tag = 'AccentButtonIcon'
            $iconBlock.Foreground = ConvertTo-UiBrush $colors.AccentHeaderFg
        }
        else {
            $iconBlock.Tag = 'AccentBrush'
            $iconBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'AccentBrush')
        }
        [PsUi.ThemeEngine]::RegisterElement($iconBlock)

        [void]$contentPanel.Children.Add($iconBlock)

        $textBlock = [System.Windows.Controls.TextBlock]@{
            Text              = $Text
            VerticalAlignment = 'Center'
            TextTrimming      = 'CharacterEllipsis'
        }
        
        # Set foreground: accent buttons use contrasting color, regular buttons use ButtonForeground
        if ($Accent) {
            $textBlock.Tag        = 'AccentButtonText'
            $textBlock.Foreground = ConvertTo-UiBrush $colors.AccentHeaderFg
        }
        else {
            $textBlock.Tag = 'ButtonFgBrush'
            $textBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'ButtonForegroundBrush')
        }
        
        [void]$contentPanel.Children.Add($textBlock)

        # Always use ViewBox for icon+text buttons to handle overflow gracefully
        $viewBox = [System.Windows.Controls.Viewbox]@{
            StretchDirection = 'DownOnly'
            Stretch          = 'Uniform'
        }
        if ($Width -gt 0) {
            $viewBox.MaxWidth  = $Width - 16
            $viewBox.MaxHeight = $Height - 8
        }
        $viewBox.Child = $contentPanel
        $button.Content = $viewBox
    }
    else {
        # Just text - use ViewBox for auto-scaling if needed
        $textBlock = [System.Windows.Controls.TextBlock]@{
            Text              = $Text
            TextAlignment     = 'Center'
            VerticalAlignment = 'Center'
        }
        
        # Set foreground: accent buttons use contrasting color, regular buttons use ButtonForeground
        if ($Accent) {
            $textBlock.Tag        = 'AccentButtonText'
            $textBlock.Foreground = ConvertTo-UiBrush $colors.AccentHeaderFg
        }
        else {
            $textBlock.Tag = 'ButtonFgBrush'
            $textBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'ButtonForegroundBrush')
        }

        if ($Width -gt 0) {
            # Fixed width - use ViewBox for scaling
            $viewBox = [System.Windows.Controls.Viewbox]@{
                StretchDirection = 'DownOnly'
                Stretch          = 'Uniform'
                MaxWidth         = $Width - 16
                MaxHeight        = $Height - 8
            }
            $viewBox.Child = $textBlock
            $button.Content = $viewBox
        }
        else {
            $button.Content = $textBlock
        }
    }

    # Apply grid positioning if specified
    if ($GridColumn -ge 0) {
        [System.Windows.Controls.Grid]::SetColumn($button, $GridColumn)
    }
    if ($GridRow -ge 0) {
        [System.Windows.Controls.Grid]::SetRow($button, $GridRow)
    }

    # Context capture via Get-UiActionContext
    # Captures variables, functions, and modules from caller scope using AST analysis
    $ctxParams = @{
        Action            = $Action
        LinkedVariables   = $LinkedVariables
        LinkedFunctions   = $LinkedFunctions
        LinkedModules     = $LinkedModules
        ExplicitVariables = $Variables
    }
    $actionContext = Get-UiActionContext @ctxParams

    $capturedVars  = $actionContext.CapturedVars
    $capturedFuncs = $actionContext.CapturedFuncs
    $resolvedModules = $actionContext.LinkedModules

    # Store action context in button tag for click handler
    $displayTitle = if ($OutputTitle) { $OutputTitle } else { $Text }

    $button.Tag = @{
        Action          = $Action
        Parameters      = $Parameters
        WindowRef       = $session.Window
        Text            = $displayTitle
        NoAsync         = $NoAsync
        NoWait          = $NoWait
        IsCSharpLoaded  = [PsUi.ModuleContext]::IsInitialized
        ResultActions   = $ResultActions
        SingleSelect    = $SingleSelect
        CapturedVars    = $capturedVars
        CapturedFuncs   = $capturedFuncs
        LinkedModules   = $resolvedModules
        Capture         = $Capture
        NoOutput        = $NoOutput
        NoInteractive   = $NoInteractive
        HideEmptyOutput = $HideEmptyOutput
        ScrollToTop     = $ScrollToTop
        ValidateScript  = $ValidateScript
        IsAccent        = $Accent.IsPresent
    }

    # Apply accent styling AFTER Tag is set (so Set-ButtonStyle can merge IsAccent properly)
    if ($Accent) {
        Set-ButtonStyle -Button $button -Accent
    }

    # Click handler
    $button.Add_Click({
        param($sender, $eventArgs)
        $ctx = $this.Tag
        if ($null -eq $ctx) {
            Write-Warning "[New-UiButton] Tag is null - cannot execute action"
            return
        }
        Write-Debug "Click handler fired, Action is null: $($null -eq $ctx.Action)"
        $btn = $this

        $originalContent = $btn.Content
        
        # Capture current button size before swapping content to spinner
        $originalMinWidth  = $btn.MinWidth
        $originalMinHeight = $btn.MinHeight
        if ($btn.ActualWidth -gt 0) { $btn.MinWidth = $btn.ActualWidth }
        if ($btn.ActualHeight -gt 0) { $btn.MinHeight = $btn.ActualHeight }

        # Run pre-validation script synchronously if provided
        if ($ctx.ValidateScript) {
            try {
                $validationErrors = & $ctx.ValidateScript
                if ($validationErrors -and $validationErrors.Count -gt 0) {
                    # Use [char]0x2022 for bullet point (PS 5.1 compatible, unlike `u{2022})
                    $bullet = [char]0x2022
                    $errorMessage = "Please fix the following issues:`n`n" + (($validationErrors | ForEach-Object { "  $bullet $_" }) -join "`n")
                    Show-UiMessageDialog -Title 'Validation Error' -Message $errorMessage -Icon Warning -Buttons OK | Out-Null
                    return
                }
            }
            catch {
                Show-UiMessageDialog -Title 'Validation Error' -Message "Validation failed: $_" -Icon Error -Buttons OK | Out-Null
                return
            }
        }

        $themeColors = Get-ThemeColors
        
        # Use contrasting spinner color for accent buttons
        $isAccentButton = $btn.Tag -is [System.Collections.IDictionary] -and $btn.Tag['IsAccent']
        $spinnerColor = if ($isAccentButton) { $themeColors.AccentHeaderFg } else { $themeColors.Accent }
        $spinner = New-UiLoadingSpinner -Size 14 -Color $spinnerColor
        $btn.Content = $spinner
        $btn.IsEnabled = $false

        try {
            $forceSynchronous = $ctx.NoAsync

            if (!$forceSynchronous -and $ctx.Action) {
                $actionText = $ctx.Action.ToString()
                if ($actionText -match 'New-UiChildWindow') {
                    $forceSynchronous = $true
                }
            }

            if ($forceSynchronous -eq $true) {
                $result = if ($ctx.Parameters) {
                    & $ctx.Action @($ctx.Parameters)
                } else {
                    & $ctx.Action
                }
                $btn.Content = $originalContent
                $btn.MinWidth = $originalMinWidth
                $btn.MinHeight = $originalMinHeight
                $btn.IsEnabled = $true
            }
            elseif ($ctx.IsCSharpLoaded) {
                $executor = [PsUi.AsyncExecutor]::new()
                
                # Store executor in session for Stop-UiAsync cancellation
                $execSession = [PsUi.SessionManager]::Current
                if ($execSession) { $execSession.ActiveExecutor = $executor }
                
                # Set the UI dispatcher for proper thread marshaling (critical for NoOutput mode)
                $executor.UiDispatcher = $btn.Dispatcher

                $currentThemeColors = Get-ThemeColors
                $varsWithTheme = if ($ctx.CapturedVars) { $ctx.CapturedVars.Clone() } else { @{} }
                if ($currentThemeColors) {
                    $varsWithTheme['__WPFThemeColors'] = $currentThemeColors
                }
                
                # Inject credentials from session.Variables at CLICK TIME (not capture time)
                $clickSession = [PsUi.SessionManager]::Current
                if ($clickSession) {
                    foreach ($credKvp in $clickSession.Variables.GetEnumerator()) {
                        $credName = $credKvp.Key
                        $credWrapper = $credKvp.Value
                        
                        # Skip if already in captured vars
                        if ($varsWithTheme.ContainsKey($credName)) { continue }
                        
                        # Credential wrappers need their inner controls extracted
                        if ($credWrapper -and $credWrapper.PSObject.TypeNames -contains 'PsUi.CredentialControl') {
                            $userBox = $credWrapper.UsernameBox
                            $passBox = $credWrapper.PasswordBox
                            
                            if ($userBox -and $passBox) {
                                $username = $userBox.Text
                                $secPass  = $passBox.SecurePassword
                                
                                if (![string]::IsNullOrWhiteSpace($username) -and $secPass.Length -gt 0) {
                                    $cred = [System.Management.Automation.PSCredential]::new($username, $secPass)
                                    $varsWithTheme[$credName] = $cred
                                    Write-Debug "Injected credential '$credName' at click time"
                                }
                            }
                        }
                    }
                }

                if ($ctx.NoOutput) {
                    # For NoOutput mode only: register handlers to restore button and dispose executor
                    # Show-UiOutput modes handle this themselves via the output window lifecycle
                    $buttonToRestore    = $btn
                    $contentToRestore   = $originalContent
                    $minWidthToRestore  = $originalMinWidth
                    $minHeightToRestore = $originalMinHeight
                    $executorToDispose  = $executor

                    # Wire up window close handler to prevent zombie executors
                    # If window closes while task runs, cancel executor to avoid crash on dead dispatcher
                    #
                    # GetNewClosure() captures the entire scope into a dynamic module. If you are
                    # doing something insane like creating 100 buttons in a loop where the scope has a
                    # giant array, congrats - you now have 100 references to that array. For normal forms
                    # with 5-20 buttons this is fine. We clean up on window close so nothing leaks after.
                    # If you hit memory issues, refactor your loop or stop holding massive objects in scope.
                    $parentWindow = $ctx.WindowRef
                    if ($parentWindow) {
                        $closedHandler = [System.EventHandler]{
                            param($sender, $eventArgs)
                            if ($executorToDispose.IsRunning) {
                                try { $executorToDispose.Cancel() } catch { <# Best-effort cleanup #> }
                            }
                        }.GetNewClosure()
                        $parentWindow.Add_Closed($closedHandler)
                        
                        # Store handler reference so we can remove it when task completes
                        $windowToCleanup = $parentWindow
                        $handlerToRemove = $closedHandler
                    }

                    # Add input providers unless NoInteractive was specified
                    # Without providers, executor uses fast pooled runspace but throws on Read-Host
                    if (!$ctx.NoInteractive) {
                        $inputParams = @{
                            Executor     = $executor
                            DebugEnabled = $false
                        }
                        Add-InputProviders @inputParams
                    }

                    # Shared cleanup: unhook window handler, restore button state, dispose executor.
                    # Called from OnComplete, OnError, and OnCancelled to avoid triple copy-paste.
                    $restoreAndDispose = {
                        param([string]$CallerName)
                        if ($windowToCleanup -and $handlerToRemove) {
                            try { $windowToCleanup.Remove_Closed($handlerToRemove) } catch { <# Window may already be closed #> }
                        }
                        try {
                            if ($buttonToRestore.Dispatcher.HasShutdownStarted) { return }
                            $buttonToRestore.Dispatcher.Invoke([Action]{
                                $buttonToRestore.Content   = $contentToRestore
                                $buttonToRestore.MinWidth  = $minWidthToRestore
                                $buttonToRestore.MinHeight = $minHeightToRestore
                                $buttonToRestore.IsEnabled = $true
                            })
                        }
                        catch { Write-Debug "$CallerName UI restore skipped (window closed): $_" }
                        try { $executorToDispose.Dispose() } catch { Write-Debug "$CallerName dispose error: $_" }
                    }.GetNewClosure()

                    $executor.add_OnComplete({
                        & $restoreAndDispose 'OnComplete'
                    }.GetNewClosure())

                    $executor.add_OnError({
                        param($errorRecord)
                        # Show error dialog since NoOutput mode has no console to display errors
                        if ($errorRecord) {
                            try {
                                if (!$buttonToRestore.Dispatcher.HasShutdownStarted) {
                                    $errorMsg = $errorRecord.ToString()
                                    $buttonToRestore.Dispatcher.Invoke([Action]{
                                        Show-UiMessageDialog -Title 'Action Error' -Message $errorMsg -Icon Error
                                    })
                                }
                            }
                            catch { Write-Debug "OnError dialog skipped (window closed): $_" }
                        }
                        & $restoreAndDispose 'OnError'
                    }.GetNewClosure())

                    $executor.add_OnCancelled({
                        & $restoreAndDispose 'OnCancelled'
                    }.GetNewClosure())

                    # Set capture variables if specified
                    if ($ctx.Capture) {
                        $executor.CaptureVariables = [string[]]$ctx.Capture
                    }

                    # Fire and forget - handlers will restore button when done
                    $executor.ExecuteAsync(
                        $ctx.Action,
                        $ctx.Parameters,
                        $varsWithTheme,
                        $ctx.CapturedFuncs,
                        [string[]]@($ctx.LinkedModules | Where-Object { $_ })
                    )
                    return
                }
                else {
                    # Output window path (HideEmptyOutput and normal share the same flow)
                    try {
                        $outParams = @{
                            Executor                  = $executor
                            Title                     = $ctx.Text
                            ParentWindow              = $ctx.WindowRef
                            Action                    = $ctx.Action
                            Parameters                = $ctx.Parameters
                            ResultActions             = $ctx.ResultActions
                            SingleSelect              = $ctx.SingleSelect
                            LinkedVariableValues      = $varsWithTheme
                            LinkedFunctionDefinitions = $ctx.CapturedFuncs
                            LinkedModules             = $ctx.LinkedModules
                            Capture                   = $ctx.Capture
                            NoWait                    = $ctx.NoWait
                        }
                        if ($ctx.HideEmptyOutput) { $outParams['HideUntilContent'] = $true }
                        if ($ctx.ScrollToTop) { $outParams['ScrollToTop'] = $true }

                        $outputWindow = Show-UiOutput @outParams

                        # NoWait mode: wire up Closed event to restore button when output window closes
                        if ($ctx.NoWait -and $outputWindow) {
                            $buttonToRestore    = $btn
                            $contentToRestore   = $originalContent
                            $minWidthToRestore  = $originalMinWidth
                            $minHeightToRestore = $originalMinHeight
                            $outputWindow.Add_Closed({
                                $buttonToRestore.Content   = $contentToRestore
                                $buttonToRestore.MinWidth  = $minWidthToRestore
                                $buttonToRestore.MinHeight = $minHeightToRestore
                                $buttonToRestore.IsEnabled = $true
                            }.GetNewClosure())
                            return
                        }
                    }
                    catch {
                        Write-Warning "Output window error: $($_.Exception.Message)"
                        # Kill the executor if it's still running
                        try {
                            if ($executor.IsRunning) { $executor.Cancel() }
                            $executor.Dispose()
                        } catch { Write-Debug "Output cleanup error: $_" }
                    }
                }

                # Restore button after output window closes (whether success or failure)
                $btn.Content = $originalContent
                $btn.MinWidth = $originalMinWidth
                $btn.MinHeight = $originalMinHeight
                $btn.IsEnabled = $true
            }
            else {
                Write-Warning "Async unavailable. Running synchronously."
                $result = if ($ctx.Parameters) {
                    & $ctx.Action @($ctx.Parameters)
                } else {
                    & $ctx.Action
                }
                $btn.Content = $originalContent
                $btn.MinWidth = $originalMinWidth
                $btn.MinHeight = $originalMinHeight
                $btn.IsEnabled = $true
            }
        }
        catch {
            $btn.Content = $originalContent
            $btn.MinWidth = $originalMinWidth
            $btn.MinHeight = $originalMinHeight
            $btn.IsEnabled = $true

            # Log error details for debugging
            Write-Debug "Action error: $($_.Exception.GetType().Name) - $($_.Exception.Message)"
            Write-Debug "Stack: $($_.ScriptStackTrace)"

            # Show error dialog for sync execution errors
            Show-UiMessageDialog -Title "Error: $($ctx.Text)" -Message $_.Exception.Message -Icon Error -Buttons OK | Out-Null
        }
    })

    # Apply custom WPF properties if specified
    if ($WPFProperties) {
        Set-UiProperties -Control $button -Properties $WPFProperties
    }

    # Wire up conditional enabling if specified
    if ($EnabledWhen) {
        Register-UiCondition -TargetControl $button -Condition $EnabledWhen
    }

    # Register button by name for -SubmitButton lookups
    if ($Variable) {
        $session.RegisterButton($Variable, $button)
    }

    Write-Debug "Adding to $($parent.GetType().Name)"
    $addedToParent = $false
    if ($parent -is [System.Windows.Controls.Panel]) {
        [void]$parent.Children.Add($button)
        $addedToParent = $true
    }
    elseif ($parent -is [System.Windows.Controls.ItemsControl]) {
        [void]$parent.Items.Add($button)
        $addedToParent = $true
    }
    elseif ($parent -is [System.Windows.Controls.ContentControl]) {
        $parent.Content = $button
        $addedToParent = $true
    }

    # Only return button if not added to parent (for manual layout scenarios)
    if (!$addedToParent) {
        return $button
    }
    }
}
