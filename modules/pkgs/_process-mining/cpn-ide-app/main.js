// A window for CPN IDE.
//
// The upstream Windows build ships its own Electron shell, but that one is
// written against Electron 4: it drives file dialogs through the `remote`
// module, which no longer exists. So this is a plain frame around the same
// frontend, served by the backend the launcher starts.
//
// The frontend decides which code path to take by looking for "Electron" in
// the user agent, and the Electron path is the one that needs `remote`. We
// strip the token so it takes the browser path instead: HTML file inputs for
// opening, downloads for saving. Electron shows a native save dialog for a
// download, so saving still ends up feeling like a desktop app.

const { app, BrowserWindow, shell } = require("electron");

const url = process.env.CPN_IDE_URL || "http://localhost:8080/";

app.setName("CPN IDE");
app.userAgentFallback =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) " +
  `Chrome/${process.versions.chrome} Safari/537.36`;

function createWindow() {
  const win = new BrowserWindow({
    width: 1600,
    height: 1000,
    title: "CPN IDE",
    autoHideMenuBar: true,
    backgroundColor: "#ffffff",
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      spellcheck: false,
    },
  });

  // Keep the window on the app; anything aiming elsewhere goes to the browser.
  win.webContents.setWindowOpenHandler(({ url: target }) => {
    shell.openExternal(target);
    return { action: "deny" };
  });

  win.loadURL(url);
}

app.whenReady().then(createWindow);

app.on("activate", () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
});

// Closing the window ends the session; the launcher then stops the backend.
app.on("window-all-closed", () => app.quit());
