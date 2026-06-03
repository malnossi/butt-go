package main

import (
	"context"
	"embed"

	"atheer/internal/audio"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
)

//go:embed all:frontend/dist
var assets embed.FS

func main() {
	// Create an instance of the app structure
	app := NewApp()

	// Initialize PortAudio before Wails initializes COM on Windows
	if err := audio.Initialize(); err != nil {
		println("PortAudio Init Error:", err.Error())
	}
	defer audio.Terminate()

	// Create application with options
	err := wails.Run(&options.App{
		Title:         "Atheer",
		Width:         480,
		Height:        640,
		DisableResize: true,
		AssetServer: &assetserver.Options{
			Assets: assets,
		},
		BackgroundColour: &options.RGBA{R: 27, G: 38, B: 54, A: 1},
		OnStartup: func(ctx context.Context) {
			app.startup(ctx)
		},
		OnShutdown: func(ctx context.Context) {
			// Clean shutdown
		},
		Bind: []interface{}{
			app,
		},
	})

	if err != nil {
		println("Error:", err.Error())
	}
}
