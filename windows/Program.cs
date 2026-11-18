using System.Diagnostics;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace AgentOffice;

static class Program
{
    [STAThread]
    static void Main()
    {
        using var instance = new Mutex(true, @"Local\AgentOffice", out var first);
        if (!first) return;
        ApplicationConfiguration.Initialize();
        using var office = new OfficeWindow();
        Application.Run(office);
    }
}

sealed class OfficeWindow : ApplicationContext
{
    const string Location = "https://agent-office.local/index.html";
    readonly WebView2 view = new() { Dock = DockStyle.Fill };
    readonly Form panel = new()
    {
        Text = "Agent Office", Size = new Size(880, 670), MinimumSize = new Size(430, 430),
        StartPosition = FormStartPosition.CenterScreen, ShowInTaskbar = false, TopMost = true
    };
    readonly NotifyIcon tray = new();
    readonly System.Windows.Forms.Timer timer = new() { Interval = 4000 };
    readonly Icon icon = new(Path.Combine(AppContext.BaseDirectory, "AgentOffice.ico"));
    readonly ContextMenuStrip menu = new();
    readonly JsonSerializerOptions json = new(JsonSerializerDefaults.Web);
    Snapshot snapshot = new([], []);
    string? rendered;
    bool started, ready, polling, quitting;

    public OfficeWindow()
    {
        panel.Icon = icon;
        panel.Controls.Add(view);
        panel.FormClosing += (_, e) => { if (!quitting && e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; panel.Hide(); } };
        panel.Deactivate += (_, _) => panel.Hide();
        panel.VisibleChanged += async (_, _) =>
        {
            if (ready) await view.ExecuteScriptAsync($"window.setOfficeVisibility({(panel.Visible ? "true" : "false")})");
        };
        menu.Items.Add("Open Agent Office", null, async (_, _) => await ShowOffice());
        menu.Items.Add("Quit", null, (_, _) => ExitThread());
        tray.Icon = icon;
        tray.Text = "Agent Office";
        tray.ContextMenuStrip = menu;
        tray.MouseClick += async (_, e) =>
        {
            if (e.Button == MouseButtons.Left) await ShowOffice();
        };
        tray.Visible = true;
        timer.Tick += async (_, _) => await Refresh();
        timer.Start();
        _ = Refresh();
    }

    async Task ShowOffice()
    {
        var area = Screen.FromPoint(Cursor.Position).WorkingArea;
        panel.Size = new Size(Math.Min(880, area.Width), Math.Min(670, area.Height));
        panel.Location = new Point(area.Left + (area.Width - panel.Width) / 2, area.Top + 12);
        panel.Show();
        panel.Activate();
        if (started) return;
        started = true;
        try
        {
            var profile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AgentOffice", "WebView2");
            var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: profile);
            await view.EnsureCoreWebView2Async(environment);
            var browser = view.CoreWebView2;
            browser.Settings.AreDevToolsEnabled = false;
            browser.Settings.AreDefaultContextMenusEnabled = false;
            browser.SetVirtualHostNameToFolderMapping("agent-office.local",
                Path.Combine(AppContext.BaseDirectory, "Office"), CoreWebView2HostResourceAccessKind.Deny);
            browser.NavigationStarting += (_, e) => e.Cancel = e.Uri != Location;
            browser.NewWindowRequested += (_, e) => e.Handled = true;
            browser.WebMessageReceived += async (_, e) =>
            {
                if (e.Source != Location) return;
                using var message = JsonDocument.Parse(e.WebMessageAsJson);
                var body = message.RootElement;
                if (body.ValueKind != JsonValueKind.Object) return;
                switch (Sessions.Get(body, "type").Text())
                {
                    case "officeReady":
                        ready = true;
                        rendered = null;
                        await Render();
                        await view.ExecuteScriptAsync($"window.setOfficeVisibility({(panel.Visible ? "true" : "false")})");
                        break;
                    case "openSession":
                        await OpenSession(Sessions.Get(body, "id").Text());
                        break;
                }
            };
            browser.Navigate(Location);
        }
        catch (WebView2RuntimeNotFoundException)
        {
            started = false;
            panel.Hide();
            MessageBox.Show("Install the Microsoft Edge WebView2 Runtime, then open Agent Office again.", "Agent Office");
        }
        catch (Exception error)
        {
            started = false;
            panel.Hide();
            MessageBox.Show(error.Message, "Agent Office could not open");
        }
    }

    async Task Refresh()
    {
        if (polling || quitting) return;
        polling = true;
        try
        {
            snapshot = await Task.Run(Sessions.Read);
            if (quitting) return;
            var count = snapshot.Sessions.Count;
            tray.Text = count == 0 ? "Agent Office" : $"Agent Office · {count} working";
            if (ready) await Render();
        }
        finally { polling = false; }
    }

    async Task Render()
    {
        var payload = JsonSerializer.Serialize(snapshot, json);
        if (payload == rendered) return;
        rendered = payload;
        await view.ExecuteScriptAsync($"window.showLocalActivity({payload})");
    }

    async Task OpenSession(string? id)
    {
        var session = snapshot.Sessions.FirstOrDefault(item => item.Id == id);
        if (session is null) return;
        var target = session.Provider == "Codex" && Guid.TryParse(session.Id, out var guid)
            ? $"codex://threads/{guid:D}"
            : session.Directory is { } directory && Directory.Exists(directory) ? directory : null;
        if (target is null) return;
        try
        {
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
            panel.Hide();
        }
        catch (System.ComponentModel.Win32Exception)
        {
            await view.ExecuteScriptAsync("window.showSessionOpenError()");
        }
    }

    protected override void ExitThreadCore()
    {
        quitting = true;
        timer.Stop();
        tray.Visible = false;
        panel.Close();
        base.ExitThreadCore();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            timer.Dispose();
            tray.Dispose();
            menu.Dispose();
            panel.Dispose();
            icon.Dispose();
        }
        base.Dispose(disposing);
    }
}
