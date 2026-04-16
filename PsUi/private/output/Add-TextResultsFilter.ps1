function Add-TextResultsFilter {
    <#
    .SYNOPSIS
        Adds a live search filter box for text-type results in a RichTextBox.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.RichTextBox]$RichTextBox,

        [Parameter(Mandatory)]
        [System.Windows.Controls.StackPanel]$FilterPanel,

        [Parameter(Mandatory)]
        [System.Windows.Controls.DockPanel]$Toolbar2
    )

    $filterResult = New-FilterBoxWithClear -Width 200 -Height 28 -IncludeIcon -AdditionalTagData @{
        RichTextBox = $RichTextBox
        Timer       = $null
    }
    $filterBox = $filterResult.TextBox

    [void]$FilterPanel.Children.Add($filterResult.Icon)
    [void]$FilterPanel.Children.Add($filterResult.Container)
    [System.Windows.Controls.DockPanel]::SetDock($FilterPanel, 'Left')
    $Toolbar2.Children.Insert(0, $FilterPanel)

    $filterBox.Add_TextChanged({
        $tag = $this.Tag

        $tag.ClearButton.Visibility = if ([string]::IsNullOrEmpty($this.Text)) { 'Collapsed' } else { 'Visible' }

        if ($tag.Timer) {
            $tag.Timer.Stop()
            $tag.Timer = $null
        }

        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(300)
        $timer.Tag = $this
        $tag.Timer = $timer

        $timer.Add_Tick({
            try {
                $fb = $this.Tag
                $fbTag = $fb.Tag
                $rtb = $fbTag.RichTextBox

                $searchText = $fb.Text.Trim()
                Find-ConsoleText -RichTextBox $rtb -SearchText $searchText
            }
            catch { Write-Debug "RichTextBox search failed: $_" }
            finally {
                $this.Stop()
                $fb = $this.Tag
                $fb.Tag.Timer = $null
            }
        })

        $timer.Start()
    })

    return @{ FilterBox = $filterBox }
}
