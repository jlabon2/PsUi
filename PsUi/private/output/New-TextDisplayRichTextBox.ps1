function New-TextDisplayRichTextBox {
    <#
    .SYNOPSIS
        Creates a styled RichTextBox for displaying text output with search highlighting support.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Colors,

        [Parameter(Mandatory)]
        [array]$Lines
    )

    # Determine highlight color for selection
    $hlColor = if ($Colors.TextHighlight) { $Colors.TextHighlight } else { $Colors.Selection }

    $richTextBox = [System.Windows.Controls.RichTextBox]@{
        IsReadOnly                    = $true
        VerticalScrollBarVisibility   = 'Auto'
        HorizontalScrollBarVisibility = 'Auto'
        FontFamily                    = [System.Windows.Media.FontFamily]::new('Consolas')
        FontSize                      = 12
        Background                    = ConvertTo-UiBrush $Colors.ControlBg
        Foreground                    = ConvertTo-UiBrush $Colors.ControlFg
        BorderThickness               = [System.Windows.Thickness]::new(0)
        Padding                       = [System.Windows.Thickness]::new(8)
        SelectionBrush                = ConvertTo-UiBrush $hlColor
    }

    # Build document with one Run per line for efficient highlighting
    $paragraph = [System.Windows.Documents.Paragraph]::new()
    $paragraph.Margin = [System.Windows.Thickness]::new(0)
    $paragraph.LineHeight = 1

    $lineCount = 0
    foreach ($line in $Lines) {
        if ($lineCount -gt 0) {
            [void]$paragraph.Inlines.Add([System.Windows.Documents.LineBreak]::new())
        }
        $run = [System.Windows.Documents.Run]::new($line.ToString())
        [void]$paragraph.Inlines.Add($run)
        $lineCount++
    }

    $flowDoc = [System.Windows.Documents.FlowDocument]::new($paragraph)
    $flowDoc.PageWidth = 10000
    $richTextBox.Document = $flowDoc

    # Store highlighting state in Tag for text search
    $highlightBrush = if ($Colors.FindHighlight) { ConvertTo-UiBrush $Colors.FindHighlight } else { [System.Windows.Media.Brushes]::Gold }
    $resetBrush = ConvertTo-UiBrush $Colors.ControlBg

    $richTextBox.Tag = @{
        Paragraph      = $paragraph
        HighlightBrush = $highlightBrush
        ResetBrush     = $resetBrush
        Matches        = [System.Collections.Generic.List[object]]::new()
    }

    return $richTextBox
}
