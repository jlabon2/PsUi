function New-UiDropdown {
    <#
    .SYNOPSIS
        Creates a dropdown selection control.
    .DESCRIPTION
        Creates a labeled ComboBox for selecting from a list of items.
    .PARAMETER Label
        Label text displayed above the dropdown.
    .PARAMETER Variable
        Variable name to store selection.
    .PARAMETER Items
        Array of selectable items. Mutually exclusive with ItemsSource.
    .PARAMETER Default
        Initially selected item. Matched against the choices without regard to source, whether
        they came from -Items or a prefilled -ItemsSource. A source that fills after the window
        is built stays unselected, since selecting mid feed would fire -OnChange and flip
        -EnabledWhen while the feed is still running.
    .PARAMETER CaptureScrollWheel
        Same as -ScrollWheel Capture.
    .PARAMETER ScrollWheel
        Says what gets the scrollwheel while the cursor is over a closed dropdown. Page, the default,
        scrolls the page under the cursor. Capture steps the selection instead, whether or not
        the dropdown has been clicked. An open dropdown list scrolls itself either way.
    .PARAMETER FullWidth
        Forces the control to take full width in WrapPanel layouts.
    .PARAMETER EnabledWhen
        Conditional enabling based on another control's state. Accepts either:
        - A control proxy (e.g., $toggleControl) - enables when that control is truthy
        - A scriptblock (e.g., { $toggle -and $userName }) - enables when expression is true

        Truthy values: CheckBox=checked, TextBox=non-empty, ComboBox=has selection.
    .PARAMETER ClearIfDisabled
        When used with -EnabledWhen, resets the dropdown selection when it becomes disabled.
    .PARAMETER OnChange
        ScriptBlock to execute when the selection changes. Receives the new
        selection value as the first parameter.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
        Allows setting any valid WPF property not explicitly exposed as a parameter.
        Bad values warn and get skipped. A property name that does not exist on the control is
        skipped silently (-Verbose shows it). Nothing stops execution.
        Supports attached properties using dot notation (e.g., "Grid.Row").
    .PARAMETER ItemsSource
        A collection to show as the choices, for choices that change at runtime. Anything that
        isn't already a PsUi threadsafe collection gets wrapped in one, and the variable is
        repointed at the wrap so $choices.Add() from a background action shows up. The wrap is
        no longer the type passed in, so .AddRange(), .Sort() and -is [ArrayList] stop working.
        A [ref] has its .Value repointed instead. Items display through ToString(), so keep them
        strings. -NoBind skips the repoint.
    .PARAMETER NoBind
        Skip the repoint. The dropdown still shows the wrap, the original keeps its own
        identity, and the two only stay in step while the mirror holds.
    .EXAMPLE
        New-UiDropdown -Label "Color" -Variable "color" -Items @('Red','Green','Blue') -WPFProperties @{ ToolTip = "Pick a color" }
    .EXAMPLE
        # Choices that fill in later. $fruits is the threadsafe list after the call.
        $fruits = [System.Collections.Generic.List[object]]::new()
        New-UiDropdown -Label "Fruit" -Variable "fruit" -ItemsSource $fruits
        New-UiButton -Text "Load" -Action { 'Apple', 'Pear' | ForEach-Object { $fruits.Add($_) } }
    .EXAMPLE
        New-UiDropdown -Label "Environment" -Variable "env" -Items @('Dev','Staging','Prod') -OnChange {
            param($selected)
            Write-Host "Switched to: $selected"
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string]$Variable,

        [Parameter()]
        [string[]]$Items,

        [string]$Default,

        [switch]$CaptureScrollWheel,

        [switch]$FullWidth,

        [Parameter()]
        [object]$EnabledWhen,

        [Parameter()]
        [switch]$ClearIfDisabled,

        [scriptblock]$OnChange,

        [Parameter()]
        [hashtable]$WPFProperties,

        [Parameter()]
        $ItemsSource,

        [switch]$NoBind,

        [ValidateSet('Page', 'Capture')]
        [string]$ScrollWheel = 'Page'
    )

    # ContainsKey and not truthiness, since an empty -ItemsSource collection evals as false and still means "show this one".
    if ($Items.Count -gt 0 -and $PSBoundParameters.ContainsKey('ItemsSource')) {
        throw "New-UiDropdown cannot use both -Items and -ItemsSource. Choose one."
    }

    try {
        $session = Assert-UiSession -CallerName 'New-UiDropdown'
        Write-Debug "Label='$Label', Variable='$Variable', Items=$($Items.Count)"

        $colors  = Get-ThemeColors
        $parent  = $session.CurrentParent
        Write-Debug "Parent: $($parent.GetType().Name)"

        $stack = [System.Windows.Controls.StackPanel]@{
            Margin = [System.Windows.Thickness]::new(4, 4, 4, 8)
        }

        $labelBlock = [System.Windows.Controls.TextBlock]@{
            Text       = $Label
            FontSize   = 12
            Foreground = ConvertTo-UiBrush $colors.ControlFg
            Margin     = [System.Windows.Thickness]::new(0, 0, 0, 4)
            Tag        = 'ControlFgBrush'
        }
        [PsUi.ThemeEngine]::RegisterElement($labelBlock)
        [void]$stack.Children.Add($labelBlock)

        $combo = [System.Windows.Controls.ComboBox]@{
            Height = 28
        }

        # Before Set-ComboBoxStyle, which hands the wheel to the page on any combo not already routed.
        $wheelMode = if ($CaptureScrollWheel) { 'Capture' } else { $ScrollWheel }
        Set-UiWheelRouting -Control $combo -Mode $wheelMode
        Set-ComboBoxStyle -ComboBox $combo

        # AsyncObservableCollection for the background Add-UiListItem case.
        $collection     = $null
        $mirrorAttached = $false
        if ($PSBoundParameters.ContainsKey('ItemsSource')) {
            $resolved       = Resolve-UiListSource -Source $ItemsSource -NoBind:$NoBind
            $collection     = $resolved.Collection
            $mirrorAttached = $resolved.MirrorAttached

            if ($resolved.NeedsBind -and !$NoBind -and $resolved.Repointed.Count -eq 0 -and $resolved.Converted.Count -eq 0) {
                Write-Warning 'New-UiDropdown -ItemsSource: could not repoint any script variable to the autowrapped collection. Use a variable declared before New-UiWindow (or inside -Content) so $choices.Add() and Add-UiListItem stay connected to the dropdown.'
            }

            if ($resolved.RefWriteMissed) {
                Write-Warning 'New-UiDropdown -ItemsSource: only a [ref] to a variable can be repointed, so a [ref] built from a property still holds the original list. Add through the [ref] .Value, or pass an ObservableCollection, which the dropdown tracks wherever it lives.'
            }

            if ($resolved.Converted.Count -gt 0) {
                Write-Warning "New-UiDropdown -ItemsSource: a type constrained target converted the threadsafe collection on assignment, and the copy never reaches the dropdown ($($resolved.Converted -join ', ')). Drop the type, or use -NoBind and drive the dropdown with Add-UiListItem."
            }
        }
        elseif ($Items.Count -gt 0) { $collection = [PsUi.AsyncObservableCollection[object]]::new($Items) }
        else {
            # ::new($null) can't pick between the collection and Dispatcher overloads.
            $collection = [PsUi.AsyncObservableCollection[object]]::new()
        }
        $combo.ItemsSource = $collection
        $session.RegisterListCollection($Variable, $collection)

        # -eq ignores case and SelectedItem doesn't, so -Default 'west' matches 'West' here and then fails to select it.
        # Sources that fill later stay unselected, since selecting mid feed fires -OnChange and flips -EnabledWhen while the loop runs.
        $defaultItem = $null
        if ($Default) {
            foreach ($item in $collection) {
                # Quoted, or an item that is itself a list turns -eq into a filter over that list.
                if ("$item" -eq $Default) { $defaultItem = $item; break }
            }
        }

        if ($null -ne $defaultItem) { $combo.SelectedItem = $defaultItem }
        elseif ($collection.Count -gt 0) { $combo.SelectedIndex = 0 }

        [void]$stack.Children.Add($combo)

        # Tag wrapper for FormLayout unwrapping in New-UiGrid
        Set-UiFormControlTag -Wrapper $stack -Label $labelBlock -Control $combo

        # FullWidth in WrapPanel contexts
        Set-FullWidthConstraint -Control $stack -Parent $parent -FullWidth:$FullWidth

        # Apply custom WPF properties if specified
        if ($WPFProperties) {
            Set-UiProperties -Control $stack -Properties $WPFProperties
        }

        Write-Debug "Adding to $($parent.GetType().Name)"
        [void]$parent.Children.Add($stack)

        # Hung on the combo (New-UiGrid -FormLayout unwraps the stack out from under it).
        if ($mirrorAttached) { Register-UiCollectionCleanup -Control $combo -Collection $collection }

        # Register control in all session registries
        Register-UiControlComplete -Name $Variable -Control $combo -InitialValue $combo.SelectedItem

        # Store the OnChange callback in Tag so the event handler can reach it
        if ($OnChange) {
            if (!$combo.Tag -or $combo.Tag -isnot [hashtable]) { $combo.Tag = @{} }
            $combo.Tag['OnChange'] = $OnChange

            $combo.Add_SelectionChanged({
                param($sender, $e)
                $tag = $sender.Tag
                if (!$tag -or !$tag.OnChange) { return }

                $selectedValue = $sender.SelectedItem
                try { & $tag.OnChange $selectedValue }
                catch { Write-Warning "OnChange callback error: $_" }
            })
        }

        # Hook conditional enabling if specified
        if ($EnabledWhen) {
            Register-UiCondition -TargetControl $combo -Condition $EnabledWhen -ClearIfDisabled:$ClearIfDisabled
        }
    }
    catch {
        Write-Debug "ERROR: $($_.Exception.Message)"
        Write-Debug "STACK: $($_.ScriptStackTrace)"
        throw
    }
}
