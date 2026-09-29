#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Private PowerShell helpers. No test here touches WPF or a live session.
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

        It 'Renders a generic argument list instead of a PublicKeyToken' {
            Get-CleanTypeName -Item ([System.Collections.Generic.Dictionary[string, object]]::new()) | Should -Be 'Dictionary<String,Object>'
        }

        It 'Keeps two instantiations of one generic apart' {
            $strings = [System.Tuple]::Create('a', 'b', 'c')
            $mixed   = [System.Tuple]::Create('a', 1)
            Get-CleanTypeName -Item $strings | Should -Be 'Tuple<String,String,String>'
            Get-CleanTypeName -Item $mixed   | Should -Be 'Tuple<String,Int32>'
            (Get-CleanTypeName -Item $strings) | Should -Not -Be (Get-CleanTypeName -Item $mixed)
        }
    }

    # Formats values for display in the datagrid cells
    Describe 'ConvertTo-DisplayValue' {
        It 'Survives a hashtable carrying Keys and Count keys' {
            # .Keys and .Count answer with the key on a hashtable, so one carrying either listed that key's value as its keys.
            ConvertTo-DisplayValue -Value ([ordered]@{ Keys = 'k'; Count = 0 }) | Should -Be "@{Keys='k'; Count=0}"
            ConvertTo-DisplayValue -Value @{ Keys = 1; Count = 2; A = 3; B = 4 } | Should -Be '@{...} (4 keys)'
        }

        It 'Counts a long HashSet without copying it' {
            $set = [System.Collections.Generic.HashSet[int]]::new()
            1..50 | ForEach-Object { [void]$set.Add($_) }
            ConvertTo-DisplayValue -Value $set | Should -Be '[50 items]'
        }

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

        It 'Takes a null value' {
            # Mandatory with no AllowNull, so a hashtable holding a null threw at parameter binding and killed the results view.
            ConvertTo-DisplayValue -Value $null | Should -Be '(null)'
        }

        It 'Spells out a short list and counts a long one' {
            # switch walked the elements, so the join part never ran and the cell read as System.Object[].
            ConvertTo-DisplayValue -Value @('web', 'prod')      | Should -Be 'web, prod'
            ConvertTo-DisplayValue -Value @(1, 2, 3, 4, 5, 6, 7) | Should -Be '[7 items]'
            ConvertTo-DisplayValue -Value @()                   | Should -Be '[empty]'
        }

        It 'Treats every list type the same, not just a plain array' {
            # -is [array] was the old test and it is false for both of these.
            ConvertTo-DisplayValue -Value ([System.Collections.ArrayList]@('web', 'prod'))            | Should -Be 'web, prod'
            ConvertTo-DisplayValue -Value ([System.Collections.Generic.List[object]]@('web', 'prod')) | Should -Be 'web, prod'
        }

        It 'Emits one string for a list-valued key' {
            # The inner switch walked the list too and did not return, so one key produced one pair per element.
            $result = @(ConvertTo-DisplayValue -Value @{ k = @('a', 'b') })
            $result.Count | Should -Be 1
            $result[0]    | Should -Be '@{k=[2 items]}'
        }

        It 'Names the elements of a list of hashtables' {
            ConvertTo-DisplayValue -Value @(@{ a = 1 }, @{ b = 2 }) | Should -Be '@{...}, @{...}'
        }

        It 'Reads a type whose own ToString is its type name through the one PowerShell hangs on it' {
            # A RequiredServices cell listed System.ServiceProcess.ServiceController once per element, since [string] takes the CLR method and PS's own is a script method.
            $service = @(Get-Service)[0]
            [PsUi.ValueKind]::DisplayText($service)  | Should -Be $service.Name
            ConvertTo-DisplayValue -Value @($service) | Should -Be $service.Name
        }

        It 'Leaves a value that spells itself where it was' {
            # The scripted ToString on a date is the culture format, so the fallback only fires when the first answer is the type name.
            $when = [datetime]'2026-09-22 13:45'
            [PsUi.ValueKind]::DisplayText($when)  | Should -Be ([System.Management.Automation.LanguagePrimitives]::ConvertTo($when, [string]))
            [PsUi.ValueKind]::DisplayText(1.5)    | Should -Be '1.5'
            [PsUi.ValueKind]::DisplayText('web')  | Should -Be 'web'
            [PsUi.ValueKind]::DisplayText($null)  | Should -Be ''
        }

        It 'Leaves a type nobody dressed up reading as its own name' {
            # The fallback asks the object and takes what it gets, which for most of the BCL is the name it already had.
            $rule = (Get-Acl $env:WINDIR).Access[0]
            [PsUi.ValueKind]::DisplayText($rule) | Should -Be $rule.GetType().FullName
        }

        It 'Shows a null inside a hashtable as a PowerShell literal' {
            ConvertTo-DisplayValue -Value ([ordered]@{ k = $null }) | Should -Be '@{k=$null}'
        }
    }

    # One classifier behind the cell text, the clickable flag and the expand popups
    Describe 'Get-UiValueKind' {
        It 'Answers List for every list type, not just a plain array' {
            Get-UiValueKind -Value @('a')                                                   | Should -Be 'List'
            Get-UiValueKind -Value ([System.Collections.ArrayList]@('a'))                   | Should -Be 'List'
            Get-UiValueKind -Value ([System.Collections.Generic.List[object]]@('a'))        | Should -Be 'List'
            Get-UiValueKind -Value ([System.Collections.ObjectModel.ObservableCollection[object]]@('a')) | Should -Be 'List'
            Get-UiValueKind -Value ([System.Collections.Queue]@(1, 2))                      | Should -Be 'List'

            # A HashSet answers only the generic ICollection[T], so the plain test called it a sequence and its cell read [sequence].
            Get-UiValueKind -Value ([System.Collections.Generic.HashSet[string]]@('a'))     | Should -Be 'List'
        }

        It 'Survives a type carrying ICollection[T] twice' {
            # Looked up by name, GetInterface threw Ambiguous match, and the throw walked out through ConvertTo-DisplayValue
            # into the one catch around the results build, which lost every tab.
            { Get-UiValueKind -Value ([PsUiTest.DoubleCollection]::new()) } | Should -Not -Throw
            Get-UiValueKind -Value ([PsUiTest.DoubleCollection]::new()) | Should -Be 'List'
            ConvertTo-DisplayValue -Value ([PsUiTest.DoubleCollection]::new()) | Should -Be 'web, prod'
        }

        It 'Answers Dictionary for an ordered hashtable as well as a plain one' {
            # A Hashtable is an ICollection as well, so the dictionary test has to come first.
            Get-UiValueKind -Value @{ x = 1 }          | Should -Be 'Dictionary'
            Get-UiValueKind -Value ([ordered]@{ x = 1 }) | Should -Be 'Dictionary'
        }

        It 'Keeps a string out of the list bucket' {
            # A string enumerates as characters, so it has to be answered before any enumerable test.
            Get-UiValueKind -Value 'hi' | Should -Be 'Text'
        }

        It 'Answers Sequence for a reader' {
            # A real file reader, since it has no Count
            $reader = [System.IO.File]::ReadLines((Join-Path $PSScriptRoot '_Setup.ps1'))
            Get-UiValueKind -Value $reader | Should -Be 'Sequence'
        }

        It 'Answers Null, Bool and Scalar for the rest' {
            Get-UiValueKind -Value $null                  | Should -Be 'Null'
            Get-UiValueKind -Value $true                  | Should -Be 'Bool'
            Get-UiValueKind -Value 42                     | Should -Be 'Scalar'
            Get-UiValueKind -Value ([datetime]'2026-09-21') | Should -Be 'Scalar'
        }

        It 'Is the same answer [PsUi.ValueKind] gives, a PSObject included' {
            # One classifier for both, so a PSObject off a pipeline reads as what it wraps here and in the C# converters alike.
            Get-UiValueKind -Value ([psobject]@{ a = 1 })       | Should -Be 'Dictionary'
            Get-UiValueKind -Value ([pscustomobject]@{ a = 1 }) | Should -Be 'Scalar'
            [PsUi.ValueKind]::Of(@{ a = 1 })                    | Should -Be (Get-UiValueKind -Value @{ a = 1 })
        }
    }

    # Figures out whether button action output shows as text or as a grid
    Describe 'Get-OutputPresenter' {
        It 'Returns Empty for null and for an empty array' {
            Get-OutputPresenter -Data $null | Should -Be 'Empty'
            Get-OutputPresenter -Data @()   | Should -Be 'Empty'
        }

        It 'Returns Text for string arrays (multiline output)' {
            Get-OutputPresenter -Data @('line1', 'line2', 'line3') | Should -Be 'Text'
        }

        It 'Returns Collection for object arrays' {
            $data = @(
                [PSCustomObject]@{ Name = 'Alice'; Score = 95 }
                [PSCustomObject]@{ Name = 'Bob'; Score = 82 }
            )
            Get-OutputPresenter -Data $data | Should -Be 'Collection'
        }

        It 'Returns Collection for one hashtable in an array' {
            # Invoke-OnCompleteHandler unwrapped a lone dictionary before this call and got Dictionary back, which built a plain grid with no expandable Value column and no filter box.
            Get-OutputPresenter -Data @(@{ Name = 'srv01'; Tags = @('web', 'prod') }) | Should -Be 'Collection'
        }
    }

    # Filters out empty/null columns so the datagrid isn't full of blank cols
    Describe 'Get-PopulatedProperties' {
        It 'Counts a hashtable carrying a Count key and an empty HashSet the way the picker does' {
            # .Count on an ICollection read the key, so @{Count=0} hid its column, and an empty HashSet is no ICollection, so it counted as filled.
            $items  = @([PSCustomObject]@{ CountKey = @{ Count = 0; a = 1 }; EmptySet = [System.Collections.Generic.HashSet[string]]::new(); Zero = 0 })
            $result = Get-PopulatedProperties -Items $items -PropertyNames @('CountKey', 'EmptySet', 'Zero')
            $result.Contains('CountKey') | Should -BeTrue
            $result.Contains('EmptySet') | Should -BeFalse
            $result.Contains('Zero')     | Should -BeTrue
        }

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

    Describe 'Get-UiCollectionType' {
        It 'classifies every input form' {
            Get-UiCollectionType -Obj ([System.Collections.ObjectModel.ObservableCollection[object]]::new()) | Should -Be 'WpfObservable'
            Get-UiCollectionType -Obj ([PsUi.AsyncObservableCollection[object]]::new([System.Windows.Threading.Dispatcher]::CurrentDispatcher)) | Should -Be 'PsUiObservable'
            Get-UiCollectionType -Obj ([System.Collections.ArrayList]::new()) | Should -Be 'Other'
            Get-UiCollectionType -Obj (@('a', 'b')) | Should -Be 'Other'
            Get-UiCollectionType -Obj $null | Should -Be 'Null'
            $target = @(1)
            Get-UiCollectionType -Obj ([ref]$target) | Should -Be 'Ref'
        }

        It 'classifies a typed AsyncObservableCollection, which the old name match missed for subclasses' {
            Get-UiCollectionType -Obj ([PsUi.AsyncObservableCollection[string]]::new([System.Windows.Threading.Dispatcher]::CurrentDispatcher)) | Should -Be 'PsUiObservable'
        }

        It 'classifies GridOwnedCollection as PsUiObservable via inheritance' {
            # GridOwnedCollection derives from AsyncObservableCollection, so the walk stops at the base.
            Get-UiCollectionType -Obj ([PsUi.GridOwnedCollection[object]]::new()) | Should -Be 'PsUiObservable'
        }
    }
}
