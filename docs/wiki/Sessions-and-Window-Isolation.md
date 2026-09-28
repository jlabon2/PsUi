# Sessions and Window Isolation

Every window `New-UiWindow` creates gets its own session, running on its own UI thread. If you open the same tool twice, the two copies can't mess with each other directly.

A plain `New-UiWindow` call blocks your script until the window closes. So to get two top level windows at once you either use `-PassThru` (the call returns the window object once it's up and your script keeps going, though `-ExportOnClose` is ignored then) or run a second console. The demo's Multi-Window Test panel opens a child window and can print both session IDs, but the child runs on its opener's UI thread, so that's two sessions on one thread.

## What's in a PsUi session

- The control registry which maps every `-Variable` name to its control.
- Captured values. That's whatever a button's `-Capture` saved after it ran, plus anything an action stored with `Set-UiCapturedVariable`.

The theme and the icon font aren't part of the session. They're module state. Pass `-IconFont` to a window and PsUi swaps the module font before `-Content` runs, then puts it back when the window closes. `-Theme` sets the theme and leaves it that way, and the next window applies its own (Auto by default).

The runspace pool is module state too. There's one pool for every window in the process, capped at eight runspaces, and `Reset-UiSession` shuts it down for all of them at once. Most button clicks never touch it, though, since a button only takes a runspace from the pool when it has both `-NoOutput` and `-NoInteractive`. Every other combination can prompt so it gets a fresh runspace per click that's thrown away afterward. Links and `Invoke-UiAsync` never get input dialogs, so they always run in the pool, and so do grid actions and hotkeys unless they're `-NoAsync`.

The session gets created when `New-UiWindow` starts building and torn down when the window closes. `New-UiChildWindow` gets its own session and inherits the parent's theme. It's built and shown on the thread that opened it, and `New-UiButton` switches itself to `-NoAsync` when its action opens one.

Each control runs its actions under the window that built it, so with a nonmodal child open, a parent button's `Write-Status` still goes to the parent's status bar and a `Stop-UiAsync` there still stops the parent's run. Hotkeys work inside a child too. `Close-UiWindow` closes whichever window the code is running in. From a child, `-Window Parent` closes the window that opened it (the child goes too), and `-Window Main` closes the main window and every child.

## Where Get-UiSession works

`Get-UiSession` returns the live session object inside an action or an `-OnChange` handler, and inside `-Content` while the window builds. All of those run in runspaces PsUi created and tagged with the window's session before your code runs. At the console after the window closes, or in a script that never opened one, it returns `$null`.

Inside the `-NoAsync` action that opens a nonmodal child, `Get-UiSession` returns the child from that line on so grab `$session = Get-UiSession` before you open it. With `-Modal` that doesn't happen since the action waits on that line until the child closes.

You don't need it to read values. A name you typed in the action gets hydrated automatically, and for a name you build at runtime, use `Get-UiValue`:

```powershell
New-UiButton -Text 'Check' -Action {
    foreach ($index in 1..3) {
        $serverName = Get-UiValue -Variable "server$index"
        Write-Host "Server $index is $serverName"
    }
}
```

### State that sticks around between clicks

Each click runs in a new runspace, or a pooled one with its globals wiped, and neither remembers the last click. If something needs to survive, put it in the session's captured values:

```powershell
New-UiButton -Text 'Remember' -Action {
    Set-UiCapturedVariable -Name 'lastRun' -Value (Get-Date)
}

New-UiButton -Text 'Recall' -Action {
    Write-Host "Last run was $lastRun"
}
```

Anything in the captured store gets hydrated into later actions under its own name so the second button just reads `$lastRun`. It beats a `$lastRun` your script already had, and loses only to `-Variables` and `-LinkedVariables`. A button's `-Capture` parameter fills that store too without you touching the session. If you assign `$session.CapturedVariables['lastRun']` directly, the value gets stored, but a control with `-EnabledWhen` on that name stays disabled.

`$session.Variables` looks like the obvious place for this and isn't. It's the control registry with one entry per `-Variable` name, and PsUi scans it at click time for credential controls. If your key matches a control's name, you overwrite that control's entry.

### The raw control

`$session.GetControl('name')` gives you the actual WPF control, for the rare thing no PsUi function covers. If you swap a dropdown's items through the raw control, `Add-UiListItem` and the other list commands keep editing the list PsUi registered while the dropdown shows your new one, so for choices that change while the window is open, give `New-UiDropdown` a list through `-ItemsSource` and `.Add()` to it from an action instead. There's also no threadsafe proxy in the way so only touch the control from code that's already on the UI thread. `-Content` runs there while the window builds, and so do `-NoAsync` actions and `-OnChange` handlers. From an async action, stick to `Set-UiValue` and `Get-UiValue` which switch threads for you.

## When a session dies badly

If a window crashes, it can leave module state behind like a stuck runspace pool or a theme engine that still points at a dead window. `Reset-UiSession` clears all of it, live sessions included.
