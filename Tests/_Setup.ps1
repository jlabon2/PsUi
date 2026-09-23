# Every test file dot sources this twice, at the top and again in BeforeAll.
# Pester runs discovery and the tests in separate scopes, so a single pass leaves one of them without the module or the helpers.
$repoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoModule = Join-Path $repoRoot 'PsUi\PsUi.psd1'
$loaded     = Get-Module PsUi | Where-Object { $_.Path -like '*.psm1' -and $_.Path.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase) }

if (!$loaded) {
    Write-Debug "PsUi tests: importing $repoModule"
    Import-Module $repoModule -Force
}

# Without this a control with no window around it opens one, and the run sits there until somebody closes it.
# The variable outlives the run. Remove-Item env:PsUiNoImplicitWindow puts the implicit window back.
$env:PsUiNoImplicitWindow = '1'

# The three helpers below are only for the cross thread Describes in Collections.Tests.ps1, which run outside module scope.
# MTA so AsyncObservableCollection.Add sees CheckAccess false and takes the hop to the UI thread.
function Start-BackgroundAdd {
    param($Wrapper, $Item)
    $rs                = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = [System.Threading.ApartmentState]::MTA
    $rs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
    $rs.Open()
    $ps          = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({ param($target, $item) $target.Add($item) }).AddArgument($Wrapper).AddArgument($Item)
    @{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke() }
}

function Complete-BackgroundAdd {
    param([hashtable]$Invocation, [int]$TimeoutMs = 2000)
    $ok = $Invocation.Handle.AsyncWaitHandle.WaitOne($TimeoutMs)

    # EndInvoke blocks until the pipeline ends, so calling it on a stuck worker hangs the run in lieu of failing it.
    if ($ok) {
        try   { [void]$Invocation.PS.EndInvoke($Invocation.Handle) }
        catch { Write-Debug "EndInvoke threw: $_" }
    }
    else {
        try   { $Invocation.PS.Stop() }
        catch { Write-Debug "Stop threw: $_" }
    }
    $Invocation.PS.Dispose()
    $Invocation.RS.Close()
    $Invocation.RS.Dispose()
    return $ok
}

# A single PushFrame races the worker. ApplicationIdle fires on an empty queue, so the sentinel comes back before the background add has landed.
function Wait-BackgroundAdd {
    param([hashtable]$Invocation, [int]$TimeoutSec = 2)
    $disp     = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline -and !$Invocation.Handle.IsCompleted) {
        $frame = [System.Windows.Threading.DispatcherFrame]::new()
        [void]$disp.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::ApplicationIdle,
            [Action]{ $frame.Continue = $false })
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
        if (!$Invocation.Handle.IsCompleted) { [System.Threading.Thread]::Sleep(20) }
    }
}

# Type.GetInterface by name throws 'Ambiguous match' on a type that use ICollection[T] twice, so we need a type to test with
if (!('PsUiTest.DoubleCollection' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Collections;
using System.Collections.Generic;
namespace PsUiTest {
    public class DoubleCollection : ICollection<string>, ICollection<int> {
        private string[] _values = new string[] { "web", "prod" };
        public int Count { get { return _values.Length; } }
        public bool IsReadOnly { get { return true; } }
        public void Add(string v) { } public void Add(int v) { }
        public void Clear() { }
        public bool Contains(string v) { return false; } public bool Contains(int v) { return false; }
        public void CopyTo(string[] a, int i) { } public void CopyTo(int[] a, int i) { }
        public bool Remove(string v) { return false; } public bool Remove(int v) { return false; }
        IEnumerator<string> IEnumerable<string>.GetEnumerator() { return ((IEnumerable<string>)_values).GetEnumerator(); }
        IEnumerator<int> IEnumerable<int>.GetEnumerator() { return new List<int>().GetEnumerator(); }
        public IEnumerator GetEnumerator() { return _values.GetEnumerator(); }
    }

    public class CountingSequence : IEnumerable {
        public static int Passes = 0;
        public IEnumerator GetEnumerator() {
            Passes++;
            return new string[] { "a", "b" }.GetEnumerator();
        }
        public override string ToString() { return "CountingSequence"; }
    }

    // A getter that throws on every row for the search sampler
    public class ThrowingGetter {
        public string Name { get; set; }
        public string Broken { get { throw new System.InvalidOperationException("no"); } }
    }
}
'@
}
