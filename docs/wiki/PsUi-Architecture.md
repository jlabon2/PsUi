# PsUi Architecture

This page is for reading the source, or for a threading problem that needs more than the rules. The rules themselves are on [How PsUi Scripts Work](How-PsUi-Scripts-Work) and [Threading and Variable Hydration](Threading-and-Variable-Hydration).

PsUi comes in two layers. The commands you call are PowerShell functions, one file each under `PsUi/public`, with their helpers under `PsUi/private`. Underneath is a C# backend in `src/`, compiled into `PsUi.dll`, which runs your scripts on other threads and gets their output and their changes back onto the window's thread.

`New-UiWindow` is the odd one out. It's a compiled cmdlet instead of a function, split across `NewUiWindowCommand.cs`, `.Builder.cs`, `.Capture.cs`, and `.ErrorPreference.cs` in `src/`.

## Loading the module

`PsUi.psm1` goes through this on import:

1. It picks a build of the DLL. 7 loads `lib\core` (net6.0-windows). 5.1 loads `lib\desktop` (net472), or `lib\net452` when the registry says .NET Framework 4.7.2 isn't there, which covers WinPE and Server builds older than 1803.
2. It loads the two WebView2 assemblies, then `PsUi.dll`.
3. It reads the icon names in `resources/CharList.json` into `ModuleContext`, and warns if neither Segoe MDL2 Assets nor Segoe Fluent Icons is installed.
4. It reads every `.ps1` under `private` and `public` into one string and runs that as a single scriptblock. Dot sourcing more than 300 files one at a time is about ten times slower, and a lot worse than that on a OneDrive folder or a UNC share.
5. It keeps the text of every private function, plus 20 public ones that actions call a lot (`Set-UiValue`, `Write-Status`, `Invoke-UiAsync`, and the like), in `ModuleContext` so they can be defined inside action runspaces later.
6. It exports the file names under `public`, plus `New-UiWindow`.

Removing the module shuts the runspace pool down. It only resets the theme engine and the session registry when no window is open, because `Import-Module -Force` runs the same removal hook, and resetting then would break the window that's still open.

## Windows and threads

Every `New-UiWindow` starts an STA thread of its own and builds the window there. It creates a session which is a `SessionContext` that `SessionManager` keeps under a new GUID. Then it opens a runspace on that thread, imports PsUi into it by the manifest path, defines PsUi's private functions, and copies in your script's variables and functions. After that it runs `-Content`, which builds the controls, and shows the window.

Your console waits on the window's thread until the window closes. `-PassThru` hands back the window as soon as it's up instead. Errors that `-Content` writes come back to your console as they happen, with their file and line, and the window opens anyway. `-Splash` gets a thread of its own that shows the splash window while the main one builds.

Variables come across as the same objects, not copies, so a hashtable an action changes is the one your script holds. Functions come across as text and get defined again. A `SqlConnection`, stream, socket, or COM object gets a warning when it's captured, since those misbehave when two threads use one at the same time. [Live objects](Threading-and-Variable-Hydration#live-objects) has the details.

`New-UiChildWindow` builds on the thread that opens it, which is the opener's UI thread, and gets a session of its own. The theme and the icon font aren't per window at all. They're module state. [Sessions and Window Isolation](Sessions-and-Window-Isolation) covers what a child window shares with its opener.

## What a click does

When `New-UiButton` builds the button, it walks the action's syntax tree for the variables the action reads and the commands it calls. It skips variables the action only assigns to, scope qualified ones like `$global:count`, and automatic ones like `$_`. Then it looks each name up in your script's scope and keeps the values and the function text on the button. `-LinkedVariables`, `-LinkedFunctions`, and `-LinkedModules` add to those lists, and PsUi's own module always goes on the module list.

On a click, an `AsyncExecutor` takes over. At most eight runs go at once across every window in the process. A ninth waits its turn and gives up with an error after 60 seconds.

If the run can prompt (`Read-Host`, `Get-Credential`, a choice prompt, `ReadKey`), it gets a fresh runspace with PsUi's `StreamingHost`, and the runspace is thrown away when the run ends. Anything else borrows one from the shared pool, which skips the startup cost. The pool holds one to eight runspaces with a lighter host of its own, and gets rebuilt if a script leaves it broken. Which runs can prompt is on [Sessions and Window Isolation](Sessions-and-Window-Isolation#whats-in-a-psui-session).

Before your code runs, a cached setup script defines the host overrides and the module functions, then the button's own functions and variables. `StateHydrationEngine` reads every control's value in one trip to the UI thread and defines each one as a variable named after its `-Variable`.

While it runs, the output streams raise events on the `AsyncExecutor`, and the output window or the status bar listens to them. The next section covers how those get to the window's thread.

When it ends, variables that changed get written back to their controls and any `-Capture` names get saved to the session. A pooled runspace has the hydrated variables and any new globals cleared out before it goes back to the pool.

The pipeline runs on an STA thread either way. `-AsyncApartment` only picks the thread that waits on it, a thread pool thread by default or a new STA thread per run with `STA`. [Threading modes](Threading-and-Variable-Hydration#threading-modes) has more on that.

## Getting back to the UI thread

WPF only lets a control's own thread touch it, and PsUi is, give or take, one long workaround for that.

- Controls get registered through `AddControlSafe` which puts a `ThreadSafeControlProxy` next to each one in the session. Reading or setting a property through the proxy from another thread hands the call to the control's UI thread and waits for the answer.
- `AsyncObservableCollection` is the list behind `-ItemsSource`. A background runspace can add to it, and it queues each change onto the window's thread in the order it came in.
- Errors, warnings, and verbose lines reach the window's thread through `BeginInvoke`, and so does progress, throttled except for its last update. `Write-Host` lines go into a queue instead, and a 50ms timer empties it.
- A prompt like `Read-Host` has to wait for its answer so it goes through `BeginInvoke` plus a wait handle. A plain `Dispatcher.Invoke` deadlocks when the UI thread has a modal dialog up.

## Output and errors

A fresh runspace gets `StreamingHost` and a pooled one gets `MinimalHost`. Both hand host output (`Write-Host`, `Out-Host`) and progress to the `AsyncExecutor`. Warnings, errors, verbose, and information come through the runspace's own stream events instead so no line shows up twice.

An error gets flattened into a `PSErrorRecord` (in `HostTypes.cs`) with the message, the line number, the code on that line, and the stack trace, and the Errors tab shows those. `$host.UI.RawUI.ReadKey()` opens `KeyCaptureDialog`, a small window that waits for a key without stealing focus.

## Theming

The 18 builtin themes are hashtables in `private/theme/ThemeDefinitions.ps1`. `ThemeEngine` turns the active one into brushes and loads the XAML styles under `resources/xaml` into each window. Commands register the controls they build with `[PsUi.ThemeEngine]::RegisterElement`, so a theme switch can walk them and reapply their brushes, and `ThemeChanged` fires for code that needs to redo something itself.

`WindowManager` covers the Win32 side that WPF leaves out. It can hide the console window and gives the title bar the theme's dark or light look. It also keeps PsUi windows from grouping under powershell.exe on the taskbar.

## The classes

| Class | File | Job |
|-------|------|-----|
| `AsyncExecutor` | `AsyncExecutor.cs`, `.Routing.cs`, `.Setup.cs` | Runs one action. Picks the runspace, sets it up, routes its output to events, and handles cancel |
| `RunspacePoolManager` | `RunspacePoolManager.cs` | The shared pool of one to eight runspaces, plus `MinimalHost` |
| `StreamingHost` | `StreamingHost.cs` | The host for fresh runspaces, and the one prompts need |
| `SessionManager` | `SessionManager.cs` | Every live session by GUID, and which session each thread belongs to |
| `SessionContext` | `SessionContext.cs` | One window's state: the control registry, captured values, lists, hotkeys, and submit buttons |
| `StateHydrationEngine` | `StateHydrationEngine.cs` | Control values into variables before an action, and changes back after |
| `ControlValueExtractor`, `ControlValueApplicator` | same names | How each control type gets read and written |
| `ThreadSafeControlProxy` | `ThreadSafeControlProxy.cs` | Property access from any thread, handed to the control's UI thread |
| `AsyncObservableCollection` | `AsyncObservableCollection.cs` | The list behind `-ItemsSource` |
| `ThemeEngine` | `ThemeEngine.cs` | Loads the XAML styles, keeps the registered elements, and reapplies brushes on a switch |
| `ControlFactory` | `ControlFactory.cs` | Builds controls with the house styles already on |
| `ModuleContext` | `ModuleContext.cs` | Module wide state: icons, the icon font, the active theme, and the function text for action runspaces |
| `WindowManager` | `WindowManager.cs` | Win32 calls for the title bar, taskbar, and console |
| `NewUiWindowCommand` | `NewUiWindowCommand.cs` and three partials | `New-UiWindow` |
| `KeyCaptureDialog` | `KeyCaptureDialog.cs` | The window behind `ReadKey` |
| `ObjectPicker`, `OuPicker` | same names | The Windows object picker and the OU browse dialog |
| `Converters` | `Converters.cs` | Works out what kind of value something is, for cells, tooltips, search, and export |
| `WebViewHelper` | `WebViewHelper.cs` | Finds the WebView2 runtime and sets up `New-UiWebView` |

## Building it

`Build-PsUi.ps1` compiles `src/` for three targets: net452 for WinPE, net472 for 5.1, and net6.0-windows for 7.2 and up. The DLLs are committed under `PsUi/lib` so importing the module never needs a build. The net452 target pins the language at C# 6 so the backend does without pattern matching and tuples.

.NET keeps a loaded assembly's types for the life of the PowerShell session so after a build you have to restart PowerShell to see the change. `Build-PsUi.ps1 -BuildDocs` runs `Build-Docs.ps1` afterwards in a fresh pwsh for the same reason.
