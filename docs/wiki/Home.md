# PsUi

For building UIs in PowerShell without the misery.

<p align="center"><img src="../images/feature-showcase.gif" alt="PsUi Feature Showcase"></p>

You write plain PowerShell (no XAML needed) and PsUi turns it into a WPF window. Button clicks run your code in a background runspace so the window stay available to recieve input while your code does something slow.

It needs Windows 10/11 or Server 2016+ with PowerShell 5.1 or 7.2 and up. It's WPF underneath so there's no Linux build and there never will be. The ISE is out too ([here's why](FAQ-and-Troubleshooting#does-it-run-in-the-ise)).

```powershell
New-UiWindow -Title 'Hello' -Content {
    New-UiInput -Label 'Name' -Variable 'name'
    New-UiButton -Text 'Greet' -Accent -Action {
        Write-Host "Hello, $name!"
    }
}
```

Run that, type a name, and click Greet. A second window opens with the greeting on its Console tab. That's [the output window](Output), and async buttons open one by default (`-NoOutput` turns it off).

<p align="center"><img src="../images/home-greet.gif" alt="Typing a name, clicking Greet, and the output window opening with the greeting on its Console tab"></p>

You can leave out the `New-UiWindow` block in a script. PsUi then puts everything from the first control to the last in a window titled after the file and the script exits when you close it, so any lines below the last control never run.

## Where to go

If you haven't installed it yet, start with [Getting Started](Getting-Started). Every command has its own page and the [Command Index](Command-Index) lists them with a line each. When a window does something you didn't expect it's usually the threading model so read [Threading and Variable Hydration](Threading-and-Variable-Hydration) before you go to the [FAQ](FAQ-and-Troubleshooting).

## How it works

The [background runspace](Async-and-Stream-Interception) gets its own PowerShell host so `Write-Progress` draws a real progress bar and `Read-Host` opens a dialog you can type into. Warnings and errors each get their own tab next to Console.

In the example, `-Variable 'name'` gives the Greet action a `$name` holding whatever was typed. If you assign to it, the box updates when the action finishes. That only works in [async actions](Threading-and-Variable-Hydration). With `-NoAsync` the action runs on the window's own thread and there's no separate runspace to fill in so you read values with `Get-UiValue` instead.

Every window is its own [session](Sessions-and-Window-Isolation) and other windows can't see its controls or variables.

There are eighteen themes, and you can switch between them while the window is open. If you build your own on top of one of them and only change a couple of colors, that's four lines with `Register-UiTheme` ([Theming](Theming-and-Custom-Themes)).
