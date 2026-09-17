#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Private PowerShell helpers. Nothing here touches WPF or a live session.
. (Join-Path $PSScriptRoot '_Setup.ps1')

BeforeAll { . (Join-Path $PSScriptRoot '_Setup.ps1') }

# Private functions aren't exported, so they need module scope to reach.
InModuleScope PsUi {
    # Picks black or white text based on background luminance
    Describe 'Get-ContrastColor' {
        It 'Returns black for white background' {
            Get-ContrastColor -HexColor '#FFFFFF' | Should -Be '#000000'
        }

        It 'Returns white for black background' {
            Get-ContrastColor -HexColor '#000000' | Should -Be '#FFFFFF'
        }

        It 'Returns black for bright green (luminance > 128)' {
            # #78B802 is R 120, G 184, B 2, luminance about 143
            Get-ContrastColor -HexColor '#78B802' | Should -Be '#000000'
        }

        It 'Returns white for dark navy' {
            Get-ContrastColor -HexColor '#1A1A2E' | Should -Be '#FFFFFF'
        }

        It 'Handles 8-char ARGB format (strips alpha channel)' {
            # A colour where the alpha byte flips the answer, so an alpha blind read picks white here.
            Get-ContrastColor -HexColor '#FF00FF00' | Should -Be '#000000'
        }

        It 'Handles hex without leading hash' {
            Get-ContrastColor -HexColor 'FFFFFF' | Should -Be '#000000'
        }

        It 'Returns white for pure red' {
            # #FF0000 luminance is 0.299*255 = 76.2, below 128
            Get-ContrastColor -HexColor '#FF0000' | Should -Be '#FFFFFF'
        }

        It 'Returns black for pure yellow' {
            # #FFFF00 luminance is 0.299*255 + 0.587*255 = 226, well above 128
            Get-ContrastColor -HexColor '#FFFF00' | Should -Be '#000000'
        }
    }

    Describe 'Get-ContrastColor edge cases' {
        It 'Handles mid-grey boundary' {
            # #808080 luminance works out to exactly 128
            $result = Get-ContrastColor -HexColor '#808080'
            # Luminance = 128, not > 128, so white
            $result | Should -Be '#FFFFFF'
        }
    }

    # Brush factory with caching - WPF brushes are expensive to create
    Describe 'ConvertTo-UiBrush' {
        It 'Creates a frozen SolidColorBrush from hex' {
            $brush = ConvertTo-UiBrush '#FF0000'
            $brush | Should -BeOfType [System.Windows.Media.SolidColorBrush]
            $brush.IsFrozen | Should -BeTrue
            $brush.Color | Should -Be ([System.Windows.Media.Colors]::Red)
        }

        It 'Returns cached brush on repeat calls' {
            Reset-BrushCache
            $first  = ConvertTo-UiBrush '#00FF00'
            $second = ConvertTo-UiBrush '#00FF00'
            [object]::ReferenceEquals($first, $second) | Should -BeTrue
        }

        It 'Handles named WPF colors' {
            $brush = ConvertTo-UiBrush 'Red'
            $brush | Should -BeOfType [System.Windows.Media.SolidColorBrush]
            $brush.Color | Should -Be ([System.Windows.Media.Colors]::Red)
        }

        It 'Falls back to gray on garbage input' {
            $brush = ConvertTo-UiBrush 'not_a_color_at_all'
            $brush | Should -Be ([System.Windows.Media.Brushes]::Gray)
        }

        It 'Reset-BrushCache clears the cache' {
            $before = ConvertTo-UiBrush '#AABB11'
            Reset-BrushCache
            $after = ConvertTo-UiBrush '#AABB11'
            # After reset, a new object. Same color, different reference
            [object]::ReferenceEquals($before, $after) | Should -BeFalse
        }

        It 'Handles ARGB hex (#AARRGGBB)' {
            $brush = ConvertTo-UiBrush '#80FF0000'
            $brush | Should -BeOfType [System.Windows.Media.SolidColorBrush]
            # 0x80 = 128
            $brush.Color.A | Should -Be 128
        }
    }

    # Turns ugly type names like 'Deserialized.System.IO.FileInfo' into 'FileInfo'
    Describe 'Get-CleanTypeName' {
        It 'Returns simple name for .NET types' {
            Get-CleanTypeName -Item 'hello' | Should -Be 'String'
        }

        It 'Strips fully qualified namespace' {
            $fileInfo = [System.IO.FileInfo]::new('C:\fake.txt')
            Get-CleanTypeName -Item $fileInfo | Should -Be 'FileInfo'
        }

        It 'Handles PSCustomObject' {
            $obj = [PSCustomObject]@{ Name = 'test' }
            Get-CleanTypeName -Item $obj | Should -Be 'PSCustomObject'
        }

        It 'Strips the Deserialized prefix' {
            # Anything that came back over the wire wears it, and the grid would show the whole prefixed name.
            $obj = [PSCustomObject]@{}
            $obj.PSObject.TypeNames.Insert(0, 'Deserialized.System.IO.FileInfo')
            Get-CleanTypeName -Item $obj | Should -Be 'FileInfo'
        }

        It 'Strips ETS adapter suffix (the # thing)' {
            $obj = [PSCustomObject]@{}
            $obj.PSObject.TypeNames.Insert(0, 'System.ServiceProcess.ServiceController#StartupType')
            Get-CleanTypeName -Item $obj | Should -Be 'ServiceController'
        }
    }

    # Formats values for display in the datagrid cells
    Describe 'ConvertTo-DisplayValue' {
        It 'Shows small hashtables inline' {
            $ht     = [ordered]@{ Name = 'Bob'; Age = 30 }
            $result = ConvertTo-DisplayValue -Value $ht
            $result | Should -BeLike '@{*Name=*Bob*Age=30*}'
        }

        It 'Abbreviates large hashtables' {
            $ht     = @{ A = 1; B = 2; C = 3; D = 4 }
            $result = ConvertTo-DisplayValue -Value $ht
            $result | Should -BeLike '@{...} (4 keys)'
        }

        It 'Formats bools with dollar prefix in hashtables' {
            $ht     = [ordered]@{ Enabled = $true }
            $result = ConvertTo-DisplayValue -Value $ht
            $result | Should -Match '\$True'
        }

        It 'Quotes strings inside hashtables' {
            $ht     = [ordered]@{ Color = 'Red' }
            $result = ConvertTo-DisplayValue -Value $ht
            $result | Should -Match "Color='Red'"
        }

        It 'Passes through scalars unchanged' {
            ConvertTo-DisplayValue -Value 42 | Should -Be 42
            ConvertTo-DisplayValue -Value 'plain text' | Should -Be 'plain text'
        }
    }

    # Figures out the best way to show button action output (text, grid, dict, etc)
    Describe 'Get-OutputPresenter' {
        It 'Returns Empty for null' {
            $result = Get-OutputPresenter -Data $null
            $result.Type | Should -Be 'Empty'
        }

        It 'Returns Text for strings' {
            $result = Get-OutputPresenter -Data 'hello world'
            $result.Type | Should -Be 'Text'
            $result.Info.Length | Should -Be 11
        }

        It 'Returns Dictionary for hashtables' {
            $result = Get-OutputPresenter -Data @{ A = 1; B = 2 }
            $result.Type | Should -Be 'Dictionary'
            $result.Info.Count | Should -Be 2
        }

        It 'Returns Empty for empty arrays' {
            $result = Get-OutputPresenter -Data @()
            $result.Type | Should -Be 'Empty'
        }

        It 'Returns Text for string arrays (multiline output)' {
            $result = Get-OutputPresenter -Data @('line1', 'line2', 'line3')
            $result.Type | Should -Be 'Text'
            $result.Info.LineCount | Should -Be 3
        }

        It 'Returns Collection for object arrays' {
            $data = @(
                [PSCustomObject]@{ Name = 'Alice'; Score = 95 }
                [PSCustomObject]@{ Name = 'Bob'; Score = 82 }
            )
            $result = Get-OutputPresenter -Data $data
            $result.Type | Should -Be 'Collection'
            $result.Info.Count | Should -Be 2
            $result.Info.Properties | Should -Contain 'Name'
            $result.Info.Properties | Should -Contain 'Score'
        }

        It 'Returns SingleObject for a lone PSCustomObject' {
            $obj    = [PSCustomObject]@{ Host = 'srv01'; Port = 443 }
            $result = Get-OutputPresenter -Data $obj
            $result.Type | Should -Be 'SingleObject'
            $result.Info.Properties | Should -Contain 'Host'
        }
    }

    # Filters out empty/null columns so the datagrid isn't full of blank cols
    Describe 'Get-PopulatedProperties' {
        It 'Returns only properties with actual values' {
            $items = @(
                [PSCustomObject]@{ Name = 'Alice'; Email = ''; Notes = $null }
                [PSCustomObject]@{ Name = 'Bob';   Email = 'bob@test.com'; Notes = $null }
            )
            $result = Get-PopulatedProperties -Items $items
            $result | Should -Contain 'Name'
            $result | Should -Contain 'Email'
            $result | Should -Not -Contain 'Notes'
        }

        It 'Skips underscore-prefixed properties' {
            $items  = @([PSCustomObject]@{ Name = 'Test'; _internal = 'hidden' })
            $result = Get-PopulatedProperties -Items $items
            $result | Should -Contain 'Name'
            $result | Should -Not -Contain '_internal'
        }

        It 'Treats an empty list as not populated' {
            $items  = @([PSCustomObject]@{ Name = 'Alice'; Tags = @() })
            $result = Get-PopulatedProperties -Items $items
            $result | Should -Contain 'Name'
            $result | Should -Not -Contain 'Tags'
        }

        It 'Filters to specific properties when PropertyNames given' {
            $items  = @([PSCustomObject]@{ A = 'yes'; B = 'yes'; C = 'yes' })
            $result = Get-PopulatedProperties -Items $items -PropertyNames @('A', 'C')
            $result | Should -Contain 'A'
            $result | Should -Contain 'C'
            $result | Should -Not -Contain 'B'
        }
    }

    # Makes up names for controls with no explicit -Variable on them.
    Describe 'New-UniqueControlName' {
        It 'Uses default ctrl prefix' {
            $name = New-UniqueControlName
            $name | Should -Match '^ctrl_[a-f0-9]{8}$'
        }

        It 'Uses custom prefix' {
            $name = New-UniqueControlName -Prefix 'btn'
            $name | Should -Match '^btn_[a-f0-9]{8}$'
        }

        It 'Generates a different name each call' {
            # The format pins above are all satisfied by a constant, so a cached guid would sail through them and collide every control.
            New-UniqueControlName | Should -Not -Be (New-UniqueControlName)
        }

    }

    Describe 'Get-UiCollectionKind' {
        It 'classifies every input form' {
            Get-UiCollectionKind -Obj ([System.Collections.ObjectModel.ObservableCollection[object]]::new()) | Should -Be 'WpfObservable'
            Get-UiCollectionKind -Obj ([PsUi.AsyncObservableCollection[object]]::new([System.Windows.Threading.Dispatcher]::CurrentDispatcher)) | Should -Be 'PsUiObservable'
            Get-UiCollectionKind -Obj ([System.Collections.ArrayList]::new()) | Should -Be 'Other'
            Get-UiCollectionKind -Obj (@('a', 'b')) | Should -Be 'Other'
            Get-UiCollectionKind -Obj $null | Should -Be 'Null'
            $target = @(1)
            Get-UiCollectionKind -Obj ([ref]$target) | Should -Be 'Ref'
        }

        It 'classifies a typed AsyncObservableCollection, which the old name match missed for subclasses' {
            Get-UiCollectionKind -Obj ([PsUi.AsyncObservableCollection[string]]::new([System.Windows.Threading.Dispatcher]::CurrentDispatcher)) | Should -Be 'PsUiObservable'
        }

        It 'classifies GridOwnedCollection as PsUiObservable via inheritance' {
            # GridOwnedCollection derives from AsyncObservableCollection, so the walk stops at the base.
            Get-UiCollectionKind -Obj ([PsUi.GridOwnedCollection[object]]::new()) | Should -Be 'PsUiObservable'
        }
    }
}
