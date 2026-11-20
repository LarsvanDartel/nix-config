// cpn-ide-app — a plain Electron window around the CPN IDE frontend, served by the backend the launcher starts.

const { app, BrowserWindow, shell } = require("electron");

const url = process.env.CPN_IDE_URL || "http://localhost:8080/";

app.setName("CPN IDE");
// No "Electron" token: the frontend's Electron path needs the `remote` module, which current
// Electron lacks; the browser path uses file inputs and downloads.
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
